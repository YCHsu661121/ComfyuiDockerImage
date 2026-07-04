#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# entrypoint.sh — 自動偵測 VRAM 最大的 GPU，作為 ComfyUI 主卡
#
# 邏輯：
#   1. 呼叫 nvidia-smi 列出所有可見 GPU 的 index 與 VRAM (MiB)
#   2. 選出 VRAM 最大的 GPU index
#   3. 以 --cuda-device <index> 啟動 ComfyUI
#
# 在 comfyui-gpu0 / comfyui-gpu1 容器中，NVIDIA_VISIBLE_DEVICES 只映射一張卡，
# nvidia-smi 只看到 index=0，因此永遠選到該卡，行為與原來一致。
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BEST_GPU=0

if command -v nvidia-smi &>/dev/null; then
    # 輸出格式：  0, 16376
    #            1, 24576
    BEST_GPU=$(nvidia-smi \
        --query-gpu=index,memory.total \
        --format=csv,noheader,nounits \
        | awk -F',' '
            {
                idx = $1; gsub(/ /, "", idx)
                mem = $2; gsub(/ /, "", mem)
                if (mem + 0 > max + 0) { max = mem + 0; best = idx }
            }
            END { print (best != "" ? best : 0) }
        ')
fi

echo "[entrypoint] Detected GPU ${BEST_GPU} as primary (largest VRAM)"

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --cuda-device "${BEST_GPU}" \
    --enable-manager \
    "$@"
