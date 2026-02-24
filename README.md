# App Builder

## Скрипт для автоматической сборки приложений на golang

### Закинуть иконку в папку icons
### Переименовать ex-config.json в config.json и запонить его

```json
{
  "app": {
    "name": "Название приложения",
    "icon": "icon.ico",
    "desc": "Описание приложения",
    "license": "Лицензия © 2026",
    "company": "Компания",
    "main": "Путь\\к\\файлу\\main.go",
    "versionFile": "Путь\\к\\файлу\\version.go",
    "distrDir": "Путь\\к\\папке\\APP_BUILDER\\dist",
    "buildDir": "Путь\\к\\папке\\\\APP_BUILDER\\build",
    "sevenZip": "Путь\\к\\7-Zip\\7z.exe",
    "version": "" // берётся из version.go
  }
}
```
### Примерный вид version.go


```go
package utils

import "github.com/fatih/color"

var VersionText = color.GreenString("v1.1.3")
```

Убедиться в правильности данных и запустить builder.ps1

Он выполнит билд go в exe, заполнит данные, сменит иконку, 
запакует всё это в 7z и поместит файл exe и его архив в папку build