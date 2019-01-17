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

Write-Output "$subsriptionid"
Write-Output "$AADApplicationId"

Write-Output "$AADTenantId"
Write-Output "$fileURI"
Write-Output "$RDBrokerURL"
Write-Output "$JobCollectionName"
Write-Output "$webhookName"
Write-Output "$schJObName"