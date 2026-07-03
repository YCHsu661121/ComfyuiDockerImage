#Requires -Version 5.1
<#
.SYNOPSIS
    自動追蹤 ComfyUI GitHub 最新 Release，若 Docker Hub 尚無該版本則自動 Build & Push。
.DESCRIPTION
    1. 透過 GitHub API 取得 ComfyUI 最新 Release tag
    2. 查詢 Docker Hub 確認該 tag 是否已存在
    3. 若尚未存在 → 呼叫 build-push.ps1 自動 Build + Push
    4. 所有動作記錄至 auto-update.log

.EXAMPLE
    .\auto-update.ps1                     # 正常執行
    .\auto-update.ps1 -Force              # 強制重建（即使 tag 已存在）
    .\auto-update.ps1 -CheckOnly          # 只查版本，不 Build
    .\auto-update.ps1 -CudaTag "13.0.0-cudnn-runtime-ubuntu24.04" -TorchIndex cu130
#>
param(
    [switch]$Force,
    [switch]$CheckOnly,
    [string]$CudaTag    = "13.0.0-cudnn-runtime-ubuntu24.04",
    [string]$TorchIndex = "cu130"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── 設定 ────────────────────────────────────────────────────────────────────
$HubUser    = "superyc1121"
$HubRepo    = "comfyui"
$GithubRepo = "Comfy-Org/ComfyUI"
$ScriptDir  = $PSScriptRoot
$LogFile    = Join-Path $ScriptDir "auto-update.log"

# ── 工具函式 ─────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    switch ($Level) {
        "INFO"  { Write-Host $line -ForegroundColor Cyan }
        "OK"    { Write-Host $line -ForegroundColor Green }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "ERROR" { Write-Host $line -ForegroundColor Red }
    }
}

function Invoke-ApiGet {
    param([string]$Url, [hashtable]$Headers = @{})
    try {
        $resp = Invoke-RestMethod -Uri $Url -Headers $Headers `
                    -TimeoutSec 30 -ErrorAction Stop
        return $resp
    } catch {
        throw "API 請求失敗 [$Url]: $_"
    }
}

# ── Step 1：取得 GitHub 最新 Release ────────────────────────────────────────
Write-Log "=== ComfyUI Docker Auto-Update 開始 ==="
Write-Log "查詢 GitHub 最新 Release: $GithubRepo"

$ghUrl     = "https://api.github.com/repos/$GithubRepo/releases/latest"
$ghHeaders = @{ "User-Agent" = "ComfyUI-Docker-AutoUpdate/1.0" }

# 若設定了 GITHUB_TOKEN 環境變數則使用（避免 rate limit）
if ($env:GITHUB_TOKEN) {
    $ghHeaders["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    Write-Log "使用 GITHUB_TOKEN 認證"
}

$release       = Invoke-ApiGet -Url $ghUrl -Headers $ghHeaders
$latestVersion = $release.tag_name
$releaseDate   = $release.published_at
$releaseUrl    = $release.html_url

Write-Log "GitHub 最新版本: $latestVersion (發布於 $releaseDate)"
Write-Log "Release URL: $releaseUrl"

if ($CheckOnly) {
    Write-Log "CheckOnly 模式，跳過 Build & Push。" "WARN"
    exit 0
}

# ── Step 2：查詢 Docker Hub 該 tag 是否存在 ──────────────────────────────────
# Tag 格式與 build-push.ps1 一致：v0.27.0-cu130
$versionedTag = "${latestVersion}-${TorchIndex}"
Write-Log "查詢 Docker Hub: $HubUser/$HubRepo`:$versionedTag"

$tagExists = $false
try {
    $dhUrl  = "https://hub.docker.com/v2/repositories/$HubUser/$HubRepo/tags/$versionedTag"
    $tagInfo = Invoke-ApiGet -Url $dhUrl
    $pushedAt = $tagInfo.last_pushed
    Write-Log "Tag 已存在於 Docker Hub (最後推送: $pushedAt)" "WARN"
    $tagExists = $true
} catch {
    # 404 = tag 不存在，這是預期的
    if ($_ -match "404" -or $_ -match "Not Found") {
        Write-Log "Tag $versionedTag 尚未在 Docker Hub 上，需要 Build & Push"
        $tagExists = $false
    } else {
        Write-Log "Docker Hub 查詢錯誤（網路問題？繼續執行）: $_" "WARN"
        $tagExists = $false
    }
}

# ── Step 3：決定是否 Build ────────────────────────────────────────────────────
if ($tagExists -and -not $Force) {
    Write-Log "已是最新版本 ($latestVersion)，無需 Build。" "OK"
    Write-Log "=== 完成（無更新）==="
    exit 0
}

if ($Force -and $tagExists) {
    Write-Log "-Force 指定，強制重建 $latestVersion" "WARN"
}

# ── Step 4：呼叫 build-push.ps1 ──────────────────────────────────────────────
$buildScript = Join-Path $ScriptDir "build-push.ps1"
if (-not (Test-Path $buildScript)) {
    Write-Log "找不到 build-push.ps1: $buildScript" "ERROR"
    exit 1
}

Write-Log "開始 Build & Push: $latestVersion (CUDA: $CudaTag, Torch: $TorchIndex)"

try {
    & $buildScript `
        -Version    $latestVersion `
        -CudaTag    $CudaTag `
        -TorchIndex $TorchIndex

    if ($LASTEXITCODE -ne 0) { throw "build-push.ps1 結束碼: $LASTEXITCODE" }

    Write-Log "Build & Push 成功: $HubUser/$HubRepo`:$latestVersion" "OK"
} catch {
    Write-Log "Build & Push 失敗: $_" "ERROR"
    exit 1
}

# ── Step 5：更新版本記錄 ──────────────────────────────────────────────────────
$versionFile = Join-Path $ScriptDir ".last-built-version"
Set-Content -Path $versionFile -Value $latestVersion -Encoding UTF8
Write-Log "版本記錄已更新: $versionFile"
Write-Log "=== 完成（已更新至 $latestVersion）===" "OK"
