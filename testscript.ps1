$subsriptionid = Get-AutomationVariable -Name 'subsriptionid'
$ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
$Location = Get-AutomationVariable -Name 'Location'
$RDBrokerURL = Get-AutomationVariable -Name 'RDBrokerURL'
$TenantGroupName = Get-AutomationVariable -Name 'TenantGroupName'
$fileURI = Get-AutomationVariable -Name 'fileURI'
$TenantName = Get-AutomationVariable -Name 'TenantName'
$HostPoolName = Get-AutomationVariable -Name 'HostPoolName'
$AADTenantId = Get-AutomationVariable -Name 'AADTenantId'
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


$JobCollectionName = "AutoScaleJobCollection"
$webhookName = "$HostPoolName-webhook"
$schJObName = "$HostpoolName-job"


Invoke-WebRequest -Uri $fileURI -OutFile "C:\PowerShellModules.zip"
New-Item -Path "C:\PowerShellModules" -ItemType directory -Force -ErrorAction SilentlyContinue
Expand-Archive "C:\PowerShellModules.zip" -DestinationPath "C:\PowerShellModules" -Force -ErrorAction SilentlyContinue
$AzureModulesPath = Get-ChildItem -Path "C:\PowerShellModules"| Where-Object {$_.FullName -match 'AzureModules'}
Expand-Archive $AzureModulesPath.fullname -DestinationPath 'C:\Modules\Global' -ErrorAction SilentlyContinue

Import-Module AzureRM.Resources
Import-Module AzureRM.Profile
Import-Module AzureRM.Websites
Import-Module Azure
Import-Module AzureRM.Automation
Import-Module AzureAD

    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
    Get-ExecutionPolicy -List
    #The name of the Automation Credential Asset this runbook will use to authenticate to Azure.
    $CredentialAssetName = 'DefaultAzureCredential'

    #Get the credential with the above name from the Automation Asset store
    $Cred = Get-AutomationPSCredential -Name $CredentialAssetName
    Add-AzureRmAccount -Environment 'AzureCloud' -Credential $Cred
    Select-AzureRmSubscription -SubscriptionId $subsriptionid
    $EnvironmentName = "AzureCloud"