Try{
#Current Path
$CurrentPath = Split-Path $script:MyInvocation.MyCommand.Path
#XMl Configuration File Path
$XMLPath = "$CurrentPath\RemoveRG.xml"
##### Load XML Configuration values as variables #########
Write-Verbose "loading values from RemoveRG.xml"
$Variable=[XML] (Get-Content "$XMLPath")
$SubscriptionId = $Variable.RemoveRG.SubscriptionId
$UserName = $Variable.RemoveRG.UserName
$Password = $Variable.RemoveRG.Password
$ResourceGroupName = $Variable.RemoveRG.RGName
$VMName = $Variable.RemoveRG.VMName

$automationAccountName = "Msftsaasapirg876"
$runbookName = "MsftSaaSapiRunbook"
$AAResourcegroupName="Msftsaasapirg876rg"
$AaLocation="South Central US"
$scriptPath = "C:\msft-rdmi-saas-offering\msft-rdmi-saas-offering\RemoveResouces.ps1"



do{                      
    if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) 
    {
    Install-PackageProvider NuGet -Force 
    }         
    # Getting the Modules available in Azure
               
    $LoadModule=Get-Module -ListAvailable "Azure*"
                        
    if(!$LoadModule){

    # Installing Modules

    Install-Module -Name AzureRM.profile -AllowClobber -Force 
    Install-Module -Name AzureRM.resources -AllowClobber -Force
    Install-Module -Name AzureRM.Compute -AllowClobber -Force
    Install-Module -Name AzureRM.Automation -AllowClobber -Force
    }
    } until($LoadModule)

    # Importing Modules 

    Import-Module AzureRM.profile
    Import-Module AzureRM.resources
    Import-Module AzureRM.Compute  
    $Securepass=ConvertTo-SecureString -String $Password -AsPlainText -Force
    $Azurecred=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList($UserName, $Securepass)
    $login=Login-AzureRmAccount -Credential $Azurecred -SubscriptionId $SubscriptionId
    
    #create a new resourcegroup
    New-AzureRmResourceGroup -Name $AAResourcegroupName -Location $AaLocation -Force

    #Creating Automation Account
    $AAccount=New-AzureRmAutomationAccount -ResourceGroupName $AAResourcegroupName -Name $automationAccountName -Location $AaLocation -Plan Free

    #Create a Run Book
    $AAcctRunbook=New-AzureRmAutomationRunbook -Name $runbookName -Type PowerShell -ResourceGroupName $AAResourcegroupName -AutomationAccountName $automationAccountName

    #Import modules to Automation Account
    $modules="AzureRM.profile,Azurerm.compute,azurerm.resources"
    $modulenames=$modules.Split(",")
    foreach($modulename in $modulenames){
    Set-AzureRmAutomationModule -Name $modulename -AutomationAccountName $automationAccountName -ResourceGroupName $AAResourcegroupName
    }

    #Importe powershell file to Runbooks
    Import-AzureRmAutomationRunbook -Path $scriptPath -Name $runbookName -Type PowerShell -ResourceGroupName $AAResourcegroupName -AutomationAccountName $automationAccountName -Force

    #Publishing Runbook
    Publish-AzureRmAutomationRunbook -Name $runbookName -ResourceGroupName $AAResourcegroupName -AutomationAccountName $automationAccountName

    #Providing parameter values to powershell script file
    $params=@{"UserName"=$UserName;"Password"=$Password;"AAResourcegroupName"=$AAResourcegroupName;"ResourceGroupName"=$ResourceGroupName;"VMName"=$VMName;"SubscriptionId"=$SubscriptionId}
    Start-AzureRmAutomationRunbook -Name $runbookName -ResourceGroupName $AAResourcegroupName -AutomationAccountName $automationAccountName -Parameters $params

    }
    catch{
    Write-Error $_.Exception.Message
    }