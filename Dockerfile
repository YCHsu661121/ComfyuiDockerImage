# ============================================================
# ComfyUI Docker Image — NVIDIA CUDA + Python 3.12
# Base: ComfyUI v0.27.0 (https://github.com/Comfy-Org/ComfyUI)
#
# CUDA 版本選擇 (build-arg):
#   --build-arg CUDA_TAG=12.6.3-cudnn-runtime-ubuntu22.04  (預設，兼容 UMD 13.3)
#   --build-arg CUDA_TAG=13.0.0-cudnn-runtime-ubuntu24.04  (完整 cu130 效能)
#   --build-arg TORCH_INDEX=cu130                          (搭配 cu130 映像使用)
#
# 驅動要求：CUDA UMD ≥ 12.6 即可；UMD 13.3 完全支援
# 多 GPU  ：docker-compose.yml 中 NVIDIA_VISIBLE_DEVICES=all / device_ids 控制
# ============================================================
ARG CUDA_TAG=13.0.0-cudnn-runtime-ubuntu24.04
FROM nvidia/cuda:${CUDA_TAG}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1

# ---------- System dependencies ----------
# Ubuntu 24.04 內建 Python 3.12，不需 deadsnakes PPA
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        git \
        python3 \
        python3-pip \
        python3-dev \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxrender1 \
        libxext6 \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# ---------- Clone ComfyUI ----------
ARG COMFYUI_VERSION=v0.27.0
WORKDIR /app
RUN git clone --depth 1 --branch ${COMFYUI_VERSION} \
        https://github.com/Comfy-Org/ComfyUI.git .

# ---------- PyTorch (可切換 cu126 / cu130) + ComfyUI dependencies ----------
ARG TORCH_INDEX=cu130
RUN python -m pip install --upgrade pip --ignore-installed \
    && python -m pip install \
        torch torchvision torchaudio \
        --extra-index-url https://download.pytorch.org/whl/${TORCH_INDEX} \
    && python -m pip install -r requirements.txt

# ---------- ComfyUI-Manager dependencies ----------
RUN python -m pip install -r manager_requirements.txt

# ---------- Persistent data (mount at runtime) ----------
VOLUME ["/app/models", "/app/output", "/app/input", "/app/custom_nodes"]

EXPOSE 8188

# ---------- Entrypoint: auto-select GPU with most VRAM ----------
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

CMD ["/app/entrypoint.sh"]
