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
  - [雙 GPU 協同（ComfyUI-MultiGPU）](#雙-gpu-協同comfyui-multigpu)
  - [純 CPU（無 GPU）](#純-cpu無-gpu)
- [Volume 掛載說明](#volume-掛載說明)
- [常用 CLI 參數](#常用-cli-參數)
- [自行 Build & Push](#自行-build--push)
  - [切換 cu130（CUDA 13.x 最佳化）](#切換-cu130cuda-13x-最佳化)
- [Easy-Install Custom Nodes](#easy-install-custom-nodes)
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
docker compose --profile multi-gpu up -d comfyui-gpu0 comfyui-gpu1
```

> 務必指定服務名稱。若省略（`docker compose --profile multi-gpu up -d`），
> Compose 會連同沒有 profile 的預設 `comfyui` 服務、以及同屬 `multi-gpu`
> profile 的 `comfyui-multigpu` 一起啟動，四個容器搶同一張 GPU 與
> port 8188，一定會啟動失敗。

| 容器 | GPU | 網址 |
|------|-----|------|
| `comfyui-gpu0` | GPU 0 | http://localhost:8188 |
| `comfyui-gpu1` | GPU 1 | http://localhost:8189 |

> ComfyUI 核心本身是單 GPU 設計，這個模式下兩個實例各自獨立、互不共用顯存，
> 適合「兩個人各用一張卡」或「兩個工作流各自平行跑」的情境。

---

### 雙 GPU 協同（ComfyUI-MultiGPU）

若想在**同一個** ComfyUI 實例中，把不同模型（例如 UNET、CLIP、VAE）分別載入到
GPU 0 / GPU 1 以節省單卡顯存或加速，使用 `comfyui-multigpu` 服務：

```bash
docker compose --profile multi-gpu up -d comfyui-multigpu
```

瀏覽器開啟 → `http://localhost:8190`

此服務讓容器同時看到兩張 GPU，`entrypoint.sh` 偵測到多於 1 張可見 GPU 時會自動
不加 `--cuda-device` 限制，兩張卡都留給 ComfyUI 進程。實際分派是在工作流節點上完成：
映像已內建 [pollockjj/ComfyUI-MultiGPU](https://github.com/pollockjj/ComfyUI-MultiGPU)，
載入模型的節點（如 `UNETLoaderMultiGPU`、`CLIPLoaderMultiGPU`）會多出 `device` 選項，
選擇 `cuda:0` 或 `cuda:1` 即可指定該模型載入的顯卡。

> 與「雙 GPU 各自獨立」模式互斥：兩者都會佔用實體 GPU，不建議同時啟動。

不使用 docker-compose 的話，`run.sh` 也支援同樣的效果：

```bash
bash run.sh -g all
```

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
├── embeddings/    ← Textual Inversion
└── LLM/           ← llama-cpp-python 用的 GGUF 語言模型（見下方「LLM 自動下載」）
```

### LLM 自動下載（容器啟動時，依偵測到的 VRAM 自動選 quant）

容器啟動（`docker run` / `docker compose up`）時，`entrypoint.sh` 會用偵測 GPU
的同一套邏輯讀出 VRAM 大小，自動挑選對應的 Gemma 4 12B quant 等級並下載到
`/app/models/LLM/gemma-4-12b/`（已存在的檔案不重抓，避免把大型 GGUF 烘進 image）：

| 偵測到的 VRAM | 下載的 quant | 檔案大小 |
|---|---|---|
| ≥ 28 GB | `UD-Q8_K_XL` | ~13.6 GB |
| ≥ 20 GB | `UD-Q6_K_XL` | ~10.7 GB |
| ≥ 14 GB | `UD-Q5_K_XL` | ~8.6 GB |
| ≥ 11 GB | `UD-Q4_K_XL` | ~7.4 GB |
| ≥ 8 GB | `UD-Q3_K_XL` | ~6.0 GB |
| ≥ 6 GB | `UD-IQ3_XXS` | ~4.6 GB |
| < 6 GB 或無 GPU | 不下載 | — |

另外固定下載 `mmproj-BF16.gguf`（約 175 MB，供影像輸入用的多模態投影器）。

來源：[unsloth/gemma-4-12b-it-GGUF](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF)，
供 [ComfyUI-MiniMaxH3-Prompt-Writer](https://github.com/duckyshell/ComfyUI-MiniMaxH3-Prompt-Writer) 的
Direct GGUF 模式使用。因掛載在 `/app/models` volume，下載一次後重啟容器不會重抓；
若換到不同 VRAM 等級的機器，會額外下載新等級的檔案，舊檔案需自行清理。

用 `LLM_QUANT_OVERRIDE` 可略過自動偵測、強制指定 quant（例如 `UD-Q6_K_XL`）：

```bash
docker run -e LLM_QUANT_OVERRIDE=UD-Q6_K_XL ...
```


若不需要、或想離線啟動，設定環境變數關閉：

```bash
docker run -e SKIP_LLM_DOWNLOAD=1 ...
```

```yaml
environment:
  - SKIP_LLM_DOWNLOAD=1
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

> `build-push.ps1` / `build-push.sh` 已移除，Build + Push 邏輯已併入
> `auto-update.ps1` / `auto-update.sh`（未指定 `-Version` 時會自動抓 GitHub 最新版）。

### 預設（CUDA 13.0 + cu130 PyTorch）

```powershell
.\auto-update.ps1 -Force
```

```bash
bash auto-update.sh --force
```

### 切換 cu126（相容 UMD 12.6）

```powershell
.\auto-update.ps1 -Force `
  -CudaTag    "12.6.3-cudnn-runtime-ubuntu22.04" `
  -TorchIndex "cu126"
```

```bash
bash auto-update.sh --force --cuda 12.6.3-cudnn-runtime-ubuntu22.04 --torch cu126
```

### 只 Build 不 Push

```powershell
.\auto-update.ps1 -Force -NoPush
```

```bash
bash auto-update.sh --force --no-push
```

### 指定 ComfyUI 版本

```powershell
.\auto-update.ps1 -Force -Version v0.28.0
```

```bash
bash auto-update.sh --force --version v0.28.0
```

## Easy-Install Custom Nodes

映像預設加入 Tavris1/ComfyUI-Easy-Install 的 `standard` 節點 profile：
ComfyUI-Manager、Easy-Use、ControlNet Aux、rgthree、iTools、GGUF、
ControlAltAI、Inpaint CropAndStitch、RMBG、VideoHelperSuite、TiledDiffusion、
KJNodes、WanVideoWrapper、QwenVL、Qwen-TTS、FishAudioS2、SeedVR2、LayerStyle、
WanAnimatePreprocess、Pixaroma、Easy-Sam3、SCAIL-Pose、MelBandRoFormer、
Krea2T-Enhancer、Krea2Edit、WAS Node Suite、H3-Motion-Context-MultiRef、
MAINodes、SolAttn_triton、Minimax-H3-Latent-Upscaler、MiniMaxH3-Context-Loop、
MultiGPU、MiniMaxH3-Prompt-Writer 與 MiniMaxH3-Director。

節點會先建置到映像內的範本目錄；容器首次啟動時才複製到持久化的
`/app/custom_nodes` 掛載目錄。既有同名節點不會被覆寫。自訂節點的
`requirements.txt` 會排除 `torch`、`torchvision` 與 `torchaudio`，以維持所選
CUDA PyTorch wheel。

若只需要基礎 ComfyUI，可在建置時停用這個 profile：

```powershell
.\auto-update.ps1 -EasyInstallNodes none -Force -NoPush
```

```bash
bash auto-update.sh --easy-install-nodes none --no-push --force
```

Nunchaku、SageAttention、FlashAttention、InsightFace 與 Trellis2 維持選用，
因為它們需要與 GPU 架構、PyTorch/CUDA 版本或模型授權相符的額外設定。

### llama-cpp-python（CUDA 加速，隨映像固定安裝）

映像會以 multi-stage build 先在含 `nvcc` 的 CUDA devel 階段（自動由
`CUDA_TAG` 推導出對應的 `-devel-` 版本）編譯出啟用 `GGML_CUDA` 的
`llama-cpp-python` wheel，再安裝進最終的 runtime 映像，讓 GGUF 格式的 LLM
節點（QwenVL、MAINodes 等）可使用 GPU 推理。因需要編譯，build 時間會拉長。

---

## 自動更新

`auto-update.bat` / `auto-update.ps1` 會自動：
1. 查詢 GitHub 最新 Release tag
2. 檢查 Docker Hub 是否已有該 tag
3. 若沒有 → 自動 Build + Push（邏輯已內建於 `auto-update.ps1`，不再依賴 `build-push.ps1`）

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
├── auto-update.ps1         ← 自動偵測 GitHub 新版並 Build & Push（含 Build+Push 邏輯）
├── auto-update.sh          ← auto-update.ps1 的 Linux/bash 版本
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
A: 執行 `.\auto-update.ps1 -Force`（或 `bash auto-update.sh --force`）即會自動抓取 GitHub
   最新 Release 並重建；也可用 `-Version v0.28.0` / `--version v0.28.0` 指定特定版本。  
   最新版本請查看：https://github.com/Comfy-Org/ComfyUI/releases
