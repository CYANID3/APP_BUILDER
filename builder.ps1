param(
    $json = ".\config.json"
)

# ===== Читаем JSON =====
$config = Get-Content $json | ConvertFrom-Json

# ===== Читаем версию из version.go =====
$versionPath = $config.app.versionFile
$versionLines = Get-Content $versionPath
$version = $null

foreach ($line in $versionLines) {
    if ($line -match 'VersionText\s*=\s*color\.GreenString\("v?([^"]+)"\)') {
        $version = $matches[1]
        break
    }
}

if (-not $version) {
    Write-Error "Не удалось найти версию в $versionPath"
    exit 1
}

# ===== Обновляем JSON =====
$config.app.version = $version
$config | ConvertTo-Json -Depth 10 | Set-Content $json

# ===== Вывод логов =====
Write-Host -NoNewline "Путь до файла main..............: " -ForegroundColor Yellow
Write-Host "$($config.app.main)" -ForegroundColor Green
Write-Host -NoNewline "Готовый файл будет перемещён в..: " -ForegroundColor Yellow
Write-Host "$($config.app.buildDir)" -ForegroundColor Green

# ===== Подготовка пути для билда =====
$mainGo = $config.app.main
$exeName = "app.exe"
$mainDir = Split-Path $mainGo
$mainFile = Split-Path $mainGo -Leaf
$distrDir = $config.app.distrDir
$buildDir = $config.app.buildDir
$sevenZip = $config.app.sevenZip

# ===== Создаём dist (distrDir), если нет =====
if (-not (Test-Path $distrDir)) { New-Item -ItemType Directory -Path $distrDir | Out-Null }

# ===== Билдим из папки с main.go =====
Push-Location $mainDir
go build -ldflags "-s -w" -o "$distrDir\$exeName" $mainFile
Pop-Location

# ===== Пути к exe =====
$exePath = Join-Path $distrDir $exeName
$newExe = Join-Path $distrDir "$($config.app.name).exe"

if (-not (Test-Path $exePath)) {
    Write-Error "Файл $exePath не найден после сборки"
    exit 1
}

# ===== Меняем свойства через rcedit =====
.\Tools\rcedit-x64.exe $exePath --set-file-version $config.app.version
.\Tools\rcedit-x64.exe $exePath --set-product-version $config.app.version
.\Tools\rcedit-x64.exe $exePath --set-version-string "ProductName" $config.app.name
.\Tools\rcedit-x64.exe $exePath --set-version-string "FileDescription" $config.app.desc
.\Tools\rcedit-x64.exe $exePath --set-version-string "LegalCopyright" $config.app.license
.\Tools\rcedit-x64.exe $exePath --set-version-string "CompanyName" $config.app.company
.\Tools\rcedit-x64.exe $exePath --set-icon ".\icons\$($config.app.icon)"

# ===== Вывод логов =====
Write-Host -NoNewline "Имя.............................: " -ForegroundColor Yellow
Write-Host "$($config.app.name)" -ForegroundColor Green
Write-Host -NoNewline "Описание........................: " -ForegroundColor Yellow
Write-Host "$($config.app.desc)" -ForegroundColor Green
Write-Host -NoNewline "Лицензия........................: " -ForegroundColor Yellow
Write-Host "$($config.app.license)" -ForegroundColor Green
Write-Host -NoNewline "Компания........................: " -ForegroundColor Yellow
Write-Host "$($config.app.company)" -ForegroundColor Green
Write-Host -NoNewline "Иконка..........................: " -ForegroundColor Yellow
Write-Host "$($config.app.icon)" -ForegroundColor Green
Write-Host -NoNewline "Версия..........................: " -ForegroundColor Yellow
Write-Host "$($config.app.version)" -ForegroundColor Green

# ===== Переименовываем exe по имени приложения безопасно =====
if ($exePath -ne $newExe) {
    if (Test-Path $newExe) { Remove-Item $newExe -Force }
    Rename-Item $exePath $newExe -Force
}

# ===== Перемещаем готовый exe из dist в build безопасно =====
if (-not (Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir | Out-Null }

$finalPath = Join-Path $buildDir "$($config.app.name).exe"

# Если уже есть файл с таким именем, удаляем
if (Test-Path $finalPath) { Remove-Item $finalPath -Force }

Move-Item $newExe $finalPath -Force

# ===== Создание .7z архива прямо в buildDir без вывода =====
$archivePath = Join-Path $buildDir "$($config.app.name).7z"

if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

# Временные файлы для подавления вывода
$outFile = [System.IO.Path]::GetTempFileName()
$errFile = [System.IO.Path]::GetTempFileName()

Start-Process -FilePath $sevenZip `
    -ArgumentList "a `"$archivePath`" `"$finalPath`"" `
    -Wait `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outFile `
    -RedirectStandardError $errFile

# Удаляем временные файлы
Remove-Item $outFile, $errFile

Write-Host "Готово 👍 Архив создан в buildDir: $archivePath" -ForegroundColor Cyan