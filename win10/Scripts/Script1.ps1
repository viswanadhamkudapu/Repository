Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String
Write-Output $log

Invoke-WebRequest -Uri "https://github.com/viswanadhamkudapu/Repository/blob/master/win10/Scripts/DeployAgent.zip" -OutFile "C:\DeployAgent.zip"
    #Write-Log -Message "Downloaded DeployAgent.zip into this location C:\"

    #Creating a folder inside rdsh vm for extracting deployagent zip file
    New-Item -Path "C:\DeployAgent" -ItemType directory -Force -ErrorAction SilentlyContinue
    #Write-Log -Message "Created a new folder 'DeployAgent' inside VM"
    Expand-Archive "C:\DeployAgent.zip" -DestinationPath "C:\DeployAgent" -ErrorAction SilentlyContinue
    #Write-Log -Message "Extracted the 'Deployagent.zip' file into 'C:\Deployagent' folder inside VM"
    Set-Location "C:\DeployAgent"
    #Write-Log -Message "Setting up the location of Deployagent folder"

    .\Scripts\Script1.ps1 -FileURI "https://github.com/viswanadhamkudapu/Repository/blob/master/win10/Scripts/DeployAgent.zip" -registrationToken "" -ActivationKey "NJCF7-PW8QT-3324D-688JX-2YV66" -rdshIs1809OrLater 'True' -localAdminUserName "vmadmin" -localAdminPassword "keepcalm@123"

