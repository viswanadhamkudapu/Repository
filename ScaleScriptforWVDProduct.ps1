param(
[Parameter(Mandatory = $True)]
$RDBroker,

[Parameter(Mandatory = $True)]
$AADTenantId,

[Parameter(Mandatory = $True)]
$AADApplicationId,

[Parameter(Mandatory = $True)]
$AADServicePrincipalSecret,

#[Parameter(Mandatory = $True)]
#$SubscriptionID,

[Parameter(Mandatory = $True)]
$HostpoolName
)

$fileURI = "https://raw.githubusercontent.com/viswanadhamkudapu/Repository/master/RDMIMonitoring.zip"

    Invoke-WebRequest -Uri $fileURI -OutFile "C:\RDMIMonitoring-$HostpoolName.zip"
    New-Item -Path "C:\RDMIMonitoring-$HostpoolName" -ItemType Directory -Force -ErrorAction SilentlyContinue
    Expand-Archive "C:\RDMIMonitoring-$HostpoolName.zip" -DestinationPath "C:\RDMIMonitoring-$HostpoolName" -ErrorAction SilentlyContinue
    Copy-Item -Path "C:\RDMIMonitoring-$HostpoolName\AzureModules\*"  -Destination 'C:\Modules\Global' -Force -Recurse

    Import-Module AzureRM.Profile
    Import-Module AzureRM.Compute
    Import-Module AzureRM.Sql
    Import-module AzureAD
    Import-module AzureRM.Resources
    #XMl Configuration File Path 
    $XMLPath = "C:\RDMIMonitoring-$hostpoolName\SQLSettings.xml"

    ##### Load XML Configuration values as variables #########
    Write-output "loading values from SQLSettings.xml"
    $Variable=[XML] (Get-Content "$XMLPath")

	    $Variable = [XML] (Get-Content "$XMLPath")
		$SQLUsername = $Variable.Credentials.UserID
		$SQLPassword = $Variable.Credentials.password
		$SQLServer = $Variable.Credentials.Server
		$Databasename = $Variable.Credentials.Database

        Write-output -Message "Connecting to the Hello RDS database"
		$secpasswd = ConvertTo-SecureString $SQLPassword -AsPlainText -Force
		$db_credential = New-Object System.Management.Automation.PSCredential ($SQLUsername, $secpasswd)
		$DatabaseServer=$SQLServer
        $HelloRDSDB=$Databasename
        $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection -ArgumentList "Initial Catalog=${HelloRDSDB};Password=$($db_credential.GetNetworkCredential().Password);Server=${DatabaseServer};User Id=$($db_credential.UserName);"
        $connection.Open()

        $query = “SELECT * FROM tbl_autoscaledetails where HostpoolName='$($HostpoolName)'”
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        #$result = $command.ExecuteReader()
        
        $DataAdapter = new-object System.Data.SqlClient.SqlDataAdapter $Command
        $Dataset = new-object System.Data.Dataset
        $DataAdapter.Fill($Dataset)
        #$dataset = Get-Dataset -Connection $Connection -SQL $query
        #$Dataset
        [String]$TenantName = $Dataset.Tables.TENANTNAME
        [String]$BeginPeakTime = $Dataset.Tables.STARTTIME
        [String]$EndPeakTime = $Dataset.Tables.ENDTIME
        $TimeDifference = $Dataset.Tables.TIMEDIFFERENCE
        $SessionThresholdPerCPU = $Dataset.Tables.SESSIONTHRESHOLDPERCPU
        $MinimumNumberOfRDSH = $Dataset.Tables.MINNOOFRDSESSION
        $LimitSecondsToForceLogOffUser = $Dataset.Tables.LIMITFORCELOGOFFUSERSINMIN
        [String]$LogOffMessageTitle = $Dataset.Tables.LOGOFFMESSAGETITLE
        [String]$LogOffMessageBody = $Dataset.Tables.LOGOFFMESSAGEBODY


#$CurrentPath = Split-Path $script:MyInvocation.MyCommand.Path
$CurrentPath = "C:\RDMIMonitoring-$HostpoolName"

#Log path
$rdmiTenantlog = "$CurrentPath\RdmiTenantScale"

#usage log path
$RdmiTenantUsagelog = "$CurrentPath\RdmiTenantUsage.log"

#Load Azure ps module and RDMI Module
#Import-Module -Name AzureRM
cd "$CurrentPath\PowershellModules"
Import-Module .\Microsoft.RdInfra.RdPowershell.dll

#The the following three lines is to use password/secret based authentication for service principal, to use certificate based authentication, please comment those lines, and uncomment the above line
$secpasswd = ConvertTo-SecureString $AADServicePrincipalSecret -AsPlainText -Force
$appcreds = New-Object System.Management.Automation.PSCredential ($AADApplicationId, $secpasswd)

#Login-AzureRmAccount -ServicePrincipal -Credential $appcreds -TenantId $AADTenantId #-Subscription $CurrentAzureSubscriptionName
 Connect-AzureRmAccount -ServicePrincipal -Credential $appcreds -TenantId $AADTenantId

#select the current Azure Subscription specified in the config
#Select-AzureRmSubscription -SubscriptionId $SubscriptionID

#Construct Begin time and End time for the Peak period
#$CurrentDateTime = Get-Date
$CurrentDateTime = Get-Date
$CurrentDateTime=$CurrentDateTime.ToUniversalTime()
write-output "Starting RDMI Tenant Hosts Scale Optimization: Current Date Time is: $CurrentDateTime" "Info"

$TimeDifferenceInHours = $TimeDifference.Split(":")[0]
$TimeDifferenceInMinutes = $TimeDifference.Split(":")[1]
#Azure is using UTC time, justify it to the local time
$CurrentDateTime = $CurrentDateTime.AddHours($TimeDifferenceInHours).AddMinutes($TimeDifferenceInMinutes);
	
$BeginPeakDateTime = [DateTime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $BeginPeakTime)
	
$EndPeakDateTime = [DateTime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $EndPeakTime)
	
    
#check the calculated end time is later than begin time in case of time zone
if ($EndPeakDateTime -lt $BeginPeakDateTime) {
    $EndPeakDateTime = $EndPeakDateTime.AddDays(1)
}	

#get the available HostPoolnames in the RDMITenant
try {
    Add-RdsAccount -DeploymentUrl $RDBroker -ServicePrincipal -Credential $appcreds -TenantId $AADTenantId
    #Set-RdsContext -DeploymentUrl $Rdbroker -Credential $credential
    #$hostPoolNames=Get-RdsHostPool -TenantName $tenantName -Name $hostPoolName -ErrorAction Stop
}
catch {
    write-output "Failed to retrieve RDMITenant Hostpools: $($_.exception.message)" "Error"
    Exit 1
}



	
#check if it is during the peak or off-peak time
if ($CurrentDateTime -ge $BeginPeakDateTime -and $CurrentDateTime -le $EndPeakDateTime) {
    Write-output "It is in peak hours now"
    write-output "Peak hours: starting session hosts as needed based on current workloads." "Info"
    write-output "Looping thru available hostpool list ..." "Info"
    #Get the Session Hosts in the hostPool
		
    #foreach($hostPoolName in $hostPoolNames){
    try {
        $RDSessionHost = Get-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -ErrorAction SilentlyContinue
            
            
    }
    catch {
        write-output "Failed to retrieve RDS session hosts in hostPool $($hostPoolName) : $($_.exception.message)" "Error"
        Exit 1
    }
		
    #Get the User Sessions in the hostPool
    try {    
        $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName
              
    }
    catch {
        write-output "Failed to retrieve user sessions in hostPool:$($hostPoolName) with error: $($_.exception.message)" "Error"
        Exit 1
    }
		
    #check the number of running session hosts
    $numberOfRunningHost = 0
		
    #total of running cores
    $totalRunningCores = 0
		
    #total capacity of sessions of running VMs
    $AvailableSessionCapacity = 0
		
    foreach ($sessionHost in $RDSessionHost.SessionHostName) {
        write-output "Checking session host: $($sessionHost)" "Info"
			
        #Get Azure Virtual Machines
        try {
            $TenantLogin = Add-AzureRmAccount -ServicePrincipal -Credential $appcreds -TenantId $AADTenantId
				
        }
        catch {
            write-output "Failed to retrieve deployment information from Azure with error: $($_.exception.message)" "Error"
            Exit 1
        }
			
			
        #foreach ($roleInstance in $Deployment)
        #{
				 
        $VMName = $sessionHost.Split(".")[0]
        $roleInstance = Get-AzureRmVM -Status | Where-Object {$_.Name.Contains($VMName)} | Select-Object -Unique
                 
        if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {   
            #check the azure vm is running or not      
            if ($roleInstance.PowerState -eq "VM running") {
                $numberOfRunningHost = $numberOfRunningHost + 1
						
                #we need to calculate available capacity of sessions
						
						
                $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object {$_.Name -eq $roleInstance.HardwareProfile.VmSize}
                       
						
                $AvailableSessionCapacity = $AvailableSessionCapacity + $roleSize.NumberOfCores * $SessionThresholdPerCPU
						
                $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
            }
            #Break # break out of the inner foreach loop once a match is found and checked
        }
        #}
    }
		
    write-output "Current number of running hosts: " $numberOfRunningHost
    write-output "Current number of running hosts: $numberOfRunningHost" "Info"
		
    if ($numberOfRunningHost -lt $MinimumNumberOfRDSH) {
			
        write-output "Current number of running session hosts is less than minimum requirements, start session host ..." "Info"
			
        #start VM to meet the minimum requirement            
        foreach ($sessionHost in $RDSessionHost.SessionHostName) {
				
				         
            #check whether the number of running VMs meets the minimum or not
            if ($numberOfRunningHost -lt $MinimumNumberOfRDSH) {
					
                #foreach ($roleInstance in $Deployment)
                #{
                $VMName = $sessionHost.Split(".")[0]
                $roleInstance = Get-AzureRmVM -Status | Where-Object {$_.Name.Contains($VMName)} | Select-Object -Unique
                        
                if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {
							
                    #check if the azure VM is running or not
							
                    if ($roleInstance.PowerState -ne "VM running") {
                        $getShsinfo = Get-RdsSessionHost -TenantName $tenantname -HostPoolName $hostPoolName -Name $sessionHost
                                
                        if ($getShsinfo.AllowNewSession -eq $false) {
                            Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $true

                        }


                        #start the azure VM
                        try {
                            Start-AzureRmVM -Name $roleInstance.Name -Id $roleInstance.Id -ErrorAction SilentlyContinue
									
                        }
                        catch {
                            write-output "Failed to start Azure VM: $($roleInstance.Name) with error: $($_.exception.message)" "Error"
                            Exit 1
                        }
								
                        #wait for the VM to start
                        $IsVMStarted = $false
                        while (!$IsVMStarted) {
									
                            $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
									
                            if ($vm.PowerState -eq "VM running" -and $vm.ProvisioningState -eq "Succeeded") {
                                $IsVMStarted = $true
                            }
                            #wait for 15 seconds
                            Start-Sleep -Seconds 15
                        }
								
                        # we need to calculate available capacity of sessions
								
                        $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
								
                        $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object {$_.Name -eq $roleInstance.HardwareProfile.VmSize}
                               
								
                        $AvailableSessionCapacity = $AvailableSessionCapacity + $roleSize.NumberOfCores * $SessionThresholdPerCPU
                        $numberOfRunningHost = $numberOfRunningHost + 1
								
                        $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
                        if ($numberOfRunningHost -ge $MinimumNumberOfRDSH) {
                            break
                        }
                    }
                    #Break # break out of the inner foreach loop once a match is found and checked
                }
            }
        }
    }
		
    else {
        #check if the available capacity meets the number of sessions or not
        write-output "Current total number of user sessions: $(($hostPoolUserSessions).count)" "Info"
        write-output "Current available session capacity is: $AvailableSessionCapacity" "Info"
        if ($hostPoolUserSessions.Count -ge $AvailableSessionCapacity) {
            write-output "Current available session capacity is less than demanded user sessions, starting session host" "Info"
            #running out of capacity, we need to start more VMs if there are any 
				
            foreach ($sessionHost in $RDSessionHost.SessionHostName) {
					
                if ($hostPoolUserSessions.count -ge $AvailableSessionCapacity) {
						
                    #foreach ($roleInstance in $Deployment)
                    #{ 
                    $VMName = $sessionHost.Split(".")[0]
                    $roleInstance = Get-AzureRmVM -Status | Where-Object {$_.Name.Contains($VMName)} | Select-Object -Unique
							
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
                                write-output "Failed to start Azure VM: $($roleInstance.Name) with error: $($_.exception.message)" "Error"
                                Exit 1
                            }
									
                            #wait for the VM to start
                            $IsVMStarted = $false
                            while (!$IsVMStarted) {
                                $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
										
										
                                if ($vm.PowerState -eq "VM running" -and $vm.ProvisioningState -eq "Succeeded") {
                                    $IsVMStarted = $true
                                }
                                #wait for 15 seconds
                                Start-Sleep -Seconds 15
                            }
									
									
									
                            # we need to calculate available capacity of sessions
									
                            $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
																		
                            $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object {$_.Name -eq $roleInstance.HardwareProfile.VmSize}
																		
                            $AvailableSessionCapacity = $AvailableSessionCapacity + $roleSize.NumberOfCores * $SessionThresholdPerCPU
                            $numberOfRunningHost = $numberOfRunningHost + 1
									
                            $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
                            write-output "new available session capacity is: $AvailableSessionCapacity" "Info"
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
		
    #write to the usage log
    write-output $hostPoolName $totalRunningCores $numberOfRunningHost 

}
#} #Peak or not peak hour
else {
    write-output "It is Off-peak hours"
    write-output "It is off-peak hours. Starting to scale down RD session hosts..." "Info"
    Write-output ("Processing hostPool {0}" -f $hostPoolName)
    #foreach($hostPoolName in $hostPoolNames)
    #{
    write-output "Processing hostPool $($hostPoolName)"
    #Get the Session Hosts in the hostPool
    try {
            
        $RDSessionHost = Get-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName

            
                       
    }
    catch {
        write-output "Failed to retrieve session hosts in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Error"
        Exit 1
    }
		
		
    #check the number of running session hosts
    $numberOfRunningHost = 0
		
    #total of running cores
    $totalRunningCores = 0
		
    foreach ($sessionHost in $RDSessionHost.SessionHostName) {
			
        #refresh the Azure VM list
        try {
            $TenantLogin = Add-AzureRmAccount -ServicePrincipal -Credential $appcreds -TenantId $AADTenantId
				
				
        }
        catch {
            write-output "Failed to retrieve Azure deployment information for cloud service: $ResourceGroupName with error: $($_.exception.message)" "Error"
            Exit 1
        }
			
        #foreach ($roleInstance in $Deployment)
        #{
        $VMName = $sessionHost.Split(".")[0]
        $roleInstance = Get-AzureRmVM -Status | Where-Object {$_.Name.Contains($VMName)} | Select-Object -Unique
				
        if ($sessionHost.ToLower().Contains($roleInstance.Name.ToLower())) {
            
            #check if the Azure VM is running or not
			if ($roleInstance.PowerState -eq "VM running") {
                $numberOfRunningHost = $numberOfRunningHost + 1
						
                # we need to calculate available capacity of sessions  
                $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object {$_.Name -eq $roleInstance.HardwareProfile.VmSize}
                        
                $totalRunningCores = $totalRunningCores + $roleSize.NumberOfCores
            }
            #Break # break out of the inner foreach loop once a match is found and checked
        }
        #}
    }
		
    if ($numberOfRunningHost -gt $MinimumNumberOfRDSH) {
        #shutdown VM to meet the minimum requirement
			
        foreach ($sessionHost in $RDSessionHost.SessionHostName) {
            if ($numberOfRunningHost -gt $MinimumNumberOfRDSH) {
					
                #foreach ($roleInstance in $Deployment)
                #{
                $VMName = $sessionHost.Split(".")[0]
                $roleInstance = Get-AzureRmVM -Status | Where-Object {$_.Name.Contains($VMName)} | Select-Object -Unique
						
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
                            #wait for 15 seconds
                            Start-Sleep -Seconds 15
                        }
								
                        if ($isInstanceReady) {
                            #ensure the running Azure VM is set as drain mode
                            try {
                                                                               
                                #setting hosts
                                        
                                Set-RdsSessionHost -TenantName $tenantName -HostPoolName $hostPoolName -Name $sessionHost -AllowNewSession $false -ErrorAction SilentlyContinue

										
                            } 
                            catch {
                                write-output "Failed to set drain mode on session host: $($sessionHost.SessionHost) with error: $($_.exception.message)" "Error"
                                Exit 1
                            }
								
                            #notify user to log off session
                            #Get the user sessions in the hostPool
                            try {
                                        
                                $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName
                                       
                            }
                            catch {
                                write-output "Failed to retrieve user sessions in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Error"
                                Exit 1
                            }
									
                            write-output "Counting the current sessions on the host..." "Info"
                            $existingSession = 0
                            foreach ($session in $hostPoolUserSessions) {
                                if ($session.SessionHostName -eq $sessionHost) {
                                    if ($LimitSecondsToForceLogOffUser -ne 0) {
                                        #send notification
                                        try {
                                            
                                            Send-RdsUserSessionMessage -TenantName $tenantName -HostPoolName $hostPoolName -SessionHostName $session.SessionHostName -SessionId $session.sessionid -MessageTitle $LogOffMessageTitle -MessageBody "$($LogOffMessageBody) You will logged off in $($LimitSecondsToForceLogOffUser) seconds." -NoConfirm:$false
                                            
                                        }
                                        catch {
                                            write-output "Failed to send message to user with error: $($_.exception.message)" "Error"
                                            Exit 1
                                        }
                                    }
											
                                    $existingSession = $existingSession + 1
                                }
                            }
									
									
                            #wait for n seconds to log off user
                            Start-Sleep -Seconds $LimitSecondsToForceLogOffUser
									
                            if ($LimitSecondsToForceLogOffUser -ne 0) {
                                #force users to log off
                                write-output "Force users to log off..." "Info"
                                try {
                                    $hostPoolUserSessions = Get-RdsUserSession -TenantName $tenantName -HostPoolName $hostPoolName
                                            
                                }
                                catch {
                                    write-output "Failed to retrieve list of user sessions in hostPool: $($hostPoolName) with error: $($_.exception.message)" "Error"
                                    exit 1
                                }
                                foreach ($session in $hostPoolUserSessions) {
                                    if ($session.SessionHostName -eq $sessionHost) {
                                        #log off user
                                        try {
    													
                                            Invoke-RdsUserSessionLogoff -TenantName $tenantName -HostPoolName $hostPoolName -SessionHostName $session.SessionHostName -SessionId $session.SessionId -NoConfirm:$false
                                                   
                                            $existingSession = $existingSession - 1
                                            #break
                                        }
                                        catch {
                                            write-output "Failed to log off user with error: $($_.exception.message)" "Error"
                                            exit 1
                                        }
                                    }
                                }
                            }
									
									
									
                            #check the session count before shutting down the VM
                            if ($existingSession -eq 0) {
										
                                #shutdown the Azure VM
                                try {
                                    Stop-AzureRmVM -Name $roleInstance.Name -Id $roleInstance.Id -Force -ErrorAction SilentlyContinue
											
                                }
                                catch {
                                    write-output "Failed to stop Azure VM: $($roleInstance.Name) with error: $($_.exception.message)" "Error"
                                    exit 1
                                }
										
                                #wait for the VM to stop
                                $IsVMStopped = $false
                                while (!$IsVMStopped) {
											
                                    $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
											
                                    if ($vm.PowerState -eq "VM deallocated") {
                                        $IsVMStopped = $true
                                    }
                                    write-output "Waiting for Azure VM to stop $($roleInstance.Name) ..." "Info"
                                    #wait for 15 seconds
                                    Start-Sleep -Seconds 15
                                }
										
                                $vm = Get-AzureRmVM -Status | Where-Object { $_.Name -eq $roleInstance.Name }
										
                                $roleSize = Get-AzureRmVMSize -Location $roleInstance.Location | Where-Object {$_.Name -eq $roleInstance.HardwareProfile.VmSize}
										
										
                                #decrement the number of running session host
                                $numberOfRunningHost = $numberOfRunningHost - 1
										
                                $totalRunningCores = $totalRunningCores - $roleSize.NumberOfCores
                            }
                        }
                    }
                    #Break # break out of the inner foreach loop once a match is found and checked
                }
                #}
            }
        }
			
        #write to the usage log
        write-output $HostpoolName $totalRunningCores $numberOfRunningHost
    }
    #}
} #Scale hostPools

#endregion
