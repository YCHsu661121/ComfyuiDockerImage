@echo off
:: ==============================================================
:: cleanup.bat — 刪除所有未使用的 Docker Image
::
:: 模式（預設：dangling）：
::   cleanup.bat            只刪除 dangling image（無 tag 的孤立層）
::   cleanup.bat --all      刪除所有未被容器使用的 image
::   cleanup.bat --dry-run  預覽會刪什麼，不實際執行
:: ==============================================================
setlocal EnableDelayedExpansion

set "MODE=dangling"
set "DRY_RUN=0"

:: ── 解析參數 ──────────────────────────────────────────────────
:parse_args
if "%~1"=="" goto :check_docker
if /i "%~1"=="--all"     set "MODE=all"     & shift & goto :parse_args
if /i "%~1"=="--dry-run" set "DRY_RUN=1"    & shift & goto :parse_args
echo [ERR] 未知參數: %~1  （可用：--all、--dry-run）
exit /b 1

:check_docker
docker version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERR] 找不到 docker，請確認 Docker Desktop 已啟動
    exit /b 1
)

:: ── 顯示目前磁碟使用量 ────────────────────────────────────────
echo.
echo [INFO] 目前 Docker 磁碟使用量：
docker system df
echo.

:: ── 列出將被刪除的 image ─────────────────────────────────────
if "%MODE%"=="all" (
    echo [WARN] 模式：--all（刪除所有未被任何容器使用的 image）
    echo.
    echo 將刪除的 image：
    docker images --filter "dangling=true"  --format "  [dangling]  {{.Repository}}:{{.Tag}}  {{.Size}}  {{.ID}}"
    docker images --filter "dangling=false" --format "  [unused]    {{.Repository}}:{{.Tag}}  {{.Size}}  {{.ID}}"
) else (
    echo [WARN] 模式：dangling（只刪除無 tag 的孤立 image）
    echo.
    :: 檢查是否有 dangling image
    for /f "tokens=*" %%i in ('docker images --filter "dangling=true" -q') do (
        set "HAS_DANGLING=1"
    )
    if not defined HAS_DANGLING (
        echo [ OK ] 沒有 dangling image，無需清理。
        exit /b 0
    )
    echo 將刪除的 dangling image：
    docker images --filter "dangling=true" --format "  {{.ID}}   {{.Size}}   建立於 {{.CreatedSince}}"
)
echo.

:: ── Dry-run 結束 ──────────────────────────────────────────────
if "%DRY_RUN%"=="1" (
    echo [WARN] --dry-run 模式，不實際刪除。
    exit /b 0
)

:: ── 確認 ──────────────────────────────────────────────────────
set /p "CONFIRM=確定要刪除？[y/N] "
if /i not "%CONFIRM%"=="y" (
    echo [WARN] 已取消。
    exit /b 0
)

:: ── 執行清理 ─────────────────────────────────────────────────
if "%MODE%"=="all" (
    docker image prune -a -f
) else (
    docker image prune -f
)

echo.
echo [INFO] 清理後 Docker 磁碟使用量：
docker system df
echo [ OK ] 完成！
