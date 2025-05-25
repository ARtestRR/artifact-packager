#Requires -PSEdition Core
#Requires -Version 7.0

param(
    [string] $RootDir = './dev_build'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDirFull = Join-Path $ScriptDir $RootDir

try {
    $RootDirFull = Resolve-Path -Path $RootDirFull -ErrorAction Stop
} catch {
    throw "Не удалось разрешить путь: '$RootDirFull'. Причина: $_"
}

if (-not (Test-Path $RootDirFull -PathType Container)) {
    throw "Директория '$RootDirFull' не существует!"
}

$sevenZipCmd = (Get-Command '7z' -ErrorAction SilentlyContinue)?.Source ?? 
              (Get-Command '7za' -ErrorAction SilentlyContinue)?.Source

if (-not $sevenZipCmd) {
    throw '7-Zip не найден. Установите p7zip-full (Linux) или 7-Zip (Windows)'
}

$hashAlgos = @('MD5', 'SHA1', 'SHA256')

Get-ChildItem -Path $RootDirFull -Directory | ForEach-Object {
    $proj = $_
    $name = $proj.Name
    $archive = Join-Path $proj.FullName "${name}_artifacts.7z"
    $tempDir = Join-Path $env:TEMP "${name}_temp_$(Get-Random)"

    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $proj.FullName '*') -Destination $tempDir -Recurse -Force

        foreach ($algo in $hashAlgos) {
            $sumFile = Join-Path $tempDir ("{0}sums.txt" -f $algo.ToLower())
            Get-ChildItem -Path $tempDir -Recurse -File | Where-Object {
                $_.FullName -ne $sumFile
            } | ForEach-Object {
                $hash = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                $relPath = $_.FullName.Substring($tempDir.Length + 1).Replace('\', '/')
                "$hash  $relPath" | Add-Content -Path $sumFile -Encoding utf8
            }
        }

        & $sevenZipCmd a -t7z $archive (Join-Path $tempDir '*') -mx9 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Ошибка архивации $name" }

        foreach ($algo in $hashAlgos) {
            $hash = (Get-FileHash $archive -Algorithm $algo).Hash
            "$hash  $(Split-Path $archive -Leaf)" | Set-Content -Path "$archive.$($algo.ToLower())" -Encoding utf8
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[SUCCESS] Все артефакты успешно созданы!"