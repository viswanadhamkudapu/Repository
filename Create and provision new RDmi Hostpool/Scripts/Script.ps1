<#

.SYNOPSIS
Creating Hostpool and add sessionhost servers to existing/new Hostpool.

.DESCRIPTION
This script add sessionhost servers to existing/new Hostpool
The supported Operating Systems Windows Server 2016.

.ROLE
Readers

#>
param(
    [Parameter(mandatory = $false)]
    [string]$RDBrokerURL,

    [Parameter(mandatory = $false)]
    [string]$TenantName,

    [Parameter(mandatory = $false)]
    [string]$HostPoolName,

    [Parameter(mandatory = $false)]
    [string]$Description,

    [Parameter(mandatory = $false)]
    [string]$FriendlyName,

    [Parameter(mandatory = $true)]
    [string]$Hours,
	
	[Parameter(mandatory = $true)]
    [string]$rdshIs1809OrLater,

    [Parameter(Mandatory = $false)]
    [string]$ActivationKey,
    
    [Parameter(mandatory = $false)]
    [string]$TenantAdminUPN,

    [Parameter(mandatory = $false)]
    [string]$TenantAdminPassword,

    [Parameter(mandatory = $true)]
    [string]$localAdminUserName,

    [Parameter(mandatory = $true)]
    [string]$registrationToken,

    [Parameter(mandatory = $true)]
    [string]$localAdminPassword
)

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String

function Write-Log { 


    [CmdletBinding()] 
    param ( 
        [Parameter(Mandatory = $false)] 
        [string]$Message,
        [Parameter(Mandatory = $false)] 
        [string]$Error 
    ) 
     
    try { 


        $DateTime = Get-Date -Format ‘MM-dd-yy HH:mm:ss’ 
        $Invocation = "$($MyInvocation.MyCommand.Source):$($MyInvocation.ScriptLineNumber)" 
        if ($Message) {
            Add-Content -Value "$DateTime - $Invocation - $Message" -Path "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\ScriptLog.log" 
        }
        else {
            Add-Content -Value "$DateTime - $Invocation - $Error" -Path "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\ScriptLog.log" 
        }
    } 
    catch { 


        Write-Error $_.Exception.Message 
    } 
}

Write-Log -Message "Policy List: $log"

function ActivateWin10
{
    param
    (
        [Parameter(Mandatory = $false)] 
        [string]$ActivationKey
    )

    cscript c:\windows\system32\slmgr.vbs /ipk $ActivationKey
    dism /online /Enable-Feature /FeatureName:AppServerClient /NoRestart /Quiet
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    
    $ScriptPath = [system.io.path]::GetDirectoryName($PSCommandPath)
	$DeployAgentLocation = "C:\DeployAgent"
	$rdshIs1809OrLaterBool = ($rdshIs1809OrLater -eq "True")

	
	Write-Log -Message "Creating a folder inside rdsh vm for extracting deployagent zip file"
	if (Test-Path $DeployAgentLocation)
	{
    Remove-Item -Path $DeployAgentLocation -Force -Confirm:$false -Recurse
	}

	New-Item -Path "$DeployAgentLocation" -ItemType directory -Force 

	# Locating and extracting DeployAgent.zip
	Write-Log -Message "Locating DeployAgent.zip within Custom Script Extension folder structure: $ScriptPath"
	$DeployAgentFromRepo = (Get-ChildItem $ScriptPath\ -Filter DeployAgent.zip -Recurse | Select-Object).FullName
	if ((-not $DeployAgentFromRepo) -or (-not (Test-Path $DeployAgentFromRepo)))
	{
    throw "DeployAgent.zip file not found at $ScriptPath"
	}

	Write-Log -Message "Extracting 'Deployagent.zip' file into '$DeployAgentLocation' folder inside VM"
	Expand-Archive $DeployAgentFromRepo -DestinationPath "$DeployAgentLocation" 

	Write-Log -Message "Changing current folder to Deployagent folder: $DeployAgentLocation"
	Set-Location "$DeployAgentLocation"
	
    #Checking if RDInfragent is registered or not in rdsh vm
    $CheckRegistery = Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDInfraAgent" -ErrorAction SilentlyContinue

    Write-Log -Message "Checking whether VM was Registered with RDInfraAgent"

    if ($CheckRegistery) {
        Write-Log -Message "VM was already registered with RDInfraAgent, script execution was stopped"

    }
    else {
    
        Write-Log -Message "VM was not registered with RDInfraAgent, script is executing"
    }


   
    if (!$CheckRegistery) {


        if($registrationToken -eq " ") 
        {
            #Importing RDMI PowerShell module
            Import-Module .\PowershellModules\Microsoft.RDInfra.RDPowershell.dll
            Write-Log -Message "Imported RDMI PowerShell modules successfully"
            $Securepass = ConvertTo-SecureString -String $TenantAdminPassword -AsPlainText -Force
            $Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($TenantAdminUPN, $Securepass)
            $AdminSecurepass = ConvertTo-SecureString -String $localAdminPassword -AsPlainText -Force
            $adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($localAdminUserName, $AdminSecurepass)

            #Getting fqdn of rdsh vm
            $SessionHostName = (Get-WmiObject win32_computersystem).DNSHostName + "." + (Get-WmiObject win32_computersystem).Domain
            Write-Log  -Message "Getting fully qualified domain name of RDSH VM: $SessionHostName"

    
            #Setting RDS Context
            #$authentication = Set-RdsContext -DeploymentUrl $RDBrokerURL -Credential $Credentials
            $authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Credentials
            $obj = $authentication | Out-String
    
            if ($authentication) {
                Write-Log -Message "RDMI Authentication successfully Done. Result: `
       $obj"  
            }
            else {
                Write-Log -Error "RDMI Authentication Failed, Error: `
       $obj"
        
            }
    
            $HPName = Get-RdsHostPool -TenantName $TenantName -Name $HostPoolName -ErrorAction SilentlyContinue
            Write-Log -Message "Checking Hostpool exists inside the Tenant"

            if ($HPName) {
                $HPName = Get-RdsHostPool -TenantName $TenantName -Name $HostPoolName -ErrorAction SilentlyContinue
                Write-log -Message "Hostpool exists inside tenant: $TenantName"


                Write-Log -Message "Checking Hostpool UseResversconnect is true or false"
                # Cheking UseReverseConnect is true or false
                if ($HPName.UseReverseConnect -eq $False) {

                    Write-Log -Message "Usereverseconnect is false, it will be changed to true"
                    Set-RdsHostPool -TenantName $TenantName -Name $HostPoolName -UseReverseConnect $true
                }
                else {
                    Write-Log -Message "Hostpool Usereverseconnect already enabled as true"
                }



                #Exporting existed rdsregisterationinfo of hostpool
                $Registered = Export-RdsRegistrationInfo -TenantName $TenantName -HostPoolName $HostPoolName
                $reglog = $registered | Out-String
                Write-Log -Message "Exported Rds RegisterationInfo into variable 'Registered': $reglog"
                $systemdate = (GET-DATE)
                #$Tokenexpiredate = $Registered.ExpirationUtc #June Codebit
                $Tokenexpiredate = $Registered.expirationtime #July Codebit
                $difference = $Tokenexpiredate - $systemdate
                write-log -Message "Calculating date and time of expiration with system date and time"
                if ($difference -lt 0 -or $Registered -eq 'null') {
                    write-log -Message "Registerationinfo expired, creating new registeration info with hours $Hours"
                    $Registered = New-RdsRegistrationInfo -TenantName $TenantName -HostPoolName $HostPoolName -ExpirationHours $Hours
                }
                else {

                    $reglogexpired = $Tokenexpiredate | Out-String -Stream
                    Write-Log -Message "Registerationinfo not expired and expiring on $reglogexpired"
                }
                #Executing DeployAgent psl file in rdsh vm and add to hostpool
                $DAgentInstall = .\DeployAgent.ps1 -ComputerName $SessionHostName -AgentBootServiceInstaller ".\RDAgentBootLoaderInstall\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi" -AgentInstaller ".\RDInfraAgentInstall\Microsoft.RDInfra.RDAgent.Installer-x64.msi" -SxSStackInstaller ".\RDInfraSxSStackInstall\Microsoft.RDInfra.StackSxS.Installer-x64.msi" -AdminCredentials $adminCredentials -TenantName $TenantName -PoolName $HostPoolName -RegistrationToken $Registered.Token -StartAgent $true
                Write-Log -Message "DeployAgent Script was successfully executed and RDAgentBootLoader,RDAgent,StackSxS installed inside VM for existing hostpool: $HostPoolName `
        $DAgentInstall"
            }

            else {
                Write-Log -Message "Hostpool does not exists inside tenant: $TenantName"

                # creating new hostpool
                $Hostpool = New-RdsHostPool -TenantName $TenantName -Name $HostPoolName -Description $Description -FriendlyName $FriendlyName
                $HName = $hostpool.name | Out-String -Stream
                Write-Log -Message "Successfully created new Hostpool: $HName"
        
                # setting up usereverseconnect as true
                Write-Log -Message "setting up the UserReverseconnect value as true for Hostpool: $HName"
                Set-RdsHostPool -TenantName $TenantName -Name $HostPoolName -UseReverseConnect $true

        
        
                #Registering hostpool with 365 days
                Write-log -Message "Creating new registeration info for hostpool:$HName with expired hours $Hours"
                $ToRegister = New-RdsRegistrationInfo -TenantName $TenantName -HostPoolName $HostPoolName -ExpirationHours $Hours
                $newRegInfo = $ToRegister.ExpirationUtc | Out-String -Stream
                Write-Log -Message "Successfully registered $HName, expiration date: $newRegInfo"
        
                #Executing DeployAgent psl file in rdsh vm and add to hostpool
                $DAgentInstall = .\DeployAgent.ps1 -ComputerName $SessionHostName -AgentBootServiceInstaller ".\RDAgentBootLoaderInstall\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi" -AgentInstaller ".\RDInfraAgentInstall\Microsoft.RDInfra.RDAgent.Installer-x64.msi" -SxSStackInstaller ".\RDInfraSxSStackInstall\Microsoft.RDInfra.StackSxS.Installer-x64.msi" -AdminCredentials $adminCredentials -TenantName $TenantName -PoolName $HostPoolName -RegistrationToken $ToRegister.Token -StartAgent $true
        
                Write-Log -Message "DeployAgent Script was successfully executed and RDAgentBootLoader, RDAgent, StackSxS installed inside VM for new $HName `
        $DAgentInstall"
            }
            #add rdsh vm to hostpool
            $addRdsh = Set-RdsSessionHost -TenantName $TenantName -HostPoolName $HostPoolName -Name $SessionHostName -AllowNewSession $true
            $rdshName = $addRdsh.name | Out-String -Stream
            $poolName = $addRdsh.hostpoolname | Out-String -Stream
            Write-Log -Message "Successfully added $rdshName VM to $poolName"
        
        }
        else {
            #Converting Local Admin Credentials
            $AdminSecurepass = ConvertTo-SecureString -String $localAdminPassword -AsPlainText -Force
            $adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($localAdminUserName, $AdminSecurepass)
        
            #Getting fqdn of rdsh vm
            $SessionHostName = (Get-WmiObject win32_computersystem).DNSHostName + "." + (Get-WmiObject win32_computersystem).Domain
            Write-Log  -Message "Getting fully qualified domain name of RDSH VM: $SessionHostName"
                   
            #Executing DeployAgent psl file in rdsh vm and add to hostpool
            $DAgentInstall = .\DeployAgent.ps1 -ComputerName $SessionHostName -AgentBootServiceInstaller ".\RDAgentBootLoaderInstall\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi" -AgentInstaller ".\RDInfraAgentInstall\Microsoft.RDInfra.RDAgent.Installer-x64.msi" -SxSStackInstaller ".\RDInfraSxSStackInstall\Microsoft.RDInfra.StackSxS.Installer-x64.msi" -AdminCredentials $adminCredentials -RegistrationToken $registrationToken -StartAgent $true
            Write-Log -Message "DeployAgent Script was successfully executed and RDAgentBootLoader,RDAgent,StackSxS installed inside VM for existing hostpool: $HostPoolName `
                $DAgentInstall"
        
            Write-Log -Message "Successfully added $SessionHostName VM to HostPool"
        
        }
        
    }

}
catch {
    Write-log -Error $_.Exception.Message

}
if($rdshIs1809OrLater -eq "True"){
Write-Log -Message "Activating Windows 10 Pro"
ActivateWin10 -ActivationKey $ActivationKey

Write-Log -Message "Rebooting VM"
Shutdown -r -t 90
}


