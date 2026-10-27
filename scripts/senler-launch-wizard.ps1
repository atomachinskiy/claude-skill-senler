# senler-launch-wizard.ps1 - Spawn a separate PowerShell window running
# senler-key-setup.ps1 (API key, default) or senler-oauth-setup.ps1 (-OAuth).
# Used on Windows to keep secrets out of the AI assistant's transcript.
#
# AI assistant calls this script via the Bash tool:
#   powershell -ExecutionPolicy Bypass -File senler-launch-wizard.ps1
#
# A new PowerShell window appears on the user's desktop. The user enters
# the API key (or client_id / client_secret) in that window. The AI never sees them.

[CmdletBinding()]
param(
    # Старый путь через OAuth-приложение. По умолчанию подключение по ключу API.
    [switch]$OAuth
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Setup     = Join-Path $ScriptDir $(if ($OAuth) { 'senler-oauth-setup.ps1' } else { 'senler-key-setup.ps1' })

if (-not (Test-Path $Setup)) {
    Write-Host "[x] Не найден $Setup" -ForegroundColor Red
    exit 1
}

# Spawn a NEW PowerShell window, run setup script, keep window open after.
$psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $psExe) { $psExe = 'powershell.exe' }

Start-Process -FilePath $psExe `
              -ArgumentList @(
                  '-NoExit',
                  '-ExecutionPolicy', 'Bypass',
                  '-File', "`"$Setup`""
              )

Write-Host "[+] Открыл отдельное окно PowerShell с мастером настройки Senler." -ForegroundColor Green
Write-Host "    Перейди в новое окно и следуй инструкциям там."
Write-Host "    Ключ вводится в новом окне, в этот чат он не попадёт."
