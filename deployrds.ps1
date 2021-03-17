Configuration CreateRootDomain {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [Array]$RDSParameters
    )

    $DomainName = $RDSParameters[0].DomainName
    $TimeZoneID = $RDSParameters[0].TimeZoneID
    $DNSServer  = $RDSParameters[0].DNSServer
    $ExternalDnsDomain = $RDSParameters[0].ExternalDnsDomain
    $IntBrokerLBIP = $RDSParameters[0].IntBrokerLBIP
    $IntWebGWLBIP = $RDSParameters[0].IntWebGWLBIP
    $WebGWDNS = $RDSParameters[0].WebGWDNS
    $IntADFSIP = $RDSParameters[0].IntADFSIP

    Import-DscResource -ModuleName PsDesiredStateConfiguration,xActiveDirectory,xNetworking,ComputerManagementDSC,xComputerManagement,xDnsServer,NetworkingDsc
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)",$Admincreds.Password)
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
    }
}

