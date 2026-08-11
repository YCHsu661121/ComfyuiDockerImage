#Requires -Version 5.1
<#
.SYNOPSIS
    Build ComfyUI Docker image and push to Docker Hub.
.DESCRIPTION
    Builds superyc1121/comfyui with version tag, latest tag, and rebuild-data tag,
    then pushes all to Docker Hub.
#>
param(
    [string]$Version    = "v0.27.0",
    [string]$CudaTag    = "13.0.0-cudnn-runtime-ubuntu24.04",
    [string]$TorchIndex = "cu130",
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Settings --
$HubUser         = "superyc1121"
$ImageName       = "comfyui"

# 【格式更新】Tag format: ${Version}-${TorchIndex}-${MMdd}
# 例如：v0.31.0-cu130-0811
$DateSuffix      = Get-Date -Format "MMdd"
$FullTag         = "${HubUser}/${ImageName}:${Version}-${TorchIndex}-${DateSuffix}"

$LatestTag       = "${HubUser}/${ImageName}:latest"
$RebuildDataTag  = "${HubUser}/${ImageName}:rebuild-data"
$ScriptDir       = $PSScriptRoot

Write-Host "==> Building : $FullTag" -ForegroundColor Cyan
Write-Host "==> Also tags: $LatestTag" -ForegroundColor Cyan
Write-Host "==> Also tags: $RebuildDataTag" -ForegroundColor Cyan
Write-Host ""

# -- Build Phase --
$buildArgs = @(
    "build",
    "--platform", "linux/amd64",
    "--build-arg", "COMFYUI_VERSION=$Version",
    "--build-arg", "CUDA_TAG=$CudaTag",
    "--build-arg", "TORCH_INDEX=$TorchIndex",
    "-t", $FullTag,
    "-t", $LatestTag,
    "-t", $RebuildDataTag,
    $ScriptDir
)

Write-Host "Executing: docker $($buildArgs -join ' ')" -ForegroundColor DarkGray
docker @buildArgs
if ($LASTEXITCODE -ne 0) { throw "Docker build failed (exit code: $LASTEXITCODE)" }

Write-Host "`n==> Build complete!" -ForegroundColor Green

if ($NoPush) {
    Write-Host "==> -NoPush specified. Skipping push phase." -ForegroundColor Yellow
    exit 0
}

# -- Login Check Phase --
Write-Host "`n==> Checking Docker Hub login..." -ForegroundColor Cyan
$loginInfo = docker info --format "{{.RegistryConfig.IndexConfigs}}" 2>&1
if ($loginInfo -notmatch "https://index.docker.io/v1/") {
    Write-Host "Not logged in to Docker Hub. Please run 'docker login' manually." -ForegroundColor Yellow
}

# -- Push Phase --
$tagsToPush = @($FullTag, $LatestTag, $RebuildDataTag)
foreach ($tag in $tagsToPush) {
    Write-Host "`n==> Pushing tag: $tag ..." -ForegroundColor Cyan
    docker push $tag
    if ($LASTEXITCODE -ne 0) { throw "Docker push failed for $tag (exit code: $LASTEXITCODE)" }
}

Write-Host "`n==> All tasks completed successfully!" -ForegroundColor Green
Write-Host "Images are now available at:" -ForegroundColor White
Write-Host "    https://hub.docker.com/r/${HubUser}/${ImageName}" -ForegroundColor White
