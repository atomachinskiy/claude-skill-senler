# senler-oauth-setup.ps1 - Native PowerShell wizard for Senler OAuth setup.
# Runs in a separate PowerShell window opened by senler-launch-wizard.ps1.
# AI assistant must NOT call this script directly via Bash tool - it would
# capture stdin prompts where the user types client_secret. The wizard pattern
# (separate window) keeps secrets out of the AI transcript.
#
# Cross-platform: this script is Windows-only (replaces Git Bash dependency).
# macOS / Linux still use senler-oauth-setup.sh.

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SkillDir    = Join-Path $env:USERPROFILE '.claude\skills\senler'
$SecretsDir  = Join-Path $env:USERPROFILE '.claude\secrets'
$AppFile     = Join-Path $SecretsDir 'senler-app.json'
$EnvFile     = Join-Path $SkillDir 'config\.env'
$RedirectUri = 'https://oauth.senler.ru/blank.html'

function Write-Step($msg)  { Write-Host ""; Write-Host "[>] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Die($msg)         { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $SkillDir)) {
    Die "Папка $SkillDir не найдена. Сначала склонируй скилл: git clone https://github.com/atomachinskiy/claude-skill-senler.git $SkillDir"
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  Senler API - мастер настройки OAuth (PowerShell, без Git Bash)" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Path $SecretsDir -Force | Out-Null

# ----- Step 1: credentials -----
$reuse = $false
if ((Test-Path $AppFile) -and -not $Force) {
    Write-Ok "Найден существующий $AppFile"
    $ans = Read-Host 'Использовать сохранённый client_id? [Y/n]'
    if ($ans -match '^[Yy]?$') { $reuse = $true } else { Remove-Item $AppFile -Force }
}

if (-not $reuse) {
    Write-Host ""
    Write-Host "=== Шаг 1: создание OAuth-приложения в Senler ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Открой https://senler.ru -> авторизуйся"
    Write-Host "2. Аватарка справа сверху -> 'Разработчикам'"
    Write-Host "3. '+ Добавить приложение'"
    Write-Host "4. Заполни:"
    Write-Host "   - Название: Claude AI Analyst"
    Write-Host "   - Интеграция: 'Авторизация на стороннем сайте (OAuth)'"
    Write-Host "   - redirect_uri: $RedirectUri"
    Write-Host "5. 'Сохранить' - увидишь client_id и client_secret"
    Write-Host ""
    Write-Warn "client_secret показывается ОДИН РАЗ - копируй сразу"
    Write-Host ""

    $clientId = Read-Host 'client_id'
    if (-not $clientId) { Die "client_id пустой" }

    $clientSecretSecure = Read-Host 'client_secret (ввод скрыт)' -AsSecureString
    $clientSecret = [System.Net.NetworkCredential]::new('', $clientSecretSecure).Password
    if (-not $clientSecret) { Die "client_secret пустой" }

    $payload = [ordered]@{
        client_id     = $clientId
        client_secret = $clientSecret
        redirect_uri  = $RedirectUri
    }
    $json = $payload | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($AppFile, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Restrict ACL
    try {
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        $me = "$env:USERDOMAIN\$env:USERNAME"
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')))
        Set-Acl -Path $AppFile -AclObject $acl
    } catch {}

    Write-Ok "Сохранено в $AppFile (доступ ограничен)"
}

$app = Get-Content $AppFile -Raw -Encoding UTF8 | ConvertFrom-Json
$ClientId     = $app.client_id
$ClientSecret = $app.client_secret
$RedirectUri  = $app.redirect_uri

# ----- Step 2: build authorize URL and open browser -----
Add-Type -AssemblyName System.Web
$state       = [guid]::NewGuid().Guid
$encRedirect = [System.Web.HttpUtility]::UrlEncode($RedirectUri)
$authUrl     = "https://senler.ru/cabinet/OAuth2authorize?client_id=$ClientId&redirect_uri=$encRedirect&state=$state"

Write-Host ""
Write-Host "=== Шаг 2: получить авторизационный код ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Открой URL в браузере, где залогинен в Senler"
Write-Host "(если в РФ - Senler иногда блокируется некоторыми провайдерами, может понадобиться VPN):"
Write-Host ""
Write-Host "  $authUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  -> выбери канал -> нажми 'Разрешить'"
Write-Host "  -> перебросит на $RedirectUri" + "?code=XXXX&state=...&group_id=NNNN"
Write-Host "  -> страница может быть пустой, нужен только URL из адресной строки"
Write-Host ""
Write-Warn "code в URL ОДНОРАЗОВЫЙ и быстро устаревает. Если получишь 'Wrong authCode' - открой URL заново."
Write-Host ""

$openAns = Read-Host 'Открыть URL автоматически? [Y/n]'
if ($openAns -match '^[Yy]?$') {
    try { Start-Process $authUrl } catch { Write-Warn "Не удалось открыть браузер автоматически. Скопируй URL руками." }
}

Write-Host ""
$redirectUrlFromBrowser = Read-Host 'Вставь ВЕСЬ URL после редиректа (со всем хвостом ?code=...&group_id=...)'

if (-not $redirectUrlFromBrowser) { Die "URL пустой" }

$code = $null
$groupId = $null
if ($redirectUrlFromBrowser -match '[?&]code=([^&\s#]+)')     { $code    = $Matches[1] }
if ($redirectUrlFromBrowser -match '[?&]group_id=([^&\s#]+)') { $groupId = $Matches[1] }

if (-not $code)    { $code    = Read-Host 'Не нашёл code= в URL. Введи code вручную' }
if (-not $groupId) { $groupId = Read-Host 'Не нашёл group_id= в URL. Введи group_id вручную' }

if (-not $code)    { Die "code пустой" }
if (-not $groupId) { Die "group_id пустой" }

Write-Ok ("code=" + $code.Substring(0, [Math]::Min(8, $code.Length)) + "... group_id=$groupId")

# ----- Step 3: exchange code for access_token -----
Write-Host ""
Write-Host "=== Шаг 3: обмен code на access_token ===" -ForegroundColor Yellow
Write-Host ""

$tokenUrl = 'https://senler.ru/ajax/cabinet/OAuth2token'
$query = @{
    client_id     = $ClientId
    client_secret = $ClientSecret
    redirect_uri  = $RedirectUri
    code          = $code
    group_id      = $groupId
}

try {
    $resp = Invoke-RestMethod -Uri $tokenUrl -Method Get -Body $query -TimeoutSec 30
} catch {
    Write-Warn "HTTP ошибка: $($_.Exception.Message)"
    Die "Не удалось обменять code на токен. Перезапусти мастер с свежим code."
}

$accessToken = $resp.access_token
if (-not $accessToken) {
    Write-Warn "В ответе нет access_token:"
    $resp | ConvertTo-Json -Depth 5 | Write-Host
    if ($resp.message -match 'Wrong\s*authCode' -or $resp.error -match 'Wrong\s*authCode') {
        Write-Warn "code устарел или уже использован. Открой URL ещё раз, возьми СВЕЖИЙ code, перезапусти мастер."
    }
    Die "Не получен access_token"
}

Write-Ok ("Получен access_token (" + $accessToken.Length + " символов)")

# ----- Step 4: save .env -----
$ConfigDir = Split-Path $EnvFile -Parent
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

$envContent = @"
SENLER_ACCESS_TOKEN=$accessToken
SENLER_GROUP_ID=$groupId
SENLER_V=2
"@
[System.IO.File]::WriteAllText($EnvFile, $envContent, (New-Object System.Text.UTF8Encoding($false)))

try {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')))
    Set-Acl -Path $EnvFile -AclObject $acl
} catch {}

Write-Ok "Записано в $EnvFile (доступ ограничен)"

# ----- Step 5: sanity-check -----
Write-Host ""
Write-Host "=== Шаг 4: проверка подключения ===" -ForegroundColor Yellow
Write-Host ""

try {
    $body = "group_id=$groupId&access_token=$accessToken&v=2"
    $check = Invoke-RestMethod -Uri 'https://senler.ru/api/subscribers/count' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30
    $subs = $null
    if ($check.count -ne $null) { $subs = $check.count }
    elseif ($check.items -and $check.items.count -ne $null) { $subs = $check.items.count }
    if ($subs -ne $null) {
        Write-Ok "Работает! Подписчиков в канале: $subs"
    } else {
        Write-Warn "Ответ API:"
        $check | ConvertTo-Json -Depth 5 | Write-Host
    }
} catch {
    Write-Warn "Sanity-check упал: $($_.Exception.Message)"
    Write-Warn "Конфиг сохранён, попробуй вручную позже."
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  + Senler настроен. Можно работать." -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Дальше попроси Claude:"
Write-Host "  - 'Покажи мои воронки в Senler'"
Write-Host "  - 'Сделай аналитику моего канала Senler'"
Write-Host "  - 'Найди где люди отваливаются'"
Write-Host ""
Read-Host 'Нажми Enter чтобы закрыть это окно'
