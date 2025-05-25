BeforeAll {
    $scriptDir = $PSScriptRoot
    $repoRoot = Resolve-Path (Join-Path $scriptDir '..')
    $testRoot = Join-Path $env:TEMP "pester_$(Get-Random)"
    
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $testRoot -ItemType Directory | Out-Null
    
    Copy-Item -Path (Join-Path $repoRoot 'dev_build') -Destination $testRoot -Recurse
}

Describe 'Artifact Validation' -Tag CI {
    BeforeEach {
        Set-Location $testRoot
    }

    It 'Archives exist for all projects' {
        $projects = Get-ChildItem -Path './dev_build' -Directory | 
            Where-Object { $_.Name -match '^(grpedit|modservice|rsysconf|scada)$' }
        $projects | ForEach-Object {
            Join-Path $_.FullName "$($_.Name)_artifacts.7z" | Should -Exist
        }
    }

    It 'Archive contains 3 hash files' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $tempDir = New-Item -ItemType Directory -Path $env:TEMP -Name "extract_$(Get-Random)"
            try {
                & 7z x $_.FullName "-o$($tempDir.FullName)" -y | Out-Null
                $hashFiles = Get-ChildItem -Path $tempDir -Filter '*sums.txt'
                $hashFiles.Count | Should -Be 3
            }
            finally {
                Remove-Item $tempDir -Recurse -Force
            }
        }
    }

    It 'Internal hashes match' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $tempDir = New-Item -ItemType Directory -Path $env:TEMP -Name "extract_$(Get-Random)"
            try {
                & 7z x $_.FullName "-o$($tempDir.FullName)" -y | Out-Null
                Get-ChildItem -Path $tempDir -Filter '*sums.txt' | ForEach-Object {
                    $sumFile = $_
                    Get-Content $sumFile | ForEach-Object {
                        $hash, $relPath = $_ -split '\s+', 2
                        $fullPath = Join-Path $tempDir $relPath
                        (Get-FileHash $fullPath -Algorithm ($sumFile.BaseName -replace 'sums$', '')).Hash | Should -Be $hash
                    }
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force
            }
        }
    }

    It 'External hash files are valid' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' | ForEach-Object {
            $archive = $_
            'MD5', 'SHA1', 'SHA256' | ForEach-Object {
                $algo = $_
                $hashFile = Get-Item "$($archive.FullName).$($algo.ToLower())sums.txt"
                $expectedHash = ($hashFile | Get-Content -Raw).Split()[0]
                (Get-FileHash $archive.FullName -Algorithm $algo).Hash | Should -Be $expectedHash
            }
        }
    }
}