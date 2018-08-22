param(
[parameter(mandatory)]
[String]$UserName,
[parameter(mandatory)]
[String]$Password,
[parameter(mandatory)]
[String]$AAResourcegroupName,
[parameter(mandatory)]
[String]$ResourceGroupName,
[parameter(mandatory)]
[String]$SubscriptionId,
[parameter(mandatory)]
[String]$VMName
)


$Securepass=ConvertTo-SecureString -String $Password -AsPlainText -Force
$Credentials=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList($UserName, $Securepass)
Login-AzureRmAccount -Credential $Credentials -SubscriptionId $SubscriptionId
#New-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroupName -Name "testremoveavset" -Location "Central US"
         try{
         $resources=0
         $resources=@()
         $allreosurces=Get-AzureRmResource | Where-Object{$_.ResourceGroupName -eq $ResourceGroupName}
         $resourceidss=$allreosurces.resourceid
         foreach($resourceids in $resourceidss){
         $path=split-path -path $resourceids -Leaf
         if($path -like "*$VMName*"){ # -or $resourceids -like "*vnet*"){
         $resources += $resourceids
         }
         }
               #Remove the VM
               Remove-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
               foreach($resource in $resources)
                    {
                    Remove-AzureRmResource -ResourceId $resource -Force
                    <#Remove-AzureRmPublicIpAddress -Name $resource -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
                    Remove-AzureRmNetworkSecurityGroup -Name $resource -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
                    Remove-AzureRmVirtualNetwork -Name $resource -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
                    #>
                    }
            }
            Catch {
               Write-Output $_.Exception.Message
            }#Catch

#Removing Automation Account Resource group
Remove-AzureRmResourceGroup -Name $AAResourcegroupName -Force