Param(
[Parameter(Mandatory = $false)]
[object]$WebHookData
)

# If runbook was called from Webhook, WebhookData will not be null.
if ($WebHookData){

    # Collect properties of WebhookData
    $WebhookName     =     $WebHookData.WebhookName
    $WebhookHeaders  =     $WebHookData.RequestHeader
    $WebhookBody     =     $WebHookData.RequestBody

    # Collect individual headers. Input converted from JSON.
    $From = $WebhookHeaders.From
    $Input = (ConvertFrom-Json -InputObject $WebhookBody)
    Write-Verbose "WebhookBody: $Input"
    Write-Output -InputObject ('Runbook started from webhook {0} by {1}.' -f $WebhookName, $From)
}
else
{
   Write-Error -Message 'Runbook was not started from Webhook' -ErrorAction stop
}

$AADTenantId = $Input.AADTenantId
$SubscriptionID = $Input.SubscriptionID
$TenantGroupName = $Input.TenantGroupName
$TenantName = $Input.TenantName
$HostpoolName = $Input.HostpoolName
$PeakLoadBalancingType = $Input.PeakLoadBalancingType
$BeginPeakTime = $Input.BeginPeakTime
$EndPeakTime = $Input.EndPeakTime
$TimeDifference = $Input.TimeDifference
$SessionThresholdPerCPU = $Input.SessionThresholdPerCPU
$MinimumNumberOfRDSH = $Input.MinimumNumberOfRDSH
$LimitSecondsToForceLogOffUser = $Input.LimitSecondsToForceLogOffUser
$LogOffMessageTitle = $Input.LogOffMessageTitle
$LogOffMessageBody = $Input.LogOffMessageBody
$MaintenanceTagName = $Input.MaintenanceTagName
$CredentialAssetName = $Input.CredentialAssetName
$LogAnalyticsWorkspaceId = $Input.LogAnalyticsWorkspaceId
$LogAnalyticsPrimaryKey = $Input.LogAnalyticsPrimaryKey
$RDBrokerURL = "https://rdbroker.wvd.microsoft.com"

Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false

#$DateTime = Get-Date -Format "MM-dd-yy HH:mm"
#$DateFilename = $DateTime.Replace(":","-")

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "Stop"
<#
.Description
Helper functions
#>
#Function to convert from UTC to Local time
function ConvertUTCtoLocal {
    param(
        $TimeDifferenceInHours
    )

    $UniversalTime = (Get-Date).ToUniversalTime()
    $TimeDifferenceMinutes = 0 
    if ($TimeDifferenceInHours -match ":") {
        $TimeDifferenceHours = $TimeDifferenceInHours.Split(":")[0]
        $TimeDifferenceMinutes = $TimeDifferenceInHours.Split(":")[1]
    }
    else {
        $TimeDifferenceHours = $TimeDifferenceInHours
    }
    #Azure is using UTC time, justify it to the local time
    $ConvertedTime = $UniversalTime.AddHours($TimeDifferenceHours).AddMinutes($TimeDifferenceMinutes)
    Return $ConvertedTime
}

#Function for to add logs to log analytics workspace
function #AddToLog {
    param(
     [Object]$LogMessage,
     [string]$LogAnalyticsWorkspaceId,
     [string]$LogAnalyticsPrimaryKey,
     [string]$LogType,
     $TimeDifferenceInHours
    ) 
 
    if ($LogAnalyticsWorkspaceId -ne $null) {
        #$LogMessage= ''
        foreach ($Key in $LogMessage.Keys) {
            switch ($Key.Substring($Key.Length-2)) {
                '_s' {$sep = '"';$trim=$Key.Length-2}
                '_t' {$sep = '"';$trim=$Key.Length-2}
                '_b' {$sep = '';$trim=$Key.Length-2}
                '_d' {$sep = '';$trim=$Key.Length-2}
                '_g' {$sep = '"';$trim=$Key.Length-2}
                default {$sep = '"';$trim=$Key.Length}
            }
            #$LogMessage= #$LogMessage+ '"' + $Key.Substring(0,$trim) + '":' + $sep + $LogMessage.Item($Key) + $sep + ','
        }
        $TimeStamp = ConvertUTCtoLocal -TimeDifferenceInHours $TimeDifferenceInHours
        #$LogMessage= #$LogMessage+ '"TimeStamp":"' + $timestamp + '"'
 
        Write-Verbose "LogData: $($LogMessage)"
        $json = "{$($LogMessage)}"
 
        $PostResult = Send-OMSAPIIngestionFile -customerId $LogAnalyticsWorkspaceId -sharedKey $LogAnalyticsPrimaryKey -body $json -logType $LogType -TimeStampField "TimeStamp"
        Write-Verbose "PostResult: $($PostResult)"
        if ($PostResult -ne "Accepted") {
            Write-Error "Error posting to OMS - $PostResult"
        }
    }
}

#Function to validate the allow new connections
function ValidateAllowNewConnections{
    param (
       [string]$TenantName,
       [string]$HostpoolName,
       [string]$SessionHostName
    )

 # Check if the session host is allowing new connections
  $StateOftheSessionHost = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHostName
  if (!($StateOftheSessionHost.AllowNewSession)) {
      Set-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHostName -AllowNewSession $true
    }
    
}

# Check if the host is enabled maintenance tag              
function Maintenance
{
  param(
  [string]$VMName
  )
    # Check the session host is in maintenance
    $VmInfo = Get-AzureRmVM | Where-Object { $_.Name -eq $VMName }
        if ($VmInfo.Tags.Keys -contains $MaintenanceTagName) {
              #$LogMessage= @{logmessage_s = "Session Host is in Maintenance: $SessionHostName"}
              #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
              continue
         }
}

# Start the AzureRMVM 
function StartAzureRMVM{
  param(
  [string]$VMName
  )
           try {
                #$LogMessage= @{logmessage_s = "Starting Azure VM: $VMName and waiting for it to complete ..."}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                Get-AzureRmVM | Where-object {$_.Name -eq $VMName} | Start-AzureRmVM
              }
              catch {
                #$LogMessage= @{logmessage_s = "Failed to start Azure VM: $($VMName) with error: $($_.exception.message)"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                exit
              }

}
# Stop the AzureRMVM
function StopAzureRMVM{
  param(
    [string]$VMName
  )
            try {
                #$LogMessage= @{logmessage_s = "Stopping Azure VM: $VMName and waiting for it to complete ..."}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                Get-AzureRmVM | Where-Object {$_.Name -eq $VMName} | Stop-AzureRMVM -Force
              }
              catch {
                #$LogMessage= @{logmessage_s = "Failed to stop Azure VM: $VMName with error: $_.exception.message"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                exit
              }
}
 
#Collect the credentials from Azure Automation Account Assets
$Credentials = Get-AutomationPSCredential -Name $CredentialAssetName
#Authenticating to Azure
Add-AzureRmAccount -Credential $Credentials -TenantId $AADTenantId -SubscriptionID $SubscriptionID -ServicePrincipal

#Authenticating to WVD
Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Credentials -TenantId $AADTenantId -ServicePrincipal

#Converting date time from UTC to Local
$CurrentDateTime = ConvertUTCtoLocal -TimeDifferenceInHours $TimeDifference

#Set context to the appropriate tenant group
$CurrentTenantGroupName = (Get-RdsContext).TenantGroupName
if ($TenantGroupName -ne $CurrentTenantGroupName) {
  #Write-Log 1 "Running switching to the $TenantGroupName context" "Info"
  #$LogMessage= @{logmessage_s = "Running switching to the $TenantGroupName context"}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
  Set-RdsContext -TenantGroupName $TenantGroupName
}


$BeginPeakDateTime = [datetime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $BeginPeakTime)
$EndPeakDateTime = [datetime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $EndPeakTime)


#Checking givne host pool name exists in Tenant
$HostpoolInfo = Get-RdsHostPool -TenantName $TenantName -Name $HostpoolName
if ($HostpoolInfo -eq $null) {
  #Write-Log 1 "Hostpoolname '$HostpoolName' does not exist in the tenant of '$TenantName'. Ensure that you have entered the correct values." "Info"
  #$LogMessage= @{logmessage_s = "Hostpoolname '$HostpoolName' does not exist in the tenant of '$TenantName'. Ensure that you have entered the correct values."}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
  exit
}

#Compare session loadbalancing peak hours and setting up appropriate load balacing type based on PeakLoadBalancingType
if ($CurrentDateTime -ge $BeginPeakDateTime -and $CurrentDateTime -le $EndPeakDateTime) {

    if ($HostpoolInfo.LoadBalancerType -ne $PeakLoadBalancingType) {
        #$LogMessage= @{logmessage_s = "Changing Hostpool Load Balance Type:$PeakLoadBalancingType Current Date Time is: $CurrentDateTime"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
        if ($PeakLoadBalancingType -eq "DepthFirst") {                
            Set-RdsHostPool -TenantName $TenantName -Name $HostpoolName -DepthFirstLoadBalancer -MaxSessionLimit $HostpoolInfo.MaxSessionLimit
        }
        else {
            Set-RdsHostPool -TenantName $TenantName -Name $HostpoolName -BreadthFirstLoadBalancer -MaxSessionLimit $HostpoolInfo.MaxSessionLimit
        }
        #$LogMessage= @{logmessage_s = "Hostpool Load balancer Type in Session Load Balancing Peak Hours is '$PeakLoadBalancingType Load Balancing'"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    }
}
else{
    if ($HostpoolInfo.LoadBalancerType -eq $PeakLoadBalancingType) {
        #$LogMessage= @{logmessage_s = "Changing Hostpool Load Balance Type in off peak hours Current Date Time is: $CurrentDateTime"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
        if ($hostpoolinfo.LoadBalancerType -ne "DepthFirst") {                
            $LoadBalanceType = Set-RdsHostPool -TenantName $TenantName -Name $HostpoolName -DepthFirstLoadBalancer -MaxSessionLimit $HostpoolInfo.MaxSessionLimit

         }else{
            $LoadBalanceType = Set-RdsHostPool -TenantName $TenantName -Name $HostpoolName -BreadthFirstLoadBalancer -MaxSessionLimit $HostpoolInfo.MaxSessionLimit
        }
        $LoadBalancerType = $LoadBalanceType.LoadBalancerType
        #$LogMessage= @{logmessage_s = "Hostpool Load balancer Type in off Peak Hours is '$LoadBalancerType Load Balancing'"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    }
    }


#Write-Log 3 "Starting WVD Tenant Hosts Scale Optimization: Current Date Time is: $CurrentDateTime" "Info"
#$LogMessage= @{logmessage_s = "Starting WVD Tenant Hosts Scale Optimization: Current Date Time is: $CurrentDateTime"}
#AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

#Check the after changing hostpool loadbalancer type
$HostpoolInfo = Get-RdsHostPool -TenantName $tenantName -Name $hostPoolName
if ($HostpoolInfo.LoadBalancerType -eq "DepthFirst")
{

  #Write-Log 1 "$HostpoolName hostpool loadbalancer type is $($HostpoolInfo.LoadBalancerType)" "Info"
  #$LogMessage= @{logmessage_s = "$HostpoolName hostpool loadbalancer type is $($HostpoolInfo.LoadBalancerType)"}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

  #Gathering hostpool maximum session and calculating Scalefactor for each host.										  
  $HostpoolMaxSessionLimit = $HostpoolInfo.MaxSessionLimit
  $ScaleFactorEachHost = $HostpoolMaxSessionLimit * 0.80
  $SessionhostLimit = [math]::Floor($ScaleFactorEachHost)

  #Write-Log 1 "Hostpool Maximum Session Limit: $($HostpoolMaxSessionLimit)"
  #$LogMessage= @{logmessage_s = "Hostpool Maximum Session Limit: $($HostpoolMaxSessionLimit)"}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours


  if ($CurrentDateTime -ge $BeginPeakDateTime -and $CurrentDateTime -le $EndPeakDateTime) 
  {
    Write-Output "It is in peak hours now"
    #Write-Log 1 "It is in peak hours now" "Info"
    #$LogMessage= @{logmessage_s = "It is in peak hours now"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    #Write-Log 1 "Peak hours: starting session hosts as needed based on current workloads." "Info"
    #$LogMessage= @{logmessage_s = "Peak hours: starting session hosts as needed based on current workloads."}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

    # Get all session hosts in the host pool
    $AllSessionHosts = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName | Sort-Object Sessions -Descending | Sort-Object Status
    if ($AllSessionHosts -eq $null) {
      #Write-Log 1 "Session hosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?." "Info"
      #$LogMessage= @{logmessage_s = "Session hosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      exit
    }
    <# Check dynamically created offpeakusage-minimumnoofRDSh text file and will remove in peak hours.
    if (Test-Path -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt) {
      Remove-Item -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
    }#>

    # Check the number of running session hosts
    $NumberOfRunningHost = 0
    foreach ($SessionHost in $AllSessionHosts) {

      #Write-Log 1 "Checking session host:$($SessionHost.SessionHostName | Out-String)  of sessions:$($SessionHost.Sessions) and status:$($SessionHost.Status)" "Info"
      #$LogMessage= @{logmessage_s = "Checking session host:$($SessionHost.SessionHostName | Out-String)  of sessions:$($SessionHost.Sessions) and status:$($SessionHost.Status)"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      $SessionCapacityofSessionHost = $SessionHost.Sessions

      if ($SessionHostLimit -lt $SessionCapacityofSessionHost -or $SessionHost.Status -eq "Available") {
        $NumberOfRunningHost = $NumberOfRunningHost + 1
      }
    }
    #Write-Log 1 "Current number of running hosts: $NumberOfRunningHost" "Info"
    #$LogMessage= @{logmessage_s = "Current number of running hosts: $NumberOfRunningHost"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    if ($NumberOfRunningHost -lt $MinimumNumberOfRDSH) 
    {
      #Write-Log 1 "Current number of running session hosts is less than minimum requirements, start session host ..." "Info"
      #$LogMessage= @{logmessage_s = "Current number of running session hosts is less than minimum requirements, start session host ..."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

      foreach ($SessionHost in $AllSessionHosts) {

        if ($NumberOfRunningHost -lt $MinimumNumberOfRDSH) {
          $SessionHostSessions = $SessionHost.Sessions
          if ($HostpoolMaxSessionLimit -ne $SessionHostSessions) {
            # Check the session host status and if the session host is healthy before starting the host
            if ($SessionHost.Status -eq "NoHeartbeat" -and $SessionHost.UpdateState -eq "Succeeded") {
              $SessionHostName = $SessionHost.SessionHostName | Out-String
              $VMName = $SessionHostName.Split(".")[0]
              # Check if the session host is in maintenance
              Maintenance -VMName $VMName
              # ValidateAllowNewConnections
              ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostPoolName -SessionHostName $SessionHost.SessionHostName
              # Start the azureRM VM
              StartAzureRMVM  -VMName $VMName
              # Wait for the sessionhost is available
              $IsHostAvailable = $false
              while (!$IsHostAvailable) {
                $SessionHostStatus = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost.SessionHostName
                if ($SessionHostStatus.Status -eq "Available") {
                  $IsHostAvailable = $true
                }
              }
            }
          }
          $NumberOfRunningHost = $NumberOfRunningHost + 1
        }

      }
    }

    else {
      $AllSessionHosts = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName | Sort-Object "Sessions" -Descending | Sort-Object Status
      foreach ($SessionHost in $AllSessionHosts) {
        if ($SessionHost.Sessions -ne $HostpoolMaxSessionLimit) {
          if ($SessionHost.Sessions -ge $SessionHostLimit) {
            foreach ($SessionHost in $AllSessionHosts) {
              
              # Check the session host status and if the session host is healthy before starting the host
              if ($SessionHost.UpdateState -eq "Succeeded") {
                #Write-Log 1 "Existing Sessionhost Sessions value reached near by hostpool maximumsession limit need to start the session host" "Info"
                #$LogMessage= @{logmessage_s = "Existing Sessionhost Sessions value reached near by hostpool maximumsession limit need to start the session host"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                $SessionHostName = $SessionHost.SessionHostName | Out-String
                $VMName = $SessionHostName.Split(".")[0]
                
                # Check the session host is in maintenance
                Maintenance -VMName $VMName
                
                # Validating session host is allowing new connections
                ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostPoolName -SessionHostName $SessionHost.SessionHostName

                # Start the azureRM VM
                StartAzureRMVM -VMName $VNName

                # Wait for the sessionhost is available
                $IsHostAvailable = $false
                while (!$IsHostAvailable) {
                  $SessionHostStatus = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost.SessionHostName
                  if ($SessionHostStatus.Status -eq "Available") {
                    $IsHostAvailable = $true
                  }
                }
                $NumberOfRunningHost = $NumberOfRunningHost + 1
                break

              }
            }

          }
        }
      }
    }

    #Write-Log 1 "HostpoolName:$HostpoolName, NumberofRunnighosts:$NumberOfRunningHost" "Info"
    #$LogMessage= @{logmessage_s = "HostpoolName:$HostpoolName, NumberofRunnighosts:$NumberOfRunningHost"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    #Write-UsageLog -HostPoolName $HostpoolName -VMCount $NumberOfRunningHost -DepthBool $DepthBool
    <#$LogMessage= @{
    hostpoolName_s = $HostPoolName
    numberofRunnigHosts_s = $NumberOfRunningHost
    } #>
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantUsage_CL" -TimeDifferenceInHours $TimeDifferenceInHours
  }
  else {
    #Write-Log 1 "It is Off-peak hours" "Info"
    #$LogMessage= @{logmessage_s = "It is Off-peak hours"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    Write-Output "It is Off-peak hours"
    #Write-Log 1 "It is off-peak hours. Starting to scale down RD session hosts..." "Info"
    #$LogMessage= @{logmessage_s = "It is off-peak hours. Starting to scale down RD session hosts..."}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    #Write-Log 1 ("Processing hostPool {0}" -f $HostpoolName) "Info"
    #$LogMessage= @{logmessage_s = "Processing hostPool $($HostpoolName)"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    # Get all session hosts in the host pool

    $AllSessionHosts = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName | Sort-Object Sessions
    if ($AllSessionHosts -eq $null) {
      #Write-Log 1 "Sessionhosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?." "Info"
      #$LogMessage= @{logmessage_s = "Sessionhosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      exit
    }

    # Check the number of running session hosts
    $NumberOfRunningHost = 0
    foreach ($SessionHost in $AllSessionHosts) {
      if ($SessionHost.Status -eq "Available") {
        $NumberOfRunningHost = $NumberOfRunningHost + 1
      }
    }
    # Defined minimum no of rdsh value from JSON file
    [int]$DefinedMinimumNumberOfRDSH = $MinimumNumberOfRDSH

    # Check and Collecting dynamically stored MinimumNoOfRDSH Value																 
    if (Test-Path -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt) {
      [int]$MinimumNumberOfRDSH = Get-Content $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
    }

    if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {
      foreach ($SessionHost in $AllSessionHosts.SessionHostName) {
        if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {

          $SessionHostInfo = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost
          if ($SessionHostInfo.Status -eq "Available") {

            # Ensure the running Azure VM is set as drain mode
            try {
              Set-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost -AllowNewSession $false -ErrorAction SilentlyContinue
            }
            catch {
              #Write-Log 1 "Unable to set it to allow connections on session host: $($SessionHost.SessionHost) with error: $($_.exception.message)" "Info"
              #$LogMessage= @{logmessage_s = "Unable to set it to allow connections on session host: $($SessionHost.SessionHost) with error: $($_.exception.message)"}
              #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
              exit
            }
            # Notify user to log off session
            # Get the user sessions in the hostPool
            try {
              $HostPoolUserSessions = Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName
            }
            catch {
              Write-ouput "Failed to retrieve user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)"
              exit
            }
            $HostUserSessionCount = ($HostPoolUserSessions | Where-Object -FilterScript { $_.SessionHostName -eq $SessionHost }).Count
            #Write-Log 1 "Counting the current sessions on the host $SessionHost...:$HostUserSessionCount" "Info"
            #$LogMessage= @{logmessage_s = "Counting the current sessions on the host $SessionHost...:$HostUserSessionCount"}
            #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

            $ExistingSession = 0
            foreach ($Session in $HostPoolUserSessions) {
              if ($Session.SessionHostName -eq $SessionHost) {
                if ($LimitSecondsToForceLogOffUser -ne 0) {
                  # Send notification to user
                  try {
                    Send-RdsUserSessionMessage -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $session.SessionHostName -SessionId $session.sessionid -MessageTitle $LogOffMessageTitle -MessageBody "$($LogOffMessageBody) You will logged off in $($LimitSecondsToForceLogOffUser) seconds." -NoUserPrompt

                  }
                  catch {
                    #Write-Log 1 "Failed to send message to user with error: $($_.exception.message)" "Info"
                    #$LogMessage= @{logmessage_s = "Failed to send message to user with error: $($_.exception.message)"}
                    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                    exit
                  }
                }

                $ExistingSession = $ExistingSession + 1
              }
            }
            #wait for n seconds to log off user
            Start-Sleep -Seconds $LimitSecondsToForceLogOffUser
            if ($LimitSecondsToForceLogOffUser -ne 0) {
              #force users to log off
              #Write-Log 1 "Force users to log off..." "Info"
              #$LogMessage= @{logmessage_s = "Force users to log off..."}
              #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
              try {
                $HostPoolUserSessions = Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName

              }
              catch {
                #Write-Log 1 "Failed to retrieve list of user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)" "Info"
                #$LogMessage= @{logmessage_s = "Failed to retrieve list of user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                exit
              }
              foreach ($Session in $HostPoolUserSessions) {
                if ($Session.SessionHostName -eq $SessionHost) {
                  #log off user
                  try {

                    Invoke-RdsUserSessionLogoff -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $Session.SessionHostName -SessionId $Session.sessionid -NoUserPrompt
                    $ExistingSession = $ExistingSession - 1

                  }
                  catch {
                    Write-ouput "Failed to log off user with error: $($_.exception.message)"
                    exit
                  }
                }
              }
            }

            $VMName = $SessionHost.Split(".")[0]
            # Check the Session host is in maintenance
            Maintenance -VMName $VMName
            # Check the session count before shutting down the VM
            if ($ExistingSession -eq 0) {
              # Shutdown the Azure VM
              StopAzureRMVM -VMName $VMName
            }

            # Check if the session host server is healthy before enable allowing new connections
            if ($SessionHostInfo.UpdateState -eq "Succeeded") {
              # Ensure Azure VMs that are stopped have the allowing new connections state True
              ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostPoolName -SessionHostName $SessionHost
            }
            # Decrement the number of running session host
            $NumberOfRunningHost = $NumberOfRunningHost - 1
          }
        }
      }
    }

    # Check whether minimumNoofRDSH Value stored dynamically
    if (Test-Path -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt) {
      [int]$MinimumNumberOfRDSH = Get-Content $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
      $NoConnectionsofhost = 0
      if ($NumberOfRunningHost -le $MinimumNumberOfRDSH) {
        foreach ($SessionHost in $AllSessionHosts) {
          if ($SessionHost.Status -eq "Available" -and $SessionHost.Sessions -eq 0) {
            $NoConnectionsofhost = $NoConnectionsofhost + 1

          }
        }
        if ($NoConnectionsofhost -gt $DefinedMinimumNumberOfRDSH) {
          [int]$MinimumNumberOfRDSH = [int]$MinimumNumberOfRDSH - $NoConnectionsofhost
          Clear-Content -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
          Set-Content -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt $MinimumNumberOfRDSH
        }
      }
    }


    $HostpoolMaxSessionLimit = $HostpoolInfo.MaxSessionLimit
    $HostpoolSessionCount = (Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName).Count
    if ($HostpoolSessionCount -eq 0) {
      #Write-Log 1 "HostpoolName:$HostpoolName, NumberofRunnighosts:$NumberOfRunningHost" "Info"
      #$LogMessage= @{logmessage_s = "HostpoolName:$HostpoolName, NumberofRunnighosts:$NumberOfRunningHost"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      #write to the usage log					   
      #Write-UsageLog -HostPoolName $HostpoolName -VMCount $NumberOfRunningHost -DepthBool $DepthBool
      <#$LogMessage= @{
      hostpoolName_s = $HostPoolName
      numberofRunnigHosts_s = $NumberOfRunningHost
      }#>
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantUsage_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      #Write-Log 3 "End WVD Tenant Scale Optimization." "Info"
      #$LogMessage= @{logmessage_s = "End WVD Tenant Scale Optimization."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      break
    }
    else {
      # Calculate the how many sessions will allow in minimum number of RDSH VMs in off peak hours and calculate TotalAllowSessions Scale Factor
      $TotalAllowSessionsInOffPeak = [int]$MinimumNumberOfRDSH * $HostpoolMaxSessionLimit
      $SessionsScaleFactor = $TotalAllowSessionsInOffPeak * 0.90
      $ScaleFactor = [math]::Floor($SessionsScaleFactor)


      if ($HostpoolSessionCount -ge $ScaleFactor) {

        foreach ($SessionHost in $AllSessionHosts) {
          if ($SessionHost.Sessions -ge $SessionHostLimit) {

            $AllSessionHosts = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName | Sort-Object Sessions | Sort-Object Status
            foreach ($SessionHost in $AllSessionHosts) {

              if ($SessionHost.Status -eq "Available" -and $SessionHost.Sessions -eq 0)
              { break }
              # Check the session host status and if the session host is healthy before starting the host
              if ($SessionHost.Status -eq "NoHeartbeat" -and $SessionHost.UpdateState -eq "Succeeded") {
                #Write-Log 1 "Existing Sessionhost Sessions value reached near by hostpool maximumsession limit need to start the session host" "Info"
                #$LogMessage= @{logmessage_s = "Existing Sessionhost Sessions value reached near by hostpool maximumsession limit need to start the session host"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                $SessionHostName = $SessionHost.SessionHostName | Out-String
                $VMName = $SessionHostName.Split(".")[0]
                
                # Check the Session host is in maintenance
                Maintenance -VMName $VMName

                # Validating session host is allowing new connections
                ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $SessionHost.SessionHostName

                # Start the azureRM VM
                StartAzureRMVM -VMName $VMName
                # Wait for the sessionhost is available
                $IsHostAvailable = $false
                while (!$IsHostAvailable) {

                  $SessionHostStatus = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost.SessionHostName

                  if ($SessionHostStatus.Status -eq "Available") {
                    $IsHostAvailable = $true
                  }
                }
                $NumberOfRunningHost = $NumberOfRunningHost + 1
                [int]$MinimumNumberOfRDSH = $MinimumNumberOfRDSH + 1
                if (!(Test-Path -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt)) {
                  New-Item -ItemType File -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
                  Add-Content $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt $MinimumNumberOfRDSH
                }
                else {
                  Clear-Content -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
                  Set-Content -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt $MinimumNumberOfRDSH
                }
                break
              }
            }

          }
        }
      }
    }

    #Write-Log 1 "HostpoolName:$HostpoolName, NumberofRunnighosts:$NumberOfRunningHost" "Info"
    #$LogMessage= @{logmessage_s = "HostpoolName:$HostpoolName, NumberofRunnighosts:$NumberOfRunningHost"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    
    #Write-UsageLog -HostPoolName $HostpoolName -VMCount $NumberOfRunningHost -DepthBool $DepthBool
    #$LogMessage= @{
    #hostpoolName_s = $HostPoolName
    #numberofRunnigHosts_s = $NumberOfRunningHost
    #}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantUsage_CL" -TimeDifferenceInHours $TimeDifferenceInHours

  }
  #Write-Log 3 "End WVD Tenant Scale Optimization." "Info"
  #$LogMessage= @{logmessage_s = "End WVD Tenant Scale Optimization."}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
}
else {
  #Write-Log 3 "$HostpoolName hostpool loadbalancer type is $($HostpoolInfo.LoadBalancerType)" "Info"
  #$LogMessage= @{logmessage_s = "$HostpoolName hostpool loadbalancer type is $($HostpoolInfo.LoadBalancerType)"}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
  # Check if it is during the peak or off-peak time
  if ($CurrentDateTime -ge $BeginPeakDateTime -and $CurrentDateTime -le $EndPeakDateTime) {
    Write-Output "It is in peak hours now"
    #Write-Log 1 "It is in peak hours now" "Info"
    #$LogMessage= @{logmessage_s = "It is in peak hours now"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    #Write-Log 3 "Peak hours: starting session hosts as needed based on current workloads." "Info"
    #$LogMessage= @{logmessage_s = "Peak hours: starting session hosts as needed based on current workloads."}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    # Get the Session Hosts in the hostPool		
    $AllSessionHosts = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -ErrorAction SilentlyContinue | Sort-Object SessionHostName
    if ($AllSessionHosts -eq $null) {
      #Write-Log 1 "Sessionhosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?." "Info"
      #$LogMessage= @{logmessage_s = "Sessionhosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      exit
    }

    # Get the User Sessions in the hostPool
    try {
      $HostPoolUserSessions = Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName
    }
    catch {
      #Write-Log 1 "Failed to retrieve user sessions in hostPool:$($HostpoolName) with error: $($_.exception.message)" "Error"
      #$LogMessage= @{logmessage_s = "Failed to retrieve user sessions in hostPool:$($HostpoolName) with error: $($_.exception.message)"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      exit 1
    }

    # Check and Remove the MinimumnoofRDSH value dynamically stored file												   
    if (Test-Path -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt) {
      Remove-Item -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
    }

    # Check the number of running session hosts
    $NumberOfRunningHost = 0

    # Total of running cores
    $TotalRunningCores = 0

    # Total capacity of sessions of running VMs
    $AvailableSessionCapacity = 0

    foreach ($SessionHost in $AllSessionHosts) {
      #Write-Log 1 "Checking session host:$($SessionHost.SessionHostName | Out-String)  of sessions:$($SessionHost.Sessions) and status:$($SessionHost.Status)" "Info"
      #$LogMessage= @{logmessage_s = "Checking session host:$($SessionHost.SessionHostName | Out-String)  of sessions:$($SessionHost.Sessions) and status:$($SessionHost.Status)"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      $SessionHostName = $SessionHost.SessionHostName | Out-String
      $VMName = $SessionHostName.Split(".")[0]
      
      # Check the Session host is in maintenance
      Maintenance -VMName $VMName
      
      $RoleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }
      if ($SessionHostName.ToLower().Contains($RoleInstance.Name.ToLower())) {
        # Check if the azure vm is running       
        if ($RoleInstance.PowerState -eq "VM running") {
          $NumberOfRunningHost = $NumberOfRunningHost + 1
          # Calculate available capacity of sessions						
          $RoleSize = Get-AzureRmVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
          $AvailableSessionCapacity = $AvailableSessionCapacity + $RoleSize.NumberOfCores * $SessionThresholdPerCPU
          $TotalRunningCores = $TotalRunningCores + $RoleSize.NumberOfCores
        }

      }

    }
    #Write-Log 1 "Current number of running hosts:$NumberOfRunningHost" "Info"
    #$LogMessage= @{logmessage_s = "Current number of running hosts:$NumberOfRunningHost"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

    if ($NumberOfRunningHost -lt $MinimumNumberOfRDSH) {

      #Write-Log 1 "Current number of running session hosts is less than minimum requirements, start session host ..." "Info"
      #$LogMessage= @{logmessage_s = "Current number of running session hosts is less than minimum requirements, start session host ..."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

      # Start VM to meet the minimum requirement            
      foreach ($SessionHost in $AllSessionHosts.SessionHostName) {

        # Check whether the number of running VMs meets the minimum or not
        if ($NumberOfRunningHost -lt $MinimumNumberOfRDSH) {

          $VMName = $SessionHost.Split(".")[0]
         
          # Check if the Session host is in maintenance
          Maintenance -VMName $VMName         

          $RoleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

          if ($SessionHost.ToLower().Contains($RoleInstance.Name.ToLower())) {

            # Check if the Azure VM is running and if the session host is healthy
            $SessionHostInfo = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost
            if ($RoleInstance.PowerState -ne "VM running" -and $SessionHostInfo.UpdateState -eq "Succeeded") {
              # Check if the session host is allowing new connections
              # Validating session host is allowing new connections
              ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $SessionHost
              # Start the AzureRM VM
              StartAzureRMVM -VMName $VMName
              # Wait for the VM to start
              $IsVMStarted = $false
              while (!$IsVMStarted) {
                $VMState = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $RoleInstance.Name }
                if ($VMState.PowerState -eq "VM running" -and $VMState.ProvisioningState -eq "Succeeded") {
                  $IsVMStarted = $true
                }
              }
              # Calculate available capacity of sessions
              $RoleSize = Get-AzureRmVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
              $AvailableSessionCapacity = $AvailableSessionCapacity + $RoleSize.NumberOfCores * $SessionThresholdPerCPU
              $NumberOfRunningHost = $NumberOfRunningHost + 1
              $TotalRunningCores = $TotalRunningCores + $RoleSize.NumberOfCores
              if ($NumberOfRunningHost -ge $MinimumNumberOfRDSH) {
                break;
              }
            }
          }
        }
      }
    }

    else {
      #check if the available capacity meets the number of sessions or not
      #$LogMessage= @{logmessage_s = "Current total number of user sessions: $(($HostPoolUserSessions).Count)"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      #Write-Log 1 "Current available session capacity is: $AvailableSessionCapacity" "Info"
      #$LogMessage= @{logmessage_s = "Current available session capacity is: $AvailableSessionCapacity"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      if ($HostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
        #Write-Log 1 "Current available session capacity is less than demanded user sessions, starting session host" "Info"
        #$LogMessage= @{logmessage_s = "Current available session capacity is less than demanded user sessions, starting session host"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
        # Running out of capacity, we need to start more VMs if there are any 
        foreach ($SessionHost in $AllSessionHosts.SessionHostName) {
          if ($HostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
            $VMName = $SessionHost.Split(".")[0]
            # Check the Session host is in maintenance
            Maintenance -VMName $VMName

            $RoleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

            if ($SessionHost.ToLower().Contains($RoleInstance.Name.ToLower())) {
              # Check if the Azure VM is running and if the session host is healthy
              $SessionHostInfo = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost
              if ($RoleInstance.PowerState -ne "VM running" -and $SessionHostInfo.UpdateState -eq "Succeeded") {
                # Check if the session host is allowing new connections
                # Validating session host is allowing new connections
                ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $SessionHost
                # Start the AzureRM VM
                StartAzureRMVM -VMName $VMName
                # Wait for the VM to Start
                $IsVMStarted = $false
                while (!$IsVMStarted) {
                  $VMState = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $RoleInstance.Name }

                  if ($VMState.PowerState -eq "VM running" -and $VMState.ProvisioningState -eq "Succeeded") {
                    $IsVMStarted = $true
                    #Write-Log 1 "Azure VM has been started: $($RoleInstance.Name) ..." "Info"
                    #$LogMessage= @{logmessage_s = "Azure VM has been started: $($RoleInstance.Name) ..."}
                    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                  }
                  else {
                    #Write-Log 3 "Waiting for Azure VM to start $($RoleInstance.Name) ..." "Info"
                    #$LogMessage= @{logmessage_s = "Waiting for Azure VM to start $($RoleInstance.Name) ..."}
                    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                  }
                }
                # Calculate available capacity of sessions
                $RoleSize = Get-AzureRmVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                $AvailableSessionCapacity = $AvailableSessionCapacity + $RoleSize.NumberOfCores * $SessionThresholdPerCPU
                $NumberOfRunningHost = $NumberOfRunningHost + 1
                $TotalRunningCores = $TotalRunningCores + $RoleSize.NumberOfCores
                #Write-Log 1 "New available session capacity is: $AvailableSessionCapacity" "Info"
                #$LogMessage= @{logmessage_s = "New available session capacity is: $AvailableSessionCapacity"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                if ($AvailableSessionCapacity -gt $HostPoolUserSessions.Count) {
                  break
                }
              }
              #Break # break out of the inner foreach loop once a match is found and checked
            }
          }
        }
      }
    }
    #Write-Log 1 "HostpoolName:$HostpoolName, TotalRunningCores:$TotalRunningCores NumberOfRunningHost:$NumberOfRunningHost" "Info"
    #$LogMessage= @{logmessage_s = "HostpoolName:$HostpoolName, TotalRunningCores:$TotalRunningCores NumberOfRunningHost:$NumberOfRunningHost"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    # Write to the usage log
    #Write-UsageLog -HostPoolName $HostpoolName -Corecount $TotalRunningCores -VMCount $NumberOfRunningHost -DepthBool $DepthBool
    <#$LogMessage= @{
    hostpoolName_s = $HostPoolName
    numberofCores_s = $TotalRunningCores
    numberofRunnigHosts_s = $NumberOfRunningHost
    } #>
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantUsage_CL" -TimeDifferenceInHours $TimeDifferenceInHours
  }
   
  else {
    #Write-Log 1 "It is Off-peak hours" "Info"
    #$LogMessage= @{logmessage_s = "It is Off-peak hours"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    Write-Output "It is Off-peak hours"
    #Write-Log 3 "It is off-peak hours. Starting to scale down RD session hosts..." "Info"
    #$LogMessage= @{logmessage_s = "It is off-peak hours. Starting to scale down RD session hosts..."}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    Write-Output ("Processing hostPool {0}" -f $HostpoolName)
    #Write-Log 3 "Processing hostPool $($HostpoolName)"
    #$LogMessage= @{logmessage_s = "Processing hostPool $($HostpoolName)"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    # Get the Session Hosts in the hostPool
    $AllSessionHosts = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName
    # Check the sessionhosts are exist in the hostpool
    if ($AllSessionHosts -eq $null) {
      #Write-Log 1 "Sessionhosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?." "Info"
      #$LogMessage= @{logmessage_s = "Sessionhosts does not exist in the Hostpool of '$HostpoolName'. Ensure that hostpool have hosts or not?."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      exit
    }

    # Check the number of running session hosts
    $NumberOfRunningHost = 0

    # Total number of running cores
    $TotalRunningCores = 0

    foreach ($SessionHost in $AllSessionHosts.SessionHostName) {

      $VMName = $SessionHost.Split(".")[0]
      $RoleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

      if ($SessionHost.ToLower().Contains($RoleInstance.Name.ToLower())) {
        #check if the Azure VM is running or not

        if ($RoleInstance.PowerState -eq "VM running") {
          $NumberOfRunningHost = $NumberOfRunningHost + 1

          # Calculate available capacity of sessions  
          $RoleSize = Get-AzureRmVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
          $TotalRunningCores = $TotalRunningCores + $RoleSize.NumberOfCores
        }
      }
    }
    # Defined minimum no of rdsh value from JSON file
    [int]$DefinedMinimumNumberOfRDSH = $MinimumNumberOfRDSH

    # Check and Collecting dynamically stored MinimumNoOfRDSH Value																 
    if (Test-Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt) {
      [int]$MinimumNumberOfRDSH = Get-Content $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
    }
    if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {
      # Shutdown VM to meet the minimum requirement
      foreach ($SessionHost in $AllSessionHosts.SessionHostName) {
        if ($NumberOfRunningHost -gt $MinimumNumberOfRDSH) {

          $VMName = $SessionHost.Split(".")[0]
          $RoleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

          if ($SessionHost.ToLower().Contains($RoleInstance.Name.ToLower())) {

            # Check if the Azure VM is running
            if ($RoleInstance.PowerState -eq "VM running") {
              # Check if the role isntance status is ReadyRole before setting the session host
              $IsInstanceReady = $false
              $NumerOfRetries = 0
              while (!$IsInstanceReady -and $NumerOfRetries -le 3) {
                $NumerOfRetries = $NumerOfRetries + 1
                $Instance = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $RoleInstance.Name }
                if ($Instance.ProvisioningState -eq "Succeeded" -and $Instance -ne $null) {
                  $IsInstanceReady = $true
                }

              }
              if ($IsInstanceReady) {

                # Ensure the running Azure VM is set as drain mode
                try {
                  Set-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost -AllowNewSession $false -ErrorAction SilentlyContinue
                }
                catch {

                  #Write-Log 1 "Unable to set it to allow connections on session host: $($SessionHost.SessionHost) with error: $($_.exception.message)" "Error"
                  #$LogMessage= @{logmessage_s = "Unable to set it to allow connections on session host: $($SessionHost.SessionHost) with error: $($_.exception.message)"}
                  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                  exit 1

                }
                # Notify user to log off session
                # Get the user sessions in the hostPool
                try {
                  $HostPoolUserSessions = Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName
                }
                catch {
                  #Write-Log 1 "Failed to retrieve user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)" "Error"
                  #$LogMessage= @{logmessage_s = "Failed to retrieve user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)"}
                  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                  exit 1
                }

                $HostUserSessionCount = ($HostPoolUserSessions | Where-Object -FilterScript { $_.SessionHostName -eq $SessionHost }).Count
                #Write-Log 1 "Counting the current sessions on the host $SessionHost...:$HostUserSessionCount" "Info"
                #$LogMessage= @{logmessage_s = "Counting the current sessions on the host $SessionHost...:$HostUserSessionCount"}
                #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                $ExistingSession = 0

                foreach ($session in $HostPoolUserSessions) {

                  if ($session.SessionHostName -eq $SessionHost) {

                    if ($LimitSecondsToForceLogOffUser -ne 0) {
                      # Send notification
                      try {
                        Send-RdsUserSessionMessage -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $SessionHost -SessionId $session.sessionid -MessageTitle $LogOffMessageTitle -MessageBody "$($LogOffMessageBody) You will logged off in $($LimitSecondsToForceLogOffUser) seconds." -NoUserPrompt
                      }
                      catch {
                        #Write-Log 1 "Failed to send message to user with error: $($_.exception.message)" "Error"
                        #$LogMessage= @{logmessage_s = "Failed to send message to user with error: $($_.exception.message)"}
                        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                        exit 1

                      }
                    }
                    $ExistingSession = $ExistingSession + 1
                  }
                }
                # Wait for n seconds to log off user
                Start-Sleep -Seconds $LimitSecondsToForceLogOffUser
                if ($LimitSecondsToForceLogOffUser -ne 0) {
                  # Force users to log off
                  #Write-Log 1 "Force users to log off..." "Info"
                  #$LogMessage= @{logmessage_s = "Force users to log off..."}
                  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                  try {
                    $HostPoolUserSessions = Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName
                  }
                  catch {
                    #Write-Log 1 "Failed to retrieve list of user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)" "Error"
                    #$LogMessage= @{logmessage_s = "Failed to retrieve list of user sessions in hostPool: $($HostpoolName) with error: $($_.exception.message)"}
                    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                    exit 1
                  }
                  foreach ($Session in $HostPoolUserSessions) {
                    if ($Session.SessionHostName -eq $SessionHost) {
                      #Log off user
                      try {
                        Invoke-RdsUserSessionLogoff -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $Session.SessionHostName -SessionId $Session.sessionid -NoUserPrompt
                        $ExistingSession = $ExistingSession - 1
                      }
                      catch {
                        #Write-Log 1 "Failed to log off user with error: $($_.exception.message)" "Error"
                        #$LogMessage= @{logmessage_s = "Failed to log off user with error: $($_.exception.message)"}
                        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                        exit 1
                      }
                    }
                  }
                }
                # Check the session count before shutting down the VM
                if ($ExistingSession -eq 0) {
                  # Check the Session host is in maintenance
                  Maintenance -VMName $VMName
                  # Shutdown the Azure VM
                  StopAzureRMVM -VMName $VMName
                  #wait for the VM to stop
                  $IsVMStopped = $false
                  while (!$IsVMStopped) {

                    $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $RoleInstance.Name }

                    if ($vm.PowerState -eq "VM deallocated") {
                      $IsVMStopped = $true
                      #Write-Log 1 "Azure VM has been stopped: $($RoleInstance.Name) ..." "Info"
                      #$LogMessage= @{logmessage_s = "Azure VM has been stopped: $($RoleInstance.Name) ..."}
                      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                    }
                    else {
                      #Write-Log 3 "Waiting for Azure VM to stop $($RoleInstance.Name) ..." "Info"
                      #$LogMessage= @{logmessage_s = "Waiting for Azure VM to stop $($RoleInstance.Name) ..."}
                      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                    }
                  }
                  $SessionHostInfo = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost
                  if ($SessionHostInfo.UpdateState -eq "Succeeded") {
                    # Ensure the Azure VMs that are off have Allow new connections mode set to True
                      ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $SessionHost
                  }
                  $RoleSize = Get-AzureRmVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
                  #decrement number of running session host
                  $NumberOfRunningHost = $NumberOfRunningHost - 1
                  $TotalRunningCores = $TotalRunningCores - $RoleSize.NumberOfCores
                }
              }
            }
          }
        }
      }

    }

  # Change to automation variable 
  # Dynamically store the minimum no of rdsh
  
    # Calculate the how many sessions will allow in minimum number of RDSH VMs in off peak hours
    $HostpoolMaxSessionLimit = $HostpoolInfo.MaxSessionLimit
    $HostpoolSessionCount = (Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostpoolName).Count
    if ($HostpoolSessionCount -eq 0) {
      #Write-Log 1 "HostpoolName:$HostpoolName, TotalRunningCores:$TotalRunningCores NumberOfRunningHost:$NumberOfRunningHost" "Info"
      #$LogMessage= @{logmessage_s = "HostpoolName:$HostpoolName, TotalRunningCores:$TotalRunningCores NumberOfRunningHost:$NumberOfRunningHost"}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      # Write to the usage log
      #Write-UsageLog $HostpoolName $TotalRunningCores $NumberOfRunningHost $DepthBool
      #$LogMessage= @{
      #hostpoolName_s = $HostPoolName
      #numberofCores_s = $TotalRunningCores
      #numberofRunnigHosts_s = $NumberOfRunningHost
      
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantUsage_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      
      #Write-Log 3 "End WVD Tenant Scale Optimization." "Info"
      #$LogMessage= @{logmessage_s = "End WVD Tenant Scale Optimization."}
      #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
      break
      }
    
    
    else {
      # Calculate the how many sessions will allow in minimum number of RDSH VMs in off peak hours and calculate TotalAllowSessions Scale Factor
      $TotalAllowSessionsInOffPeak = [int]$MinimumNumberOfRDSH * $HostpoolMaxSessionLimit
      $SessionsScaleFactor = $TotalAllowSessionsInOffPeak * 0.90
      $ScaleFactor = [math]::Floor($SessionsScaleFactor)
      if ($HostpoolSessionCount -ge $ScaleFactor) {
        # Check if the available capacity meets the number of sessions or not
        #Write-Log 1 "Current total number of user sessions: $HostpoolSessionCount" "Info"
        #$LogMessage= @{logmessage_s = "Current total number of user sessions: $HostpoolSessionCount"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
        #Write-Log 1 "Current available session capacity is less than demanded user sessions, starting session host" "Info"
        #$LogMessage= @{logmessage_s = "Current available session capacity is less than demanded user sessions, starting session host"}
        #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
        # Running out of capacity, we need to start more VMs if there are any 
        foreach ($SessionHost in $AllSessionHosts) {
          $SessionHostName = $SessionHost.SessionHostName | Out-String
          $VMName = $SessionHostName.Split(".")[0]

          # Check the Session host is in maintenance
          Maintenance -VMName $VMName
         
          $RoleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }
          if ($SessionHostName.ToLower().Contains($RoleInstance.Name.ToLower())) {
            # Check if the Azure VM is running and if the session host is healthy
            $SessionHostInfo = Get-RdsSessionHost -TenantName $TenantName -HostPoolName $HostpoolName -Name $SessionHost.SessionHostName
            if ($RoleInstance.PowerState -ne "VM running" -and $SessionHostInfo.UpdateState -eq "Succeeded") {

              # Check if the session host is allowing new connections
              ValidateAllowNewConnections -TenantName $TenantName -HostPoolName $HostpoolName -SessionHostName $$SessionHostName
              # Start the AzureRM VM
              StartAzureRMVM -VMName $VMName
              # Wait for the VM to start
              $IsVMStarted = $false
              while (!$IsVMStarted) {
                $VMState = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $RoleInstance.Name }

                if ($VMState.PowerState -eq "VM running" -and $VMState.ProvisioningState -eq "Succeeded") {
                  $IsVMStarted = $true
                  #Write-Log 1 "Azure VM has been started: $($RoleInstance.Name) ..." "Info"
                  #$LogMessage= @{logmessage_s = "Azure VM has been started: $($RoleInstance.Name) ..."}
                  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                }
                else {
                  #Write-Log 3 "Waiting for Azure VM to start $($RoleInstance.Name) ..." "Info"
                  #$LogMessage= @{logmessage_s = "Waiting for Azure VM to start $($RoleInstance.Name) ..."}
                  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
                }
              }
              # Calculate available capacity of sessions
              $RoleSize = Get-AzureRmVMSize -Location $RoleInstance.Location | Where-Object { $_.Name -eq $RoleInstance.HardwareProfile.VmSize }
              $AvailableSessionCapacity = $TotalAllowSessions + $HostpoolInfo.MaxSessionLimit
              $NumberOfRunningHost = $NumberOfRunningHost + 1
              $TotalRunningCores = $TotalRunningCores + $RoleSize.NumberOfCores
              #Write-Log 1 "New available session capacity is: $AvailableSessionCapacity" "Info"
              #$LogMessage= @{logmessage_s = "New available session capacity is: $AvailableSessionCapacity"}
              #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours

              [int]$MinimumNumberOfRDSH = [int]$MinimumNumberOfRDSH + 1
              if (!(Test-Path -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt)) {
                New-Item -ItemType File -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
                Add-Content $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt $MinimumNumberOfRDSH
              }
              else {
                Clear-Content -Path $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt
                Set-Content $CurrentPath\OffPeakUsage-MinimumNoOfRDSH.txt $MinimumNumberOfRDSH
              }
              break
            }
            #Break # break out of the inner foreach loop once a match is found and checked
          }
        }
      }

    }

    #Write-Log 1 "HostpoolName:$HostpoolName, TotalRunningCores:$TotalRunningCores NumberOfRunningHost:$NumberOfRunningHost" "Info"
    #$LogMessage= @{logmessage_s = "HostpoolName:$HostpoolName, TotalRunningCores:$TotalRunningCores NumberOfRunningHost:$NumberOfRunningHost"}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
    #write to the usage log
    #Write-UsageLog -HostPoolName $HostpoolName -Corecount $TotalRunningCores -VMCount $NumberOfRunningHost -DepthBool $DepthBool
    #$LogMessage= @{
    #hostpoolName_s = $HostPoolName
    #numberofCores_s = $TotalRunningCores
    #numberofRunnigHosts_s = $NumberOfRunningHost
    #}
    #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantUsage_CL" -TimeDifferenceInHours $TimeDifferenceInHours
   #Scale hostPool
  #Write-Log 3 "End WVD Tenant Scale Optimization." "Info"
  #$LogMessage= @{logmessage_s = "End WVD Tenant Scale Optimization."}
  #AddToLog -LogData #$LogMessage-CustomerId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsPrimaryKey -LogType "WVDTenantScale_CL" -TimeDifferenceInHours $TimeDifferenceInHours
}
}

