BeforeAll {
    # Вычисляем корень репозитория
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $repoRoot  = Resolve-Path (Join-Path $scriptDir '..') -ErrorAction Stop

    $testRoot = Join-Path $env:TEMP "pester_$(Get-Random)"
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $testRoot -ItemType Directory | Out-Null

    # Копируем dev_build из корня репозитория
    Copy-Item -Path (Join-Path $repoRoot 'dev_build') -Destination $testRoot -Recurse
    Set-Location $testRoot
}

Describe 'Проверка артефактов' {
    It 'Архивы созданы для всех проектов' {
        Get-ChildItem -Directory './dev_build' | ForEach-Object {
            $archivePath = Join-Path $_.FullName "$($_.Name)_artifacts.7z"
            $archivePath | Should -Exist
        }
    }

    It 'Архив содержит 3 файла хешей' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $tempDir = Join-Path $env:TEMP "extract_$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory | Out-Null
            try {
                & /usr/bin/7z x "$($_.FullName)" "-o$tempDir" -y | Out-Null
                (Get-ChildItem $tempDir -Recurse -Include '*sums.txt').Count | Should -Be 3
            }
            finally {
                Remove-Item $tempDir -Recurse -Force
            }
        }
    }

    It 'Внутренние хеши совпадают' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $tempDir = Join-Path $env:TEMP "extract_$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory | Out-Null
            try {
                & /usr/bin/7z x "$($_.FullName)" "-o$tempDir" -y | Out-Null
                foreach ($sumFile in (Get-ChildItem $tempDir -Recurse -Include '*sums.txt')) {
                    Get-Content $sumFile | ForEach-Object {
                        $hash, $relPath = $_ -split '\s+', 2
                        $fullPath = Join-Path $tempDir $relPath
                        (Get-FileHash $fullPath -Algorithm ($sumFile.BaseName -replace 'sums$', '')).Hash |
                            Should -Be $hash
                    }
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force
            }
        }
    }

    It 'Внешние хеши архива валидны' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $archivePath = $_.FullName
            foreach ($algo in 'MD5', 'SHA1', 'SHA256') {
                $hashFile = "$archivePath.$($algo.ToLower())"
                $expectedHash = (Get-Content $hashFile).Split()[0]
                $actualHash = (Get-FileHash $archivePath -Algorithm $algo).Hash
                $actualHash | Should -Be $expectedHash
            }
        }
    }

    It 'Хеши разных архивов уникальны' {
        $allHashes = Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        }
        $uniqueHashes = $allHashes | Sort-Object -Unique
        $uniqueHashes.Count | Should -Be $allHashes.Count
    }
}