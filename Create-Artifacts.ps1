#Requires -PSEdition Core
#Requires -Version 7.0

param(
    [string]$RootDir = './dev_build'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$RootDirFull = Join-Path $ScriptDir $RootDir -Resolve

# Проверка 7-Zip
$sevenZipCmd = if ($IsWindows) { '7z.exe' } else { '7z' }
if (-not (Get-Command $sevenZipCmd -ErrorAction SilentlyContinue)) {
    throw "7-Zip not found! Install p7zip-full (Linux) or 7-Zip (Windows)"
}

$hashAlgos = @('MD5', 'SHA1', 'SHA256')
$excludePatterns = @('.gitkeep', 'distr.deb', 'syms.7z', 'tests')

Get-ChildItem -Path $RootDirFull -Directory | Where-Object {
    $_.Name -match '^(grpedit|modservice|rsysconf|scada)$'
} | ForEach-Object {
    $proj = $_
    $archivePath = Join-Path $proj.FullName "$($proj.Name)_artifacts.7z"
    
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name "artifacts_$(Get-Random)"
    try {
        # Копирование только нужных файлов
        Get-ChildItem -Path $proj.FullName -Exclude $excludePatterns |
            Copy-Item -Destination $tempDir -Recurse -Force

        # Создание хеш-файлов
        $hashAlgos | ForEach-Object {
            $algo = $_
            $sumFile = Join-Path $tempDir "$($algo.ToLower())sums.txt"
            
            Get-ChildItem -Path $tempDir -Recurse -File -Exclude '*sums.txt' |
                ForEach-Object {
                    $relPath = $_.FullName.Substring($tempDir.FullName.Length + 1)
                    $hash = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                    "${hash}  ${relPath}" | Add-Content -Path $sumFile -Encoding utf8
                }
        }

        # Архивирование
        & $sevenZipCmd a -t7z $archivePath "$(Join-Path $tempDir '*')" -mx9 -r
        if ($LASTEXITCODE -ne 0) { throw "Archive failed for $($proj.Name)" }

        # Создание внешних хешей
        $hashAlgos | ForEach-Object {
            $algo = $_
            $hash = (Get-FileHash -Path $archivePath -Algorithm $algo).Hash
            "${hash}  $($proj.Name)_artifacts.7z" | Set-Content -Path "$archivePath.$($algo.ToLower())" -Encoding utf8
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[SUCCESS] All artifacts created successfully!"