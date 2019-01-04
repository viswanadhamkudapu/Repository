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

Set-Location "C:\DeployAgent"
 #"C:\Users\Viswa\Desktop\script.ps1" -RDBrokerURL "https://rdbroker.wvd.microsoft.com" -TenantName "Peopletech-tenant" -HostPoolName "ptgarm-hostpool" -Description "ARM through created Hostpool will remove shortly" -FriendlyName "arm hostpool" -Hours 48 -rdshIs1809OrLater $true -ActivationKey "NJCF7-PW8QT-3324D-688JX-2YV66" -TenantAdminUPN "wvd.demo@peopletechcsp.onmicrosoft.com" -TenantAdminPassword "Ptgindia@123" -localAdminUserName "vmadmin" -localAdminPassword "keepcalm@123"
 .\Scripts\Script1.ps1 -FileURI $FileURI -registrationToken $registrationToken -ActivationKey $ActivationKey -rdshIs1809OrLater $rdshIs1809OrLater -localAdminUserName $localAdminUserName -localAdminPassword $localAdminPassword
