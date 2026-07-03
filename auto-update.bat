@echo off
:: ============================================================
:: ComfyUI Docker Auto-Update — 雙擊執行 或 工作排程器呼叫
:: 功能：自動從 GitHub 偵測新版本，Build & Push 到 Docker Hub
:: ============================================================

setlocal

:: 切換到腳本所在目錄
cd /d "%~dp0"

:: 執行 PowerShell 腳本（繞過執行原則限制）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-update.ps1" %*

:: 若由工作排程器呼叫，結束碼會被記錄
exit /b %ERRORLEVEL%
