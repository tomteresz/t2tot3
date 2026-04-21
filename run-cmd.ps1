-1) Check ENA status, enable/disable

#this is for runpscommand
$instances = @(
    "i-1234567890abcdef0",
    "i-0987654321fedcba0",
    "i-0a1b2c3d4e5f67890"
)

#this is for foreach
$instances = "i-0ded60d486f784339","i-082c37e4c60c9d9f5"

(Get-EC2Instance -InstanceId <instance-id>).Instances.EnaSupport

Edit-EC2InstanceAttribute -InstanceId <instance-id> -EnaSupport $false/$true

foreach ($instance in $instances) {
  Write-Host `Instance ID: $instance ENA status: (Get-EC2Instance -InstanceId $instance).Instances.EnaSupport
}

0) Test connection

$runPSCommand = Send-SSMCommand `
-InstanceIds $instances `
-DocumentName "AWS-RunPowerShellScript" `
-Comment "Connection test" `
-Parameter @{'commands'=@('hostname')}
  
1) Check the status

a) 
Get-SSMCommandInvocation `
    -CommandId $runPSCommand.CommandId

(Get-SSMCommandInvocation -CommandId $runPSCommand.commandid).instanceName
(Get-SSMCommandInvocation -CommandId $runPSCommand.commandid).instanceID

b)
(Get-SSMCommandInvocation -CommandId $runPSCommand.CommandId -Details $true -InstanceId i-0ded60d486f784339 | Select -ExpandProperty CommandPlugins).output

c)

Executed commands list available under following link:

https://eu-central-1.console.aws.amazon.com/systems-manager/run-command/executing-commands?region=eu-central-1

Systems Manager - > Run Command - > Command history

2) Install PV Drivers

$runPSCommand = Send-SSMCommand `
-InstanceIds $instances `
-DocumentName "AWS-RunPowerShellScript" `
-Comment "Install PV drivers" `
-Parameter @{'commands'=@('New-Item -Type Directory -Path C:\t3mp132','Start-Sleep 1', '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12','Start-Sleep 1', 'Invoke-WebRequest -Uri "https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/Latest/AWSPVDriver.zip" -OutFile C:\t3mp132\AWSPVDriver.zip','Start-Sleep 1', 'Expand-Archive -LiteralPath C:\t3mp132\AWSPVDriver.zip -DestinationPath "C:\t3mp132\AWSPVDriver"','Start-Sleep 1', 'C:\t3mp132\AWSPVDriver\install.ps1 -quiet', 'start-sleep 1', 'New-Item -Type file -Path C:\t3mp132\done-pv-drivers.txt')}

Get-SSMCommandInvocation -CommandId $runPSCommand.CommandId

3) Install ENA and NVME Drivers

$runPSCommand = Send-SSMCommand `
-InstanceIds $instances `
-DocumentName "AWS-RunPowerShellScript" `
-Comment "Install ENA and NVME drivers" `
-Parameter @{'commands'=@('[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12','Start-Sleep 1', 'Invoke-WebRequest -Uri "https://s3.amazonaws.com/ec2-windows-drivers-downloads/ENA/Latest/AwsEnaNetworkDriver.zip" -OutFile C:\t3mp132\AwsEnaNetworkDriver.zip', 'Start-Sleep 1', 'Expand-Archive -LiteralPath C:\t3mp132\AwsEnaNetworkDriver.zip -DestinationPath "C:\t3mp132\AwsEnaNetworkDriver"','Start-Sleep 1', 'C:\t3mp132\AwsEnaNetworkDriver\install.ps1', 'start-sleep 1', 'Invoke-WebRequest -Uri "https://s3.amazonaws.com/ec2-windows-drivers-downloads/NVMe/Latest/AWSNVMe.zip" -OutFile C:\t3mp132\AWSNVMe.zip','Start-Sleep 1', 'Expand-Archive -LiteralPath C:\t3mp132\AWSNVMe.zip -DestinationPath "C:\t3mp132\AWSNVMe"','Start-Sleep 1', 'C:\t3mp132\AWSNVMe\install.ps1 -force', 'start-sleep 1', 'New-Item -Type file -Path C:\t3mp132\done-ena-nvme.txt')}

4) Reboot

$runPSCommand = Send-SSMCommand `
-InstanceIds $instances `
-DocumentName "AWS-RunPowerShellScript" `
-Comment "Reboot instance" `
-Parameter @{'commands'=@('shutdown -r -t 10')}

5) Remove files

$runPSCommand = Send-SSMCommand `
-InstanceIds $instances `
-DocumentName "AWS-RunPowerShellScript" `
-Comment "Remove files from C:\ drive" `
-Parameter @{'commands'=@('Remove-Item -Force -Recurse C:\t3mp132')}

foreach ($instance in $instances) {
  Stop-EC2Instance -InstanceId $instance
  Edit-EC2InstanceAttribute -InstanceId $instance -InstanceType t3.medium
  Start-EC2Instance -InstanceId $instance
}
