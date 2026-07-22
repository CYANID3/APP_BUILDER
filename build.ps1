param(
    [string] $Project  = "",
    [string] $Version  = "",
    [switch] $SkipTests
)

$ErrorActionPreference = "Stop"
$BuilderRoot = $PSScriptRoot

# ── Визуальная ширина строки (кириллица = 2) ─────────────────────────────────
function Get-DisplayLength([string]$str) {
    $len = 0
    foreach ($char in $str.ToCharArray()) {
        if ([int]$char -gt 127) { $len += 2 } else { $len += 1 }
    }
    return $len
}

# ── Рамка ────────────────────────────────────────────────────────────────────
function Write-Box {
    param([string[]]$Lines, [string]$Color = "Cyan")

    $width = $Host.UI.RawUI.WindowSize.Width - 2
    $hr    = "─" * $width

    Write-Host "┌$hr┐" -ForegroundColor $Color
    foreach ($line in $Lines) {
        # Обрезаем если не влезает
        $maxText = $width - 4
        if ($line.Length -gt $maxText) {
            $line = $line.Substring(0, $maxText - 3) + "..."
        }
        $pad = " " * ($maxText - $line.Length)
        Write-Host "│  $line$pad  │" -ForegroundColor $Color
    }
    Write-Host "└$hr┘" -ForegroundColor $Color
}
# ── Глобальный конфиг ────────────────────────────────────────────────────────
$globalCfgPath = "$BuilderRoot\config.json"
if (-not (Test-Path $globalCfgPath)) {
    Write-Error "Не найден глобальный конфиг: $globalCfgPath"
    exit 1
}
$global    = Get-Content $globalCfgPath -Raw | ConvertFrom-Json
$RceditExe = "$BuilderRoot\$($global.rceditPath)"
$IconsDir  = "$BuilderRoot\$($global.iconsDir)"

# ── Список проектов если не указан ───────────────────────────────────────────
if ($Project -eq "") {
    Write-Host ""
    Write-Box @("APP_BUILDER") -Color Magenta
    Write-Host ""
    Write-Host "  Доступные проекты:" -ForegroundColor Cyan
    Get-ChildItem "$BuilderRoot\projects\*.json" | ForEach-Object {
        Write-Host "    • $($_.BaseName)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Использование:" -ForegroundColor Gray
    Write-Host "    .\build.ps1 -Project <имя> -Version <версия> [-SkipTests]" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

if ($Version -eq "") {
    Write-Error "Укажите версию: -Version 0.15"
    exit 1
}

# ── Конфиг проекта ───────────────────────────────────────────────────────────
$cfgPath = "$BuilderRoot\projects\$Project.json"
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
$ProjectPath = Sub $cfg.projectDir
$BinaryPath  = "$ProjectPath\$($cfg.binaryName)"
$IconPath    = "$IconsDir\$($cfg.icon)"
$FileVersion = Sub $cfg.versionFormat

# ── Проверки ─────────────────────────────────────────────────────────────────
if (-not (Test-Path $ProjectPath)) {
    Write-Error "Папка проекта не найдена: $ProjectPath"
    exit 1
}
# ── Заголовок ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Box @("GO-TOOLS  //  App Builder") -Color Magenta
Write-Host ""

# ── Заголовок ────────────────────────────────────────────────────────────────
Set-Location $ProjectPath
Write-Box @(
    "Проект  : $Project"
    "Папка   : $ProjectPath"
    "Версия  : $Version  →  $FileVersion"
    "Тесты   : $(if ($SkipTests) { 'пропущены' } else { 'включены' })"
) -Color Cyan
Write-Host ""

# ── Считаем шаги динамически ─────────────────────────────────────────────────
$steps     = @()
$hasTests  = (-not $SkipTests -and $cfg.testCmd)
if ($hasTests)  { $steps += "Tests"     }
$steps += "Build"
$steps += "Resources"
$totalSteps = $steps.Count

$step = 0
function Write-Step([string]$label) {
    $script:step++
    Write-Host ""
    Write-Host "[ $($script:step)/$totalSteps ]  $label" -ForegroundColor DarkCyan
    Write-Host ""
}

# ── 1. Тесты (если есть) ─────────────────────────────────────────────────────
if ($hasTests) {
    Write-Step "Testing..."
    Invoke-Expression (Sub $cfg.testCmd)
    if ($LASTEXITCODE -ne 0) { Write-Error "[$Project] Тесты упали — сборка отменена"; exit 1 }
    Write-Host ""
    Write-Host " ✔  Tests passed" -ForegroundColor Green
}

# ── 2. Сборка ────────────────────────────────────────────────────────────────
Write-Step "Building..."
$buildCmd = (Sub $cfg.buildCmd) -replace "go build", "go build -v"
Invoke-Expression $buildCmd
if ($LASTEXITCODE -ne 0) { Write-Error "[$Project] Build failed"; exit 1 }
Write-Host " ✔  Build complete" -ForegroundColor Green

# ── 3. Ресурсы ───────────────────────────────────────────────────────────────
Write-Step "Applying resources..."
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
    Write-Host " ✔  Icon applied" -ForegroundColor Green
    Write-Host " ✔  Version info applied" -ForegroundColor Green
    Write-Host " ✔  Metadata applied" -ForegroundColor Green
} else {
    Write-Host " ⚠  rcedit не найден, пропускаем" -ForegroundColor Yellow
}

# ── Готово ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Box @("✔  Done: $BinaryPath") -Color Yellow
Write-Host ""