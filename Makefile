.PHONY: build test clean

build:
    pwsh -NoProfile -Command "./Create-Artifacts.ps1"

test:
    pwsh -NoProfile -Command "Invoke-Pester ./tests/Artifacts.Tests.ps1"

clean:
    pwsh -Command "Remove-Item ./dev_build/*_artifacts.7z* -Force"
