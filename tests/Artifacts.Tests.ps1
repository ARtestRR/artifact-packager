BeforeAll {
    $scriptDir = $PSScriptRoot
    $repoRoot  = Resolve-Path (Join-Path $scriptDir '..')
    $testRoot  = Join-Path $env:TEMP "pester_$(Get-Random)"
    
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $testRoot -ItemType Directory | Out-Null
    
    Copy-Item -Path (Join-Path $repoRoot 'dev_build') -Destination $testRoot -Recurse
    Set-Location $testRoot
}

Describe 'Проверка артефактов' -Tag CI {
    It 'Архивы созданы для всех проектов' {
        Get-ChildItem -Directory './dev_build' | ForEach-Object {
            Join-Path $_.FullName "$($_.Name)_artifacts.7z" | Should -Exist
        }
    }

    It 'Архив содержит 3 файла хешей' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $tempDir = Join-Path $env:TEMP "extract_$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory | Out-Null
            try {
                & '7z' x $_.FullName "-o$tempDir" -y | Out-Null
                (Get-ChildItem $tempDir -Filter '*sums.txt').Count | Should -Be 3
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
                & '7z' x $_.FullName "-o$tempDir" -y | Out-Null
                Get-ChildItem $tempDir -Filter '*sums.txt' | ForEach-Object {
                    $sumFile = $_
                    Get-Content $sumFile | ForEach-Object {
                        $hash, $relPath = $_ -split '\s+', 2
                        $fullPath = Join-Path $tempDir ($relPath -replace '/', [IO.Path]::DirectorySeparatorChar)
                        (Get-FileHash $fullPath -Algorithm ($sumFile.BaseName -replace 'sums$', '')).Hash | Should -Be $hash
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
            'MD5','SHA1','SHA256' | ForEach-Object {
                $algo = $_
                $hashFile = "$archivePath.$($algo.ToLower())"
                $expected = (Get-Content $hashFile).Split()[0]
                (Get-FileHash $archivePath -Algorithm $algo).Hash | Should -Be $expected
            }
        }
    }
}
