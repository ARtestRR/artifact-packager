#Requires -PSEdition Core
#Requires -Version 7.0

<#
.SYNOPSIS
    Упаковывает подпроекты в 7z-архивы с хешами
#>

param(
    [string] $RootDir = './dev_build'
)

# Прекращаем выполнение при любой ошибке
$ErrorActionPreference = 'Stop'

# Вычисляем абсолютный путь к RootDir относительно местоположения скрипта
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDirFull = Join-Path $ScriptDir $RootDir

# Отладочный вывод пути
Write-Host "[DEBUG] Script location: $($MyInvocation.MyCommand.Definition)"
Write-Host "[DEBUG] ScriptDir: $ScriptDir"
Write-Host "[DEBUG] RootDirFull before Resolve-Path: $RootDirFull"

try {
    $RootDirFull = Resolve-Path -Path $RootDirFull -ErrorAction Stop
} catch {
    throw "Не удалось разрешить путь: '$RootDirFull'. Причина: $_"
}

Write-Host "[DEBUG] RootDirFull after Resolve-Path: $RootDirFull"
Write-Host "[DEBUG] dev_build exists: $(Test-Path $RootDirFull -PathType Container)"

# Проверяем существование директории
if (-not (Test-Path $RootDirFull -PathType Container)) {
    throw "Директория '$RootDirFull' не существует!"
}

# Ищем команду 7z или 7za в PATH
$sevenZipCmd = (Get-Command '7z' -ErrorAction SilentlyContinue)?.Source ?? 
              (Get-Command '7za' -ErrorAction SilentlyContinue)?.Source

if (-not $sevenZipCmd) {
    throw '7-Zip не найден. Установите p7zip-full (Linux) или 7-Zip (Windows)'
}

Write-Host "[DEBUG] 7z path: $sevenZipCmd"
$7zCommand = $sevenZipCmd

# Алгоритмы хеширования
$hashAlgos = @('MD5', 'SHA1', 'SHA256')

# Обходим все подпроекты в $RootDirFull
Get-ChildItem -Path $RootDirFull -Directory | ForEach-Object {
    $proj = $_
    Write-Host "[PROCESSING] Найден проект: $($proj.FullName)"

    $name = $proj.Name
    $archive = Join-Path $proj.FullName "${name}_artifacts.7z"
    $tempDir = Join-Path $env:TEMP "${name}_temp_$(Get-Random)"

    try {
        Write-Host "[DEBUG] Создаём временную директорию: $tempDir"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        # Копируем всё из подпроекта
        Write-Host "[COPY] Копируем файлы из $($proj.FullName) в $tempDir"
        Copy-Item -Path (Join-Path $proj.FullName '*') -Destination $tempDir -Recurse -Force

        # Внутренние хеши
        foreach ($algo in $hashAlgos) {
            $sumFile = Join-Path $tempDir ("{0}sums.txt" -f $algo.ToLower())
            Write-Host "[HASH] Генерируем $algo суммы в $sumFile"
            
            Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
                $hash = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                $relPath = $_.FullName.Substring($tempDir.Length + 1).TrimStart('\', '/')
                "$hash  $relPath" | Add-Content -Path $sumFile -Encoding UTF8
            }
        }

        # Собираем 7z
        Write-Host "[7Z] Создаём архив: $archive"
        & $7zCommand a -t7z $archive (Join-Path $tempDir '*') -mx9 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка архивации подпроекта '$name'. Код выхода: $LASTEXITCODE"
        }

        # Внешние хеши
        foreach ($algo in $hashAlgos) {
            $hash = (Get-FileHash $archive -Algorithm $algo).Hash
            $hashFile = "$archive.$($algo.ToLower())"
            Write-Host "[HASH] Создаём хеш-файл: $hashFile"
            "$hash  $(Split-Path $archive -Leaf)" | Set-Content -Path $hashFile -Encoding UTF8
        }
    }
    finally {
        Write-Host "[CLEANUP] Удаляем временную директорию: $tempDir"
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[SUCCESS] Все артефакты успешно созданы!"