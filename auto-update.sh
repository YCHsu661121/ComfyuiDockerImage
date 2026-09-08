#!/usr/bin/env bash
# ==============================================================
# auto-update.sh — Linux 版自動偵測 ComfyUI 新版並 Build & Push
# 對應 Windows 的 auto-update.ps1
#
# 流程：
#   1. 查詢 GitHub 最新 Release tag
#   2. 查詢 Docker Hub 該 tag 是否已存在
#   3. 若不存在 → Build + Push（邏輯已內建，不再依賴 build-push.sh）
#   4. 記錄至 auto-update.log
#
# Usage : bash auto-update.sh [OPTIONS]
#
#   -f, --force       強制重建（即使 tag 已存在）
#   -c, --check-only  只查版本，不 Build
#   -v, --version     指定 ComfyUI 版本（未指定則自動查詢 GitHub 最新 Release）
#   -t, --torch       PyTorch wheel index，預設 cu130
#       --cuda        CUDA base image tag
#   -n, --easy-install-nodes <profile>
#                     Easy-Install custom-node profile: standard/none，預設 standard
#       --no-push     只 build，不 push
#   -h, --help        顯示說明
#
# 搭配 cron 排程（每週一 08:00）：
#   0 8 * * 1 /path/to/auto-update.sh >> /path/to/auto-update.log 2>&1
#
# 設定 GITHUB_TOKEN 可避免 API rate limit：
#   export GITHUB_TOKEN=ghp_your_token
# ==============================================================
set -euo pipefail

# ── 設定 ──────────────────────────────────────────────────────
HUB_USER="superyc1121"
HUB_REPO="comfyui"
GITHUB_REPO="Comfy-Org/ComfyUI"
CUDA_TAG="13.0.0-cudnn-runtime-ubuntu24.04"
TORCH_INDEX="cu130"
EASY_INSTALL_NODES="standard"
FORCE=false
CHECK_ONLY=false
NO_PUSH=false
VERSION_OVERRIDE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/auto-update.log"
VERSION_FILE="${SCRIPT_DIR}/.last-built-version"

# ── 顏色 / log ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RESET='\033[0m'
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { local m="[$(_ts)][INFO ] $*"; echo -e "${CYAN}${m}${RESET}"; echo "$m" >> "$LOG_FILE"; }
ok()   { local m="[$(_ts)][ OK  ] $*"; echo -e "${GREEN}${m}${RESET}"; echo "$m" >> "$LOG_FILE"; }
warn() { local m="[$(_ts)][WARN ] $*"; echo -e "${YELLOW}${m}${RESET}"; echo "$m" >> "$LOG_FILE"; }
die()  { local m="[$(_ts)][ERROR] $*"; echo -e "${RED}${m}${RESET}" >&2; echo "$m" >> "$LOG_FILE"; exit 1; }

usage() { sed -n '3,28p' "$0" | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)      FORCE=true;        shift   ;;
        -c|--check-only) CHECK_ONLY=true;   shift   ;;
        -v|--version)    VERSION_OVERRIDE="$2"; shift 2 ;;
        -t|--torch)      TORCH_INDEX="$2";  shift 2 ;;
        --cuda)          CUDA_TAG="$2";     shift 2 ;;
        -n|--easy-install-nodes) EASY_INSTALL_NODES="$2"; shift 2 ;;
        --no-push)       NO_PUSH=true;      shift   ;;
        -h|--help)       usage ;;
        *) die "未知參數: $1，使用 -h 查看說明" ;;
    esac
done

[[ "$EASY_INSTALL_NODES" == "standard" || "$EASY_INSTALL_NODES" == "none" ]] \
    || die "--easy-install-nodes 僅接受 standard 或 none"

command -v docker &>/dev/null || die "找不到 docker"
command -v curl   &>/dev/null || die "找不到 curl，請執行: apt-get install -y curl"

log "=== ComfyUI Docker Auto-Update 開始 ==="

# ── Step 1：查 GitHub 最新 Release（或使用 --version 指定版本）───
if [[ -n "$VERSION_OVERRIDE" ]]; then
    LATEST_VERSION="$VERSION_OVERRIDE"
    log "使用手動指定版本: ${LATEST_VERSION}"
else
log "查詢 GitHub 最新 Release: ${GITHUB_REPO}"

GH_HEADERS=(-H "User-Agent: ComfyUI-Docker-AutoUpdate/1.0" -H "Accept: application/vnd.github.v3+json")
[[ -n "${GITHUB_TOKEN:-}" ]] && GH_HEADERS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

GH_JSON=$(curl -fsSL "${GH_HEADERS[@]}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest") \
    || die "GitHub API 查詢失敗"

LATEST_VERSION=$(echo "$GH_JSON" | grep -m1 '"tag_name"'     | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
RELEASE_DATE=$(echo  "$GH_JSON"  | grep -m1 '"published_at"' | sed 's/.*"published_at": *"\([^"]*\)".*/\1/')
[[ -z "$LATEST_VERSION" ]] && die "無法解析 GitHub Release tag"

log "GitHub 最新版本: ${LATEST_VERSION}（發布於 ${RELEASE_DATE}）"
fi

# 防呆：--version 誤填 URL 或 GitHub API 解析失敗，會做出無效的 docker tag
case "$LATEST_VERSION" in
    *://*|*/*|""|null)
        die "解析出的版本無效: '${LATEST_VERSION}'（需為 v0.34.0 這類 tag，不可為 URL）"
        ;;
esac

[[ "$CHECK_ONLY" == true ]] && {
    CURRENT_VERSION=$([[ -f "$VERSION_FILE" ]] && cat "$VERSION_FILE" || echo "（未記錄）")
    echo "  最新版本 : ${LATEST_VERSION}"
    echo "  本機版本 : ${CURRENT_VERSION}"
    [[ "${LATEST_VERSION}-${TORCH_INDEX}" == "$CURRENT_VERSION" ]] \
        && ok "已是最新版本。" || warn "有新版本可更新！"
    exit 0
}

# ── Step 2：查詢 Docker Hub tag 是否存在 ─────────────────────
VERSIONED_TAG="${LATEST_VERSION}-${TORCH_INDEX}"
log "查詢 Docker Hub: ${HUB_USER}/${HUB_REPO}:${VERSIONED_TAG}"

TAG_EXISTS=false
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://hub.docker.com/v2/repositories/${HUB_USER}/${HUB_REPO}/tags/${VERSIONED_TAG}")

if [[ "$HTTP_CODE" == "200" ]]; then
    warn "Tag ${VERSIONED_TAG} 已存在於 Docker Hub"
    TAG_EXISTS=true
elif [[ "$HTTP_CODE" == "404" ]]; then
    log "Tag ${VERSIONED_TAG} 尚未在 Docker Hub 上，需要 Build & Push"
else
    warn "Docker Hub 查詢回傳 HTTP ${HTTP_CODE}，繼續執行..."
fi

# ── Step 3：決定是否 Build ────────────────────────────────────
if [[ "$TAG_EXISTS" == true && "$FORCE" == false ]]; then
    ok "已是最新版本（${VERSIONED_TAG}），無需 Build。"
    log "=== 完成（無更新）==="
    exit 0
fi
[[ "$TAG_EXISTS" == true && "$FORCE" == true ]] && warn "--force 指定，強制重建 ${VERSIONED_TAG}"

# ── Step 4：Build & Push（原 build-push.sh 邏輯已內建於此）───
DATE_SUFFIX=$(date +%m%d)
FULL_TAG="${HUB_USER}/${HUB_REPO}:${LATEST_VERSION}-${TORCH_INDEX}-${DATE_SUFFIX}"
LATEST_TAG="${HUB_USER}/${HUB_REPO}:latest"
REBUILD_DATA_TAG="${HUB_USER}/${HUB_REPO}:rebuild-data"
# devel tag 用於建置 llama-cpp-python 的 CUDA wheel（含 nvcc）
CUDA_TAG_DEVEL="${CUDA_TAG/runtime/devel}"

log "開始 Build: ${LATEST_VERSION} (CUDA: ${CUDA_TAG}, Torch: ${TORCH_INDEX}, Nodes: ${EASY_INSTALL_NODES})"
log "Tags: ${FULL_TAG} / ${LATEST_TAG} / ${REBUILD_DATA_TAG}"

docker build \
    --platform linux/amd64 \
    --build-arg "COMFYUI_VERSION=${LATEST_VERSION}" \
    --build-arg "CUDA_TAG=${CUDA_TAG}" \
    --build-arg "CUDA_TAG_DEVEL=${CUDA_TAG_DEVEL}" \
    --build-arg "TORCH_INDEX=${TORCH_INDEX}" \
    --build-arg "EASY_INSTALL_NODES=${EASY_INSTALL_NODES}" \
    -t "$FULL_TAG" \
    -t "$LATEST_TAG" \
    -t "$REBUILD_DATA_TAG" \
    "$SCRIPT_DIR" \
    || die "Docker build 失敗"

ok "Build 完成: ${FULL_TAG}"

if [[ "$NO_PUSH" == true ]]; then
    warn "--no-push 指定，跳過 push。"
else
    docker push "$FULL_TAG"         || die "Push 失敗: ${FULL_TAG}"
    docker push "$LATEST_TAG"       || die "Push 失敗: ${LATEST_TAG}"
    docker push "$REBUILD_DATA_TAG" || die "Push 失敗: ${REBUILD_DATA_TAG}"
    ok "Build & Push 成功: ${FULL_TAG}"
fi

# ── Step 5：記錄版本 ──────────────────────────────────────────
echo "${VERSIONED_TAG}" > "$VERSION_FILE"
ok "=== 完成（已更新至 ${VERSIONED_TAG}）==="
