Describe 'Artifact Validation' -Tag CI {

    It 'Archives exist for all projects' {
        Get-ChildItem -Path './dev_build' -Directory |
          Where-Object Name -Match '^(grpedit|modservice|rsysconf|scada)$' |
          ForEach-Object {
            Join-Path $_.FullName "$($_.Name)_artifacts.7z" | Should -Exist
          }
    }

    It 'Archive contains 3 hash files' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' |
          ForEach-Object {
            $temp = New-Item -ItemType Directory -Path $env:TEMP -Name "extract_$(Get-Random)"
            try {
              & 7z x $_.FullName "-o$($temp.FullName)" -y | Out-Null
              (Get-ChildItem -Path $temp -Filter '*sums.txt').Count | Should -Be 3
            } finally {
              Remove-Item $temp -Recurse -Force
            }
          }
    }

    It 'Internal hashes match' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' |
          ForEach-Object {
            $temp = New-Item -ItemType Directory -Path $env:TEMP -Name "extract_$(Get-Random)"
            try {
              & 7z x $_.FullName "-o$($temp.FullName)" -y | Out-Null
              Get-ChildItem -Path $temp -Filter '*sums.txt' | ForEach-Object {
                $sumFile = $_
                Get-Content $sumFile | ForEach-Object {
                  $hash, $rel = $_ -split '\s+', 2
                  $filePath = Join-Path $temp $rel
                  (Get-FileHash $filePath -Algorithm ($sumFile.BaseName -replace 'sums$', '')).Hash |
                    Should -Be $hash
                }
              }
            } finally {
              Remove-Item $temp -Recurse -Force
            }
          }
    }

    It 'External hash files are valid' {
        Get-ChildItem -Path './dev_build' -Filter '*_artifacts.7z' |
          ForEach-Object {
            $archive = $_.FullName
            'MD5','SHA1','SHA256' | ForEach-Object {
              $algo     = $_.ToLower()
              $hashFile = "$archive.$algo"
              (Get-Content $hashFile -Raw).Split()[0] |
                Should -Be (Get-FileHash -Path $archive -Algorithm $_).Hash
            }
          }
    }

}
