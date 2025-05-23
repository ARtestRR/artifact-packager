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
$RootDirFull = Resolve-Path (Join-Path $ScriptDir $RootDir) -ErrorAction Stop

# Ищем команду 7z или 7za в PATH
$sevenZipCmd = (Get-Command '7z'  -ErrorAction SilentlyContinue)?.Source `
             ?? (Get-Command '7za' -ErrorAction SilentlyContinue)?.Source
if (-not $sevenZipCmd) {
    throw '7-Zip не найден. Установите p7zip-full (Linux) или 7-Zip (Windows)'
}
$7zCommand = $sevenZipCmd

# Алгоритмы хеширования
$hashAlgos = @('MD5','SHA1','SHA256')

# Обходим все подпроекты в $RootDirFull
Get-ChildItem -Path $RootDirFull -Directory | ForEach-Object {
    $proj     = $_
    $name     = $proj.Name
    $archive  = Join-Path $proj.FullName "${name}_artifacts.7z"
    $tempDir  = Join-Path $env:TEMP     "${name}_temp"

    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        # Копируем всё из подпроекта
        Copy-Item -Path (Join-Path $proj.FullName '*') -Destination $tempDir -Recurse

        # Внутренние хеши
        foreach ($algo in $hashAlgos) {
            $sumFile = Join-Path $tempDir ("{0}sums.txt" -f $algo.ToLower())
            Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
                $hash    = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                $relPath = $_.FullName.Substring($tempDir.Length+1).TrimStart('\','/')
                "$hash  $relPath" | Add-Content -Path $sumFile -Encoding UTF8
            }
        }

        # Собираем 7z
        & $7zCommand a -t7z $archive (Join-Path $tempDir '*') -mx9 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка архивации подпроекта '$name'"
        }

        # Внешние хеши
        foreach ($algo in $hashAlgos) {
            $hash     = (Get-FileHash $archive -Algorithm $algo).Hash
            $hashFile = "$archive.$($algo.ToLower())"
            "$hash  $(Split-Path $archive -Leaf)" | Set-Content -Path $hashFile -Encoding UTF8
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
