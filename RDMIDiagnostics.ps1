Param(
[Parameter(Mandatory = $True)]
[string] $tenantID,

[Parameter(Mandatory = $True)]
[string] $RDBrokerURL,

[Parameter(Mandatory = $True)]
[string] $tenantName,

[Parameter(Mandatory = $True)]
[string] $hostpoolName
)

$fileURI = "https://raw.githubusercontent.com/viswanadhamkudapu/Repository/master/RDMIMonitoring.zip"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Idle sessions and active sessions are unable to get through powershell in this codebit, at present inserting Null values
$ActiveSessions = 0
$IdleSessions = 0

Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
    Get-ExecutionPolicy -List
 try
   {
    Invoke-WebRequest -Uri $fileURI -OutFile "C:\RDMIMonitoring.zip"
    New-Item -Path "C:\RDMIMonitoring" -ItemType Directory -Force -ErrorAction SilentlyContinue
    Expand-Archive "C:\RDMIMonitoring.zip" -DestinationPath "C:\RDMIMonitoring" -ErrorAction SilentlyContinue
    Copy-Item -Path "C:\RDMIMonitoring\AzureModules\*"  -Destination 'C:\Modules\Global' -Force -Recurse

    Import-Module AzureRM.Profile
    Import-Module AzureRM.Compute
    Import-Module AzureRM.Sql
    Import-module AzureAD
    Import-module AzureRM.Resources
    #XMl Configuration File Path
    $XMLPath = "C:\RDMIMonitoring\SQLSettings.xml"

    ##### Load XML Configuration values as variables #########
    Write-Verbose "loading values from SQLSettings.xml"
    $Variable=[XML] (Get-Content "$XMLPath")

	    $Variable = [XML] (Get-Content "$XMLPath")
		$SQLUsername = $Variable.Credentials.UserID
		$SQLPassword = $Variable.Credentials.password
		$SQLServer = $Variable.Credentials.Server
		$Databasename = $Variable.Credentials.Database

        Write-Verbose -Message "Connecting to the Hello RDS database"
		$secpasswd = ConvertTo-SecureString $SQLPassword -AsPlainText -Force
		$db_credential = New-Object System.Management.Automation.PSCredential ($SQLUsername, $secpasswd)
		$DatabaseServer=$SQLServer
        $HelloRDSDB=$Databasename
        $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection -ArgumentList "Initial Catalog=${HelloRDSDB};Password=$($db_credential.GetNetworkCredential().Password);Server=${DatabaseServer};User Id=$($db_credential.UserName);"
        $connection.Open()

        $query = “SELECT * FROM tbl_tenantARMDetails where tenantid='$($tenantID)'”
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        #$result = $command.ExecuteReader()
        
        $DataAdapter = new-object System.Data.SqlClient.SqlDataAdapter $Command
        $Dataset = new-object System.Data.Dataset
        $DataAdapter.Fill($Dataset)
        #$dataset = Get-Dataset -Connection $Connection -SQL $query
        #$Dataset
        [string]$ApplicaionId = $Dataset.Tables.ARMAppID
        [string]$appScreat = $Dataset.Tables.ARMClientSecret
 
        Set-Location 'C:\RDMIMonitoring\PowershellModules'
        Import-Module .\Microsoft.RDInfra.RDPowershell.dll
    
        $Securepass=ConvertTo-SecureString -String $appScreat -AsPlainText -Force
        $Credentials=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList($ApplicaionId, $Securepass)
       
 

            #$loginrdmi=Add-RdsAccount -ServicePrincipal -TenantId $tenantID -DeploymentUrl $RDBrokerURL -Credential $Credentials
            Add-RdsAccount -ServicePrincipal -TenantId $tenantID -DeploymentUrl $RDBrokerURL -Credential $Credentials
            
            $azureappsecure = ConvertTo-SecureString $appScreat -AsPlainText -Force
            $cred = New-Object -TypeName pscredential –ArgumentList $ApplicaionId, $azureappsecure
            Connect-AzureRmAccount -ServicePrincipal -Credential $cred -TenantId $tenantID
    
            $sessionHostInfo = Get-RdsSessionHost -TenantName $tenantName -HostPoolName $hostpoolName
            $azureVMInfo = Get-AzureRmVM -Status

            $noOfSessions = 0
            $noOfAllocated = 0
            $noOfDeallocated = 0


            $noOfSessions = @()
            $noOfAllocated = @()
            $noOfDeallocated = @()

            foreach($sessionhost in $sessionHostInfo){
            $noOfSessions += $sessionhost.Sessions
            $hostName = $sessionhost.SessionHostName
            $hostNameSplit = $hostName.split(".")[0]
            foreach($allocatedVm in $azureVMInfo){
            if($allocatedVm.Name -contains $hostNameSplit){

            if($allocatedVm.PowerState -eq "VM deallocated")
                {
                    $noOfDeallocated += ($allocatedVm.name).count

                    }
                else
                {
                        $noOfAllocated += ($allocatedVm.name).count
                        }
            }
            }

            }
            $QueryTimeout = 120
            <#
            $date = "{0:d}" -f (get-date)
            $time = "{0:HH:mm}" -f (get-date)
            $SessionCountDateTime = $date+" "+$time
            #>
            $SessionCountDateTime = [DateTime]::UtcNow | get-date -Format "yyyy-MM-ddTHH:mm:ssZ"
            $noOfSessionsCount = ($noOfSessions | Measure-Object -Sum).sum
            $noOfAllocatedHostCount = ($noOfAllocated | Measure-Object -sum).sum
            $noOfDeallocatedHostCount = ($noOfDeallocated | Measure-Object -sum).Sum
           

            $Query = "INSERT INTO dbo.tbl_sessionhistory(CREATEDDATETIME,AADTENANTID,HOSTPOOLNAME,NOOFSESSIONS,ACTIVESESSIONS,IDLESESSIONS,ALLOCATEDHOSTS,DEALLOCATEDHOSTS) VALUES ('"+$SessionCountDateTime+"'"+",'"+$tenantId+"'"+",'"+$HostpoolName+"'"+",'"+$noOfSessionsCount+"'"+",'"+$ActiveSessions+"'"+",'"+$IdleSessions+"'"+",'"+$noOfAllocatedHostCount+"'"+",'"+$noOfDeallocatedHostCount+"'"+")"
            #$Query = "INSERT INTO dbo.tbl_sessionhistory(CREATEDDATETIME,AADTENANTID,HOSTPOOLNAME,NOOFSESSIONS,ALLOCATEDHOSTS,DEALLOCATEDHOSTS) VALUES ('"+$SessionCountDateTime+"'"+",'"+$tenantID+"'"+",'"+$HostpoolName+"'"+",'"+$noOfSessionsCount+"'"+",'"+$noOfAllocatedCount+"'"+",'"+$noOfDeallocatedCount+"'"+")"
            $cmd=New-Object system.Data.SqlClient.SqlCommand($Query,$connection)
            $cmd.CommandTimeout=$QueryTimeout
            $ds=New-Object system.Data.DataSet
            $da=New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
            [void]$da.fill($ds)
            
            $connection.Close()
            write-output "loaded data successfully"
    }
    catch
    {
        Write-Output $_.Exception.Message
    }
    