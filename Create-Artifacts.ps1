# Create-Artifacts.ps1
#Requires -PSEdition Core
#Requires -Version 7.0

param(
    [string]$RootDir = './dev_build'
)

$ErrorActionPreference = 'Stop'
$RootDirFull = Join-Path $PSScriptRoot $RootDir -Resolve

# 1) Чистим старые архивы и всё, что к ним прилеплено
Get-ChildItem -Path $RootDirFull -Filter '*_artifacts.7z*' -Recurse |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 2) Проверяем 7-Zip
$sevenZipCmd = if ($IsWindows) { '7z.exe' } else { '7z' }
if (-not (Get-Command $sevenZipCmd -ErrorAction SilentlyContinue)) {
    throw "7-Zip not found! Install p7zip-full (Linux) or 7-Zip (Windows)"
}

# 3) Настройки
$hashAlgos       = @('MD5','SHA1','SHA256')
$excludePatterns = @('.gitkeep','tests','*_artifacts.7z*','distr.deb','syms.7z')

# 4) Цикл по проектам
Get-ChildItem -Path $RootDirFull -Directory |
  Where-Object { $_.Name -match '^(grpedit|modservice|rsysconf|scada)$' } |
  ForEach-Object {
    $proj        = $_
    $archiveName = "$($proj.Name)_artifacts.7z"
    $archivePath = Join-Path $proj.FullName $archiveName

    Write-Host "→ Обработка проекта: $($proj.Name)"

    # 4.1) Временная папка
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $tempDir   = Join-Path ([IO.Path]::GetTempPath()) "artifact_$($proj.Name)_$timestamp"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        # 4.2) Копируем всё, кроме артефактов и тестов
        Get-ChildItem -Path $proj.FullName -Recurse -File |
          Where-Object {
            $rel = $_.FullName.Substring($proj.FullName.Length+1).TrimStart('\','/').Replace('\','/')
            -not ($excludePatterns | Where-Object { $rel -like $_ })
          } |
          ForEach-Object {
            $rel      = $_.FullName.Substring($proj.FullName.Length+1).TrimStart('\','/').Replace('\','/')
            $destPath = Join-Path $tempDir $rel
            $destDir  = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
            Copy-Item $_.FullName -Destination $destPath -Force
          }

        # 4.3) Генерируем md5sums.txt, sha1sums.txt, sha256sums.txt
        foreach ($algo in $hashAlgos) {
          $sumsFile = Join-Path $tempDir ("$($algo.ToLower())sums.txt")
          Get-ChildItem -Path $tempDir -Recurse -File |
            Where-Object { $_.Name -notlike '*sums.txt' } |
            ForEach-Object {
              $relPath = $_.FullName.Substring($tempDir.Length+1).TrimStart('\','/').Replace('\','/')
              $hash    = (Get-FileHash $_.FullName -Algorithm $algo).Hash
              "$hash  $relPath" | Add-Content -Path $sumsFile -Encoding utf8
            }
        }

        # 4.4) Удаляем старый архив, если он вдруг остался
        if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

        # 4.5) Пакуем всё из tempDir
        Push-Location $tempDir
        try {
          & $sevenZipCmd a -t7z "$archivePath" * -mx9 -r -aoa | Out-Null
          if ($LASTEXITCODE -ne 0) { throw "7z failed with code $LASTEXITCODE" }
        }
        finally { Pop-Location }

        # 4.6) Создаём внешние хеш-файлы .md5, .sha1, .sha256
        foreach ($algo in $hashAlgos) {
          $ext  = $algo.ToLower()
          $hash = (Get-FileHash -Path $archivePath -Algorithm $algo).Hash
          "$hash  $archiveName" | Set-Content -Path "$archivePath.$ext" -Encoding utf8
        }
    }
    finally {
        # 4.7) Чистим tempDir
        if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
    }
}

Write-Host "`n[SUCCESS] All artifacts created successfully! (^_^)" -ForegroundColor Green
