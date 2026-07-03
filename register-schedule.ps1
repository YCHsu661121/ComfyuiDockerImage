#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    將 auto-update.bat 登錄到 Windows 工作排程器，每週一早上 8:00 自動執行。
.EXAMPLE
    # 以系統管理員身份執行
    .\register-schedule.ps1

    # 自訂排程時間
    .\register-schedule.ps1 -DayOfWeek Monday -Time "06:00"

    # 移除排程
    .\register-schedule.ps1 -Unregister
#>
param(
    [ValidateSet("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")]
    [string]$DayOfWeek = "Monday",
    [string]$Time      = "08:00",
    [switch]$Unregister
)

$TaskName  = "ComfyUI-Docker-AutoUpdate"
$ScriptDir = $PSScriptRoot
$BatFile   = Join-Path $ScriptDir "auto-update.bat"

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "工作排程 '$TaskName' 已移除。" -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $BatFile)) {
    Write-Error "找不到 auto-update.bat: $BatFile"
    exit 1
}

$action  = New-ScheduledTaskAction `
               -Execute  "cmd.exe" `
               -Argument "/c `"$BatFile`" >> `"$ScriptDir\auto-update.log`" 2>&1" `
               -WorkingDirectory $ScriptDir

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 3)

# 使用目前登入帳號執行（需儲存密碼）
$principal = New-ScheduledTaskPrincipal `
    -UserId    "$env:USERDOMAIN\$env:USERNAME" `
    -RunLevel  Highest `
    -LogonType InteractiveOrPassword

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host "工作排程已建立：" -ForegroundColor Green
Write-Host "  名稱   : $TaskName"
Write-Host "  執行   : 每週 $DayOfWeek $Time"
Write-Host "  腳本   : $BatFile"
Write-Host "  Log    : $ScriptDir\auto-update.log"
Write-Host ""
Write-Host "手動觸發測試：" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
