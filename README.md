# install 

```
powershell.exe -NoLogo -NoProfile -Command '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name PackageManagement -Force -MinimumVersion 1.4.6 -Scope CurrentUser -AllowClobber -Repository PSGallery'

powershell.exe -NoLogo -NoProfile -Command '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name xActiveDirectory -Force -Scope CurrentUser -AllowClobber -Repository PSGallery'
```

```install-module az -Scope CurrentUser -AllowClobber -Repository PSGallery```

```Publish-AzVMDscConfiguration .\deployrds.ps1 -OutputArchivePath '.\deployrds.zip'```



https://github.com/patrikwm/tf-dsctest/blob/main/webserverconfig.zip


https://raw.githubusercontent.com/ptrikwm/tf-dsctest/main/