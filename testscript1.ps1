
$subsriptionid = Get-AutomationVariable -Name 'subsriptionid'
$ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
$Location = Get-AutomationVariable -Name 'Location'
$RDBrokerURL = Get-AutomationVariable -Name 'RDBrokerURL'
$TenantGroupName = Get-AutomationVariable -Name 'TenantGroupName'
$fileURI = Get-AutomationVariable -Name 'fileURI'
$TenantName = Get-AutomationVariable -Name 'TenantName'
$HostPoolName = Get-AutomationVariable -Name 'HostPoolName'
$AADTenantId = Get-AutomationVariable -Name 'TenantID'
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


$JobCollectionName = "AutoScaleJobCollection"
$webhookName = "$HostPoolName webhook001"
$schJObName = "$HostpoolName-job"
$autoScaleRunbookName = "WVDRunbook"
$autoScaleAccountName = "WVDAutoScaleAccount"
 $schJObName = "$hostpoolname-job01"

$fileURI = "https://raw.githubusercontent.com/viswanadhamkudapu/Repository/master/WVDModules.zip"

Invoke-WebRequest -Uri $fileURI -OutFile "C:\WVDModules.zip"
New-Item -Path "C:\WVDModules" -ItemType directory -Force -ErrorAction SilentlyContinue
Expand-Archive "C:\WVDModules.zip" -DestinationPath "C:\WVDModules" -Force -ErrorAction SilentlyContinue
Copy-Item -path "C:\WVDModules\AzureModules\*" -Recurse -Destination 'C:\Modules\Global' -ErrorAction SilentlyContinue

#$AzureModulesPath = Get-ChildItem -Path "C:\WVDModules"| Where-Object {$_.FullName -match 'AzureModules'}


Import-Module AzureRM.Resources
Import-Module AzureRM.Profile
Import-Module Azure
Import-Module AzureRM.Automation
Import-Module AzureAD
#Import-Module AzureRM.Storage

    
    #The name of the Automation Credential Asset this runbook will use to authenticate to Azure.
    $CredentialAssetName = 'DefaultAzureCredential'

    #Get the credential with the above name from the Automation Asset store
    $Cred = Get-AutomationPSCredential -Name $CredentialAssetName
    Add-AzureRmAccount -Environment 'AzureCloud' -Credential $Cred -ServicePrincipal -TenantId $AADTenantId
    Select-AzureRmSubscription -SubscriptionId $subsriptionid
    $EnvironmentName = "AzureCloud"

<#
############################################################Key Vault##########################################
#Check the KeyVault resoruce provider registered or not
    $KeyVaultRPRegInfo = Get-AzureRmResourceProvider | Where-Object {$_.ProviderNamespace -eq "Microsoft.KeyVault"}
        
        if($KeyVaultRPRegInfo.RegistrationState -eq "Registered"){
            
            $registered = $KeyVaultRPRegInfo.providernamespace | Out-String
            Write-Output "$registered was already registered"
        }
        else
        {
        Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.KeyVault" -Confirm:$false
        }


 $keyVaultinfo = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
 if(!$keyVaultinfo){
 New-AzureRmKeyVault -Name $keyVaultName -ResourceGroupName $ResourceGroupName -Location $Location -EnabledForDeployment -EnabledForTemplateDeployment
 #Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVaultName –ServicePrincipalName $AADApplicationId -PermissionsToKeys  # -PermissionsToSecrets all -ResourceGroupName $ResourceGroupName

 Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVaultName -ResourceGroupName $resourceGroupName `
  -ServicePrincipalName $AADApplicationId `
  -PermissionsToCertificates list,get `
  -PermissionsToKeys list,get `
  -PermissionsToSecrets list,get
 }

Get-AzureRmKeyVault -VaultName $keyVaultName
#>
#############################################################Key Vault###################################################
<#
New-PSDrive -Name RemoveAccount -PSProvider FileSystem -Root "C:\" | Out-Null
@"
Param(
    [Parameter(Mandatory=`$True)]
    [string] `$SubscriptionId,
    [Parameter(Mandatory=`$True)]
    [String] `$Username,
    [Parameter(Mandatory=`$True)]
    [string] `$Password,
    [Parameter(Mandatory=`$True)]
    [string] `$ResourceGroupName
 
)
Import-Module AzureRM.profile
Import-Module AzureRM.Automation
`$Securepass=ConvertTo-SecureString -String `$Password -AsPlainText -Force
`$Azurecred=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList(`$Username, `$Securepass)
`$login=Login-AzureRmAccount -Credential `$Azurecred -SubscriptionId `$SubscriptionId
Remove-AzureRmAutomationAccount -Name "msftsaas-autoAccount" -ResourceGroupName `$ResourceGroupName -Force
"@| Out-File -FilePath RemoveAccount:\RemoveAccount.ps1 -Force
#>

New-PSDrive -Name CreateScalefile -PSProvider FileSystem -Root "C:\" | Out-Null
@"
param(
`$subsriptionid,
`$ResourceGroupName,
`$Location,
`$RDBrokerURL,
`$TenantGroupName,
`$fileURI,
`$TenantName,
`$HostPoolName,
`$AADTenantId,
`$AADApplicationId,
`$AADServicePrincipalSecret,
`$BeginPeakTime,
`$EndPeakTime,
`$TimeDifferenceInHours,
`$SessionThresholdPerCPU,
`$MinimumNumberOfRDSH,
`$LimitSecondsToForceLogOffUser,
`$LogOffMessageTitle,
`$LogOffMessageBody,
`$automationAccountName,
`$runbookName
)
Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:`$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:`$false
`$PolicyList=Get-ExecutionPolicy -List
`$log = `$PolicyList | Out-String
`$TestPath = Test-Path -Path "C:\ScaleScript-`$hostpoolname"
if(!`$TestPath){
  Invoke-WebRequest -Uri `$fileURI -OutFile "C:\WvdModules.zip" -ErrorAction SilentlyContinue
  New-Item -Path "C:\ScaleScript-`$hostpoolname" -ItemType directory -Force -ErrorAction SilentlyContinue
  Expand-Archive -Path "C:\WvdModules.zip" -DestinationPath "C:\ScaleScript-`$hostpoolname"
  Copy-Item -path "C:\ScaleScript-`$hostpoolname\AzureModules\*" -Recurse -Destination 'C:\Modules\Global' -ErrorAction SilentlyContinue
    }
function Write-Log {
  [CmdletBinding()]
  param(
      [Parameter(mandatory = `$false)]
    [string]`$Message,
    [Parameter(mandatory = `$false)]
    [string]`$Error
  )
  try {
    `$DateTime = Get-Date -Format "MM-dd-yy HH:mm:ss"
    `$Invocation = "`$(`$MyInvocation.MyCommand.Source):`$(`$MyInvocation.ScriptLineNumber)"
    if (`$Message) {
     Add-Content -Value "`$DateTime - `$Invocation - `$Message" -Path "C:\ScaleScript-`$hostpoolname\ScriptLog.log"
    }
    else {
     Add-Content -Value "`$DateTime - `$Invocation - `$Error" -Path "C:\ScaleScript-`$hostpoolname\ScriptLog.log"
    }
  }
  catch {
  Write-Error `$_.Exception.Message
  }
}
Write-Log -Message "Policy List: `$log"
Import-Module AzureRM.Resources
Import-Module AzureRM.Profile
Import-Module Azure
Import-Module AzureRM.Automation
Import-Module AzureAD
Import-Module AzureRM.Storage -MaximumVersion
#The name of the Automation Credential Asset this runbook will use to authenticate to Azure.
`$CredentialAssetName = 'DefaultAzureCredential'
#Get the credential with the above name from the Automation Asset store
`$Cred = Get-AutomationPSCredential -Name `$CredentialAssetName
Add-AzureRmAccount -Environment 'AzureCloud' -Credential `$Cred -ServicePrincipal -TenantId `$AADTenantId
Select-AzureRmSubscription -SubscriptionId `$subsriptionid
`$EnvironmentName = "AzureCloud"
Get-AzureRmVM -status
Set-Location -Path "C:\ScaleScript-`$hostpoolname"
Import-Module ".\RDPowerShell\Microsoft.RDInfra.RDPowershell.dll"
Add-RdsAccount -DeploymentUrl `$RDBrokerURL -ServicePrincipal -Credential `$Cred -AadTenantId `$AADTenantId
Get-RdsTenant -Name `$TenantName
Get-RdsHostPool -TenantName `$TenantName -Name `$HostPoolName
Get-Content -Path "C:\ScaleScript-`$hostpoolname\ScriptLog.log"

"@ | Out-File -FilePath CreateScalefile:\ScleScript.ps1 -Force 
  
  
    
    #Create a Run Book
    $AAcctRunbook=New-AzureRmAutomationRunbook -Name $autoScaleRunbookName -Type PowerShell -ResourceGroupName $ResourceGroupName -AutomationAccountName $autoScaleAccountName

    #Import modules to Automation Account
    $modules="AzureRM.profile,Azurerm.compute,azurerm.resources"
    $modulenames=$modules.Split(",")
    foreach($modulename in $modulenames){
    Set-AzureRmAutomationModule -Name $modulename -AutomationAccountName $automationAccountName -ResourceGroupName $ResourcegroupName
    }

    #Importe powershell file to Runbooks
    Import-AzureRmAutomationRunbook -Path "C:\ScleScript.ps1" -Name $runbookName -Type PowerShell -ResourceGroupName $ResourcegroupName -AutomationAccountName $automationAccountName -Force

    #Publishing Runbook
    Publish-AzureRmAutomationRunbook -Name $runbookName -ResourceGroupName $ResourcegroupName -AutomationAccountName $automationAccountName

    #Providing parameter values to powershell script file
    $params=@{"subsriptionid"=$subsriptionid;"ResourceGroupName"=$ResourceGroupName;"TenantGroupName"=$TenantGroupName;"fileURI"=$fileURI;"TenantName"=$TenantName;"HostPoolName"=$HostPoolName;"AADTenantId"=$AADTenantId;"AADApplicationId"=$AADApplicationId;"AADServicePrincipalSecret"=$AADServicePrincipalSecret;"automationAccountName"=$automationAccountName;"runbookName"=$runbookName;"BeginPeakTime"=$BeginPeakTime}
    #Start-AzureRmAutomationRunbook -Name $runbookName -ResourceGroupName $ResourcegroupName -AutomationAccountName $automationAccountName -Parameters $params

    $WebhookInfo = New-AzureRmAutomationWebhook -Name $webhookName -RunbookName $runbookName -AutomationAccountName $automationAccountName -Parameters $params -IsEnabled $true -ExpiryTime (Get-Date).AddYears(1) -ResourceGroupName removerg -Force
    $webhookURI = $WebhookInfo.WebhookURI
   

  
  


    New-AzureRmSchedulerJobCollection -JobCollectionName $JobCollectionName -ResourceGroupName $ResourceGroupName -Location $Location -Plan Free

    New-AzureRmSchedulerHttpJob -ResourceGroupName $ResourceGroupName -JobCollectionName $JobCollectionName -JobName $schJObName -Method POST -Uri $webHookURI -StartTime $BeginPeakTime
   