Configuration CreateRootDomain {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [Array]$RDSParameters,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$CertCreds
    )

    $DomainName = $RDSParameters[0].DomainName
    $TimeZoneID = $RDSParameters[0].TimeZoneID
    $DNSServer  = $RDSParameters[0].DNSServer
    $ExternalDnsDomain = $RDSParameters[0].ExternalDnsDomain
    $IntBrokerLBIP = $RDSParameters[0].IntBrokerLBIP
    $IntWebGWLBIP = $RDSParameters[0].IntWebGWLBIP
    $WebGWDNS = $RDSParameters[0].WebGWDNS
    $IntADFSIP = $RDSParameters[0].IntADFSIP
    $CertificateURL = $RDSParameters[0].CertificateURL
    $SASTOKEN = $RDSParameters[0].SASTOKEN
    $domain = $RDSParameters[0].domain
    $thumbprint = $RDSParameters[0].thumbprint


    Import-DscResource -ModuleName PsDesiredStateConfiguration,xActiveDirectory,xNetworking,ComputerManagementDSC
    Import-DscResource -ModuleName xComputerManagement,xDnsServer,NetworkingDsc,ActiveDirectoryDsc,CertificateDsc
    Import-DscResource -ModuleName xPSDesiredStateConfiguration,AdfsDsc
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)",$Admincreds.Password)
    [System.Management.Automation.PSCredential]$CertificateCreds = New-Object System.Management.Automation.PSCredential ($CertCreds.UserName,$CertCreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $MyIP = ($Interface | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -First 1).IPAddress
    $InterfaceAlias = $($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        WindowsFeature DNS
        {
            Ensure = "Present"
            Name = "DNS"
        }

        WindowsFeature AD-Domain-Services
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature DnsTools
        {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature GPOTools
        {
            Ensure = "Present"
            Name = "GPMC"
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature DFSTools
        {
            Ensure = "Present"
            Name = "RSAT-DFS-Mgmt-Con"
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature RSAT-AD-Tools
        {
            Ensure = "Present"
            Name = "RSAT-AD-Tools"
            DependsOn = "[WindowsFeature]AD-Domain-Services"
            IncludeAllSubFeature = $True
        }

        TimeZone SetTimeZone
        {
            IsSingleInstance = 'Yes'
            TimeZone = $TimeZoneID
        }

        Firewall EnableSMBFwRule
        {
            Name = "FPS-SMB-In-TCP"
            Enabled = $True
            Ensure = "Present"
        }

        xDnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn = "[WindowsFeature]DNS"
        }

        If ($MyIP -eq $DNSServer) {
            xADDomain RootDomain
            {
                DomainName = $DomainName
                DomainAdministratorCredential = $DomainCreds
                SafemodeAdministratorPassword = $DomainCreds
                DatabasePath = "$Env:windir\NTDS"
                LogPath = "$Env:windir\NTDS"
                SysvolPath = "$Env:windir\SYSVOL"
                DependsOn = @("[WindowsFeature]AD-Domain-Services", "[xDnsServerAddress]DnsServerAddress")
            }

            xDnsServerForwarder SetForwarders
            {
                IsSingleInstance = 'Yes'
                IPAddresses      = @('8.8.8.8', '8.8.4.4')
                UseRootHint      = $false
                DependsOn = @("[WindowsFeature]DNS", "[xADDomain]RootDomain")
            }

            Script AddExternalZone
            {
                SetScript = {
                    Add-DnsServerPrimaryZone -Name $Using:ExternalDnsDomain `
                        -ReplicationScope "Forest" `
                        -DynamicUpdate "Secure"
                }

                TestScript = {
                    If (Get-DnsServerZone -Name $Using:ExternalDnsDomain -ErrorAction SilentlyContinue) {
                        Return $True
                    } Else {
                        Return $False
                    }
                }

                GetScript = {
                    @{
                        Result = Get-DnsServerZone -Name $Using:ExternalDnsDomain -ErrorAction SilentlyContinue
                    }
                }

                DependsOn = "[xDnsServerForwarder]SetForwarders"
            }

            xDnsRecord AddIntLBBrokerIP
            {
                Name = "broker"
                Target = $IntBrokerLBIP
                Zone = $ExternalDnsDomain
                Type = "ARecord"
                Ensure = "Present"
                DependsOn = "[Script]AddExternalZone"
            }

            xDnsRecord AddIntLBWebGWIP
            {
                Name = $WebGWDNS
                Target = $IntWebGWLBIP
                Zone = $ExternalDnsDomain
                Type = "ARecord"
                Ensure = "Present"
                DependsOn = "[Script]AddExternalZone"
            }


            xDnsRecord AddIntADFSIP
            {
                Name = "sts"
                Target = $IntADFSIP
                Zone = $ExternalDnsDomain
                Type = "ARecord"
                Ensure = "Present"
                DependsOn = "[Script]AddExternalZone"
            }

            PendingReboot RebootAfterInstallingAD
            {
                Name = 'RebootAfterInstallingAD'
                DependsOn = @("[xADDomain]RootDomain","[xDnsServerForwarder]SetForwarders")
            }
        } Else {
            xWaitForADDomain DscForestWait
            {
                DomainName = $DomainName
                DomainUserCredential= $DomainCreds
                RetryCount = 30
                RetryIntervalSec = 2400
                DependsOn = @("[WindowsFeature]AD-Domain-Services", "[xDnsServerAddress]DnsServerAddress")
            }

            xADDomainController NextDC
            {
                DomainName = $DomainName
                DomainAdministratorCredential = $DomainCreds
                SafemodeAdministratorPassword = $DomainCreds
                DatabasePath = "$Env:windir\NTDS"
                LogPath = "$Env:windir\NTDS"
                SysvolPath = "$Env:windir\SYSVOL"
                DependsOn = @("[xWaitForADDomain]DscForestWait","[WindowsFeature]AD-Domain-Services", "[xDnsServerAddress]DnsServerAddress")
            }

            xDnsServerForwarder SetForwarders
            {
                IsSingleInstance = 'Yes'
                IPAddresses      = @('8.8.8.8', '8.8.4.4')
                UseRootHint      = $false
                DependsOn = @("[WindowsFeature]DNS", "[xADDomainController]NextDC")
            }

            PendingReboot RebootAfterInstallingAD
            {
                Name = 'RebootAfterInstallingAD'
                DependsOn = @("[xADDomainController]NextDC","[xDnsServerForwarder]SetForwarders")
            }
        }

        WindowsFeature adfs-federation
        {
            Ensure = "Present"
            Name = "adfs-federation"
            IncludeAllSubFeature = $True
            DependsOn = "[PendingReboot]RebootAfterInstallingAD"
        }
        ADKDSKey CreateKDSRootKeyInPast
        {
            Ensure                   = 'Present'
            EffectiveTime            = '1/1/2021 13:00'
            AllowUnsafeEffectiveTime = $true # Use with caution
        }
        ADManagedServiceAccount AddADFSGMSA
        {
            Ensure                    = 'Present'
            ServiceAccountName        = 'adfs_gmsa'
            AccountType               = 'Group'
            ManagedPasswordPrincipals = 'Domain Controllers'
            DependsOn = "[ADKDSKey]CreateKDSRootKeyInPast"
        }

        xRemoteFile DownloadCertificate
        {
            DestinationPath = "$env:SystemDrive\certificate.pfx"
            Uri             = "${CertificateURL}${SASTOKEN}"
            UserAgent       = [Microsoft.PowerShell.Commands.PSUserAgent]::InternetExplorer
            Headers = @{
                'Accept-Language' = 'en-US'
            }
        }

        PfxImport importCertificate
        {
            Thumbprint   = "$thumbprint"
            Location     = 'LocalMachine'
            Store        = 'My'
            Path         = "$env:SystemDrive\certificate.pfx"
            Credential   = $CertificateCreds
            DependsOn    = "[xRemoteFile]DownloadCertificate"
        }

        AdfsFarm ConfigureADFS
        {
            FederationServiceName         = "sts.$ExternalDnsDomain"
            FederationServiceDisplayName  = "$domain dev ADFS Service"
            CertificateThumbprint         = "$thumbprint"
            GroupServiceAccountIdentifier = "$domain\adfs_gmsa$"
            Credential                    = $DomainCreds
        }

        AdfsProperties ADFSFarmProperties
        {
            FederationServiceName    = "sts.$ExternalDnsDomain"
            EnableIdPInitiatedSignonPage = $True
            AutoCertificateRollover = $False
            DependsOn = "[AdfsFarm]ConfigureADFS"
        }

        # AdfsCertificate TokenSigningCertificates
        # {
        #     CertificateType = 'Token-Signing'
        #     Thumbprint      = "$thumbprint"
        #     DependsOn = "[AdfsProperties]ADFSFarmProperties"
        # }
#
        # AdfsCertificate TokenDecryptingCertificates
        # {
        #     CertificateType = 'Token-Decrypting'
        #     Thumbprint      = "$thumbprint"
        #     DependsOn = "[AdfsProperties]ADFSFarmProperties"
        # }

        PendingReboot RebootAfterADFSconfigure
        {
            Name = 'RebootAfterInstallingAD'
            #DependsOn = @("[AdfsCertificate]TokenSigningCertificates","[AdfsCertificate]TokenDecryptingCertificates")
            DependsOn = "[AdfsProperties]ADFSFarmProperties"
        }

        AdfsRelyingPartyTrust RelyingPartyHomepage
        {
            Name                    = 'www.mideye.com'
            Enabled                 = $true
            MetadataURL             = 'https://www.mideye.com/?option=mosaml_metadata'
            Notes                   = 'This is a trust for https://www.mideye.com dev'
            AccessControlPolicyName = 'Permit Everyone'
            IssuanceTransformRules  = @(
                MSFT_AdfsIssuanceTransformRule
                {
                    TemplateName   = 'LdapClaims'
                    Name           = 'WebApp1 Ldap Claims'
                    AttributeStore = 'Active Directory'
                    LdapMapping    = @(
                        MSFT_AdfsLdapMapping
                        {
                            LdapAttribute     = 'objectSID'
                            OutgoingClaimType = 'http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid'
                        }
                        MSFT_AdfsLdapMapping
                        {
                            LdapAttribute     = 'userPrincipalName'
                            OutgoingClaimType = 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'
                        }
                        MSFT_AdfsLdapMapping
                        {
                            LdapAttribute     = 'mail'
                            OutgoingClaimType = 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'
                        }
                    )
                }
            )
            DependsOn = "[PendingReboot]RebootAfterADFSconfigure"
        }
    }
}

Configuration WebApplicationProxy {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [Array]$RDSParameters,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$CertCreds
    )

    $DomainName = $RDSParameters[0].DomainName
    $DNSServer = $RDSParameters[0].DNSServer
    $TimeZoneID = $RDSParameters[0].TimeZoneID
    $DomainName = $RDSParameters[0].DomainName
    $TimeZoneID = $RDSParameters[0].TimeZoneID
    $DNSServer  = $RDSParameters[0].DNSServer
    $CertificateURL = $RDSParameters[0].CertificateURL
    $SASTOKEN = $RDSParameters[0].SASTOKEN
    $thumbprint = $RDSParameters[0].thumbprint
    $FederationServiceName = $RDSParameters[0].FederationServiceName

    Import-DscResource -ModuleName PSDesiredStateConfiguration,xNetworking,ActiveDirectoryDsc,ComputerManagementDSC
    import-DscResource -ModuleName xComputerManagement,NetworkingDsc,cWAP,CertificateDsc,xPSDesiredStateConfiguration
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)",$Admincreds.Password)
    [System.Management.Automation.PSCredential]$CertificateCreds = New-Object System.Management.Automation.PSCredential ($CertCreds.UserName,$CertCreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        WindowsFeature RSAT-AD-PowerShell
        {
            Ensure = "Present"
            Name = "RSAT-AD-PowerShell"
        }

        WindowsFeature RSAT-RemoteAccess
        {
            Ensure = "Present"
            Name = "RSAT-RemoteAccess"
        }

        WindowsFeature Web-Application-Proxy
        {
            Ensure = "Present"
            Name = "Web-Application-Proxy"
        }

        xRemoteFile DownloadCertificate
        {
            DestinationPath = "$env:SystemDrive\certificate.pfx"
            Uri             = "${CertificateURL}${SASTOKEN}"
            UserAgent       = [Microsoft.PowerShell.Commands.PSUserAgent]::InternetExplorer
            Headers = @{
                'Accept-Language' = 'en-US'
            }
        }

        PfxImport importCertificate
        {
            Thumbprint   = "$thumbprint"
            Location     = 'LocalMachine'
            Store        = 'My'
            Path         = "$env:SystemDrive\certificate.pfx"
            Credential   = $CertificateCreds
            DependsOn    = "[xRemoteFile]DownloadCertificate"
        }

        TimeZone SetTimeZone
        {
            IsSingleInstance = 'Yes'
            TimeZone = $TimeZoneID
        }

        Firewall EnableSMBFwRule
        {
            Name = "FPS-SMB-In-TCP"
            Enabled = $True
            Ensure = "Present"
        }

        xDnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
        }

        WaitForADDomain WaitADDomain
        {
            DomainName = $DomainName
            Credential = $DomainCreds
            WaitTimeout = 2400
            RestartCount = 30
            WaitForValidCredentials = $True
            DependsOn = @("[xDnsServerAddress]DnsServerAddress","[WindowsFeature]RSAT-AD-PowerShell")
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn = "[WaitForADDomain]WaitADDomain"
        }

        #PendingReboot RebootAfterDomainJoin
        #{
        #    Name = 'RebootAfterDomainJoin'
        #    DependsOn = "[xComputer]DomainJoin"
        #}
            #TODO: Fix cWAP module. Meanwhile run command manually.
            # Install-WebApplicationProxy -CertificateThumbprint $thumbprint -FederationServiceName $adfsFqdn
        #cWAPConfiguration ConfigureWAP
        #{
        #    Ensure   = "Present"
        #    FederationServiceName = $FederationServiceName
        #    Credential = $DomainCreds
        #    CertificateThumbprint = $thumbprint
        #    DependsOn = @("[xComputer]DomainJoin","[PfxImport]importCertificate")
        #}

        PendingReboot RebootAfterConfigureWAP
        {
            Name = 'RebootAfterConfigureWAP'
            DependsOn = "[xComputer]DomainJoin"
        }
    }
}

Configuration RDWebGateway {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [Array]$RDSParameters,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$CertCreds

    )

    $DomainName = $RDSParameters[0].DomainName
    $DNSServer = $RDSParameters[0].DNSServer
    $TimeZoneID = $RDSParameters[0].TimeZoneID
    $ExternalDnsDomain = $RDSParameters[0].ExternalDnsDomain
    $CertificateURL = $RDSParameters[0].CertificateURL
    $SASTOKEN = $RDSParameters[0].SASTOKEN
    $thumbprint = $RDSParameters[0].thumbprint

    Import-DscResource -ModuleName PSDesiredStateConfiguration,xNetworking,ActiveDirectoryDsc,ComputerManagementDSC,xComputerManagement
    Import-DscResource -ModuleName xWebAdministration,NetworkingDsc,CertificateDsc,xPSDesiredStateConfiguration
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)",$Admincreds.Password)
    [System.Management.Automation.PSCredential]$CertificateCreds = New-Object System.Management.Automation.PSCredential ($CertCreds.UserName,$CertCreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        WindowsFeature RDS-Gateway
        {
            Ensure = "Present"
            Name = "RDS-Gateway"
        }

        WindowsFeature RDS-Web-Access
        {
            Ensure = "Present"
            Name = "RDS-Web-Access"
        }

        WindowsFeature RSAT-AD-PowerShell
        {
            Ensure = "Present"
            Name = "RSAT-AD-PowerShell"
        }

        xRemoteFile DownloadCertificate
        {
            DestinationPath = "$env:SystemDrive\certificate.pfx"
            Uri             = "${CertificateURL}${SASTOKEN}"
            UserAgent       = [Microsoft.PowerShell.Commands.PSUserAgent]::InternetExplorer
            Headers = @{
                'Accept-Language' = 'en-US'
            }
        }

        PfxImport importCertificate
        {
            Thumbprint   = "$thumbprint"
            Location     = 'LocalMachine'
            Store        = 'My'
            Path         = "$env:SystemDrive\certificate.pfx"
            Credential   = $CertificateCreds
            DependsOn    = "[xRemoteFile]DownloadCertificate"
        }

        TimeZone SetTimeZone
        {
            IsSingleInstance = 'Yes'
            TimeZone = $TimeZoneID
        }

        Firewall EnableSMBFwRule
        {
            Name = "FPS-SMB-In-TCP"
            Enabled = $True
            Ensure = "Present"
        }

        xIISMimeTypeMapping ConfigureMIME
        {
            Extension = "."
            MimeType = "text/plain"
            ConfigurationPath = "IIS:\sites\Default Web Site"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]RDS-Web-Access"
        }

        xDnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
        }

        WaitForADDomain WaitADDomain
        {
            DomainName = $DomainName
            Credential = $DomainCreds
            WaitTimeout = 2400
            RestartCount = 30
            WaitForValidCredentials = $True
            DependsOn = @("[xDnsServerAddress]DnsServerAddress","[WindowsFeature]RSAT-AD-PowerShell")
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn = "[WaitForADDomain]WaitADDomain"
        }
    }
}