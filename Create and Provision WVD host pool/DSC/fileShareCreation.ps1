param(

[Parameter(Mandatory = $true)]
[ValidateNotNullOrEmpty()]
[string] $HostpoolFolderName,
[Parameter(Mandatory = $true)]
[ValidateNotNullOrEmpty()]
[string] $Username
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
$DiskDrive = $DiskLetter + ":"
New-Item -Name $HostpoolNameFolderName -Path "$DiskDrive\" -ItemType Directory
New-SmbShare -Path "$DiskDrive\$HostpoolNameFolderName"`
  -Description 'Shared Folder for $HostpoolName users' `
  -FullAccess "ubikiteadadmmin" -ReadAccess Everyone

}

