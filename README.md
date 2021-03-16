# install 

```powershell.exe -NoLogo -NoProfile -Command '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name PackageManagement -Force -MinimumVersion 1.4.6 -Scope CurrentUser -AllowClobber -Repository PSGallery'```
```install-module az -Scope CurrentUser -AllowClobber -Repository PSGallery```
```Publish-AzVMDscConfiguration .\webserverconfig.ps1 -OutputArchivePath '.\webserverconfig.zip'```