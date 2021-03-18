# install 

Install needed powershell module
```install-module az -Scope CurrentUser -AllowClobber -Repository PSGallery```

Install required DCS modules
```
powershell.exe -NoLogo -NoProfile -Command '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name <module-name> -Force -Scope CurrentUser -AllowClobber -Repository PSGallery'
```

## Used modules

 - PackageManagement
 - xActiveDirectory
 - PSDesiredStateConfiguration
 - xActiveDirectory
 - xNetworking
 - ComputerManagementDSC
 - xComputerManagement
 - xDnsServer
 - NetworkingDsc
 - ActiveDirectoryDsc
 - CertificateDsc

Publish create a DCS zip file
```Publish-AzVMDscConfiguration .\deployrds.ps1 -OutputArchivePath '.\deployrds.zip'```

```DCS Modules URL: https://github.com/dsccommunity```

# Links 
[DSCCommunity github](https://github.com/dsccommunity)