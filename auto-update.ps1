#Requires -Version 5.1
<#
.SYNOPSIS
    ComfyUI Docker Auto-Update Orchestrator.
#>
param(
    [switch]$Force,
    [switch]$CheckOnly,
    [string]$Version    = "",
    [string]$CudaTag    = "13.0.0-cudnn-runtime-ubuntu24.04",
    [string]$TorchIndex = "cu130",
    [ValidateSet("standard", "none")]
    [string]$EasyInstallNodes = "standard",
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Settings --
$HubUser    = "superyc1121"
$HubRepo    = "comfyui"
$GithubRepo = "Comfy-Org/ComfyUI"
$ScriptDir  = $PSScriptRoot
$LogFile    = Join-Path $ScriptDir "auto-update.log"

# -- Functions --
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
        return Invoke-RestMethod -Uri $Url -Headers $Headers -TimeoutSec 30 -ErrorAction Stop
    } catch {
        throw "API Request Failed [$Url]: $_"
    }
}

# -- Step 1: Get Latest Release from GitHub (or use -Version override) --
Write-Log "=== ComfyUI Docker Auto-Update Start ==="

if ($Version) {
    $latestVersion = $Version
    $releaseDate   = "manual"
    $releaseUrl    = ""
    Write-Log "Using manually specified version: $latestVersion"
} else {
    Write-Log "Checking GitHub latest release: $GithubRepo"

    $ghUrl     = "https://api.github.com/repos/$GithubRepo/releases/latest"
    $ghHeaders = @{ "User-Agent" = "ComfyUI-Docker-AutoUpdate/1.0" }

    if ($env:GITHUB_TOKEN) {
        $ghHeaders["Authorization"] = "Bearer $env:GITHUB_TOKEN"
        Write-Log "Using GITHUB_TOKEN for authentication"
    }

    try {
        $release       = Invoke-ApiGet -Url $ghUrl -Headers $ghHeaders
        $latestVersion = $release.tag_name
        $releaseDate   = $release.published_at
        $releaseUrl    = $release.html_url
    } catch {
        Write-Log "Failed to fetch GitHub release: $_" "ERROR"
        exit 1
    }

    Write-Log "Latest GitHub Version: $latestVersion (Released: $releaseDate)"
    Write-Log "Release URL: $releaseUrl"
}

# 防呆：-Version 誤填 URL 或 GitHub API 解析失敗，會做出無效的 docker tag
if ([string]::IsNullOrEmpty($latestVersion) -or $latestVersion -match "://" -or $latestVersion -match "/") {
    Write-Log "Resolved version is invalid: '$latestVersion' (must be a tag like v0.34.0, not a URL)" "ERROR"
    exit 1
}

if ($CheckOnly) {
    Write-Log "CheckOnly mode enabled. Skipping Build and Push." "WARN"
    exit 0
}

# -- Step 2: Check Local Version Record --
# Tag format on Docker Hub includes a date suffix (e.g. v0.x.x-cu130-0812),
# so querying Docker Hub by tag is unreliable. Use the local record instead.
$versionFile = Join-Path $ScriptDir ".last-built-version"
$lastBuilt   = ""
if (Test-Path $versionFile) {
    $lastBuilt = (Get-Content $versionFile -Encoding UTF8).Trim()
    Write-Log "Last built version: $lastBuilt"
}

# -- Step 3: Decide Action --
if ($lastBuilt -eq $latestVersion -and -not $Force) {
    Write-Log "Already at latest version ($latestVersion). No update needed." "OK"
    Write-Log "=== Finished (No Update) ==="
    exit 0
}

if ($Force -and $lastBuilt -eq $latestVersion) {
    Write-Log "-Force flag detected. Forcing rebuild for $latestVersion" "WARN"
}

# -- Step 4: Build & Push (logic merged in, no longer calls build-push.ps1) --
# Tag format: ${Version}-${TorchIndex}-${MMdd}，例如 v0.31.0-cu130-0811
$dateSuffix     = Get-Date -Format "MMdd"
$fullTag        = "${HubUser}/${HubRepo}:${latestVersion}-${TorchIndex}-${dateSuffix}"
$latestTag      = "${HubUser}/${HubRepo}:latest"
$rebuildDataTag = "${HubUser}/${HubRepo}:rebuild-data"
# devel tag 才含 nvcc，用於建置 llama-cpp-python 的 CUDA wheel
$cudaTagDevel   = $CudaTag -replace "runtime", "devel"

Write-Log "Starting Build: $latestVersion (CUDA: $CudaTag, Torch: $TorchIndex, Nodes: $EasyInstallNodes)"
Write-Log "Tags: $fullTag / $latestTag / $rebuildDataTag"

try {
    $buildArgs = @(
        "build",
        "--platform", "linux/amd64",
        "--build-arg", "COMFYUI_VERSION=$latestVersion",
        "--build-arg", "CUDA_TAG=$CudaTag",
        "--build-arg", "CUDA_TAG_DEVEL=$cudaTagDevel",
        "--build-arg", "TORCH_INDEX=$TorchIndex",
        "--build-arg", "EASY_INSTALL_NODES=$EasyInstallNodes",
        "-t", $fullTag,
        "-t", $latestTag,
        "-t", $rebuildDataTag,
        $ScriptDir
    )
    docker @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed (exit code: $LASTEXITCODE)" }

    Write-Log "Build complete: $fullTag" "OK"

    if ($NoPush) {
        Write-Log "-NoPush specified. Skipping push phase." "WARN"
    } else {
        foreach ($tag in @($fullTag, $latestTag, $rebuildDataTag)) {
            docker push $tag
            if ($LASTEXITCODE -ne 0) { throw "Docker push failed for $tag (exit code: $LASTEXITCODE)" }
        }
        Write-Log "Build and Push successful: $fullTag" "OK"
    }
} catch {
    Write-Log "Build and Push failed: $_" "ERROR"
    exit 1
}

# -- Step 5: Update Version Record --
$versionFile = Join-Path $ScriptDir ".last-built-version"
Set-Content -Path $versionFile -Value $latestVersion -Encoding UTF8
Write-Log "Version record updated: $versionFile"
Write-Log "=== Finished (Updated to $latestVersion) ===" "OK"
