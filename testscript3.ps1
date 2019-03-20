<#
Copyright 2018 Microsoft
Version 1.0 June 2018
.SYNOPSIS
This is a sample script for automatically scaling Tenant Environment WVD Host Servers in Micrsoft Azure
.Description
This script will automatically start/stop Tenant WVD host VMs based on the number of user sessions and peak/off-peak time period specified in the configuration file.
During the peak hours, the script will start necessary session hosts in the Hostpool to meet the demands of users.
During the off-peak hours, the script will shutdown the session hosts and only keep the minimum number of session hosts.
This script depends on 2 powershell modules: Azure RM and WVD Module to get azurerm module execute following command.
Use "-AllowClobber" parameter if you have more than one version of PS modules installed.
PS C:\>Install-Module AzureRM  -AllowClobber
WVD PowerShell Modules included inside this folder "AutoScale-WVD" with name PowerShellModules.
#>
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

$RDBrokerURL = $Input.RDBrokerURL
$AADTenantId = $Input.AADTenantId
$AADApplicationId = $Input.AADApplicationId
$AADServicePrincipalSecret = $Input.AADServicePrincipalSecret
$SubscriptionID = $Input.SubscriptionID
$TenantGroupName = $Input.TenantGroupName
$TenantName = $Input.TenantName
$BeginPeakTime = $Input.BeginPeakTime
$fileURI = $Input.fileURI
$EndPeakTime = $Input.EndPeakTime
$TimeDifference = $Input.TimeDifference
$SessionThresholdPerCPU = $Input.SessionThresholdPerCPU
$MinimumNumberOfRDSH = $Input.MinimumNumberOfRDSH
$LimitSecondsToForceLogOffUser = $Input.LimitSecondsToForceLogOffUser
$LogOffMessageTitle = $Input.LogOffMessageTitle
$LogOffMessageBody = $Input.LogOffMessageBody
$HostpoolName = $Input.HostpoolName
$isServicePrincipal = $true


Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String

if(!(Test-Path -Path "C:\WVDAutoScale-$HostpoolName")){
  
    Invoke-WebRequest -Uri $fileURI -OutFile "C:\WVDAutoScale-$HostpoolName.zip"
    New-Item -Path "C:\WVDAutoScale-$HostpoolName" -ItemType Directory -Force -ErrorAction SilentlyContinue
    Expand-Archive "C:\WVDAutoScale-$HostpoolName.zip" -DestinationPath "C:\WVDAutoScale-$HostpoolName" -ErrorAction SilentlyContinue
    Copy-Item -Path "C:\WVDAutoScale-$HostpoolName\AzureModules\*"  -Destination 'C:\Modules\Global' -Force -Recurse
    }

Function Write-UsageLog {
    Param(
        [string]$hostpoolName,
        [int]$corecount,
        [int]$vmcount,
        [string]$logfilename = $RdmiTenantUsagelog
    )
    $time = get-date
    Add-Content $logfilename -value ("{0}, {1}, {2}, {3}" -f $time, $hostpoolName, $corecount, $vmcount)
}



Function Write-Log {
    Param(
        [int]$level
        , [string]$Message
        , [ValidateSet("Info", "Warning", "Error")][string]$severity = 'Info'
        , [string]$logname = $rdmiTenantlog
        , [string]$color = "white"
    )
    $time = get-date
    Add-Content $logname -value ("{0} - [{1}] {2}" -f $time, $severity, $Message)
    if ($interactive) {
        switch ($severity) {
            'Error' {$color = 'Red'}
            'Warning' {$color = 'Yellow'}
        }
        if ($level -le $VerboseLogging) {
            if ($color -match "Red|Yellow") {
                Write-Host ("{0} - [{1}] {2}" -f $time, $severity, $Message) -ForegroundColor $color -BackgroundColor Black
                if ($severity -eq 'Error') { 
                    
                    throw $Message 
                }
            }
            else {
                Write-Host ("{0} - [{1}] {2}" -f $time, $severity, $Message) -ForegroundColor $color
            }
        }
    }
    else {
        switch ($severity) {
            'Info' {Write-Verbose -Message $Message}
            'Warning' {Write-Warning -Message $Message}
            'Error' {
                throw $Message
            }
        }
    }
} 

#$CurrentPath = Split-Path $script:MyInvocation.MyCommand.Path
$CurrentPath = "C:\WVDAutoScale-$HostpoolName"

#Log path
$rdmiTenantlog = "$CurrentPath\WVDTenantScale.log"

#usage log path
$RdmiTenantUsagelog = "$CurrentPath\WVDTenantUsage.log"


Set-Location "$CurrentPath\RDPowershell"
Import-Module .\Microsoft.RdInfra.RdPowershell.dll
Import-Module AzureRm.profile
Import-Module AzureRM.Resources

#The the following three lines is to use password/secret based authentication for service principal, to use certificate based authentication, please comment those lines, and uncomment the above line
$secpasswd = ConvertTo-SecureString $AADServicePrincipalSecret -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($AADApplicationId, $secpasswd)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$isServicePrincipalBool = ($isServicePrincipal -eq "True")
# Check if service principal or user accoung is being user 
#Authenticating to Azure
if (!$isServicePrincipalBool) {
  # if standard account is provided login in Azure with that account 

  try {
    $authentication = connect-AzureRmAccount -SubscriptionID $SubscriptionID -Credential $Credential
  }
  catch {
    Write-Log 1 "Failed to authenticate with Azure with standard account: $($_.exception.message)" "Error"
    exit 1

  }
  Write-Log 3 "Authenticating as standard account for Azure." "Info"
}
else {
  # if service principal account is provided login in Azure with that account 
  try {
    $TenantLogin = connect-AzureRmAccount -ServicePrincipal -Credential $Credential -TenantId $AADTenantId
  }
  catch {
    Write-Log 1 "Failed to authenticate with Azure with service principal: $($_.exception.message)" "Error"
    exit 1
  }
  Write-Log 3 "Authenticating as service principal account for Azure." "Info"
}

#Authenticating to WVD
if (!$isServicePrincipalBool) {
  # if standard account is provided login in WVD with that account 
  try {
    $authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Credential
  }
  catch {
    Write-Log 1 "Failed to authenticate with WVD Tenant with standard account: $($_.exception.message)" "Error"
    exit 1
  }
  Write-Log 3 "Authenticating as standard account for WVD." "Info"
}
else {
  # if service principal account is provided login in WVD with that account 

  try {
    $authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -TenantId $AADTenantId -Credential $Credential -ServicePrincipal
  }
  catch {
    Write-Log 1 "Failed to authenticate with WVD Tenant with service principal: $($_.exception.message)" "Error"
    exit 1
  }
  Write-Log 3 "Authenticating as service principal account for WVD." "Info"
}


#Set context to the appropriate tenant group
Write-Log  1 "Running switching to the $tenantGroupName context" "Info"
Set-RdsContext -TenantGroupName $tenantGroupName

#select the current Azure Subscription specified in the config
Select-AzureRmSubscription -SubscriptionID $SubscriptionID
#Set-AzureRmSubscription -SubscriptionID $SubscriptionID
#Construct Begin time and End time for the Peak period
$CurrentDateTime = Get-Date
Write-Log 3 "Starting WVD Tenant Hosts Scale Optimization: Current Date Time is: $CurrentDateTime" "Info"

$BeginPeakDateTime = [datetime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $BeginPeakTime)

$EndPeakDateTime = [datetime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $EndPeakTime)

#check the calculated end time is later than begin time in case of time zone
if ($EndPeakDateTime -lt $BeginPeakDateTime) {
  $EndPeakDateTime = $EndPeakDateTime.AddDays(1)
}
$hostpoolInfo = Get-RdsHostPool -TenantName $tenantName -Name $hostPoolName
if ($hostpoolInfo.LoadBalancerType -eq "DepthFirst") {
Write-Log 1 "$hostPoolName hostpool loadbalancer type is $($hostpoolInfo.LoadBalancerType)" "Info"
  if ($CurrentDateTime -ge $BeginPeakDateTime -and $CurrentDateTime -le $EndPeakDateTime) {

    Write-Log 1  "It is in peak hours now" "Info"
    Write-Log 1 "Peak hours: starting session hosts as needed based on current workloads." "Info"
    $hostpoolMaxSessionLimit = $hostpoolinfo.MaxSessionLimit
    #Get the session hosts in the hostpool
    try {
      $getHosts = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname | Sort-Object $_.sessionhostname
    }
    catch {
      Write-Log 1 "Failed to retrieve sessionhost in hostpool $($hostPoolName) : $($_.exception.message)" "Info"
      exit
    }
    <#
    if ($hostpoolMaxSessionLimit -eq 2) {
      $sessionlimit = $hostpoolMaxSessionLimit - 1
    }
    else {
      $sessionlimitofhost = $hostpoolMaxSessionLimit / 4
      $var = $hostpoolMaxSessionLimit - $sessionlimitofhost
      $sessionlimit = [math]::Round($var)
    }
    #>
    if ($hostpoolMaxSessionLimit -le 10) {
        $sessionlimit = $hostpoolMaxSessionLimit - 1
        
        }
    elseif($hostpoolMaxSessionLimit -le 50) {
        $sessionlimitofhost = $hostpoolMaxSessionLimit / 4
        $var = $hostpoolMaxSessionLimit - $sessionlimitofhost
        $sessionlimit = [math]::Round($var)
        
    }
    elseif($hostpoolMaxSessionLimit -gt 50)
    {
       $sessionlimit = $hostpoolMaxSessionLimit - 10
       
    }
 
 Write-Log 1 "Hostpool Maximum Session Limit: $($hostpoolMaxSessionLimit)"

    #check the number of running session hosts
    $numberOfRunningHost = 0
    foreach ($sessionHost in $getHosts) {
           
      Write-Log 1 "Checking session host:$($sessionHost.SessionHostName | Out-String)  of sessions:$($sessionHost.Sessions) and status:$($sessionHost.Status)" "Info"

      $sessionCapacityofhost = $sessionhost.Sessions
      if ($sessionlimit -lt $sessionCapacityofhost -or $sessionHost.Status -eq "Available") {

        $numberOfRunningHost = $numberOfRunningHost + 1
      }
    }
    Write-Log 1  "Current number of running hosts: $numberOfRunningHost" "Info"
    if ($numberOfRunningHost -lt $MinimumNumberOfRDSH) {
      Write-Log 1  "Current number of running session hosts is less than minimum requirements, start session host ..." "Info"

      foreach ($sessionhost in $getHosts) {

         if ($numberOfRunningHost -lt $MinimumNumberOfRDSH) {
          $hostsessions = $sessionHost.Sessions
          if ($hostpoolMaxSessionLimit -ne $hostofsessions) {
            if ($sessionhost.Status -eq "UnAvailable") {
              $sessionhostname = $sessionhost.sessionhostname
              #Check session host is in Drain Mode
              $checkAllowNewSession = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sessionhostname
              if (!($checkAllowNewSession.AllowNewSession)) {
                Set-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sessionhostname -AllowNewSession $true
              }
              $VMName = $sessionHostname.Split(".")[0]
              #start the azureRM VM
              try {
                Get-AzureRmVM | Where-Object { $_.Name -eq $VMName } | Start-AzureRmVM

              }
              catch {
                Write-Log 1 "Failed to start Azure VM: $($VMName) with error: $($_.exception.message)" "Info"
                exit
              }
              #wait for the sessionhost is available
                $IsHostAvailable = $false
                while (!$IsHostAvailable) {

                  $hoststatus = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sessionHost.sessionhostname

                  if ($hoststatus.Status -eq "Available") {
                    $IsHostAvailable = $true
                  }
                }
            }
          }
          $numberOfRunningHost = $numberOfRunningHost + 1
          }
      }
    }

    else {
      $getHosts = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname | Sort-Object "Sessions" -Descending | Sort-Object Status
      foreach ($sessionhost in $getHosts) {
        if (!($sessionHost.Sessions -eq $hostpoolMaxSessionLimit)) {
          if ($sessionHost.Sessions -ge $sessionlimit) {
          foreach($sHost in $getHosts){
                if ($sHost.Status -eq "Available" -and $sHost.Sessions -eq 0) { break }
                if ($sHost.Status -eq "Unavailable") {
                Write-Log 1 "Existing Sessionhost Sessions value reached near by hostpool maximumsession limit need to start the session host" "Info"
                $sessionhostname = $sHost.sessionhostname
                #Check session host is in Drain Mode
                $checkAllowNewSession = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sessionhostname
                if (!($checkAllowNewSession.AllowNewSession)) {
                  Set-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sessionhostname -AllowNewSession $true
                }
                $VMName = $sessionHostname.Split(".")[0]

                #start the azureRM VM
                try {
                  Get-AzureRmVM | Where-Object { $_.Name -eq $VMName } | Start-AzureRmVM
                }
                catch {
                  Write-Log 1 "Failed to start Azure VM: $($VMName) with error: $($_.exception.message)" "Info"
                  exit
                }
                #wait for the sessionhost is available
                $IsHostAvailable = $false
                while (!$IsHostAvailable) {

                  $hoststatus = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sHost.sessionhostname

                  if ($hoststatus.Status -eq "Available") {
                    $IsHostAvailable = $true
                  }
                }
                $numberOfRunningHost = $numberOfRunningHost + 1
                break
              }
          }
        }
      }
    }
    }
    Write-Log 1  "HostpoolName:$hostpoolname, NumberofRunnighosts:$numberOfRunningHost" "Info"
    $depthBool = $true
    Write-UsageLog $hostPoolName $numberOfRunningHost $depthBool
  }
  else {
    Write-Log 1  "It is Off-peak hours" "Info"
    Write-Log 1  "It is off-peak hours. Starting to scale down RD session hosts..." "Info"
    Write-Log 1  ("Processing hostPool {0}" -f $hostPoolName) "Info"
    try {
      $getHosts = Get-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName | Sort-Object Sessions
    }
    catch {
      Write-Log 1 "Failed to retrieve session hosts in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Info"
      exit
    }
    #check the number of running session hosts
    $numberOfRunningHost = 0
    foreach ($sessionHost in $getHosts) {
       if ($sessionHost.Status -eq "Available") {
        $numberOfRunningHost = $numberOfRunningHost + 1
      }
    }
    if ($numberOfRunningHost -gt $MinimumNumberOfRDSH) {
      foreach ($sessionHost in $getHosts.sessionhostname) {
        if ($numberOfRunningHost -gt $MinimumNumberOfRDSH) {

          $sessionHostinfo1 = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostpoolname -Name $sessionHost
          if ($sessionHostinfo1.Status -eq "Available") {

            #ensure the running Azure VM is set as drain mode
            try {

              #setting host in drain mode
              Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $false -ErrorAction SilentlyContinue
            }
            catch {
              Write-Log 1 "Failed to set drain mode on session host: $($sessionHost.SessionHost) with error: $($_.exception.message)" "Info"
              exit
            }
            #notify user to log off session
            #Get the user sessions in the hostPool
            try {
              $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName
            }
            catch {
              Write-ouput "Failed to retrieve user sessions in hostPool: $($hostPoolName) with error: $($_.exception.message)"
              exit
            }
            $hostUserSessionCount = ($hostPoolUserSessions | Where-Object -FilterScript { $_.sessionhostname -eq $sessionHost }).Count
            Write-Log 1 "Counting the current sessions on the host $sessionhost...:$hostUserSessionCount" "Info"
            
            $existingSession = 0
            foreach ($session in $hostPoolUserSessions) {
              if ($session.sessionhostname -eq $sessionHost) {
                if ($LimitSecondsToForceLogOffUser -ne 0) {
                  #send notification
                  try {
                    Send-RdsUserSessionMessage -TenantName $tenantName -HostPoolName $hostPoolName -SessionHostName $session.sessionhostname -SessionId $session.sessionid -MessageTitle $LogOffMessageTitle -MessageBody "$($LogOffMessageBody) You will logged off in $($LimitSecondsToForceLogOffUser) seconds." -NoUserPrompt:$false
                  }
                  catch {
                    Write-Log 1 "Failed to send message to user with error: $($_.exception.message)" "Info"
                    exit
                  }
                }

                $existingSession = $existingSession + 1
              }
            }
            #wait for n seconds to log off user
            Start-Sleep -Seconds $LimitSecondsToForceLogOffUser
            if ($LimitSecondsToForceLogOffUser -ne 0) {
              #force users to log off
              Write-Log 1  "Force users to log off..." "Info"
              try {
                $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName

              }
              catch {
                Write-Log 1 "Failed to retrieve list of user sessions in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Info"
                exit
              }
              foreach ($session in $hostPoolUserSessions) {
                if ($session.sessionhostname -eq $sessionHost) {
                  #log off user
                  try {

                    Invoke-RdsUserSessionLogoff -TenantName $tenantName -HostPoolName $hostPoolName -SessionHostName $session.sessionhostname -SessionId $session.sessionid -NoUserPrompt:$false
                    $existingSession = $existingSession - 1

                  }
                  catch {
                    Write-ouput "Failed to log off user with error: $($_.exception.message)"
                    exit
                  }
                }
              }
            }
            $VMName = $sessionHost.Split(".")[0]
            #check the session count before shutting down the VM
            if ($existingSession -eq 0) {
              #shutdown the Azure VM
              try {
                Write-Log 1 "Stopping Azure VM: $VMName and waiting for it to complete ..." "Info"
                Get-AzureRmVM | Where-Object { $_.Name -eq $VMName } | Stop-AzureRmVM -Force
              }
              catch {
                Write-Log 1 "Failed to stop Azure VM: $VMName with error: $_.exception.message" "Info"
                exit
              }
            }
            #decrement the number of running session host
            $numberOfRunningHost = $numberOfRunningHost - 1
          }
        }
      }
      
    }
    Write-Log 1  "HostpoolName:$hostpoolname, NumberofRunnighosts:$numberOfRunningHost" "Info"
    $depthBool = $true
    Write-UsageLog $hostPoolName $numberOfRunningHost $depthBool
}
  Write-Log 3 "End WVD Tenant Scale Optimization." "Info"
}
else {
  Write-Log 3 "$hostPoolName hostpool loadbalancer type is $($hostpoolInfo.LoadBalancerType)" "Info"
  #check if it is during the peak or off-peak time
  if ($CurrentDateTime -ge $BeginPeakDateTime -and $CurrentDateTime -le $EndPeakDateTime) {
    Write-Host "It is in peak hours now"
    Write-Log 3 "Peak hours: starting session hosts as needed based on current workloads." "Info"
    #Get the Session Hosts in the hostPool		
    try {
      $RDSessionHost = Get-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -ErrorAction SilentlyContinue
    }
    catch {
      Write-Log 1 "Failed to retrieve RDS session hosts in hostPool $($hostPoolName) : $($_.exception.message)" "Error"
      exit 1
    }

    #Get the User Sessions in the hostPool
    try {
      $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName
    }
    catch {
      Write-Log 1 "Failed to retrieve user sessions in hostPool:$($hostPoolName) with error: $($_.exception.message)" "Error"
      exit 1
    }

    #check the number of running session hosts
    $numberOfRunningHost = 0

    #total of running cores
    $totalRunningCores = 0

    #total capacity of sessions of running VMs
    $AvailableSessionCapacity = 0

    foreach ($sessionHost in $RDSessionHost.sessionhostname) {
      Write-Log 1 "Checking session host: $($sessionHost)" "Info"
           
      $VMName = $sessionHost.Split(".")[0]
      $roleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }
      if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {
        #check the azure vm is running or not      
        if ($roleInstance.PowerState -eq "VM running") {
          $numberOfRunningHost = $numberOfRunningHost + 1
          #we need to calculate available capacity of sessions						
          $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object { $_.Name -eq $roleInstance.HardwareProfile.VmSize }
          $AvailableSessionCapacity = $AvailableSessionCapacity + $roleSize.NumberOfCores * $SessionThresholdPerCPU
          $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
        }

      }

    }
    Write-Log 1 "Current number of running hosts:$numberOfRunningHost" "Info"

    if ($numberOfRunningHost -lt $MinimumNumberOfRDSH) {

      Write-Log 1 "Current number of running session hosts is less than minimum requirements, start session host ..." "Info"

      #start VM to meet the minimum requirement            
      foreach ($sessionHost in $RDSessionHost.sessionhostname) {

        #check whether the number of running VMs meets the minimum or not
        if ($numberOfRunningHost -lt $MinimumNumberOfRDSH) {

          $VMName = $sessionHost.Split(".")[0]
          $roleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

          if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {

            #check if the azure VM is running or not
            if ($roleInstance.PowerState -ne "VM running") {
              $getShsinfo = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostPoolName

              if ($getShsinfo.AllowNewSession -eq $false) {
                Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $true

              }
              #start the azure VM
              try {
                Start-AzureRmVM -Name $roleInstance.Name -Id $roleInstance.Id -ErrorAction SilentlyContinue
              }
              catch {
                Write-Log 1 "Failed to start Azure VM: $($roleInstance.Name) with error: $($_.exception.message)" "Error"
                exit 1
              }
              #wait for the VM to start
              $IsVMStarted = $false
              while (!$IsVMStarted) {

                $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }

                if ($vm.PowerState -eq "VM running" -and $vm.ProvisioningState -eq "Succeeded") {
                  $IsVMStarted = $true
                  Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $true
                }
              }
              # we need to calculate available capacity of sessions
              $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
              $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object { $_.Name -eq $roleInstance.HardwareProfile.VmSize }
              $AvailableSessionCapacity = $AvailableSessionCapacity + $roleSize.NumberOfCores * $SessionThresholdPerCPU
              $numberOfRunningHost = $numberOfRunningHost + 1
              $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
              if ($numberOfRunningHost -ge $MinimumNumberOfRDSH) {
                break;
              }
            }
          }
        }
      }
    }

    else {
      #check if the available capacity meets the number of sessions or not
      Write-Log 1 "Current total number of user sessions: $(($hostPoolUserSessions).Count)" "Info"
      Write-Log 1 "Current available session capacity is: $AvailableSessionCapacity" "Info"
      if ($hostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
        Write-Log 1 "Current available session capacity is less than demanded user sessions, starting session host" "Info"
        #running out of capacity, we need to start more VMs if there are any 
        foreach ($sessionHost in $RDSessionHost.sessionhostname) {
          if ($hostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
            $VMName = $sessionHost.Split(".")[0]
            $roleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

            if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {
              #check if the Azure VM is running or not

              if ($roleInstance.PowerState -ne "VM running") {
                $getShsinfo = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostPoolName
                if ($getShsinfo.AllowNewSession -eq $false) {
                  Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $true

                }
                #start the Azure VM
                try {
                  Start-AzureRmVM -Name $roleInstance.Name -Id $roleInstance.Id -ErrorAction SilentlyContinue

                }
                catch {
                  Write-Log 1 "Failed to start Azure VM: $($roleInstance.Name) with error: $($_.exception.message)" "Error"
                  exit 1
                }
                #wait for the VM to start
                $IsVMStarted = $false
                while (!$IsVMStarted) {
                  $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }

                  if ($vm.PowerState -eq "VM running" -and $vm.ProvisioningState -eq "Succeeded") {
                    $IsVMStarted = $true
                    Write-Log 1 "Azure VM has been started: $($roleInstance.Name) ..." "Info"
                  }
                  else {
                    Write-Log 3 "Waiting for Azure VM to start $($roleInstance.Name) ..." "Info"
                  }
                }
                # we need to calculate available capacity of sessions
                $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
                $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object { $_.Name -eq $roleInstance.HardwareProfile.VmSize }
                $AvailableSessionCapacity = $AvailableSessionCapacity + $roleSize.NumberOfCores * $SessionThresholdPerCPU
                $numberOfRunningHost = $numberOfRunningHost + 1
                $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
                Write-Log 1 "new available session capacity is: $AvailableSessionCapacity" "Info"
                if ($AvailableSessionCapacity -gt $hostPoolUserSessions.Count) {
                  break
                }
              }
              #Break # break out of the inner foreach loop once a match is found and checked
            }
          }
        }
      }
    }
    Write-Log 1 "HostpoolName:$hostpoolName, TotalRunningCores:$totalRunningCores NumberOfRunningHost:$numberOfRunningHost" "Info"
    #write to the usage log
    $depthBool = $false
    Write-UsageLog $hostPoolName $totalRunningCores $numberOfRunningHost $depthBool
  }
  #} #Peak or not peak hour
  else
  {
    Write-Host "It is Off-peak hours"
    Write-Log 3 "It is off-peak hours. Starting to scale down RD session hosts..." "Info"
    Write-Host ("Processing hostPool {0}" -f $hostPoolName)
    Write-Log 3 "Processing hostPool $($hostPoolName)"
    #Get the Session Hosts in the hostPool
    try {
      $RDSessionHost = Get-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName
    }
    catch {
      Write-Log 1 "Failed to retrieve session hosts in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Error"
      exit 1
    }
    #check the number of running session hosts
    $numberOfRunningHost = 0

    #total of running cores
    $totalRunningCores = 0

    foreach ($sessionHost in $RDSessionHost.sessionhostname) {

      $VMName = $sessionHost.Split(".")[0]
      $roleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

      if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {
        #check if the Azure VM is running or not

        if ($roleInstance.PowerState -eq "VM running") {
          $numberOfRunningHost = $numberOfRunningHost + 1

          # we need to calculate available capacity of sessions  
          $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object { $_.Name -eq $roleInstance.HardwareProfile.VmSize }

          $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
        }
      }
    }
    if ($numberOfRunningHost -gt $MinimumNumberOfRDSH) {
      #shutdown VM to meet the minimum requirement

      foreach ($sessionHost in $RDSessionHost.sessionhostname) {
        if ($numberOfRunningHost -gt $MinimumNumberOfRDSH) {

          $VMName = $sessionHost.Split(".")[0]
          $roleInstance = Get-AzureRmVM -Status | Where-Object { $_.Name.Contains($VMName) }

          if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {
            #check if the Azure VM is running or not

            if ($roleInstance.PowerState -eq "VM running") {
              #check the role isntance status is ReadyRole or not, before setting the session host
              $isInstanceReady = $false
              $numOfRetries = 0

              while (!$isInstanceReady -and $num -le 3) {
                $numOfRetries = $numOfRetries + 1
                $instance = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
                if ($instance -ne $null -and $instance.ProvisioningState -eq "Succeeded") {
                  $isInstanceReady = $true
                }
            
              }

              if ($isInstanceReady) {
                #ensure the running Azure VM is set as drain mode
                try {
                  Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $false -ErrorAction SilentlyContinue
                }
                catch {

                  Write-Log 1 "Failed to set drain mode on session host: $($sessionHost.SessionHost) with error: $($_.exception.message)" "Error"
                  exit 1

                }

                #notify user to log off session
                #Get the user sessions in the hostPool
                try {

                  $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName

                }
                catch {
                  Write-Log 1 "Failed to retrieve user sessions in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Error"
                  exit 1
                }

                $hostUserSessionCount = ($hostPoolUserSessions | Where-Object -FilterScript { $_.sessionhostname -eq $sessionHost }).Count
                Write-Log 1 "Counting the current sessions on the host $sessionhost...:$hostUserSessionCount" "Info"
                #Write-Log 1 "Counting the current sessions on the host..." "Info"
                $existingSession = 0

                foreach ($session in $hostPoolUserSessions) {

                  if ($session.sessionhostname -eq $sessionHost) {

                    if ($LimitSecondsToForceLogOffUser -ne 0) {
                      #send notification
                      try {

                        Send-RdsUserSessionMessage -TenantName $tenantName -HostPoolName $hostPoolName -SessionHostName $sessionHost -SessionId $session.sessionid -MessageTitle $LogOffMessageTitle -MessageBody "$($LogOffMessageBody) You will logged off in $($LimitSecondsToForceLogOffUser) seconds." #-NoConfirm:$false

                      }
                      catch {

                        Write-Log 1 "Failed to send message to user with error: $($_.exception.message)" "Error"
                        exit 1

                      }
                    }

                    $existingSession = $existingSession + 1
                  }
                }
                #wait for n seconds to log off user
                Start-Sleep -Seconds $LimitSecondsToForceLogOffUser

                if ($LimitSecondsToForceLogOffUser -ne 0) {
                  #force users to log off
                  Write-Log 1 "Force users to log off..." "Info"
                  try {
                    $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName
                  }
                  catch {
                    Write-Log 1 "Failed to retrieve list of user sessions in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Error"
                    exit 1
                  }
                  foreach ($session in $hostPoolUserSessions) {
                    if ($session.sessionhostname -eq $sessionHost) {
                      #log off user
                      try {

                        Invoke-RdsUserSessionLogoff -TenantName $tenantName -HostPoolName $hostPoolName -SessionHostName $session.sessionhostname -SessionId $session.sessionid -NoConfirm #:$false

                        $existingSession = $existingSession - 1
                      }
                      catch {
                        Write-Log 1 "Failed to log off user with error: $($_.exception.message)" "Error"
                        exit 1
                      }
                    }
                  }
                }
                #check the session count before shutting down the VM
                if ($existingSession -eq 0) {

                  #shutdown the Azure VM
                  try {
                    Write-Log 1 "Stopping Azure VM: $($roleInstance.Name) and waiting for it to complete ..." "Info"
                    Stop-AzureRmVM -Name $roleInstance.Name -Id $roleInstance.Id -Force -ErrorAction SilentlyContinue

                  }
                  catch {
                    Write-Log 1 "Failed to stop Azure VM: $($roleInstance.Name) with error: $($_.exception.message)" "Error"
                    exit 1
                  }
                  #wait for the VM to stop
                  $IsVMStopped = $false
                  while (!$IsVMStopped) {

                    $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }

                    if ($vm.PowerState -eq "VM deallocated") {
                      $IsVMStopped = $true
                      Write-Log 1 "Azure VM has been stopped: $($roleInstance.Name) ..." "Info"
                    } else {
                      Write-Log 3 "Waiting for Azure VM to stop $($roleInstance.Name) ..." "Info"
                    }
                  }
                  #ensure the Azure VMs that are off have the AllowNewSession mode set to True
                  try {
                    Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $true -ErrorAction SilentlyContinue
                  }
                  catch {
                    Write-Log 1 "Failed to set drain mode on session host: $($sessionHost.SessionHost) with error: $($_.exception.message)" "Error"
                    exit 1
                  }
                  $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
                  $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object { $_.Name -eq $roleInstance.HardwareProfile.VmSize }
                  #decrement the number of running session host
                  $numberOfRunningHost = $numberOfRunningHost - 1
                  $totalRunningCores = $totalRunningCores - $roleSize.NumberOfCores
                }
              }
            }
          }
        }
      }

    }
    Write-Log 1 "HostpoolName:$hostpoolName, TotalRunningCores:$totalRunningCores NumberOfRunningHost:$numberOfRunningHost" "Info"
    #write to the usage log
    $depthBool = $false
    Write-UsageLog $hostPoolName $totalRunningCores $numberOfRunningHost $depthBool
  } #Scale hostPools
  Write-Log 3 "End WVD Tenant Scale Optimization." "Info"
}

get-content "$CurrentPath\WVDTenantScale.log"

#usage log path
get-content "$CurrentPath\WVDTenantUsage.log"