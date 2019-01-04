Set-ExecutionPolicy -ExecutionPolicy Bypass -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String
function Write-Log { 


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

Write-Log -Message "Policy List: $log"

    #Downloading the DeployAgent zip file to rdsh vm
    Invoke-WebRequest -Uri $fileURI -OutFile "C:\DeployAgent.zip"
    Write-Log -Message "Downloaded DeployAgent.zip into this location C:\"

    #Creating a folder inside rdsh vm for extracting deployagent zip file
    New-Item -Path "C:\DeployAgent" -ItemType directory -Force -ErrorAction SilentlyContinue
    Write-Log -Message "Created a new folder 'DeployAgent' inside VM"
    Expand-Archive "C:\DeployAgent.zip" -DestinationPath "C:\DeployAgent" -ErrorAction SilentlyContinue
    Write-Log -Message "Extracted the 'Deployagent.zip' file into 'C:\Deployagent' folder inside VM"
    Set-Location "C:\DeployAgent"
    Write-Log -Message "Setting up the location of Deployagent folder"

 #"C:\Users\Viswa\Desktop\script.ps1" -RDBrokerURL "https://rdbroker.wvd.microsoft.com" -TenantName "Peopletech-tenant" -HostPoolName "ptgarm-hostpool" -Description "ARM through created Hostpool will remove shortly" -FriendlyName "arm hostpool" -Hours 48 -rdshIs1809OrLater $true -ActivationKey "NJCF7-PW8QT-3324D-688JX-2YV66" -TenantAdminUPN "wvd.demo@peopletechcsp.onmicrosoft.com" -TenantAdminPassword "Ptgindia@123" -localAdminUserName "vmadmin" -localAdminPassword "keepcalm@123"
 .\Scripts\Script1.ps1 -FileURI $FileURI -registrationToken $registrationToken -ActivationKey $ActivationKey -rdshIs1809OrLater 'True' -localAdminUserName $localAdminUserName -localAdminPassword $localAdminPassword
