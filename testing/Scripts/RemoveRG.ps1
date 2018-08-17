Try{
#Current Path
$CurrentPath = Split-Path $script:MyInvocation.MyCommand.Path
#XMl Configuration File Path
$XMLPath = "$CurrentPath\RemoveRG.xml"
##### Load XML Configuration values as variables #########
Write-Verbose "loading values from RemoveRG.xml"
$Variable=[XML] (Get-Content "$XMLPath")
		$SubscriptionId = $Variable.RemoveRG.SubscriptionId
		$Username = $Variable.RemoveRG.Username
		$Password = $Variable.RemoveRG.Password
		$resourceGroupName = $Variable.RemoveRG.resourceGroupName
                    do{
                        
                        if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) 
                        {
                        Install-PackageProvider NuGet -Force 
                        }
                        
                        $LoadModule=Get-Module -ListAvailable "Azure*"
                        
                        if(!$LoadModule){
                        Install-Module -Name AzureRM.profile -AllowClobber -Force 
                        Install-Module -Name AzureRM.resources -AllowClobber -Force
                        Install-Module -Name AzureRM.Compute -AllowClobber -Force
                        }
                        } until($LoadModule)

                        Import-Module AzureRM.profile
                        Import-Module AzureRM.resources
                        Import-Module AzureRM.Compute

        
        $Securepass=ConvertTo-SecureString -String $Password -AsPlainText -Force
        $Azurecred=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList($Username, $Securepass)
        $login=Login-AzureRmAccount -Credential $Azurecred -SubscriptionId $SubscriptionId
        $getRGInfo=Get-AzureRmResourceGroup -Name $resourceGroupName
        $test=New-AzureRmAvailabilitySet -ResourceGroupName $resourceGroupName -Name "Test-avset" -Location $getRGInfo.Location
        Remove-AzureRmResourceGroup -Name $resourceGroupName -Force
        }
        catch{
        Write-Error $_.Exception.Message
        }