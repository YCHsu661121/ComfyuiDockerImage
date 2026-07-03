#!/usr/bin/env bash
# ==============================================================
# ComfyUI Docker — Pull & Run (Linux)
# Image : superyc1121/comfyui:latest
# Usage : bash run.sh [OPTIONS]
#
#   -p, --port <port>     Host port，預設 8188
#   -g, --gpu <id>        GPU id（0/1/all），預設 all
#       --cpu             純 CPU 模式（無 GPU）
#       --pull-only       只 pull，不啟動容器
#       --rm              容器停止後自動刪除（互動測試用）
#   -h, --help            顯示說明
#
# 範例：
#   bash run.sh                          # pull latest + 啟動
#   bash run.sh -p 8080                  # 改 port
#   bash run.sh -g 1                     # 只用 GPU 1
#   bash run.sh --cpu                    # CPU 模式
#   bash run.sh --pull-only              # 只更新 image
# ==============================================================
set -euo pipefail

# ── 預設值 ────────────────────────────────────────────────────
HUB_IMAGE="superyc1121/comfyui"
HOST_PORT=8188
GPU_ID="all"
CPU_MODE=false
PULL_ONLY=false
AUTO_REMOVE=false

# ── 目錄（和 run.sh 同一層）──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
OUTPUT_DIR="${SCRIPT_DIR}/output"
INPUT_DIR="${SCRIPT_DIR}/input"
NODES_DIR="${SCRIPT_DIR}/custom_nodes"

# ── 顏色 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RESET='\033[0m'
log()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()  { echo -e "${RED}[ERR ]${RESET} $*" >&2; exit 1; }

# ── 參數解析 ──────────────────────────────────────────────────
usage() {
    sed -n '3,20p' "$0" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)      HOST_PORT="$2"; shift 2 ;;
        -g|--gpu)       GPU_ID="$2";    shift 2 ;;
        --cpu)          CPU_MODE=true;  shift   ;;
        --pull-only)    PULL_ONLY=true; shift   ;;
        --rm)           AUTO_REMOVE=true; shift ;;
        -h|--help)      usage ;;
        *) die "未知參數: $1，使用 -h 查看說明" ;;
    esac
done

FULL_IMAGE="${HUB_IMAGE}:latest"

# ── 前置檢查 ──────────────────────────────────────────────────
command -v docker &>/dev/null || die "找不到 docker，請先安裝 Docker Engine"

# ── 建立本機資料夾 ─────────────────────────────────────────────
for dir in "$MODELS_DIR" "$OUTPUT_DIR" "$INPUT_DIR" "$NODES_DIR"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "建立資料夾: $dir"
    fi
done

# ── Pull image ─────────────────────────────────────────────────
log "拉取 image: ${FULL_IMAGE}"
docker pull "${FULL_IMAGE}"
ok "Pull 完成: ${FULL_IMAGE}"

[[ "$PULL_ONLY" == true ]] && { ok "--pull-only 模式，結束。"; exit 0; }

# ── 組裝 docker run 參數 ───────────────────────────────────────
CONTAINER_NAME="comfyui"
RUN_ARGS=(
    --name  "${CONTAINER_NAME}"
    --restart unless-stopped
    -p      "${HOST_PORT}:8188"
    -v      "${MODELS_DIR}:/app/models"
    -v      "${OUTPUT_DIR}:/app/output"
    -v      "${INPUT_DIR}:/app/input"
    -v      "${NODES_DIR}:/app/custom_nodes"
)

[[ "$AUTO_REMOVE" == true ]] && RUN_ARGS+=(--rm) && unset 'RUN_ARGS[1]' 'RUN_ARGS[2]'  # 移除 --restart

# GPU 設定
if [[ "$CPU_MODE" == true ]]; then
    warn "CPU 模式（無 GPU），速度較慢"
    CMD_EXTRA="--cpu"
else
    # 確認 nvidia-container-toolkit
    if ! docker info 2>/dev/null | grep -q "Runtimes.*nvidia\|nvidia"; then
        warn "偵測不到 nvidia runtime，若有 GPU 請安裝 nvidia-container-toolkit"
        warn "繼續以 --gpus 嘗試..."
    fi

    if [[ "$GPU_ID" == "all" ]]; then
        RUN_ARGS+=(--gpus all)
        RUN_ARGS+=(-e NVIDIA_VISIBLE_DEVICES=all)
    else
        RUN_ARGS+=(--gpus "\"device=${GPU_ID}\"")
        RUN_ARGS+=(-e "NVIDIA_VISIBLE_DEVICES=${GPU_ID}")
    fi
    RUN_ARGS+=(-e NVIDIA_DRIVER_CAPABILITIES=compute,utility)
    CMD_EXTRA=""
fi

# ── 若同名容器已存在，先移除 ──────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    warn "容器 '${CONTAINER_NAME}' 已存在，先停止並移除..."
    docker stop  "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm    "${CONTAINER_NAME}" 2>/dev/null || true
fi

# ── 啟動容器 ───────────────────────────────────────────────────
log "啟動容器..."
docker run -d "${RUN_ARGS[@]}" "${FULL_IMAGE}" \
    python main.py --listen 0.0.0.0 --port 8188 ${CMD_EXTRA}

ok "ComfyUI 已啟動！"
echo ""
echo -e "  瀏覽器開啟 → ${GREEN}http://localhost:${HOST_PORT}${RESET}"
echo -e "  查看 log   → ${CYAN}docker logs -f ${CONTAINER_NAME}${RESET}"
echo -e "  停止容器   → ${CYAN}docker stop ${CONTAINER_NAME}${RESET}"
echo ""
