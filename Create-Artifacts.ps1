#Requires -PSEdition Core
#Requires -Version 7.0

param(
    [string]$RootDir = './dev_build'
)

$ErrorActionPreference = 'Stop'

# Очистка старых артефактов
$RootDirFull = Join-Path $PSScriptRoot $RootDir -Resolve
Get-ChildItem -Path $RootDirFull -Filter '*_artifacts.7z*' -Recurse | Remove-Item -Force

# Проверка 7-Zip
$sevenZipCmd = if ($IsWindows) { '7z.exe' } else { '7z' }
if (-not (Get-Command $sevenZipCmd -ErrorAction SilentlyContinue)) {
    throw "7-Zip not found! Install p7zip-full (Linux) or 7-Zip (Windows)"
}

# Настройки обработки
$hashAlgos = @('MD5', 'SHA1', 'SHA256')
$excludePatterns = @(
    '.gitkeep', 
    'tests', 
    '*_artifacts.7z*', 
    '*.md5', 
    'distr.deb',
    'syms.7z'
)

Get-ChildItem -Path $RootDirFull -Directory | Where-Object {
    $_.Name -match '^(grpedit|modservice|rsysconf|scada)$'
} | ForEach-Object {
    $proj = $_
    $archivePath = Join-Path $proj.FullName "$($proj.Name)_artifacts.7z"
    
    # Создание временной директории
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) `
        -Name "artifact_$($proj.Name)_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    try {
        # Копирование файлов с исключениями
        Get-ChildItem -Path $proj.FullName -Exclude $excludePatterns |
            Copy-Item -Destination $tempDir -Recurse -Force

        # Создание файлов хешей
        foreach ($algo in $hashAlgos) {
            $sumFile = Join-Path $tempDir "$($algo.ToLower())sums.txt"
            
            Get-ChildItem -Path $tempDir -Recurse -File -Exclude '*sums.txt' |
                ForEach-Object {
                    $relPath = $_.FullName.Replace($tempDir.FullName, '')
                        .TrimStart([System.IO.Path]::DirectorySeparatorChar)
                        .Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                    $hash = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                    "${hash}  ${relPath}" | Add-Content -Path $sumFile -Encoding utf8
                }
        }

        # Архивирование
        & $sevenZipCmd a -t7z "$archivePath" "$(Join-Path $tempDir '*')" -mx9 -r
        if ($LASTEXITCODE -ne 0) { 
            throw "Archive failed for $($proj.Name). 7z exit code: $LASTEXITCODE" 
        }

        # Создание внешних хешей
        foreach ($algo in $hashAlgos) {
            $hash = (Get-FileHash -Path $archivePath -Algorithm $algo).Hash
            $ext = "$($algo.ToLower())sums.txt"
            "${hash}  $($proj.Name)_artifacts.7z" | Set-Content -Path "${archivePath}.${ext}" -Encoding utf8
        }
    }
    finally {
        # Очистка временной директории
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "[SUCCESS] All artifacts created successfully! (^_^)"