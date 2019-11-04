<#
.SYNOPSIS
FS Logix Configuration
.DESCRIPTION
This script is used configure the fs logix.
#>
param(
[Parameter(mandatory = $True)]
[string]$StorageAccountKey,

[Parameter(mandatory = $True)]
[string]$StorageAccountURL
)

#Static values
$fslogixDownloadURI="https://download.microsoft.com/download/5/8/4/58482cbd-4072-4e26-9015-aa4bbe56c52e/FSLogix_Apps_2.9.7205.27375.zip"
$OutFile= "C:\FSLogix.zip"
$DestinationPath="C:\FSLogixInstallers"
$StorageAccount = $StorageAccountURL.Split(".").Trim("\\")[0]
New-Item -Path $DestinationPath -ItemType "directory"
New-Item -Path "C:\UbikitePSL" -ItemType "directory"
@"
param(
[Parameter(mandatory = `$True)]
[string]`$SignName,
)
net use y: $StorageAccountURL $StorageAccountKey /user:Azure\$StorageAccount
icacls y: /grant `$SignName:(f)

"@| Out-File "C:\UbikitePSL\FSGrantingToUser.ps1"


Invoke-WebRequest -Uri $fslogixDownloadURI -OutFile $OutFile
Expand-Archive -Path $OutFile -DestinationPath $DestinationPath
Invoke-Expression -Command "cmd.exe /c C:\FileServerLogix\x64\Release\FSLogixAppsSetup.exe /quiet"
$FSRegistry = Get-Item -Path "HKLM:\Software\FSLogix"
if($FSRegistry){
New-Item -Path "HKLM:\Software\FSLogix" -Name "Profiles" –Force
$registryPath = "HKLM:\Software\FSLogix\Profiles"
New-ItemProperty -Path $registryPath -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "VHDLocations" -Value $StorageAccountURL -PropertyType "Multistring" -Force | Out-Null
}