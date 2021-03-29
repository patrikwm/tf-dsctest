
$modules = "PackageManagement",
           "xActiveDirectory",
           #"PSDesiredStateConfiguration",
           "xActiveDirectory",
           "xNetworking",
           "ComputerManagementDSC",
           "xComputerManagement",
           "xDnsServer",
           "NetworkingDsc",
           "ActiveDirectoryDsc",
           "CertificateDsc",
           "AdfsDsc",
           "cWAP",
           "xWebAdministration",
           "xRemoteDesktopSessionHost"


foreach ($item in $modules) {
    powershell.exe -NoLogo -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name ${item} -Force -Scope CurrentUser -AllowClobber -Repository PSGallery"
}

