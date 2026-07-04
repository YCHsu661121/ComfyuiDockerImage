#!/usr/bin/env bash
# ==============================================================
# check-models.sh — 掃描 /mnt/comfyui 各資料夾內容
# Usage : bash check-models.sh [BASE_DIR]
#         BASE_DIR 預設 /mnt/comfyui
# ==============================================================
set -euo pipefail

BASE_DIR="${1:-/mnt/comfyui}"

# ── 顏色 ──────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

# ── 輔助函式 ──────────────────────────────────────────────────
hr() { printf '%0.s─' {1..60}; echo; }

count_files() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \( \
        -iname "*.safetensors" -o -iname "*.ckpt" -o -iname "*.pt" -o \
        -iname "*.pth" -o -iname "*.bin" -o -iname "*.gguf" -o \
        -iname "*.pkl" -o -iname "*.npz" \) 2>/dev/null | wc -l
}

human_size() {
    du -sh "$1" 2>/dev/null | cut -f1
}

# ── 標題 ──────────────────────────────────────────────────────
echo
echo -e "${BOLD}${CYAN}ComfyUI 資料夾檢查${RESET}  →  ${BASE_DIR}"
hr

# ── 檢查 BASE_DIR 是否存在 ────────────────────────────────────
if [[ ! -d "$BASE_DIR" ]]; then
    echo -e "${RED}[ERROR]${RESET} 目錄不存在：${BASE_DIR}"
    echo "  請先建立：sudo mkdir -p ${BASE_DIR}"
    exit 1
fi

# ── Models 子目錄掃描 ─────────────────────────────────────────
MODELS_DIR="${BASE_DIR}/models"
MODEL_SUBDIRS=(
    checkpoints loras vae controlnet
    clip unet diffusion_models embeddings
    upscale_models hypernetworks style_models
    ipadapter insightface animatediff_models
)

echo -e "\n${BOLD}[ Models ]${RESET}  ${MODELS_DIR}"
hr

if [[ ! -d "$MODELS_DIR" ]]; then
    echo -e "  ${YELLOW}(目錄不存在)${RESET}"
else
    printf "  %-28s %6s  %s\n" "子資料夾" "檔案數" "大小"
    printf "  %-28s %6s  %s\n" "────────────────────────────" "──────" "──────"
    for sub in "${MODEL_SUBDIRS[@]}"; do
        dir="${MODELS_DIR}/${sub}"
        if [[ -d "$dir" ]]; then
            cnt=$(count_files "$dir")
            sz=$(human_size "$dir")
            if [[ "$cnt" -gt 0 ]]; then
                echo -e "  ${GREEN}✔${RESET} $(printf '%-28s' "$sub") $(printf '%6s' "$cnt")  ${sz}"
            else
                echo -e "  ${YELLOW}○${RESET} $(printf '%-28s' "$sub") $(printf '%6s' "0")  ${sz}"
            fi
        else
            echo -e "  ${RED}✘${RESET} $(printf '%-28s' "$sub")  ${RED}(不存在)${RESET}"
        fi
    done

    # 掃描非預設子目錄
    EXTRA=$(find "$MODELS_DIR" -mindepth 1 -maxdepth 1 -type d \
        | xargs -I{} basename {} \
        | grep -vxFf <(printf '%s\n' "${MODEL_SUBDIRS[@]}") || true)
    if [[ -n "$EXTRA" ]]; then
        echo
        echo -e "  ${CYAN}其他資料夾：${RESET}"
        while IFS= read -r sub; do
            dir="${MODELS_DIR}/${sub}"
            cnt=$(count_files "$dir")
            sz=$(human_size "$dir")
            echo -e "  ${CYAN}+${RESET} $(printf '%-28s' "$sub") $(printf '%6s' "$cnt")  ${sz}"
        done <<< "$EXTRA"
    fi
fi

# ── Custom Nodes ──────────────────────────────────────────────
NODES_DIR="${BASE_DIR}/custom_nodes"
echo -e "\n${BOLD}[ Custom Nodes ]${RESET}  ${NODES_DIR}"
hr

if [[ ! -d "$NODES_DIR" ]]; then
    echo -e "  ${YELLOW}(目錄不存在)${RESET}"
else
    mapfile -t nodes < <(find "$NODES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    if [[ ${#nodes[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}(空，尚未安裝任何插件)${RESET}"
    else
        for node in "${nodes[@]}"; do
            name=$(basename "$node")
            sz=$(human_size "$node")
            echo -e "  ${GREEN}✔${RESET} ${name}  ${CYAN}(${sz})${RESET}"
        done
        echo -e "\n  共 ${GREEN}${#nodes[@]}${RESET} 個插件"
    fi
fi

# ── Input / Output ────────────────────────────────────────────
echo -e "\n${BOLD}[ Input / Output ]${RESET}"
hr

for sub in input output; do
    dir="${BASE_DIR}/${sub}"
    if [[ -d "$dir" ]]; then
        cnt=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        sz=$(human_size "$dir")
        echo -e "  ${GREEN}✔${RESET} $(printf '%-10s' "$sub")  檔案：${cnt}  大小：${sz}"
    else
        echo -e "  ${RED}✘${RESET} $(printf '%-10s' "$sub")  ${RED}(不存在)${RESET}"
    fi
done

# ── 磁碟總覽 ──────────────────────────────────────────────────
echo -e "\n${BOLD}[ 磁碟使用 ]${RESET}"
hr
echo -e "  ${BASE_DIR} 總計：${BOLD}$(human_size "$BASE_DIR")${RESET}"
df -h "$BASE_DIR" 2>/dev/null | awk 'NR==2 {
    printf "  掛載點：%-20s 總：%s  已用：%s  可用：%s  使用率：%s\n",
           $6, $2, $3, $4, $5
}'

echo
