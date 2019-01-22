<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FRDS-Templates%2Fmaster%2Frdmi-peopletech%2FPatch%20an%20existing%20RDmi%20hostpool%2FmainTemplate.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FRDS-Templates%2Fmaster%2Frdmi-peopletech%2FPatch%20an%20existing%20RDmi%20hostpool%2FmainTemplate.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

Create and provision new WVD Host pool (Credentials)
This template creates virtual machines and registers them as session hosts to a new or existing Windows Virtual Desktop host pool. There are different sets of parameters you must enter to successfully deploy the template:
•	VM image Type
•	RDSH VM Configuration in Azure
•	Domain and Network Properties
•	Authentication to Windows Virtual Desktop
Follow the guidance below for entering the appropriate parameters for your scenario.
VM Image Type
When creating the virtual machines, you have two options:
•	Azure Gallery image
•	Custom VHD from blob storage
Enter the appropriate parameters depending on the image option you choose.
Azure Gallery Image
By selecting Azure Gallery, you can select up-to-date images provided by Microsoft and other publishers. Enter or select values for the following parameters:
•	Rdsh Image Source, select Gallery.
•	Rdsh Gallery Image SKU
•	Rdsh Is Windows Server. Note: Windows 10 Enterprise multi-session is not considered Windows Server.
•	Rdsh is 1809 Or Later. Note that Windows 10 Enterprise multi-session is an 1809 release.
•	Rdsh Use Managed Disks. Note if you are selected “false” it will automatically create new storage account and store the OSDisk into storage blob.
Ignore the following parameters:
•	Vm Image Vhd Uri
•	Storage Account Resource Group Name
Custom VHD from Blob Storage
By selecting a custom VHD from blob storage, you can create your own image locally through Hyper-V or on an Azure VM. Enter or select values for the following parameters:
•	Rdsh Image Source select CustomVHD.
•	Vm Image Vhd Uri
•	Rdsh Is Windows Server. Note: Windows 10 Enterprise multi-session is not considered Windows Server.
•	Rdsh is 1809 Or Later. Note that Windows 10 Enterprise multi-session is an 1809 release.
•	Rdsh Use Managed Disks. If you select false for Rdsh Use Managed Disks, enter the name of the resource group containing the storage account and image for the Storage Account Resource Group Name parameter. Otherwise, leave the Storage Account Resource Group Name parameter empty.
Ignore the following parameters:
•	Rdsh Gallery Image SKU
RDSH VM Configuration
Enter the remaining configuration parameters for the virtual machines.
•	Rdsh Name Prefix
•	Rdsh Number Of Instances
•	Rdsh VM Disk Type.
Domain and Network Properties
Enter the following properties to connect the virtual machines to the appropriate network and join them to the appropriate domain (and organizational unit, if defined).
•	Existing Domain UPN. This UPN must have appropriate permissions to join the virtual machines to the domain and organizational unit.
•	Existing Domain Password
•	OU Path. If you do not have a specific organizaiton unit for the virtual machines to join, leave this parameter empty.
•	Existing Vnet Name
•	Existing Subnet Name
•	Virtual Network Resource Group Name
Authentication to Windows Virtual Desktop
Enter the following information to authenticate to Windows Virtual Desktop and register the new virtual machines as session hosts to a new or existing host pool.
•	Rd Broker URL
•	Existing Tenant Group Name. If you were not given a specific tenant group name, leave this value as "Default Tenant Group".
•	Existing Tenant Name
•	Host Pool Name
•	Registration Token. If you have valid Hostpool registration token, enter registration token no need to enter hostpool name.
•	Tenant Admin Upn. If you are creating a new host pool, this User Principal Name must be assigned either the RDS Owner or RDS Contributor role at the tenant scope (or higher). If you are registering these virtual machines to an existing host pool.
•	Tenant Admin Password
Click the button below to deploy:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FRDS-Templates%2Fmaster%2Frdmi-peopletech%2FPatch%20an%20existing%20RDmi%20hostpool%2FmainTemplate.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FRDS-Templates%2Fmaster%2Frdmi-peopletech%2FPatch%20an%20existing%20RDmi%20hostpool%2FmainTemplate.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>
