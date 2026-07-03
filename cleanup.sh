#!/usr/bin/env bash
# ==============================================================
# cleanup.sh — 刪除所有未使用的 Docker Image
#
# 模式（預設：dangling）：
#   bash cleanup.sh            # 只刪除 dangling image（無 tag 的孤立層）
#   bash cleanup.sh --all      # 刪除所有未被容器使用的 image
#   bash cleanup.sh --dry-run  # 預覽會刪什麼，不實際執行
# ==============================================================
set -euo pipefail

MODE="dangling"
DRY_RUN=false

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RESET='\033[0m'
log()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()  { echo -e "${RED}[ERR ]${RESET} $*" >&2; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --all)     MODE="all"  ;;
        --dry-run) DRY_RUN=true ;;
        *) die "未知參數: $arg（可用：--all、--dry-run）" ;;
    esac
done

command -v docker &>/dev/null || die "找不到 docker"

# ── 顯示目前磁碟使用量 ────────────────────────────────────────
log "目前 Docker 磁碟使用量："
docker system df
echo ""

# ── 預覽將被刪除的 image ─────────────────────────────────────
if [[ "$MODE" == "all" ]]; then
    warn "模式：--all（刪除所有未被任何容器使用的 image）"
    PREVIEW=$(docker images --filter "dangling=false" --format \
        "  {{.Repository}}:{{.Tag}}\t{{.Size}}\tID={{.ID}}" 2>/dev/null || true)
    DANGLING=$(docker images --filter "dangling=true" --format \
        "  <none>:<none>\t{{.Size}}\tID={{.ID}}" 2>/dev/null || true)
    USED=$(docker ps -a --format "{{.Image}}" 2>/dev/null || true)

    echo "▼ 將刪除（未被容器使用）："
    while IFS= read -r line; do
        IMG=$(echo "$line" | awk '{print $1}')
        if ! echo "$USED" | grep -qF "${IMG%%$'\t'*}"; then
            echo -e "  ${RED}$line${RESET}"
        fi
    done <<< "${PREVIEW}${DANGLING}"
else
    warn "模式：dangling（只刪除無 tag 的孤立 image）"
    DANGLING_LIST=$(docker images --filter "dangling=true" \
        --format "  <none>   ID={{.ID}}   Size={{.Size}}")
    if [[ -z "$DANGLING_LIST" ]]; then
        ok "沒有 dangling image，無需清理。"
        exit 0
    fi
    echo "▼ 將刪除："
    echo -e "${RED}${DANGLING_LIST}${RESET}"
fi
echo ""

# ── Dry-run 結束 ──────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
    warn "--dry-run 模式，不實際刪除。"
    exit 0
fi

# ── 確認 ──────────────────────────────────────────────────────
read -r -p "確定要刪除？[y/N] " CONFIRM
[[ "${CONFIRM,,}" == "y" ]] || { warn "已取消。"; exit 0; }

# ── 執行清理 ─────────────────────────────────────────────────
if [[ "$MODE" == "all" ]]; then
    docker image prune -a -f
else
    docker image prune -f
fi

echo ""
log "清理後 Docker 磁碟使用量："
docker system df
ok "完成！"
