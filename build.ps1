param(
    [string] $Project  = "",
    [string] $Version  = "",
    [switch] $SkipTests
)

$ErrorActionPreference = "Stop"
$BuilderRoot = $PSScriptRoot

# ── Глобальный конфиг ────────────────────────────────────────────────────────
$globalCfgPath = "$BuilderRoot\config.json"
if (-not (Test-Path $globalCfgPath)) {
    Write-Error "Не найден глобальный конфиг: $globalCfgPath"
    exit 1
}
$global = Get-Content $globalCfgPath -Raw | ConvertFrom-Json

$RceditExe = "$BuilderRoot\$($global.rceditPath)"
$IconsDir  = "$BuilderRoot\$($global.iconsDir)"

# ── Список проектов если не указан ───────────────────────────────────────────
if ($Project -eq "") {
    Write-Host "Доступные проекты:" -ForegroundColor Cyan
    Get-ChildItem "$BuilderRoot\*.json" | ForEach-Object {
        Write-Host "  $($_.BaseName)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Использование:" -ForegroundColor Gray
    Write-Host "  .\build.ps1 -Project <имя> -Version <версия> [-SkipTests]" -ForegroundColor Gray
    exit 0
}

if ($Version -eq "") {
    Write-Error "Укажите версию: -Version 0.01"
    exit 1
}

# ── Конфиг проекта ───────────────────────────────────────────────────────────
$cfgPath = "$BuilderRoot\$Project.json"
if (-not (Test-Path $cfgPath)) {
    Write-Error "Конфиг проекта не найден: $cfgPath"
    exit 1
}
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

# ── Разбиваем версию на части ────────────────────────────────────────────────
$vp    = $Version.Split('.')
$major = if ($vp.Length -gt 0) { $vp[0] } else { "0" }
$minor = if ($vp.Length -gt 1) { $vp[1] } else { "0" }
$patch = if ($vp.Length -gt 2) { $vp[2] } else { "0" }
$build = if ($vp.Length -gt 3) { $vp[3] } else { "0" }

# ── Подстановка плейсхолдеров ────────────────────────────────────────────────
function Sub([string]$str) {
    $str `
        -replace "{{version}}", $Version `
        -replace "{{major}}",   $major   `
        -replace "{{minor}}",   $minor   `
        -replace "{{patch}}",   $patch   `
        -replace "{{build}}",   $build   `
        -replace "{{project}}", $Project `
        -replace "{{binary}}",  $BinaryPath
}

# ── Итоговые пути ────────────────────────────────────────────────────────────
$ProjectPath  = Sub $cfg.projectDir
$BinaryPath   = "$ProjectPath\$($cfg.binaryName)"
$IconPath     = "$IconsDir\$($cfg.icon)"
$FileVersion  = Sub $cfg.versionFormat

# ── Проверки ─────────────────────────────────────────────────────────────────
if (-not (Test-Path $ProjectPath)) {
    Write-Error "Папка проекта не найдена: $ProjectPath"
    exit 1
}

# ── Заголовок ────────────────────────────────────────────────────────────────
Set-Location $ProjectPath
Write-Host ""
Write-Host "[Проект]  $Project"       -ForegroundColor Cyan
Write-Host "  Папка   : $ProjectPath"   -ForegroundColor Gray
Write-Host "  Версия  : $Version  →  $FileVersion" -ForegroundColor Gray
Write-Host "  Тесты   : $(if ($SkipTests) { 'пропущены' } else { 'включены' })" -ForegroundColor Gray
Write-Host ""

# ── 1. Тесты ─────────────────────────────────────────────────────────────────
if (-not $SkipTests -and $cfg.testCmd) {
    Write-Host "[ 1/3 ] Testing..." -ForegroundColor Cyan
    Invoke-Expression (Sub $cfg.testCmd)
    if ($LASTEXITCODE -ne 0) { Write-Error "[$Project] Тесты упали - сборка отменена"; exit 1 }
    Write-Host ">> OK" -ForegroundColor Green
    Write-Host ""
}

# ── 2. Сборка ────────────────────────────────────────────────────────────────
Write-Host "[ 2/3 ] Building..." -ForegroundColor Cyan
Invoke-Expression (Sub $cfg.buildCmd)
if ($LASTEXITCODE -ne 0) { Write-Error "[$Project] Build failed"; exit 1 }
Write-Host ">> OK" -ForegroundColor Green
Write-Host ""

# ── 3. Ресурсы ───────────────────────────────────────────────────────────────
Write-Host "[ 3/3 ] Applying resources..." -ForegroundColor Cyan
if (Test-Path $RceditExe) {
    $rceditArgs  = @($BinaryPath)
    $rceditArgs += "--set-file-version",    $FileVersion
    $rceditArgs += "--set-product-version", $FileVersion
    $rceditArgs += "--set-icon",            $IconPath
    foreach ($key in $cfg.rcedit.PSObject.Properties.Name) {
        $rceditArgs += "--set-version-string", $key, (Sub $cfg.rcedit.$key)
    }
    & $RceditExe @rceditArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "[$Project] rcedit failed"; exit 1 }
    Write-Host ">> OK" -ForegroundColor Green
} else {
    Write-Host ">> rcedit не найден, пропускаем" -ForegroundColor Yellow
}

# ── Готово ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ">> Done: $BinaryPath" -ForegroundColor Yellow
Write-Host ""