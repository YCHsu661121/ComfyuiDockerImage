#Requires -Version 5.1
<#
.SYNOPSIS
    Build ComfyUI Docker image and push to Docker Hub.
.DESCRIPTION
    Builds superyc1121/comfyui with version tag and latest tag,
    then pushes both to Docker Hub.
.EXAMPLE
    .\build-push.ps1
    .\build-push.ps1 -Version v0.28.0
    .\build-push.ps1 -NoPush          # build only, skip push
#>
param(
    [string]$Version    = "v0.27.0",
    # CUDA base image tag — 切換 cu130 時改為 "13.0.0-cudnn-runtime-ubuntu24.04"
    [string]$CudaTag    = "12.6.3-cudnn-runtime-ubuntu22.04",
    # PyTorch wheel index — 搭配 CudaTag 使用：cu126 或 cu130
    [string]$TorchIndex = "cu126",
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HubUser   = "superyc1121"
$ImageName = "comfyui"
$FullTag   = "${HubUser}/${ImageName}:${Version}"
$LatestTag = "${HubUser}/${ImageName}:latest"
$ScriptDir = $PSScriptRoot

Write-Host "==> Building  : $FullTag" -ForegroundColor Cyan
Write-Host "==> Also tags : $LatestTag" -ForegroundColor Cyan
Write-Host ""

# ── Build ──────────────────────────────────────────────────────────────────
$buildArgs = @(
    "build",
    "--platform", "linux/amd64",
    "--build-arg", "COMFYUI_VERSION=$Version",
    "--build-arg", "CUDA_TAG=$CudaTag",
    "--build-arg", "TORCH_INDEX=$TorchIndex",
    "-t", $FullTag,
    "-t", $LatestTag,
    $ScriptDir
)

Write-Host "docker $($buildArgs -join ' ')" -ForegroundColor DarkGray
docker @buildArgs
if ($LASTEXITCODE -ne 0) { throw "docker build failed (exit $LASTEXITCODE)" }

Write-Host "`n==> Build complete!" -ForegroundColor Green

if ($NoPush) {
    Write-Host "==> -NoPush specified, skipping push." -ForegroundColor Yellow
    exit 0
}

# ── Login check ─────────────────────────────────────────────────────────────
Write-Host "`n==> Checking Docker Hub login..." -ForegroundColor Cyan
$loginInfo = docker info --format "{{.RegistryConfig.IndexConfigs}}" 2>&1
if ($loginInfo -notmatch "https://index.docker.io/v1/") {
    Write-Host "Not logged in to Docker Hub. Running docker login..." -ForegroundColor Yellow
    docker login
    if ($LASTEXITCODE -ne 0) { throw "docker login failed" }
}

# ── Push ────────────────────────────────────────────────────────────────────
foreach ($tag in @($FullTag, $LatestTag)) {
    Write-Host "`n==> Pushing $tag ..." -ForegroundColor Cyan
    docker push $tag
    if ($LASTEXITCODE -ne 0) { throw "docker push $tag failed (exit $LASTEXITCODE)" }
}

Write-Host "`n==> Done! Images available at:" -ForegroundColor Green
Write-Host "    https://hub.docker.com/r/${HubUser}/${ImageName}" -ForegroundColor White
