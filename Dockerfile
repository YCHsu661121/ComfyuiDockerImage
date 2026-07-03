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
ARG CUDA_TAG=12.6.3-cudnn-runtime-ubuntu22.04
FROM nvidia/cuda:${CUDA_TAG}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ---------- System dependencies ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
        wget \
        git \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxrender1 \
        libxext6 \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3.12 \
        python3.12-dev \
        python3.12-venv \
    && rm -rf /var/lib/apt/lists/*

# ---------- Bootstrap pip for Python 3.12 ----------
RUN wget -qO /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python3.12 /tmp/get-pip.py \
    && rm /tmp/get-pip.py \
    && update-alternatives --install /usr/bin/python  python  /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# ---------- Clone ComfyUI ----------
ARG COMFYUI_VERSION=v0.27.0
WORKDIR /app
RUN git clone --depth 1 --branch ${COMFYUI_VERSION} \
        https://github.com/Comfy-Org/ComfyUI.git .

# ---------- PyTorch (可切換 cu126 / cu130) + ComfyUI dependencies ----------
ARG TORCH_INDEX=cu126
RUN python -m pip install --upgrade pip \
    && python -m pip install \
        torch torchvision torchaudio \
        --extra-index-url https://download.pytorch.org/whl/${TORCH_INDEX} \
    && python -m pip install -r requirements.txt

# ---------- ComfyUI-Manager dependencies ----------
RUN python -m pip install -r manager_requirements.txt

# ---------- Persistent data (mount at runtime) ----------
VOLUME ["/app/models", "/app/output", "/app/input", "/app/custom_nodes"]

EXPOSE 8188

# ComfyUI-Manager 為選用，啟用時自行加上 --enable-manager
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--enable-manager"]
