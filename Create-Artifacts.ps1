#Requires -PSEdition Core
#Requires -Version 7.0

<#
.SYNOPSIS
    Упаковывает подпроекты в 7z-архивы с хешами
#>

param([string]$RootDir = '/app/dev_build')

$ErrorActionPreference = 'Stop'

$7zCommand = if (Get-Command '/usr/bin/7z' -ErrorAction SilentlyContinue) { '/usr/bin/7z' } 
            else { throw "7-Zip не найден. Установите p7zip-full" }

$hashAlgos = @('MD5','SHA1','SHA256')

Get-ChildItem -Path $RootDir -Directory | ForEach-Object {
    $proj = $_
    $name = $proj.Name
    $archive = Join-Path $proj.FullName "${name}_artifacts.7z"
    $tempDir = Join-Path "/tmp" "${name}_temp"

    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path "$($proj.FullName)/*" -Destination $tempDir -Recurse

        foreach ($algo in $hashAlgos) {
            $sumFile = Join-Path $tempDir "$($algo.ToLower())sums.txt"
            Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
                $hash = (Get-FileHash $_.FullName -Algorithm $algo).Hash
                $relPath = $_.FullName.Substring($tempDir.Length + 1)
                "$hash  $relPath" | Add-Content $sumFile -Encoding utf8
            }
        }

        & $7zCommand a -t7z "$archive" "$tempDir/*" -mx9
        if ($LASTEXITCODE -ne 0) { throw "Ошибка архивации" }

        foreach ($algo in $hashAlgos) {
            $hash = (Get-FileHash $archive -Algorithm $algo).Hash
            "$hash  ${name}_artifacts.7z" | Out-File -FilePath "$archive.$($algo.ToLower())" -Encoding utf8
        }
    }
    finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}