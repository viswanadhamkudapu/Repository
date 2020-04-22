param(
[Parameter(Mandatory = $true)]
[ValidateNotNullOrEmpty()]
[string] $HostpoolFolderName,
[Parameter(Mandatory = $true)]
[ValidateNotNullOrEmpty()]
[string] $Usernames
)

$RAWDisks = Get-Disk | Where-Object PartitionStyle –Eq 'RAW'

foreach($Disk in $RAWDisks){
# Initializing disk with MBR
Initialize-Disk -Number $Disk.number -PartitionStyle MBR
New-Partition –DiskNumber $Disk.number -AssignDriveLetter –UseMaximumSize
$DiskPartition = Get-Partition -DiskNumber $Disk.number
Set-Partition -DriveLetter $DiskPartition.DriveLetter -IsActive $true
Format-Volume -DriveLetter $DiskPartition.DriveLetter -FileSystem NTFS
$DiskLetter = $DiskPartition.DriveLetter
$DiskDrive = $DiskLetter + ":\"
New-Item -Name $HostpoolFolderName -Path $DiskDrive -ItemType Directory
$Path = $DiskDrive + $HostpoolFolderName
$c = new-CimSession -ComputerName $env:COMPUTERNAME
New-SmbShare -Name $HostpoolFolderName -Path $Path -CimSession $c `
  -Description 'Shared Folder for $HostpoolName users' `
  -FullAccess $Usernames -ReadAccess Everyone -ChangeAccess Everyone
  }

