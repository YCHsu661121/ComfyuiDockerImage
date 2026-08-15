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

# Accept legacy `python main.py ...` commands from existing Compose files and
# docker run invocations while retaining the initialization below.
if [[ "${1:-}" == "python" && "${2:-}" == "main.py" ]]; then
    shift 2
fi

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

# Seed baked Easy-Install nodes into the persistent mount without replacing user changes.
if [[ -d /opt/easy-install-custom-nodes ]]; then
    mkdir -p /app/custom_nodes
    for node_path in /opt/easy-install-custom-nodes/*; do
        [[ -d "$node_path" ]] || continue
        node_name=$(basename "$node_path")
        if [[ ! -e "/app/custom_nodes/${node_name}" ]]; then
            cp -a "$node_path" /app/custom_nodes/
            echo "[entrypoint] Installed bundled custom node: ${node_name}"
        fi
    done
fi

# ── 初始化預設設定（首次啟動或設定檔不存在）───────────────────────────
SETTINGS_FILE="/app/user/default/comfy.settings.json"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    cp /app/default-comfy.settings.json "$SETTINGS_FILE"
    echo "[entrypoint] Initialized default settings (Crystools monitors enabled)"
fi

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --cuda-device "${BEST_GPU}" \
    --enable-manager \
    "$@"
