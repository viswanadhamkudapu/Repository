configuration DomainJoin 
{ 
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds,

        [Int]$RetryCount=200,

        [Int]$RetryIntervalSec=30
    ) 
    
Import-DscResource -ModuleName xActiveDirectory, xComputerManagement, xNetworking, PSDesiredStateConfiguration

    $domainCreds = New-Object System.Management.Automation.PSCredential ("$domainName\$($adminCreds.UserName)", $adminCreds.Password)
   
    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADPowershell
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }
        
        xWaitForADDomain DscForestWait 
        { 
            DomainName = $domainName 
            DomainUserCredential= $domainCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
            DependsOn = "[WindowsFeature]ADPowershell" 
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $domainName
            Credential = $domainCreds
            DependsOn = "[xWaitForADDomain]DscForestWait" 
        } 
        Registry RdmsEnableUILog
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDMS"
            ValueName = "EnableUILog"
            ValueType = "Dword"
            ValueData = "1"
        }

        Registry EnableDeploymentUILog
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDMS"
            ValueName = "EnableDeploymentUILog"
            ValueType = "Dword"
            ValueData = "1"
        }

        Registry EnableTraceLog
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDMS"
            ValueName = "EnableTraceLog"
            ValueType = "Dword"
            ValueData = "1"
        }

        Registry EnableTraceToFile
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDMS"
            ValueName = "EnableTraceToFile"
            ValueType = "Dword"
            ValueData = "1"
        }
   }
}


configuration SessionHost
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 
        
    Import-DscResource -ModuleName xActiveDirectory, xComputerManagement, xNetworking, PSDesiredStateConfiguration
    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }
        xFirewall FirewallRuleForGWRDSH
        {
            Direction = "Inbound"
            Name = "Firewall-GW-RDSH-TCP-In"
            DisplayName = "Firewall-GW-RDSH-TCP-In"
            Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            DisplayGroup = "Connection Broker"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = "5985"
            Ensure = "Present"
        }
        WindowsFeature RDS-RD-Server
        {
            Ensure = "Present"
            Name = "RDS-RD-Server"
        }
    }
}


 $MemberofDomain=(Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain
do{
if($MemberofDomain -eq 'True'){
break
}else{
$MemberofDomain}
}until(start-sleep -Seconds 2)

function Write-Log
    { 
    [CmdletBinding()] 
    param
    ( 
        [Parameter(Mandatory = $false)] 
        [string]$Message,
        [Parameter(Mandatory = $false)] 
        [string]$Error 
    ) 
     
    try
    { 
        $DateTime = Get-Date -Format ‘MM-dd-yy HH:mm:ss’ 
        $Invocation = "$($MyInvocation.MyCommand.Source):$($MyInvocation.ScriptLineNumber)" 
        if ($Message)
        {
            Add-Content -Value "$DateTime - $Invocation - $Message" -Path "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\ScriptLog1.log" 
        }
        else
        {
            Add-Content -Value "$DateTime - $Invocation - $Error" -Path "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\ScriptLog1.log" 
        }
    } 
    catch
    { 
        Write-Error $_.Exception.Message 
    } 
    }

if($MemberofDomain -eq "True")
{
$MemberofDomain=Get-WmiObject -Class Win32_ComputerSystem
$computerName = $MemberofDomain.Name
$nameoftheDomain = $MemberofDomain.Domain
Write-Log -Message "'$computerName' computer is member of domain '$nameoftheDomain'"
}else{
# Workgroup (string Property)
    $MemberofWorkgroup=Get-WmiObject -Class Win32_ComputerSystem
    $computerName = $MemberofWorkgroup.Name
    $nameoftheDomain = $MemberofWorkgroup.Domain
  Write-Log -Message "'$computerName' computer is member of '$nameoftheDomain'"

}