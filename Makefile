.PHONY: build test clean

build:
	pwsh -NoProfile -Command "./Create-Artifacts.ps1"

test:
	pwsh -NoProfile -Command "Invoke-Pester ./tests/Artifacts.Tests.ps1"

clean:
	pwsh -Command "Get-ChildItem ./dev_build -Recurse -Include '*_artifacts.7z*' | Remove-Item -Force"
