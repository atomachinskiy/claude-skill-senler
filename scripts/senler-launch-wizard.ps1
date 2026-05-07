# senler-launch-wizard.ps1 - Spawn a separate PowerShell window running
# senler-oauth-setup.ps1. Used on Windows to keep client_secret out of
# the AI assistant's transcript.
#
# AI assistant calls this script via the Bash tool:
#   powershell -ExecutionPolicy Bypass -File senler-launch-wizard.ps1
#
# A new PowerShell window appears on the user's desktop. The user enters
# client_id / client_secret in that new window. The AI never sees them.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Setup     = Join-Path $ScriptDir 'senler-oauth-setup.ps1'

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
Write-Host "    client_id / client_secret вводятся в новом окне, в этот чат они не попадут."
