#!/usr/bin/env bash
# ==============================================================
# ComfyUI Docker — Linux 自動更新腳本
# 功能：查詢 GitHub 最新 Release → 比對本機版本 → Pull 新 image → 重啟容器
#
# Usage : bash update.sh [OPTIONS]
#
#   -f, --force       強制 pull，即使已是最新版
#   -c, --check-only  只顯示版本資訊，不 pull
#   -r, --no-restart  pull 後不自動重啟容器
#   -h, --help        顯示說明
#
# 搭配 cron 排程（每週一 08:00）：
#   0 8 * * 1 /path/to/update.sh >> /path/to/auto-update.log 2>&1
# ==============================================================
set -euo pipefail

# ── 設定 ──────────────────────────────────────────────────────
HUB_IMAGE="superyc1121/comfyui"
GITHUB_REPO="Comfy-Org/ComfyUI"
CONTAINER_NAME="comfyui"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/.last-pulled-version"

# ── 選項 ──────────────────────────────────────────────────────
FORCE=false
CHECK_ONLY=false
NO_RESTART=false

# ── 顏色 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RESET='\033[0m'
log()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')][INFO ] ${CYAN}$*${RESET}"; }
ok()   { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')][ OK  ] ${GREEN}$*${RESET}"; }
warn() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')][WARN ] ${YELLOW}$*${RESET}"; }
die()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')][ERROR] ${RED}$*${RESET}" >&2; exit 1; }

usage() { sed -n '3,18p' "$0" | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)       FORCE=true;      shift ;;
        -c|--check-only)  CHECK_ONLY=true; shift ;;
        -r|--no-restart)  NO_RESTART=true; shift ;;
        -h|--help)        usage ;;
        *) die "未知參數: $1，使用 -h 查看說明" ;;
    esac
done

# ── 前置檢查 ──────────────────────────────────────────────────
command -v docker   &>/dev/null || die "找不到 docker，請先安裝 Docker Engine"
command -v curl     &>/dev/null || die "找不到 curl，請執行: apt-get install -y curl"

log "=== ComfyUI Docker 自動更新開始 ==="

# ── Step 1：查 GitHub 最新 Release ────────────────────────────
log "查詢 GitHub 最新 Release: ${GITHUB_REPO}"

GH_HEADERS=(-H "User-Agent: ComfyUI-Docker-Update/1.0" -H "Accept: application/vnd.github.v3+json")
[[ -n "${GITHUB_TOKEN:-}" ]] && GH_HEADERS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

GH_JSON=$(curl -fsSL "${GH_HEADERS[@]}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest") \
    || die "GitHub API 查詢失敗（網路問題？）"

LATEST_VERSION=$(echo "$GH_JSON" | grep -m1 '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
RELEASE_DATE=$(echo "$GH_JSON"   | grep -m1 '"published_at"' | sed 's/.*"published_at": *"\([^"]*\)".*/\1/')

[[ -z "$LATEST_VERSION" ]] && die "無法解析 GitHub Release tag"
log "GitHub 最新版本: ${LATEST_VERSION}（發布於 ${RELEASE_DATE}）"

# ── Step 2：比對本機已 pull 的版本 ────────────────────────────
CURRENT_VERSION=""
[[ -f "$VERSION_FILE" ]] && CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

if [[ -n "$CURRENT_VERSION" ]]; then
    log "本機已 pull 版本: ${CURRENT_VERSION}"
else
    log "本機尚無版本記錄，首次 pull"
fi

if [[ "$CHECK_ONLY" == true ]]; then
    echo ""
    echo "  最新版本 : ${LATEST_VERSION}"
    echo "  本機版本 : ${CURRENT_VERSION:-（未記錄）}"
    [[ "$LATEST_VERSION" == "$CURRENT_VERSION" ]] \
        && ok "已是最新版本。" \
        || warn "有新版本可更新！執行 bash update.sh 進行更新。"
    exit 0
fi

if [[ "$LATEST_VERSION" == "$CURRENT_VERSION" && "$FORCE" == false ]]; then
    ok "已是最新版本（${LATEST_VERSION}），無需更新。"
    log "=== 完成（無更新）==="
    exit 0
fi

[[ "$FORCE" == true && "$LATEST_VERSION" == "$CURRENT_VERSION" ]] \
    && warn "--force 指定，強制重新 pull ${LATEST_VERSION}"

# ── Step 3：Pull image ─────────────────────────────────────────
FULL_TAG="${HUB_IMAGE}:${LATEST_VERSION}"
LATEST_TAG="${HUB_IMAGE}:latest"

log "拉取 image: ${FULL_TAG}"
docker pull "${FULL_TAG}"

log "同步更新 latest tag"
docker pull "${LATEST_TAG}"

ok "Pull 完成: ${FULL_TAG}"

# ── Step 4：重啟容器（若正在執行）────────────────────────────
if [[ "$NO_RESTART" == false ]]; then
    if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
        log "重啟容器 '${CONTAINER_NAME}'..."
        docker stop  "${CONTAINER_NAME}"
        docker rm    "${CONTAINER_NAME}"
        log "請執行 bash run.sh 以新 image 重新啟動容器"
    elif docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
        warn "容器 '${CONTAINER_NAME}' 存在但未執行，已略過重啟"
    else
        warn "找不到容器 '${CONTAINER_NAME}'，請執行 bash run.sh 啟動"
    fi
else
    warn "--no-restart 指定，跳過重啟"
fi

# ── Step 5：清理舊 image（保留最近兩個版本）─────────────────
log "清理懸空 image..."
docker image prune -f &>/dev/null || true

# ── Step 6：記錄版本 ──────────────────────────────────────────
echo "$LATEST_VERSION" > "$VERSION_FILE"

ok "=== 更新完成：${CURRENT_VERSION:-首次} → ${LATEST_VERSION} ==="
