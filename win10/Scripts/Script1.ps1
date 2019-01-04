Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String
Write-Output $log

Invoke-WebRequest -Uri "https://raw.githubusercontent.com/viswanadhamkudapu/Repository/master/win10/Scripts/DeployAgent.zip" -OutFile "C:\DeployAgent.zip"
    #Write-Log -Message "Downloaded DeployAgent.zip into this location C:\"

    #Creating a folder inside rdsh vm for extracting deployagent zip file
    New-Item -Path "C:\DeployAgent" -ItemType directory -Force -ErrorAction SilentlyContinue
    #Write-Log -Message "Created a new folder 'DeployAgent' inside VM"
    Expand-Archive "C:\DeployAgent.zip" -DestinationPath "C:\DeployAgent" -ErrorAction SilentlyContinue
    #Write-Log -Message "Extracted the 'Deployagent.zip' file into 'C:\Deployagent' folder inside VM"
    Set-Location "C:\DeployAgent"
    #Write-Log -Message "Setting up the location of Deployagent folder
   .\Script.ps1 -FileURI "https://raw.githubusercontent.com/viswanadhamkudapu/Repository/master/win10/Scripts/DeployAgent.zip" -registrationToken "eyJhbGciOiJSUzI1NiIsImtpZCI6IkFDRkQ1MTcyMkM1MTE5MDI1OTFEQUY3MUY2QzY4MzZDRDI0RjM4QTgiLCJ0eXAiOiJKV1QifQ.eyJSZWdpc3RyYXRpb25JZCI6IjM3NWQ3YzdiLTFmMjQtNDUwNS1iNWFjLWY0ZTQ5MjhhNmEzMiIsIkJyb2tlclVyaSI6Imh0dHBzOi8vcmRicm9rZXItcjAud3ZkLm1pY3Jvc29mdC5jb20vIiwiRGlhZ25vc3RpY3NVcmkiOiJodHRwczovL3JkZGlhZ25vc3RpY3MtcjAud3ZkLm1pY3Jvc29mdC5jb20vIiwibmJmIjoxNTQ2NjAwODYzLCJleHAiOjE1NDY2ODcyNjIsImlzcyI6IlJESW5mcmFUb2tlbk1hbmFnZXIiLCJhdWQiOiJSRG1pIn0.JxBowQCsnc1mnjY_UUHG18hXTYEHyEBrK-jTavysvcKpkdCQYWFzucBs6QygNcFo8FQl-mOUsVo7acWBAKYTlEpvKpvVaqwnjxIzpQDcPJXs0pE9mfVWCQvBN5CGEA6FMmvDTd8j8dRbG_I7PKTeoHYw_Z_srg9smTlUdg_P7fLsOD4PjeYYNP9zsbnMlNrbJm5sKokFLva2vYrqgWeBOAwx-x4xt6jHUPHsORI5tADCKNzikQOP2LPMwBph3D7f0_Us3NLQzyrhyOozcVYoeR9jZbm7ZjbaYZGTgMZlw3cayBnBmwmmtTYfP6f4L1yVaOPhKMnIFgui9IEuEKUDfg" -ActivationKey "NJCF7-PW8QT-3324D-688JX-2YV66" -rdshIs1809OrLater 'True' -localAdminUserName "vmadmin" -localAdminPassword "keepcalm@123"

