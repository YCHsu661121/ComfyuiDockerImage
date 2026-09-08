#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# entrypoint.sh — 自動偵測 VRAM 最大的 GPU，作為 ComfyUI 主卡
#
# 邏輯：
#   1. 呼叫 nvidia-smi 列出所有可見 GPU 的 index 與 VRAM (MiB)
#   2. 選出 VRAM 最大的 GPU index
#   3. 只有單一 GPU 可見時才加上 --cuda-device <index>
#
# 在 comfyui-gpu0 / comfyui-gpu1 容器中，NVIDIA_VISIBLE_DEVICES 只映射一張卡，
# nvidia-smi 只看到 index=0，因此永遠選到該卡，行為與原來一致。
#
# 當容器同時看到多張 GPU（雙 GPU 單容器模式，搭配 ComfyUI-MultiGPU 節點）時，
# --cuda-device 會把 CUDA_VISIBLE_DEVICES 收斂成單張卡，導致節點無法選到另一張，
# 因此這種情況下不加該參數，讓所有可見 GPU 都留給 ComfyUI-MultiGPU 節點分派。
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Accept legacy `python main.py ...` commands from existing Compose files and
# docker run invocations while retaining the initialization below.
if [[ "${1:-}" == "python" && "${2:-}" == "main.py" ]]; then
    shift 2
fi

BEST_GPU=0
BEST_GPU_VRAM_MIB=0
GPU_COUNT=0

if command -v nvidia-smi &>/dev/null; then
    # 輸出格式：  0, 16376
    #            1, 24576
    GPU_LIST=$(nvidia-smi --query-gpu=index,memory.total --format=csv,noheader,nounits || true)
    GPU_COUNT=$(echo "${GPU_LIST}" | grep -c . || true)
    read -r BEST_GPU BEST_GPU_VRAM_MIB <<< "$(echo "${GPU_LIST}" | awk -F',' '
            {
                idx = $1; gsub(/ /, "", idx)
                mem = $2; gsub(/ /, "", mem)
                if (mem + 0 > max + 0) { max = mem + 0; best = idx }
            }
            END { print (best != "" ? best : 0), (max != "" ? max : 0) }
        ')"
fi

CUDA_DEVICE_ARGS=()
if [[ "${GPU_COUNT}" -le 1 ]]; then
    CUDA_DEVICE_ARGS=(--cuda-device "${BEST_GPU}")
    echo "[entrypoint] Detected GPU ${BEST_GPU} as primary (largest VRAM)"
else
    echo "[entrypoint] Detected ${GPU_COUNT} visible GPUs; leaving all visible for ComfyUI-MultiGPU node dispatch (primary candidate: GPU ${BEST_GPU})"
fi

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

# ── LLM GGUF 模型（容器啟動時才下載，不烘進 image；設 SKIP_LLM_DOWNLOAD=1 可關閉）──
# 供 llama-cpp-python / MiniMaxH3-Prompt-Writer Direct GGUF 使用
# 來源: https://huggingface.co/unsloth/gemma-4-12b-it-GGUF
# 依偵測到的 VRAM 自動挑 quant 等級；沒偵測到 GPU（純 CPU）時不下載。
# 可用 LLM_QUANT_OVERRIDE 強制指定（例如 UD-Q4_K_XL），跳過自動偵測。
# 在背景執行，避免大檔案下載卡住 ComfyUI 啟動（多 GPU 也能立即可用）。
select_llm_quant() {
    local vram_mib="$1"
    if   (( vram_mib >= 28672 )); then echo "UD-Q8_K_XL"
    elif (( vram_mib >= 20480 )); then echo "UD-Q6_K_XL"
    elif (( vram_mib >= 14336 )); then echo "UD-Q5_K_XL"
    elif (( vram_mib >= 11264 )); then echo "UD-Q4_K_XL"
    elif (( vram_mib >= 8192  )); then echo "UD-Q3_K_XL"
    elif (( vram_mib >= 6144  )); then echo "UD-IQ3_XXS"
    else echo ""
    fi
}

if [[ "${SKIP_LLM_DOWNLOAD:-0}" != "1" ]]; then
    (
        LLM_QUANT="${LLM_QUANT_OVERRIDE:-$(select_llm_quant "${BEST_GPU_VRAM_MIB}")}"

        if [[ -z "$LLM_QUANT" ]]; then
            echo "[entrypoint] No/insufficient GPU VRAM detected (${BEST_GPU_VRAM_MIB} MiB); skipping Gemma 4 GGUF auto-download"
        else
            LLM_DIR="/app/models/LLM/gemma-4-12b"
            mkdir -p "$LLM_DIR"

            download_llm_file() {
                local url="$1" dest="$2" label="$3"
                if [[ -f "$dest" ]]; then
                    return 0
                fi
                echo "[entrypoint] Downloading ${label}..."
                if wget --progress=dot:giga -c -O "${dest}.part" "$url"; then
                    mv "${dest}.part" "$dest"
                else
                    echo "[entrypoint] WARNING: ${label} download failed, will retry on next start"
                fi
            }

            echo "[entrypoint] Selected Gemma 4 12B quant ${LLM_QUANT} for detected VRAM (${BEST_GPU_VRAM_MIB} MiB)"

            download_llm_file \
                "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-${LLM_QUANT}.gguf" \
                "${LLM_DIR}/gemma-4-12b-it-${LLM_QUANT}.gguf" \
                "Gemma 4 12B GGUF (${LLM_QUANT})"

            download_llm_file \
                "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/mmproj-BF16.gguf" \
                "${LLM_DIR}/mmproj-BF16.gguf" \
                "Gemma 4 12B mmproj (BF16, ~175MB)"
        fi
    ) &
    disown
else
    echo "[entrypoint] SKIP_LLM_DOWNLOAD=1 set; skipping Gemma 4 GGUF auto-download"
fi

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    "${CUDA_DEVICE_ARGS[@]}" \
    --enable-manager \
    "$@"
