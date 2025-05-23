#Requires -PSEdition Core
#Requires -Version 7.0

<#
.SYNOPSIS
    Упаковывает подпроекты в 7z-архивы с хешами
#>

param(
    [string]$RootDir = './dev_build'
)

# Прекращаем выполнение при любой ошибке
$ErrorActionPreference = 'Stop'

# Ищем команду 7z или 7za в PATH
$sevenZipCmd = (Get-Command '7z'  -ErrorAction SilentlyContinue)?.Source `
             ?? (Get-Command '7za' -ErrorAction SilentlyContinue)?.Source

if (-not $sevenZipCmd) {
    throw '7-Zip не найден. Установите p7zip-full (Linux) или 7-Zip (Windows)'
}

# Это путь к бинарнику 7z
$7zCommand = $sevenZipCmd

# Алгоритмы хеширования
$hashAlgos = @('MD5','SHA1','SHA256')

# Обходим все подпроекты в $RootDir
Get-ChildItem -Path $RootDir -Directory | ForEach-Object {
    $proj     = $_
    $name     = $proj.Name
    $archive  = Join-Path $proj.FullName "${name}_artifacts.7z"
    $tempDir  = Join-Path $env:TEMP     "${name}_temp"

    try {
        # Готовим временную папку
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        # Копируем все файлы из подпроекта
        Copy-Item -Path (Join-Path $proj.FullName '*') -Destination $tempDir -Recurse

        # Генерируем внутренние хеши каждого файла
        foreach ($algo in $hashAlgos) {
            $sumFile = Join-Path $tempDir ("{0}sums.txt" -f $algo.ToLower())
            Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
                $hash    = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                $relPath = $_.FullName.Substring($tempDir.Length+1).TrimStart('\','/')
                "$hash  $relPath" | Add-Content -Path $sumFile -Encoding UTF8
            }
        }

        # Архивируем всё в один 7z-файл
        & $7zCommand a -t7z $archive (Join-Path $tempDir '*') -mx9 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка архивации подпроекта '$name'"
        }

        # Генерируем внешние хеш-файлы для самого архива
        foreach ($algo in $hashAlgos) {
            $hash     = (Get-FileHash $archive -Algorithm $algo).Hash
            $hashFile = "$archive.$($algo.ToLower())"
            "$hash  $(Split-Path $archive -Leaf)" | Set-Content -Path $hashFile -Encoding UTF8
        }
    }
    finally {
        # Убираем временную папку
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
