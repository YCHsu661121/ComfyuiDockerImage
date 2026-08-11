@echo off
setlocal

:: Change to script directory
cd /d "%~dp0"

:: Execute PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-update.ps1" %*

:: Exit with error level
exit /b %ERRORLEVEL%
