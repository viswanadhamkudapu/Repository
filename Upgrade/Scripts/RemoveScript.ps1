<#

    .SYNOPSIS
    Removing hosts from Existing Hostpool and add first instance to hostpool.

    .DESCRIPTION
    This script remove old sessionhost servers from existing Hostpool and add first instance to existing hostpool.
    The supported Operating Systems Windows Server 2016/windows 10 multisession.

    .ROLE
    Readers

#>
param(
    [Parameter(mandatory = $true)]
    [string]$RDBrokerURL,
	
	[Parameter(mandatory = $true)]
    [string]$TenantGroupName,

    [Parameter(mandatory = $true)]
    [string]$TenantName,

    [Parameter(mandatory = $true)]
    [string]$HostPoolName,

    [Parameter(mandatory = $true)]
    [string]$TenantAdminUPN,

    [Parameter(mandatory = $true)]
    [string]$TenantAdminPassword,

    [Parameter(mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(mandatory = $false)]
    [string]$FileURI,
    
    [Parameter(mandatory = $false)]
    [double]$Hours,

    [Parameter(mandatory = $false)]
    [int]$userLogoffDelayInMinutes,

    [Parameter(mandatory = $false)]
    [string]$userNotificationMessege,

    [Parameter(mandatory = $false)]
    [string]$messageTitle,

    [Parameter(mandatory = $true)]
    [string]$deleteordeallocateVMs,

    [Parameter(mandatory = $true)]
    [string]$DomainName,

    [Parameter(mandatory = $true)]
    [string]$localAdminUsername,
    
    [Parameter(mandatory = $true)]
    [string]$localAdminPassword
)

	Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
	Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
	$PolicyList=Get-ExecutionPolicy -List
	$log = $PolicyList | Out-String
	
    Function Write-Log { 
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
		
    
	
	Invoke-WebRequest -Uri $fileURI -OutFile "C:\DeployAgent.zip"
    Write-Log -Message "Downloaded DeployAgent.zip into this location C:\"

    #Creating a folder inside rdsh vm for extracting deployagent zip file
    New-Item -Path "C:\DeployAgent" -ItemType directory -Force -ErrorAction SilentlyContinue
    Write-Log -Message "Created a new folder 'DeployAgent' inside VM"
    Expand-Archive "C:\DeployAgent.zip" -DestinationPath "C:\DeployAgent" -ErrorAction SilentlyContinue
    Write-Log -Message "Extracted the 'Deployagent.zip' file into 'C:\Deployagent' folder inside VM"
    Set-Location "C:\DeployAgent"
    Write-Log -Message "Setting up the location of Deployagent folder"


                do{
                        Write-Output "checking nuget package exists or not"
                        if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) 
                        {
                        Write-Output "installing nuget package inside vm: $env:COMPUTERNAME"
                            Install-PackageProvider -Name nuget -Force
                        }
                        
                        $LoadModule=Get-Module -ListAvailable "Azure*"
                        
                        if(!$LoadModule){
                        Write-Output "installing azureModule inside vm: $env:COMPUTERNAME"
                        Install-Module AzureRm -AllowClobber -Force
                        }
                        } until($LoadModule)


               
        Import-Module ".\PowershellModules\Microsoft.RDInfra.RDPowershell.dll"
        
        #AzureLogin Credentials
        $Securepass=ConvertTo-SecureString -String $TenantAdminPassword -AsPlainText -Force
        $Credentials=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList($TenantAdminUPN, $Securepass)

        #Domain Credentials
        $AdminSecurepass = ConvertTo-SecureString -String $localAdminPassword -AsPlainText -Force
        $AdminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($localAdminUsername, $AdminSecurepass)

                 # Authenticating to WVD
			  if ($isServicePrincipal -eq "True")
			  {
				$authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Credentials -ServicePrincipal -TenantId $AadTenantId
			  }
			  else
			  {
				$authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Credentials
			  }
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

             $allshs=Get-RdsSessionHost -TenantName $tenantname -HostPoolName $HostPoolName
             $allshslog=$allshs.SessionHostName | Out-String
             Write-Log -Message "All Session Host servers in $HostPoolName :`n$allshslog"
             
             $shsNames=0
             $shsNames=@()
             
             $rdsUserSessions=Get-RdsUserSession -TenantName $TenantName -HostPoolName $HostPoolName
             if($rdsUserSessions){
             foreach($rdsUserSession in $rdsUserSessions){
             
             $sessionId=$rdsUserSession.SessionId
             
             $shName=$rdsUserSession.SessionHostName
             
             $username=$rdsUserSession.UserPrincipalName | Out-String
             
             $shsNames+=$shName
             
             Send-RdsUserSessionMessage -TenantName $TenantName -HostPoolName $HostPoolName -SessionHostName $shName -SessionId $sessionId -MessageTitle $messageTitle -MessageBody $userNotificationMessage -NoConfirm:$false
             
             Write-log -message "Sent a rdsusersesionmessage to $username and sessionid was $sessionId"
             
             }
             }
              else
             {
             $shName=$allshs.SessionHostName
             Write-Log -Message "Sessions not present in $shName session host vm"
             $shsNames+=$shName
                }
    
            $allShsNames=$shsNames | select -Unique
            Write-Log -Message "Collected old sessionhosts of Hostpool $HostPoolName : `
            $allShsNames"
                        	
                        Add-WindowsFeature RSAT-AD-PowerShell
                        #Get Domaincontroller VMname
                        $DName=Get-ADDomainController -Discover -DomainName $DomainName
                        $DControllerVM=$DName.Name
                        $ZoneName=$DName.Forest
                
                
            Import-Module AzureRM.Resources
            Import-Module Azurerm
			Import-Module Azurerm.Profile
			Import-Module Azurerm.Compute
            $AzSecurepass=ConvertTo-SecureString -String $TenantAdminPassword -AsPlainText -Force
            $AzCredentials=New-Object System.Management.Automation.PSCredential($TenantAdminUPN, $AzSecurepass)
            #$loginResult=Login-AzureRmAccount -SubscriptionId $SubscriptionId  -Credential $AzCredentials
			
			#Authenticate AzureRM
			if ($isServicePrincipal -eq "True")
			  {
				$authentication = Add-AzureRmAccount -Credential $AzCredentials -ServicePrincipal -TenantId $AadTenantId
			  }
			  else
			  {
				$authentication = Add-AzureRmAccount -Credential $Credentials -SubscriptionId $SubscriptionId
			  }
					  $obj = $authentication | Out-String

					  if ($authentication)
					  {
						Write-Log -Message "AzureRM Login successfully Done. Result:`n$obj"
					  }
					  else
					  {
						Write-Log -Error "AzureRM Login Failed, Error:`n$obj"
					  }
			if ($authentication.Context.Subscription.Id -eq $SubscriptionId)
            {
                 $success=$true
                 Write-Log -Message "Successfully logged into AzureRM"
            }
            else 
            {
                 Write-Log -Error "Subscription Id $SubscriptionId not in context"
            }
            
            $convertSeconds=$userLogoffDelayInMinutes * 60
            Start-Sleep -Seconds $convertSeconds
            
            
            foreach($sh in $allShsNames){
               
                # setting rdsh vm in drain mode
                $shsDrain=Set-RdsSessionHost -TenantName $tenantname -HostPoolName $HostPoolName -Name $sh -AllowNewSession $false
                $shsDrainlog=$shsDrain | Out-String
                Write-Log -Message "Sesssion host server in drain mode : `
                $shsDrainlog"
                
                Remove-RdsSessionHost -TenantName $tenantname -HostPoolName $HostPoolName -Name $sh -Force
                Write-Log -Message "Successfully $sh removed from hostpool"
                
                $VMName=$sh.Split(".")[0]
                
                if($deleteordeallocateVMs -eq "Delete"){
                
                # Remove the VM's and then remove the datadisks, osdisk, NICs
                Get-AzureRmVM | Where-Object {$_.name -eq $VMName}  | foreach {
                    $a=$_
                    $DataDisks = @($_.StorageProfile.DataDisks.Name)
                    $OSDisk = @($_.StorageProfile.OSDisk.Name)
                    Write-Log -Message "Removing $VMName VM and associated resources from Azure"
                   
                        #Write-Warning -Message "Removing VM: $($_.Name)"
                        $_ | Remove-AzureRmVM -Force -Confirm:$false
                        Write-Log -Message "Successfully removed VM from Azure"

                        $_.NetworkProfile.NetworkInterfaces | ForEach-Object {
                            $NICName = Split-Path -Path $_.ID -leaf
                            Get-AzureRmNetworkInterface | Where-Object {$_.Name -eq $NICName} | Remove-AzureRmNetworkInterface -Force
                        }
                        Write-Log -Message "Successfully removed $VMName vm NIC"

                        # Support to remove managed disks
                        if($a.StorageProfile.OsDisk.ManagedDisk ) {
                            
                            
                            if($OSDisk){
                            foreach($ODisk in $OSDisk){
                            Get-AzureRmDisk -ResourceGroupName $_.ResourceGroupName -DiskName $ODisk | Remove-AzureRmDisk -Force
                            }
                            }
                                                        
                            if($DataDisks){
                            foreach($DDisk in $DataDisks){
                            Get-AzureRmDisk -ResourceGroupName $_.ResourceGroupName -DiskName $DDisk | Remove-AzureRmDisk -Force
                            }
                            }
                        }
                        # Support to remove unmanaged disks (from Storage Account Blob)
                        else {
                            # This assumes that OSDISK and DATADisks are on the same blob storage account
                            # Modify the function if that is not the case.
                            $saname = ($a.StorageProfile.OsDisk.Vhd.Uri -split '\.' | Select -First 1) -split '//' |  Select -Last 1
                            $sa = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $saname}
        
                            # Remove DATA disks
                            $a.StorageProfile.DataDisks | foreach {
                                $disk = $_.Vhd.Uri | Split-Path -Leaf
                                Get-AzureStorageContainer -Name vhds -Context $Sa.Context |
                                Get-AzureStorageBlob -Blob  $disk |
                                Remove-AzureStorageBlob
                                Write-Log -Message "Removed DataDisk $disk successfully"  
                            }
                            
        
                            # Remove OSDisk disk
                            $disk = $a.StorageProfile.OsDisk.Vhd.Uri | Split-Path -Leaf
                            Get-AzureStorageContainer -Name vhds -Context $Sa.Context |
                            Get-AzureStorageBlob -Blob  $disk |
                            Remove-AzureStorageBlob

                            Write-Log -Message "Removed OSDisk $disk successfully"
                
                            # Remove Boot Diagnostic
                            $diagVMName=0
                            $diag=$_.Name.ToLower()
                            $diagVMName=$diag -replace '[\-]', ''
                            $dCount=$diagVMName.Length
                                        if($dCount -cgt 9){
                                            $digsplt=$diagVMName.substring(0,9)
                                            $diagVMName=$digsplt
                                            }
                            $diagContainerName = ('bootdiagnostics-{0}-{1}' -f $diagVMName, $_.VmId)
                            Set-AzureRmCurrentStorageAccount -Context $sa.Context
                            Remove-AzureStorageContainer -Name $diagContainerName -Force
                            Write-Log -Message "Successfully removed boot diagnostic"

                        }

                        #$avSet=Get-AzureRmVM | Where-Object {$_.Name -eq $VMName} | Remove-AzureRmAvailabilitySet -Force
                        $avset=Get-AzureRmAvailabilitySet -ResourceGroupName $a.ResourceGroupName
                        if($avset.VirtualMachinesReferences.id -eq $null){
                        $removeavset=Get-AzureRmAvailabilitySet -ResourceGroupName $a.ResourceGroupName -ErrorAction SilentlyContinue | Remove-AzureRmAvailabilitySet -Force
                        Write-Log -Message "Successfully removed availabilityset"
                        }
                        $checkResources=Get-AzureRmResource -ResourceGroupName $a.ResourceGroupName
                        if(!$checkResources){
                        $removeRg=Remove-AzureRmResourceGroup -Name $a.ResourceGroupName -Force
                        Write-Log -Message "Successfully removed ResourceGroup"
                        }
                        
                }
                
                #Removing VM from domain controller and DNS Record
                $result=Invoke-Command -ComputerName $DControllerVM -Credential $AdminCredentials -ScriptBlock{
                Param($ZoneName,$VMName)
                Get-ADComputer -Identity $VMName | Remove-ADObject -Recursive -confirm:$false
                Remove-DnsServerResourceRecord -ZoneName $ZoneName -RRType "A" -Name $VMName -Force -Confirm:$false
                } -ArgumentList($ZoneName,$VMName) -ErrorAction SilentlyContinue
                if($result){
                Write-Log -Message "Successfully removed $VMName from domaincontroller"
                Write-Log -Message "successfully removed dns record of $VMName"
                }
                }
                else{
                $vmProvisioning=Get-AzureRmVM | Where-Object {$_.Name -eq $VMName} | Stop-AzureRmVM -Force
                            
                            if($vmProvisioning.Status -eq "Succeeded"){
                            write-log -Message "VM has been stopped: $VMName"
                            }
                            else
                            {
                            write-log -Error "$VMName VM cannot be stopped"
                            }
                }
                }
				