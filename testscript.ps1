$subsriptionid = Get-AutomationVariable -Name 'subsriptionid'
$ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
$Location = Get-AutomationVariable -Name 'Location'
$RDBrokerURL = Get-AutomationVariable -Name 'RDBrokerURL'
$TenantGroupName = Get-AutomationVariable -Name 'TenantGroupName'
$fileURI = Get-AutomationVariable -Name 'fileURI'
$TenantName = Get-AutomationVariable -Name 'TenantName'
$HostPoolName = Get-AutomationVariable -Name 'HostPoolName'
$AADTenantId = Get-AutomationVariable -Name 'TenantId'
$AADApplicationId = Get-AutomationVariable -Name 'AADApplicationId'
$AADServicePrincipalSecret = Get-AutomationVariable -Name 'AADServicePrincipalSecret'
$BeginPeakTime = Get-AutomationVariable -Name 'BeginPeakTime'
$EndPeakTime = Get-AutomationVariable -Name 'EndPeakTime'
$TimeDifferenceInHours = Get-AutomationVariable -Name 'TimeDifferenceInHours'
$SessionThresholdPerCPU = Get-AutomationVariable -Name 'SessionThresholdPerCPU'
$MinimumNumberOfRDSH = Get-AutomationVariable -Name 'MinimumNumberOfRDSH'
$LimitSecondsToForceLogOffUser = Get-AutomationVariable -Name 'LimitSecondsToForceLogOffUser'
$LogOffMessageTitle = Get-AutomationVariable -Name 'LogOffMessageTitle'
$LogOffMessageBody = Get-AutomationVariable -Name 'LogOffMessageBody'
$automationAccountName = Get-AutomationVariable -Name 'accountName'
$runbookName = Get-AutomationVariable -Name 'runbookName'

    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
    Get-ExecutionPolicy -List

Invoke-WebRequest -Uri $fileURI -OutFile "C:\WVDModules.zip"
New-Item -Path "C:\WVDModules" -ItemType directory -Force -ErrorAction SilentlyContinue
Expand-Archive "C:\WVDModules.zip" -DestinationPath "C:\WVDModules" -Force -ErrorAction SilentlyContinue
Copy-Item -path "C:\WVDModules\AzureModules\*" -Recurse -Destination 'C:\Modules\Global' -ErrorAction SilentlyContinue



function Write-Log {

  [CmdletBinding()]
  param(

    [Parameter(mandatory = $false)]
    [string]$Message,
    [Parameter(mandatory = $false)]
    [string]$Error
  )

  try {
    $DateTime = Get-Date -Format ‘MM-dd-yy HH:mm:ss’
    $Invocation = "$($MyInvocation.MyCommand.Source):$($MyInvocation.ScriptLineNumber)"
    if ($Message) {

      Add-Content -Value "$DateTime - $Invocation - $Message" -Path "$([environment]::GetEnvironmentVariable('WVDModules', 'Machine'))\ScriptLog.log"
    }
    else {


      Add-Content -Value "$DateTime - $Invocation - $Error" -Path "$([environment]::GetEnvironmentVariable('WVDModules', 'Machine'))\ScriptLog.log"
    }
  }
  catch {



    Write-Error $_.Exception.Message
  }
}

Write-Log -Message "Policy List: $log"

$JobCollectionName = "AutoScaleJobCollection"
$webhookName = "$HostPoolName-webhook"
$schJObName = "$HostpoolName-job"


Import-Module AzureRM.Resources
Import-Module AzureRM.Profile
Import-Module AzureRM.Websites
Import-Module Azure
Import-Module AzureRM.Automation
Import-Module AzureAD


    #The name of the Automation Credential Asset this runbook will use to authenticate to Azure.
    $CredentialAssetName = 'DefaultAzureCredential'

    #Get the credential with the above name from the Automation Asset store
    $Cred = Get-AutomationPSCredential -Name $CredentialAssetName
    #Add-AzureRmAccount -Environment 'AzureCloud' -Credential $Cred
    Add-AzureRmAccount -Environment 'AzureCloud' -Credential $Cred -TenantId $AADTenantId -ServicePrincipal
    #Select-AzureRmSubscription -SubscriptionId $subsriptionid
    $EnvironmentName = "AzureCloud"

    Import-Module "C:\WVDModules\RDPowershell\Microsoft.RDInfra.RDPowershell.dll"
    Write-Log -Message "Imported RDMI PowerShell modules successfully"

    $authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Cred -ServicePrincipal -TenantId $AadTenantId
    $obj = $authentication | Out-String


    if ($authentication)
      {
        Write-Log -Message "RDMI Authentication successfully Done. Result:`n$obj"


      }
      else
      {
        Write-Log -Error "RDMI Authentication Failed, Error:`n$obj"
      }


      # Set context to the appropriate tenant group
      Write-Log "Running switching to the $TenantGroupName context"
      Set-RdsContext -TenantGroupName $TenantGroupName
      try
      {
        $tenants = Get-RdsTenant -Name $TenantName
        if (!$tenants)
        {
          Write-Log "No tenants exist or you do not have proper access."
        }
      }
      catch
      {
        Write-Log -Message $_
      }


      $HPName = Get-RdsHostPool -TenantName $TenantName -Name $HostPoolName -ErrorAction SilentlyContinue
      Write-Log -Message "Checking Hostpool exists inside the Tenant"


Get-Content -Path "C:\WVDModules\ScriptLog.txt"

