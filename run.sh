#!/usr/bin/env bash
# ==============================================================
# ComfyUI Docker — Pull & Run (Linux)
# Image : superyc1121/comfyui:latest
# Usage : bash run.sh [OPTIONS]
#
#   -p, --port <port>     Host port，預設 8188（-g all 時預設改為 8190）
#   -g, --gpu <id>        GPU id（0/1/all），預設自動選可用 VRAM 最大的那張
#                         用 all 可讓兩張卡同時可見，交由 ComfyUI-MultiGPU 節點分派，
#                         容器名稱／port 會改用 comfyui-multigpu / 8190，
#                         對應 docker-compose.yml 的 comfyui-multigpu 服務，
#                         可與單 GPU 的 comfyui 容器同時並存
#       --cpu             純 CPU 模式（無 GPU）
#       --pull-only       只 pull，不啟動容器
#       --rm              容器停止後自動刪除（互動測試用）
#   -h, --help            顯示說明
#
# 範例：
#   bash run.sh                          # pull latest + 啟動
#   bash run.sh -p 8080                  # 改 port
#   bash run.sh -g 1                     # 只用 GPU 1
#   bash run.sh -g all                   # comfyui-multigpu 容器，兩張 GPU 同時可見
#   bash run.sh --cpu                    # CPU 模式
#   bash run.sh --pull-only              # 只更新 image
# ==============================================================
set -euo pipefail

# ── 預設值 ────────────────────────────────────────────────────
HUB_IMAGE="superyc1121/comfyui"
HOST_PORT=8188
PORT_EXPLICIT=false
GPU_ID=""
GPU_AUTO=true
CPU_MODE=false
PULL_ONLY=false
AUTO_REMOVE=false

# ── 目錄（固定掛載於 /mnt/comfyui）──────────────────────────
BASE_DIR="/mnt/comfyui"
MODELS_DIR="${BASE_DIR}/models"
OUTPUT_DIR="${BASE_DIR}/output"
INPUT_DIR="${BASE_DIR}/input"
NODES_DIR="${BASE_DIR}/custom_nodes"
USER_DIR="${BASE_DIR}/user"

# ── 顏色 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RESET='\033[0m'
log()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()  { echo -e "${RED}[ERR ]${RESET} $*" >&2; exit 1; }

# ── 參數解析 ──────────────────────────────────────────────────
usage() {
    sed -n '3,23p' "$0" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)      HOST_PORT="$2"; PORT_EXPLICIT=true; shift 2 ;;
        -g|--gpu)       GPU_ID="$2"; GPU_AUTO=false; shift 2 ;;
        --cpu)          CPU_MODE=true;  shift   ;;
        --pull-only)    PULL_ONLY=true; shift   ;;
        --rm)           AUTO_REMOVE=true; shift ;;
        -h|--help)      usage ;;
        *) die "未知參數: $1，使用 -h 查看說明" ;;
    esac
done

FULL_IMAGE="${HUB_IMAGE}:latest"

# ── 查詢 GitHub 最新版本 ────────────────────────────────────
detect_github_version() {
    command -v curl &>/dev/null || return
    curl -sf --max-time 8 \
        -H "User-Agent: ComfyUI-Docker/1.0" \
        "https://api.github.com/repos/Comfy-Org/ComfyUI/releases/latest" \
    | grep '"tag_name"' | head -1 | awk -F'"' '{print $4}'
}

# ── 自動偵測 VRAM 最大的 GPU ─────────────────────────────────
detect_best_gpu() {
    command -v nvidia-smi &>/dev/null || { echo "all"; return; }
    local best
    best=$(nvidia-smi --query-gpu=index,memory.free \
           --format=csv,noheader,nounits 2>/dev/null \
           | sort -t',' -k2 -rn | head -1 \
           | awk -F',' '{print $1}' | tr -d ' ')
    [[ -n "$best" ]] && echo "$best" || echo "all"
}

# ── 前置檢查 ──────────────────────────────────────────────────
command -v docker &>/dev/null || die "找不到 docker，請先安裝 Docker Engine"

# ── 建立本機資料夾 ─────────────────────────────────────────────
for dir in "$MODELS_DIR" "$OUTPUT_DIR" "$INPUT_DIR" "$NODES_DIR" "$USER_DIR"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir"
        log "建立資料夾: $dir"
    fi
done

# ── 偵測 GitHub 最新版本 ──────────────────────────────────────
log "查詢 ComfyUI 最新版本 (GitHub)..."
GH_VERSION=$(detect_github_version)
if [[ -n "$GH_VERSION" ]]; then
    ok "ComfyUI 最新版本: ${GH_VERSION}"
else
    warn "無法取得 GitHub 版本（網路問題？），繼續使用現有 image"
fi

# ── Pull image ─────────────────────────────────────────────────
log "拉取 image: ${FULL_IMAGE}"
docker pull "${FULL_IMAGE}"
ok "Pull 完成: ${FULL_IMAGE}"

[[ "$PULL_ONLY" == true ]] && { ok "--pull-only 模式，結束。"; exit 0; }

# GPU 設定（先決定，才能依此挑選對應 docker-compose.yml 服務的容器名稱／port）
GPU_ARGS=()
if [[ "$CPU_MODE" == true ]]; then
    warn "CPU 模式（無 GPU），速度較慢"
    CMD_EXTRA="--cpu"
else
    # 確認 nvidia-container-toolkit
    if ! docker info 2>/dev/null | grep -q "Runtimes.*nvidia\|nvidia"; then
        warn "偵測不到 nvidia runtime，若有 GPU 請安裝 nvidia-container-toolkit"
        warn "繼續以 --gpus 嘗試..."
    fi

    # 自動選 VRAM 最大的 GPU
    if [[ "$GPU_AUTO" == true ]]; then
        GPU_ID=$(detect_best_gpu)
        if [[ "$GPU_ID" == "all" ]]; then
            log "GPU 自動偵測：使用全部 GPU"
        else
            local_vram=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits \
                         2>/dev/null | sed -n "$((GPU_ID+1))p" | tr -d ' ')
            log "GPU 自動偵測：選擇 GPU ${GPU_ID}（可用 VRAM ${local_vram} MiB）"
        fi
    fi

    if [[ "$GPU_ID" == "all" ]]; then
        GPU_ARGS+=(--gpus all)
        GPU_ARGS+=(-e NVIDIA_VISIBLE_DEVICES=all)
    else
        GPU_ARGS+=(--gpus "device=${GPU_ID}")
        GPU_ARGS+=(-e "NVIDIA_VISIBLE_DEVICES=${GPU_ID}")
    fi
    GPU_ARGS+=(-e NVIDIA_DRIVER_CAPABILITIES=compute,utility)
    CMD_EXTRA=""
fi

# 雙 GPU 協同（ComfyUI-MultiGPU）：對應 docker-compose.yml 的 comfyui-multigpu 服務，
# 用獨立的容器名稱／port，才能跟單 GPU 的 comfyui 容器同時並存、互不覆蓋。
CONTAINER_NAME="comfyui"
if [[ "$GPU_ID" == "all" ]]; then
    CONTAINER_NAME="comfyui-multigpu"
    if [[ "$PORT_EXPLICIT" == false ]]; then
        HOST_PORT=8190
    fi
fi

# ── 組裝 docker run 參數 ───────────────────────────────────────
RUN_ARGS=(
    --name  "${CONTAINER_NAME}"
    --restart unless-stopped
    -p      "${HOST_PORT}:8188"
    -v      "${MODELS_DIR}:/app/models"
    -v      "${OUTPUT_DIR}:/app/output"
    -v      "${INPUT_DIR}:/app/input"
    -v      "${NODES_DIR}:/app/custom_nodes"
    -v      "${USER_DIR}:/app/user"
    -e      "COMFYUI_DB_NAME=${CONTAINER_NAME}"
    "${GPU_ARGS[@]}"
)

[[ "$AUTO_REMOVE" == true ]] && RUN_ARGS+=(--rm) && unset 'RUN_ARGS[1]' 'RUN_ARGS[2]'  # 移除 --restart

# ── 若同名容器已存在，先移除 ──────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    warn "容器 '${CONTAINER_NAME}' 已存在，先停止並移除..."
    docker stop  "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm    "${CONTAINER_NAME}" 2>/dev/null || true
fi

# ── 啟動容器 ───────────────────────────────────────────────────
log "啟動容器..."
# entrypoint.sh 會自行組出 --listen/--port/--enable-manager 與 GPU 數量判斷後的
# --cuda-device，這裡只需要傳遞 CMD_EXTRA（例如 --cpu），避免參數重複。
docker run -d "${RUN_ARGS[@]}" "${FULL_IMAGE}" ${CMD_EXTRA}

ok "ComfyUI 已啟動！"
echo ""
echo -e "  瀏覽器開啟 → ${GREEN}http://localhost:${HOST_PORT}${RESET}"
echo -e "  查看 log   → ${CYAN}docker logs -f ${CONTAINER_NAME}${RESET}"
echo -e "  停止容器   → ${CYAN}docker stop ${CONTAINER_NAME}${RESET}"
echo ""
echo -e "${CYAN}── 掛載目錄 ──────────────────────────────────${RESET}"
printf "  %-14s %s\n" "models:"       "${MODELS_DIR}"
printf "  %-14s %s\n" "output:"       "${OUTPUT_DIR}"
printf "  %-14s %s\n" "input:"        "${INPUT_DIR}"
printf "  %-14s %s\n" "custom_nodes:" "${NODES_DIR}"
printf "  %-14s %s\n" "user:"         "${USER_DIR}"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo ""
