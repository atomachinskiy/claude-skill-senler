# senler-key-setup.ps1 - мастер подключения Senler по ключу API (Windows, без Git Bash).
# Основной способ с 27.10.2026: ключ из кабинета Senler, канал -> «Настройки» -> «Работа с API».
# Приложение и OAuth не нужны.
#
# AI-ассистент НЕ запускает этот скрипт напрямую: ключ попал бы в транскрипт.
# Запуск только в отдельном окне через senler-launch-wizard.ps1.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SkillDir = Join-Path $HOME '.claude\skills\senler'
$EnvFile  = Join-Path $SkillDir 'config\.env'
$Api      = if ($env:SENLER_API_BASE) { $env:SENLER_API_BASE } else { 'https://senler.ru/api' }

function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Die($msg) {
    Write-Host "[x] $msg" -ForegroundColor Red
    Read-Host 'Нажмите Enter, чтобы закрыть окно' | Out-Null
    exit 1
}

if (-not (Test-Path $SkillDir)) { Die "Нет папки скилла $SkillDir" }

Write-Host ''
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host '  Senler: подключение по ключу API' -ForegroundColor Cyan
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '1. Откройте senler.ru и нужный канал.'
Write-Host '2. «Настройки» -> «Работа с API» -> создайте ключ и скопируйте его.'
Write-Host ''
Write-Host 'Ключ вводится только здесь, в чат агенту его не пишите.'
Write-Host ''

function Invoke-Senler($method, $fields) {
    try {
        return Invoke-RestMethod -Uri "$Api/$method" -Method Post -Body $fields `
            -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -TimeoutSec 30
    } catch {
        return [pscustomobject]@{ success = $false; error_code = $null; error_message = $_.Exception.Message }
    }
}

# group_id в API можно передать по-разному: ID канала в Senler, ID сообщества ВК,
# ID бота Telegram или МАКС. Пробуем все и берём настоящий group_id из ответа.
function Find-Group($key, $id) {
    $last = $null
    foreach ($param in 'group_id', 'vk_group_id', 'tg_bot_id', 'max_bot_id') {
        $resp = Invoke-Senler 'groups/get' @{ access_token = $key; $param = $id; v = '2' }
        $last = $resp
        if ($resp.success -eq $true) { return $resp }
        if ("$($resp.error_code)" -in '13', '14') { return $resp }
        Start-Sleep -Milliseconds 200
    }
    return $last
}

function Get-ChannelId($raw) {
    $s = ($raw -replace '\s', '')
    if ($s -match '(club|public)(\d+)') { return $Matches[2] }
    if ($s -match 'group_id=(\d+)')     { return $Matches[1] }
    if ($s -match '^(\d+):')            { return $Matches[1] }
    return ($s -replace '\D', '')
}

$key = ''
$group = $null
$attempt = 0
while ($attempt -lt 3) {
    $attempt++
    if (-not $key) {
        $secure = Read-Host 'Ключ API (ввод скрыт, вставьте и нажмите Enter)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $key = ($key -replace '\s', '')
        if (-not $key) { Write-Warn 'Пусто. Вставьте ключ ещё раз.'; $attempt--; continue }
    }
    Write-Host ''
    Write-Host 'ID канала. Подойдёт любое из:'
    Write-Host '  - ID сообщества ВКонтакте: число из ссылки vk.com/club123456 или сама ссылка;'
    Write-Host '  - ID канала в Senler: число из адресной строки кабинета;'
    Write-Host '  - для канала в Telegram: ID бота, первые цифры токена бота до двоеточия.'
    $chId = Get-ChannelId (Read-Host 'ID канала')
    if (-not $chId) { Write-Warn 'Не вижу в этом числа. Нужен числовой ID.'; $attempt--; continue }

    Write-Host 'Проверяю...'
    $resp = Find-Group $key $chId
    if ($resp.success -eq $true) { $group = $resp; break }

    switch ("$($resp.error_code)") {
        { $_ -in '13', '14' } { Write-Warn 'Ключ не подошёл. Скопируйте его целиком ещё раз из «Работа с API».'; $key = '' }
        { $_ -in '6', '7' } {
            Write-Warn "Для этого ключа канал с ID $chId не нашёлся. Проверьте ID и что ключ скопирован целиком."
            $again = Read-Host 'Ввести ключ заново? [y/N]'
            if ($again -match '^[yYдД]') { $key = '' }
        }
        '9' { Write-Warn 'Senler просит подождать: слишком много запросов. Пробую ещё раз.'; Start-Sleep -Seconds 2 }
        default {
            $msg = if ($resp.error_message) { $resp.error_message } else { 'нет ответа, проверьте интернет и VPN' }
            Write-Warn "Senler ответил: $msg"
        }
    }
}

if (-not $group) { Die 'Не получилось за 3 попытки. Пришлите агенту скрин страницы «Работа с API» (без самого ключа).' }

$groupId = "$($group.item.group_id)"
$chName  = "$($group.item.name)"
$chType  = "$($group.item.type_name)"
Write-Ok "Канал найден: $chName ($chType), ID в Senler $groupId"

$configDir = Split-Path $EnvFile -Parent
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$safeName = ($chName -replace '["$`\\]', '')
$envContent = "SENLER_ACCESS_TOKEN=$key`nSENLER_GROUP_ID=$groupId`nSENLER_V=2`nSENLER_CHANNEL_NAME=`"$safeName`"`n"
# Без BOM и с LF: файл читает bash-скрипт _common.sh
[System.IO.File]::WriteAllText($EnvFile, $envContent, (New-Object System.Text.UTF8Encoding($false)))

try {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')))
    Set-Acl -Path $EnvFile -AclObject $acl
} catch {}
Write-Ok 'Сохранено, доступ только у вас.'

$count = Invoke-Senler 'subscribers/count' @{ access_token = $key; group_id = $groupId; v = '2' }
if ($count.success -eq $true -and $null -ne $count.count) { Write-Ok "Подписчиков в канале: $($count.count)" }

Write-Host ''
Write-Host '===================================================' -ForegroundColor Green
Write-Host '  Senler настроен. Напишите агенту «готово».' -ForegroundColor Green
Write-Host '===================================================' -ForegroundColor Green
Write-Host ''
Read-Host 'Нажмите Enter, чтобы закрыть окно' | Out-Null
