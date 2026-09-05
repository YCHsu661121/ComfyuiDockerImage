#!/usr/bin/env bash
set -euo pipefail

NODES_DIR=/opt/easy-install-custom-nodes
NODES_PROFILE=${1:-standard}

install_node() {
    local repository=$1
    local directory=$2
    local node_path="${NODES_DIR}/${directory}"

    git clone --depth 1 "${repository}" "${node_path}"

    if [[ -f "${node_path}/requirements.txt" ]]; then
        # Custom-node requirements must not replace the image's selected CUDA build.
        grep -viE '^(torch|torchvision|torchaudio)([<>=!~]|$)' \
            "${node_path}/requirements.txt" > /tmp/node-requirements.txt || true
        if [[ -s /tmp/node-requirements.txt ]]; then
            python -m pip install -r /tmp/node-requirements.txt
        fi
        rm -f /tmp/node-requirements.txt
    fi
}

mkdir -p "${NODES_DIR}"

case "${NODES_PROFILE}" in
    none)
        exit 0
        ;;
    standard)
        install_node https://github.com/Comfy-Org/ComfyUI-Manager comfyui-manager
        install_node https://github.com/yolain/ComfyUI-Easy-Use ComfyUI-Easy-Use
        install_node https://github.com/Fannovel16/comfyui_controlnet_aux comfyui_controlnet_aux
        install_node https://github.com/rgthree/rgthree-comfy rgthree-comfy
        install_node https://github.com/crystian/ComfyUI-Crystools ComfyUI-Crystools
        install_node https://github.com/MohammadAboulEla/ComfyUI-iTools comfyui-itools
        install_node https://github.com/city96/ComfyUI-GGUF ComfyUI-GGUF
        install_node https://github.com/gseth/ControlAltAI-Nodes controlaltai-nodes
        install_node https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch comfyui-inpaint-cropandstitch
        install_node https://github.com/1038lab/ComfyUI-RMBG comfyui-rmbg
        install_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite comfyui-videohelpersuite
        install_node https://github.com/shiimizu/ComfyUI-TiledDiffusion ComfyUI-TiledDiffusion
        install_node https://github.com/kijai/ComfyUI-KJNodes comfyui-kjnodes
        install_node https://github.com/kijai/ComfyUI-WanVideoWrapper ComfyUI-WanVideoWrapper
        install_node https://github.com/1038lab/ComfyUI-QwenVL ComfyUI-QwenVL
        install_node https://github.com/flybirdxx/ComfyUI-Qwen-TTS qwen3-tts-comfyui
        install_node https://github.com/Saganaki22/ComfyUI-FishAudioS2 ComfyUI-fish-audio-s2
        install_node https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler seedvr2-videoupscaler
        install_node https://github.com/chflame163/ComfyUI_LayerStyle comfyui_layerstyle
        install_node https://github.com/kijai/ComfyUI-WanAnimatePreprocess ComfyUI-WanAnimatePreprocess
        install_node https://gitlab.com/pixaroma/ComfyUI-Pixaroma.git ComfyUI-Pixaroma
        install_node https://github.com/yolain/ComfyUI-Easy-Sam3 comfyui-easy-sam3
        install_node https://github.com/kijai/ComfyUI-SCAIL-Pose ComfyUI-SCAIL-Pose
        install_node https://github.com/kijai/ComfyUI-MelBandRoFormer ComfyUI-MelBandRoFormer
        install_node https://github.com/capitan01R/ComfyUI-Krea2T-Enhancer ComfyUI-Krea2T-Enhancer
        install_node https://github.com/lbouaraba/comfyui-krea2edit ComfyUI-Krea2Edit
        install_node https://github.com/WASasquatch/was-node-suite-comfyui was-node-suite-comfyui
        install_node https://github.com/seitanism/ComfyUI-H3-Motion-Context-MultiRef ComfyUI-H3-Motion-Context-MultiRef
        install_node https://github.com/matlowai/ComfyUI-MAINodes ComfyUI-MAINodes
        install_node https://github.com/kijai/ComfyUI-SolAttn_triton ComfyUI-SolAttn_triton
        install_node https://github.com/LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler Comfyui_Minimax_h3_latent_Upscaler
        install_node https://github.com/ethanfel/ComfyUI-MiniMaxH3-Context-Loop ComfyUI-MiniMaxH3-Context-Loop
        ;;
    *)
        echo "Unsupported EASY_INSTALL_NODES profile: ${NODES_PROFILE}" >&2
        exit 2
        ;;
esac