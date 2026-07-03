# ComfyUI — Docker 部署說明

> **Source** : [Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI) v0.27.0  
> **Image**  : [`superyc1121/comfyui`](https://hub.docker.com/r/superyc1121/comfyui)  
> **GPU**    : NVIDIA CUDA 12.6（驅動 UMD ≥ 12.6，含 13.3+）  
> **License**: GPL-3.0

---

## 目錄

- [系統需求](#系統需求)
- [快速開始](#快速開始)
- [Pull Image](#pull-image)
- [啟動方式](#啟動方式)
  - [單 GPU](#單-gpu)
  - [雙 GPU 各自獨立](#雙-gpu-各自獨立)
  - [純 CPU（無 GPU）](#純-cpu無-gpu)
- [Volume 掛載說明](#volume-掛載說明)
- [常用 CLI 參數](#常用-cli-參數)
- [自行 Build & Push](#自行-build--push)
  - [切換 cu130（CUDA 13.x 最佳化）](#切換-cu130cuda-13x-最佳化)
- [自動更新](#自動更新)
- [目錄結構](#目錄結構)
- [常見問題](#常見問題)

---

## 系統需求

| 項目 | 最低 | 建議 |
|------|------|------|
| OS | Linux / Windows (WSL2) / macOS | Ubuntu 22.04 / Windows 11 |
| Docker | 24.x | 29.x |
| NVIDIA Driver | UMD 12.6 | UMD 13.3+ |
| nvidia-container-toolkit | 必要 | 最新版 |
| VRAM | 4 GB | 12 GB+ |

> Windows 使用者需安裝 **Docker Desktop** 並啟用 WSL2 後端。

---

## 快速開始

```bash
# 1. Pull image
docker pull superyc1121/comfyui:latest

# 2. 建立本機資料夾
mkdir -p models output input custom_nodes

# 3. 啟動（單 GPU）
docker compose up comfyui
```

瀏覽器開啟 → `http://localhost:8188`

---

## Pull Image

```bash
# 最新版（對應 ComfyUI v0.27.0）
docker pull superyc1121/comfyui:latest

# 指定版本
docker pull superyc1121/comfyui:v0.27.0
```

---

## 啟動方式

### 單 GPU

使用 `docker-compose.yml` 中的 `comfyui` 服務，預設使用 GPU 0，所有 GPU 可見。

```bash
docker compose up comfyui
# 或背景執行
docker compose up -d comfyui
```

若不使用 Compose，直接 `docker run`：

```bash
docker run -d \
  --gpus all \
  --name comfyui \
  -p 8188:8188 \
  -v "$(pwd)/models:/app/models" \
  -v "$(pwd)/output:/app/output" \
  -v "$(pwd)/input:/app/input" \
  -v "$(pwd)/custom_nodes:/app/custom_nodes" \
  superyc1121/comfyui:latest
```

---

### 雙 GPU 各自獨立

兩個容器各鎖定一張 GPU，分別提供獨立的 ComfyUI 實例：

```bash
docker compose --profile multi-gpu up -d
```

| 容器 | GPU | 網址 |
|------|-----|------|
| `comfyui-gpu0` | GPU 0 | http://localhost:8188 |
| `comfyui-gpu1` | GPU 1 | http://localhost:8189 |

> ComfyUI 是單 GPU 設計，無法在一個實例內同時使用多張 GPU。  
> 雙 GPU 平行最佳做法為兩個獨立容器。

---

### 純 CPU（無 GPU）

```bash
docker run -d \
  --name comfyui-cpu \
  -p 8188:8188 \
  -v "$(pwd)/models:/app/models" \
  -v "$(pwd)/output:/app/output" \
  superyc1121/comfyui:latest \
  python main.py --listen 0.0.0.0 --port 8188 --cpu
```

---

## Volume 掛載說明

容器內路徑皆掛載為 Volume，**不會打包進 image**，保持 image 精簡。

| 容器內路徑 | 說明 | 放置內容 |
|-----------|------|----------|
| `/app/models` | 模型根目錄 | 見下表 |
| `/app/output` | 生成結果輸出 | PNG / WebP / 影片 |
| `/app/input` | 上傳用輸入圖片 | 任意圖片 |
| `/app/custom_nodes` | 自訂節點 | ComfyUI-Manager 安裝的節點 |

### models 子目錄

```
models/
├── checkpoints/   ← SD / SDXL / Flux ckpt、safetensors
├── vae/           ← VAE 模型
├── loras/         ← LoRA、LyCORIS
├── controlnet/    ← ControlNet 模型
├── clip/          ← CLIP 模型
├── unet/          ← 獨立 UNet（Flux 等）
├── diffusion_models/
├── upscale_models/
└── embeddings/    ← Textual Inversion
```

---

## 常用 CLI 參數

在 `docker run` 或 `docker-compose.yml` 的 `command` 欄位追加：

| 參數 | 說明 |
|------|------|
| `--cuda-device 1` | 強制使用 GPU 1 |
| `--cpu` | 改用 CPU 推理（慢） |
| `--lowvram` | 低 VRAM 模式（< 4 GB） |
| `--novram` | 極低 VRAM，全部 offload 到 RAM |
| `--preview-method auto` | 啟用即時預覽 |
| `--disable-api-nodes` | 關閉付費 API 節點 |
| `--enable-manager` | 啟用 ComfyUI-Manager |
| `--front-end-version Comfy-Org/ComfyUI_frontend@latest` | 使用最新前端 |

範例（docker run 追加參數）：

```bash
docker run -d --gpus all -p 8188:8188 \
  -v "$(pwd)/models:/app/models" \
  -v "$(pwd)/output:/app/output" \
  superyc1121/comfyui:latest \
  python main.py --listen 0.0.0.0 --port 8188 --preview-method auto --lowvram
```

---

## 自行 Build & Push

### 預設（CUDA 12.6 + cu126 PyTorch）

```powershell
.\build-push.ps1
```

### 切換 cu130（CUDA 13.x 最佳化）

適用於 UMD 13.3+ 驅動，可發揮 CUDA 13.0 全效能：

```powershell
.\build-push.ps1 `
  -CudaTag    "13.0.0-cudnn-runtime-ubuntu24.04" `
  -TorchIndex "cu130"
```

### 只 Build 不 Push

```powershell
.\build-push.ps1 -NoPush
```

### 指定 ComfyUI 版本

```powershell
.\build-push.ps1 -Version v0.28.0
```

---

## 自動更新

`auto-update.bat` / `auto-update.ps1` 會自動：
1. 查詢 GitHub 最新 Release tag
2. 檢查 Docker Hub 是否已有該 tag
3. 若沒有 → 自動執行 `build-push.ps1` 並推送

### 手動執行

```bat
:: 直接雙擊，或在命令提示字元執行
auto-update.bat

:: 強制重建（即使 tag 已存在）
auto-update.bat -Force

:: 只查版本，不 Build
auto-update.bat -CheckOnly
```

### 設定 GitHub Token（可選，避免 API rate limit）

```powershell
# 在環境變數設定一次（永久）
[System.Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "ghp_your_token", "User")
```

### 設定 Windows 工作排程器（每週自動執行）

```powershell
# 以系統管理員身份執行，每週一 08:00 自動更新
.\register-schedule.ps1

# 自訂排程（每週三 06:00）
.\register-schedule.ps1 -DayOfWeek Wednesday -Time "06:00"

# 手動觸發測試
Start-ScheduledTask -TaskName "ComfyUI-Docker-AutoUpdate"

# 移除排程
.\register-schedule.ps1 -Unregister
```

執行記錄會寫入 `auto-update.log`。

---

## 目錄結構

```
d:\Tools\comfyui\
├── Dockerfile              ← 主要建置腳本（ARG 支援 CUDA_TAG / TORCH_INDEX）
├── docker-compose.yml      ← 含單 GPU、雙 GPU (profile: multi-gpu) 設定
├── .dockerignore           ← 排除 models/output 等大型資料夾
├── build-push.ps1          ← 一鍵 Build + Push 的 PowerShell 腳本
├── auto-update.ps1         ← 自動偵測 GitHub 新版並 Build & Push
├── auto-update.bat         ← auto-update.ps1 的 .bat 包裝（雙擊或排程用）
├── register-schedule.ps1   ← 將 auto-update.bat 登錄到工作排程器
├── auto-update.log         ← (執行後產生) 自動更新記錄
├── .last-built-version     ← (執行後產生) 最後成功 Build 的版本號
├── README.md               ← 本說明文件
├── models/                 ← (執行時掛載) 模型放置位置
├── output/                 ← (執行時掛載) 輸出結果
├── input/                  ← (執行時掛載) 輸入圖片
└── custom_nodes/           ← (執行時掛載) 自訂節點
```

---

## 常見問題

**Q: `docker: Error response from daemon: could not select device driver "nvidia"`**  
A: 需安裝 [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)。

```bash
# Ubuntu
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

---

**Q: Windows 上 `--gpus` 無法使用**  
A: 確認 Docker Desktop → Settings → Resources → WSL Integration 已啟用，且安裝了最新 NVIDIA Windows Driver（≥ 527.41）。

---

**Q: 模型放在哪？**  
A: 在 `d:\Tools\comfyui\models\checkpoints\` 放入 `.safetensors` 或 `.ckpt`，  
   重啟容器後 ComfyUI 會自動掃描。

---

**Q: 如何安裝 Custom Node？**  
A: ComfyUI-Manager 已內建於映像中（`manager_requirements.txt` 已在 build 時安裝），
   且預設以 `--enable-manager` 啟動。直接在 UI 右上角點選 Manager 即可搜尋安裝節點，
   或手動把節點資料夾放進 `d:\Tools\comfyui\custom_nodes\`。

   Manager CLI 選項：
   - `--enable-manager`              啟用 Manager（映像預設已加）
   - `--enable-manager-legacy-ui`    使用舊版 Manager UI
   - `--disable-manager-ui`          保留背景功能（安全檢查、排程安裝）但關閉 UI

---

**Q: `Torch not compiled with CUDA enabled` 錯誤**  
A: 重新 build image 並確認 `TORCH_INDEX=cu126`（或 `cu130`）。

---

**Q: 想要用最新的 ComfyUI 版本**  
A: 執行 `.\build-push.ps1 -Version v0.28.0`（替換為最新 tag）。  
   最新版本請查看：https://github.com/Comfy-Org/ComfyUI/releases
