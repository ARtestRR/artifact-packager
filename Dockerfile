FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

RUN apt-get update && apt-get install -y p7zip-full git
RUN pwsh -Command "Install-Module Pester -Force -Scope CurrentUser"

WORKDIR /app
COPY . /app 

CMD ["pwsh", "-Command", "./Create-Artifacts.ps1; Invoke-Pester ./tests/Artifacts.Tests.ps1"]