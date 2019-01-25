$subscriptionId = Get-AutomationVariable -Name 'subscriptionId'
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
$automationAccountName = Get-AutomationVariable -Name 'existingAutomationAccountName'
$runbookName = Get-AutomationVariable -Name 'runbookName'
$webhookname = Get-AutomationVariable -Name 'webhookname'
$scheduledTimeInterval = Get-AutomationVariable -Name 'scheduledTimeInterval'
$scheduledFrequency = Get-AutomationVariable -Name 'scheduledFrequency'

$JobCollectionName = "wvdjobcollection"
$schJObName = "$hostpoolname-job"
$autoScaleRunbookName = "WVDAutoScaleRunbook"




$servicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
Add-AzureRmAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
    -ApplicationId $servicePrincipalConnection.ApplicationId | Out-Null


Select-AzureRmSubscription -SubscriptionId $subscriptionid



New-PSDrive -Name CreateScalefile -PSProvider FileSystem -Root "D:\" | Out-Null
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
  
  #Remove-PSDrive -Name CreateScalefile
  #
     
    $automationRunbookInfo = Get-AzureRmAutomationRunbook -Name $autoScaleRunbookName -ResourceGroupName $ResourceGroupName -AutomationAccountName $autoScaleAccountName -ErrorAction SilentlyContinue
    if(!$automationRunbookInfo){
    $newAAcctRunbook=New-AzureRmAutomationRunbook -Name $autoScaleRunbookName -Type PowerShell -ResourceGroupName $ResourceGroupName -AutomationAccountName $autoScaleAccountName
    #Import modules to Automation Account
    <#$modules="AzureRM.profile,Azurerm.compute,azurerm.resources"
    $modulenames=$modules.Split(",")
    foreach($modulename in $modulenames){
    Set-AzureRmAutomationModule -Name $modulename -AutomationAccountName $autoScaleAccountName -ResourceGroupName $ResourcegroupName
	}#>
	
    #Importe powershell file to Runbooks
    Import-AzureRmAutomationRunbook -Path "D:\ScleScript.ps1" -Name $autoScaleRunbookName -Type PowerShell -ResourceGroupName $ResourcegroupName -AutomationAccountName $autoScaleAccountName -Force

    #Publishing Runbook
    Publish-AzureRmAutomationRunbook -Name $autoScaleRunbookName -ResourceGroupName $ResourcegroupName -AutomationAccountName $autoScaleAccountName
    }

    

    $getWebhookUri = Get-AutomationVariable -Name 'webHookURI' -ErrorAction SilentlyContinue
    if(!$getWebhookUri){
    $newAAWebhook = New-AzureRmAutomationWebhook -Name $webhookName -RunbookName $autoScaleRunbookName -AutomationAccountName $autoScaleAccountName -Parameters $params -IsEnabled $true -ExpiryTime (Get-Date).AddYears(1) -ResourceGroupName $ResourceGroupName -Force
    $webhookURI = $newAAWebhook.WebhookURI | Out-String
	Set-AzureRmAutomationVariable -AutomationAccountName $autoScaleAccountName -Name "webHookURI" -ResourceGroupName $resourcegroupname -Value $webhookURI -Encrypted $False
	$getWebhookUri = Get-AutomationVariable -Name 'webHookURI' -ErrorAction SilentlyContinue
   }
   

  $JobCollectionInfo = Get-AzureRmSchedulerJobCollection -ResourceGroupName $ResourceGroupName -JobCollectionName $JobCollectionName -ErrorAction SilentlyContinue
  if(!$JobCollectionInfo){
      New-AzureRmSchedulerJobCollection -JobCollectionName $JobCollectionName -ResourceGroupName $ResourceGroupName -Location $Location -Plan Standard
    }
  <#if($JobCollectionInfo.MaxJobCount - 50){
       
   }#>
   
   
   
    #Providing parameter values to schedule job
    $params=@{"subsriptionid"=$subsriptionid;"ResourceGroupName"=$ResourceGroupName;"TenantGroupName"=$TenantGroupName;"fileURI"=$fileURI;"TenantName"=$TenantName;"HostPoolName"=$HostPoolName;"AADTenantId"=$AADTenantId;"AADApplicationId"=$AADApplicationId;"AADServicePrincipalSecret"=$AADServicePrincipalSecret;"automationAccountName"=$autoScaleAccountName;"runbookName"=$autoScaleRunbookName;"BeginPeakTime"=$BeginPeakTime}
    $scheduleJobInputs = $params | ConvertTo-Json
   
		
   
   $jobScheduledInfo = Get-AzureRmSchedulerJob -ResourceGroupName $ResourceGroupName -JobCollectionName $JobCollectionName -JobName $schJObName -ErrorAction SilentlyContinue
	if(!$jobScheduledInfo){
		
		#Providing parameter values to schedule job
		$params=@{"subsriptionid"=$subsriptionid;"ResourceGroupName"=$ResourceGroupName;"TenantGroupName"=$TenantGroupName;"fileURI"=$fileURI;"TenantName"=$TenantName;"HostPoolName"=$HostPoolName;"AADTenantId"=$AADTenantId;"AADApplicationId"=$AADApplicationId;"AADServicePrincipalSecret"=$AADServicePrincipalSecret;"automationAccountName"=$autoScaleAccountName;"runbookName"=$autoScaleRunbookName;"BeginPeakTime"=$BeginPeakTime}
		$scheduleJobInputs = $params | ConvertTo-Json
				
		New-AzureRmSchedulerHttpJob -ResourceGroupName $ResourceGroupName -JobCollectionName $JobCollectionName -JobName $schJObName -Method POST -Uri $getWebhookUri -StartTime $BeginPeakTime -Frequency Minute -EndTime (Get-Date).AddYears(1)
	}
	else{
	
	$time = $jobScheduledInfo.StartTime
	$lastScheduledtime = Get-Date $time -Format hh:mm
	if($lastScheduledtime -eq $beginpeaktime){
	
		#Providing parameter values to schedule job
		$params=@{"subsriptionid"=$subsriptionid;"ResourceGroupName"=$ResourceGroupName;"TenantGroupName"=$TenantGroupName;"fileURI"=$fileURI;"TenantName"=$TenantName;"HostPoolName"=$HostPoolName;"AADTenantId"=$AADTenantId;"AADApplicationId"=$AADApplicationId;"AADServicePrincipalSecret"=$AADServicePrincipalSecret;"automationAccountName"=$autoScaleAccountName;"runbookName"=$autoScaleRunbookName;"BeginPeakTime"=$BeginPeakTime}
		$scheduleJobInputs = $params | ConvertTo-Json
	
	}
	
	
	
	}


   Remove-PSDrive -Name CreateScalefile
   #Remove-AzureRmAutomationRunbook -Name $runbookName -Force -ResourceGroupName $resourcegroupname -AutomationAccountName $autoScaleAccountName
