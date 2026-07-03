#!/usr/bin/env bash
# ==============================================================
# build-push.sh — Linux 版 Build & Push ComfyUI Docker Image
# 對應 Windows 的 build-push.ps1
#
# Usage : bash build-push.sh [OPTIONS]
#
#   -v, --version <tag>   ComfyUI 版本，預設 v0.27.0
#   -c, --cuda <tag>      CUDA base image tag
#                         預設: 13.0.0-cudnn-runtime-ubuntu24.04
#   -t, --torch <index>   PyTorch wheel index，預設 cu130
#       --no-push         只 build，不 push
#   -h, --help            顯示說明
#
# 範例：
#   bash build-push.sh                            # 預設 cu130
#   bash build-push.sh -v v0.28.0                 # 指定版本
#   bash build-push.sh --no-push                  # 只 build
#   bash build-push.sh -c 12.6.3-cudnn-runtime-ubuntu22.04 -t cu126
# ==============================================================
set -euo pipefail

HUB_USER="superyc1121"
IMAGE_NAME="comfyui"
VERSION="v0.27.0"
CUDA_TAG="13.0.0-cudnn-runtime-ubuntu24.04"
TORCH_INDEX="cu130"
NO_PUSH=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RESET='\033[0m'
log()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()  { echo -e "${RED}[ERR ]${RESET} $*" >&2; exit 1; }

usage() { sed -n '3,18p' "$0" | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)  VERSION="$2";     shift 2 ;;
        -c|--cuda)     CUDA_TAG="$2";    shift 2 ;;
        -t|--torch)    TORCH_INDEX="$2"; shift 2 ;;
        --no-push)     NO_PUSH=true;     shift   ;;
        -h|--help)     usage ;;
        *) die "未知參數: $1，使用 -h 查看說明" ;;
    esac
done

command -v docker &>/dev/null || die "找不到 docker"

FULL_TAG="${HUB_USER}/${IMAGE_NAME}:${VERSION}-${TORCH_INDEX}"
LATEST_TAG="${HUB_USER}/${IMAGE_NAME}:latest"

log "Building  : ${FULL_TAG}"
log "Also tags : ${LATEST_TAG}"
echo ""

# ── Build ──────────────────────────────────────────────────────
docker build \
    --platform linux/amd64 \
    --build-arg "COMFYUI_VERSION=${VERSION}" \
    --build-arg "CUDA_TAG=${CUDA_TAG}" \
    --build-arg "TORCH_INDEX=${TORCH_INDEX}" \
    -t "${FULL_TAG}" \
    -t "${LATEST_TAG}" \
    "${SCRIPT_DIR}"

ok "Build complete!"

[[ "$NO_PUSH" == true ]] && { warn "--no-push 指定，跳過 push。"; exit 0; }

# ── Login check ────────────────────────────────────────────────
log "Checking Docker Hub login..."
if ! docker info 2>/dev/null | grep -q "Username"; then
    warn "尚未登入 Docker Hub，執行 docker login..."
    docker login
fi

# ── Push ───────────────────────────────────────────────────────
for tag in "$FULL_TAG" "$LATEST_TAG"; do
    log "Pushing ${tag} ..."
    docker push "${tag}"
done

ok "Done! Images available at:"
echo -e "  ${GREEN}https://hub.docker.com/r/${HUB_USER}/${IMAGE_NAME}${RESET}"
