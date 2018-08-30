$subsriptionid = Get-AutomationVariable -Name 'subsriptionid'
$subsriptionid
$ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
$ResourceGroupName
$Location = Get-AutomationVariable -Name 'Location'
$Location
$ApplicationID = Get-AutomationVariable -Name 'ApplicationID'
$ApplicationID
$RDBrokerURL = Get-AutomationVariable -Name 'RDBrokerURL'
$RDBrokerURL
$ResourceURL = Get-AutomationVariable -Name 'ResourceURL'
$ResourceURL
$fileURI = Get-AutomationVariable -Name 'fileURI'
$fileURI


Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/viswanadhamkudapu/Repository/master/msftsaas/scripts//Modules.zip' -OutFile 'C:\Modules.zip'
Expand-Archive 'C:\Modules.zip' -DestinationPath 'C:\Modules\Global' -ErrorAction SilentlyContinue
Import-Module AzureRM.Resources
Import-Module AzureRM.Profile
Import-Module AzureRM.Websites
Import-Module Azure
Import-Module AzureRM.Automation


    #The name of the Automation Credential Asset this runbook will use to authenticate to Azure.
    $CredentialAssetName = 'DefaultAzureCredential'

    #Get the credential with the above name from the Automation Asset store
    $Cred = Get-AutomationPSCredential -Name $CredentialAssetName
Add-AzureRmAccount -Environment 'AzureCloud' -Credential $Cred
Select-AzureRmSubscription -SubscriptionId $subsriptionid
    <#$ServicePrincipalConnectionName = "AzureRunAsConnection"
    $SPConnection = Get-AutomationConnection -Name $ServicePrincipalConnectionName   
        Add-AzureRmAccount -ServicePrincipal `
        -TenantId $SPConnection.TenantId `
        -ApplicationId $SPConnection.ApplicationId `
        -CertificateThumbprint $SPConnection.CertificateThumbprint | Write-Verbose
       #> 

    $EnvironmentName = "AzureCloud"
    $CodeBitPath= "C:\msft-rdmi-saas-offering\msft-rdmi-saas-offering"
    $WebAppDirectory = ".\msft-rdmi-saas-web"
    $WebAppExtractionPath = ".\msft-rdmi-saas-web\msft-rdmi-saas-web.zip"
    $ApiAppDirectory = ".\msft-rdmi-saas-api"
    $ApiAppExtractionPath = ".\msft-rdmi-saas-api\msft-rdmi-saas-api.zip"
    $AppServicePlan = "msft-rdmi-saas-$((get-date).ToString("ddMMyyyyhhmm"))"
    $WebApp = "RDmiMgmtWeb-$((get-date).ToString("ddMMyyyyhhmm"))"
    $ApiApp = "RDmiMgmtApi-$((get-date).ToString("ddMMyyyyhhmm"))"


try
{
    # Copy the files from github to VM
    Import-Module AzureRM.Profile
    Import-Module AzureRM.Resources

    Invoke-WebRequest -Uri $fileURI -OutFile "C:\msft-rdmi-saas-offering.zip"
    New-Item -Path "C:\msft-rdmi-saas-offering" -ItemType directory -Force -ErrorAction SilentlyContinue
    Expand-Archive "C:\msft-rdmi-saas-offering.zip" -DestinationPath "C:\msft-rdmi-saas-offering" -ErrorAction SilentlyContinue
    Test-Path -Path $CodeBitPath
    ## RESOURCE GROUP ##
        Add-AzureRmAccount -Environment "AzureCloud" -Credential $Cred
        Select-AzureRmSubscription -SubscriptionId $subsriptionid
        
        try 
        {
            ## APPSERVICE PLAN ##
               
            #create an appservice plan
        
            #Write-Output "Creating AppServicePlan in resource group  $ResourceGroupName ...";
            New-AzureRmAppServicePlan -Name $AppServicePlan -Location $Location -ResourceGroupName $ResourceGroupName -Tier Standard
            $AppPlan = Get-AzureRmAppServicePlan -Name $AppServicePlan -ResourceGroupName $ResourceGroupName
            #Write-Output "AppServicePlan with name $AppServicePlan has been created"

        }
        catch [Exception]
        {
            #Write-Output $_.Exception.Message
        }

        if($AppServicePlan)
        {
            try
            {
                ## CREATING APPS ##

                # create a web app
            
                #Write-Output "Creating a WebApp in resource group  $ResourceGroupName ...";
                New-AzureRmWebApp -Name $WebApp -Location $Location -AppServicePlan $AppServicePlan -ResourceGroupName $ResourceGroupName
                #Write-Output "WebApp with name $WebApp has been created"

                ## CREATING API-APP ##

                # Create an api app
            
                #Write-Output "Creating a ApiApp in resource group  $ResourceGroupName ...";
                $ServerFarmId = $AppPlan.Id
                $propertiesobject = @{"ServerFarmId"= $ServerFarmId}
                New-AzureRmResource -Location $Location -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -ResourceName $ApiApp -Kind 'api' -ApiVersion 2016-08-01 -PropertyObject $propertiesobject -Force
                #Write-Output "ApiApp with name $ApiApp has been created"
            }
            catch [Exception]
            {
                #Write-Output $_.Exception.Message
            }
        
        }
        
        if($ApiApp)
        {
            try
            {

                ## PUBLISHING API-APP PACKAGE ##
                
                Set-Location $CodeBitPath

                # Extract the Api-App ZIP file content.
            
                #Write-Output "Extracting the Api-App Zip File"
                Expand-Archive -Path $ApiAppExtractionPath -DestinationPath $ApiAppDirectory -Force 
                $ApiAppExtractedPath = Get-ChildItem -Path $ApiAppDirectory| Where-Object {$_.FullName -notmatch '\\*.zip($|\\)'} | Resolve-Path -Verbose
                
                # Get publishing profile from Api-App

                #Write-Output "Getting the Publishing profile information from Api-App"
                $ApiAppXML = (Get-AzureRmWebAppPublishingProfile -Name $ApiApp `
                -ResourceGroupName $ResourceGroupName  `
                -OutputFile null)
                $ApiAppXML = [xml]$ApiAppXML

                # Extract connection information from publishing profile

                #Write-Output "Gathering the username, password and publishurl from the Web-App Publishing Profile"
                $ApiAppUserName = $ApiAppXML.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value
                $ApiAppPassword = $ApiAppXML.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value
                $ApiAppURL = $ApiAppXML.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value
                  
                # Publish Api-App Package files recursively

                #Write-Output "Uploading the Extracted files to Api-App"
                Set-Location $ApiAppExtractedPath
                $ApiAppClient = New-Object -TypeName System.Net.WebClient
                $ApiAppClient.Credentials = New-Object System.Net.NetworkCredential($ApiAppUserName,$ApiAppPassword)
                $ApiAppFiles = Get-ChildItem -Path $ApiAppExtractedPath -Recurse
                foreach ($ApiAppFile in $ApiAppFiles)
                {
                    $ApiAppRelativePath = (Resolve-Path -Path $ApiAppFile.FullName -Relative).Replace(".\", "").Replace('\', '/')
                    $ApiAppURI = New-Object System.Uri("$ApiAppURL/$ApiAppRelativePath")
                    if($ApiAppFile.PSIsContainer)
                    {
                        $ApiAppURI.AbsolutePath + "is Directory"
                        $ApiAppFTP = [System.Net.FtpWebRequest]::Create($ApiAppURI);
                        $ApiAppFTP.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
                        $ApiAppFTP.UseBinary = $true

                        $ApiAppFTP.Credentials = New-Object System.Net.NetworkCredential($ApiAppUserName,$ApiAppPassword)

                        $ApiAppResponse = $ApiAppFTP.GetResponse();
                        $ApiAppResponse.StatusDescription
                        continue
                    }
                    "Uploading to..." + $ApiAppURI.AbsoluteUri
                    $ApiAppClient.UploadFile($ApiAppURI, $ApiAppFile.FullName)
                } 
                $ApiAppClient.Dispose() 
                #Write-Output "Uploading of Extracted files to Api-App is Successful"

                # Get Url of Web-App 

                $GetWebApp = Get-AzureRmWebApp -Name $WebApp -ResourceGroupName $ResourceGroupName
                $WebUrl = $GetWebApp.DefaultHostName 

                # Adding App Settings to Api-App
                
                #Write-Output "Adding App settings to Api-App"
                $ApiAppSettings = @{"ApplicationId" = "$ApplicationID";
                                    "RDBrokerUrl" = "$RDBrokerURL";
                                    "ResourceUrl" = "$ResourceURL";
                                    "RedirectURI" = "https://"+"$WebUrl"+"/";
                                    }
                <#$Redirecturl1="https://"+"$WebUrl"+"/"
                $Redirecturl2="https://login.microsoftonline.com/common/oauth2/logout?post_logout_redirect_uri="
                $ADapplication=Get-AzureRmADApplication -ApplicationId $ApplicationID
                $add=$ADapplication.ReplyUrls.Add($Redirecturl1)
                $add=$ADapplication.ReplyUrls.Add("$Redirecturl2"+"$Redirecturl1")
                $ReplyUrls=$ADapplication.ReplyUrls
                Set-AzureRmADApplication -ApplicationId $ApplicationID -ReplyUrl $ReplyUrls #>
                $ApiAppSettings
                Set-AzureRmWebApp -AppSettings $ApiAppSettings -Name $ApiApp -ResourceGroupName $ResourceGroupName
            }
            catch [Exception]
            {
                #Write-Output $_.Exception.Message
            }
        }
        if($WebApp -and $ApiApp)
        {
            try
            {
                ## PUBLISHING WEB-APP PACKAGE ##
                
                Set-Location $CodeBitPath

                #Write-Output "Extracting the Web-App Zip File"
 
                # Extract the Web-App ZIP file content.

                Expand-Archive -Path $WebAppExtractionPath -DestinationPath $WebAppDirectory -Force 
                $WebAppExtractedPath = Get-ChildItem -Path $WebAppDirectory| Where-Object {$_.FullName -notmatch '\\*.zip($|\\)'} | Resolve-Path -Verbose

                # Get the main.bundle.js file Path 

                $MainbundlePath = Get-ChildItem $WebAppExtractedPath -recurse | where {($_.FullName -match "main.bundle.js" ) -and ($_.FullName -notmatch "main.bundle.js.map")} | % {$_.FullName}
 
                # Get Url of Api-App 

                $GetUrl = Get-AzureRmResource -ResourceName $ApiApp -ResourceGroupName $ResourceGroupName -ExpandProperties
                $GetApiUrl = $GetUrl.Properties | select defaultHostName
                $ApiUrl = $GetApiUrl.defaultHostName

                # Change the Url in the main.bundle.js file with the ApiURL

                #Write-Output "Updating the Url in main.bundle.js file with Api-app Url"
                (Get-Content $MainbundlePath).replace( "[api_url]", "https://"+$ApiUrl) | Set-Content $MainbundlePath

                # Get publishing profile from web app
                
                #Write-Output "Getting the Publishing profile information from Web-App"
                $WebAppXML = (Get-AzureRmWebAppPublishingProfile -Name $WebApp `
                -ResourceGroupName $ResourceGroupName  `
                -OutputFile null)

                $WebAppXML = [xml]$WebAppXML

                # Extract connection information from publishing profile

                #Write-Output "Gathering the username, password and publishurl from the Web-App Publishing Profile"
                $WebAppUserName = $WebAppXML.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value
                $WebAppPassword = $WebAppXML.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value
                $WebAppURL = $WebAppXML.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value
                
                # Publish Web-App Package files recursively

                #Write-Output "Uploading the Extracted files to Web-App"
                Set-Location $WebAppExtractedPath
                $WebAppClient = New-Object -TypeName System.Net.WebClient
                $WebAppClient.Credentials = New-Object System.Net.NetworkCredential($WebAppUserName,$WebAppPassword)
                $WebAppFiles = Get-ChildItem -Path $WebAppExtractedPath -Recurse
                foreach ($WebAppFile in $WebAppFiles)
                {
                    $WebAppRelativePath = (Resolve-Path -Path $WebAppFile.FullName -Relative).Replace(".\", "").Replace('\', '/')
                    $WebAppURI = New-Object System.Uri("$WebAppURL/$WebAppRelativePath")
                    if($WebAppFile.PSIsContainer)
                    {
                        $WebAppURI.AbsolutePath + "is Directory"
                        $WebAppFTP = [System.Net.FtpWebRequest]::Create($WebAppURI);
                        $WebAppFTP.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
                        $WebAppFTP.UseBinary = $true
                        $WebAppFTP.Credentials = New-Object System.Net.NetworkCredential($WebAppUserName,$WebAppPassword)
                        $WebAppResponse = $WebAppFTP.GetResponse();
                        $WebAppResponse.StatusDescription
                        continue
                    }
                    "Uploading to..." + $WebAppURI.AbsoluteUri
                    $WebAppClient.UploadFile($WebAppURI, $WebAppFile.FullName)
                } 
                $WebAppClient.Dispose()
                #Write-Output "Uploading of Extracted files to Web-App is Successful"
            }
            catch [Exception]
            {
                #Write-Output $_.Exception.Message
            }

            #Write-Output "Api URL : https://$ApiUrl"
            #Write-Output "Web URL : https://$WebUrl"
        }
    
    <#
New-PSDrive -Name RemoveRG -PSProvider FileSystem -Root "C:\msft-rdmi-saas-offering\msft-rdmi-saas-offering" | Out-Null
@"
<RemoveRG>
<SubscriptionId>$SubscriptionId</SubscriptionId>
<UserName>$UserName</UserName>
<Password>$Password</Password>
<RGName>$ResourceGroupName</RGName>
<VMName>$VMName</VMName>
</RemoveRG>
"@| Out-File -FilePath RemoveRG:\RemoveRG.xml -Force

# creating job to run the remove resource group script

$jobname = "RemoveResourceGroup"
$script =  "C:\msft-rdmi-saas-offering\msft-rdmi-saas-offering\RemoveRG.ps1"
$repeat = (New-TimeSpan -Minutes 1)
$action = New-ScheduledTaskAction –Execute "$pshome\powershell.exe" -Argument  "-ExecutionPolicy Bypass -Command ${script}"
$duration = (New-TimeSpan -Days 1)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval $repeat -RepetitionDuration $duration
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
Register-ScheduledTask -TaskName $jobname -Action $action -Trigger $trigger -RunLevel Highest -User "system" -Settings $settings
#>
}

catch [Exception]
{
    #Write-Output $_.Exception.Message
}
#Remove-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName -Name 'Test-Account1' -Force