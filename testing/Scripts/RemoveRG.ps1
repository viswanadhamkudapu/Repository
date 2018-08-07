Param(
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $SubscriptionId,
    [Parameter(Mandatory=$True)]
    [String] $Username,
    [Parameter(Mandatory=$True)]
    [string] $Password,
     [Parameter(Mandatory=$True)]
    [string] $resourceGroupName
 
)
<#
$t = '[DllImport("user32.dll")] public static extern bool ShowWindow(int handle, int state);'
add-type -name win -member $t -namespace native
[native.win]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | Get-Process).MainWindowHandle, 0)
#>

                    do{
                        
                        if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) 
                        {
                        Install-PackageProvider NuGet -Force | Out-Null
                        }
                        
                        $LoadModule=Get-Module -ListAvailable "Azure*"
                        
                        if(!$LoadModule){
                        Install-Module -Name AzureRM.profile -AllowClobber -Force | Out-Null
                        Install-Module -Name AzureRM.resources -AllowClobber -Force | Out-Null
                        Install-Module -Name AzureRM.Compute -AllowClobber -Force | Out-Null
                        }
                        } until($LoadModule)

Import-Module AzureRM.profile
Import-Module AzureRM.resources
Import-Module AzureRM.Compute

        try{
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