# 🪟 AWS EC2 Windows Driver Upgrade Automation

PowerShell-based automation scripts for upgrading AWS Windows EC2 instances to modern
instance types (e.g., `t3.medium`) by installing the required **PV**, **ENA**, and
**NVMe** drivers remotely via **AWS Systems Manager (SSM)** — without the need for
RDP or manual intervention.

---

## 📋 Overview

When migrating Windows EC2 instances from older generation types (e.g., `t2`) to newer
ones (e.g., `t3`), AWS requires the **Elastic Network Adapter (ENA)** and **NVMe**
drivers to be installed at the OS level beforehand. This runbook automates the entire
preparation and migration process across multiple instances in a single pass using
**SSM Run Command** and **AWS Tools for PowerShell**.

---

## 🛠️ Prerequisites

- **AWS Tools for PowerShell** installed and configured locally
- **SSM Agent** running on all target Windows EC2 instances
- IAM permissions for `ssm:SendCommand`, `ec2:DescribeInstances`,
  `ec2:ModifyInstanceAttribute`, `ec2:StopInstances`, `ec2:StartInstances`
- Instances must have an **IAM Instance Profile** with `AmazonSSMManagedInstanceCore`
  policy attached
- Outbound internet access on the instances (to download drivers from AWS S3)

---

## ⚙️ How It Works

### -1. 🔍 Check & Configure ENA Support

Before installing drivers, verify the ENA support flag on each instance at the EC2
API level. This step must be performed while the instance is **stopped**.

**Check ENA status on a single instance:**
```powershell
(Get-EC2Instance -InstanceId <instance-id>).Instances.EnaSupport
```

**Enable or disable ENA support:**
```powershell
Edit-EC2InstanceAttribute -InstanceId <instance-id> -EnaSupport $true
Edit-EC2InstanceAttribute -InstanceId <instance-id> -EnaSupport $false
```

**Bulk check across multiple instances:**
```powershell
$instances = "i-0ded60d486f784339", "i-082c37e4c60c9d9f5"

foreach ($instance in $instances) {
  Write-Host "Instance ID: $instance ENA status:" (Get-EC2Instance -InstanceId $instance).Instances.EnaSupport
}
```

---

### 0. 🔗 Test SSM Connectivity

Validate that SSM Agent is reachable on all target instances before running any driver
installation.

```powershell
$instances = @(
    "i-1234567890abcdef0",
    "i-0987654321fedcba0",
    "i-0a1b2c3d4e5f67890"
)

$runPSCommand = Send-SSMCommand `
    -InstanceIds $instances `
    -DocumentName "AWS-RunPowerShellScript" `
    -Comment "Connection test" `
    -Parameter @{'commands'=@('hostname')}
```

---

### 1. 📊 Check Command Status

After each SSM command, verify the execution status.

**a) High-level status for all instances:**
```powershell
Get-SSMCommandInvocation -CommandId $runPSCommand.CommandId
(Get-SSMCommandInvocation -CommandId $runPSCommand.CommandId).instanceName
(Get-SSMCommandInvocation -CommandId $runPSCommand.CommandId).instanceID
```

**b) Detailed output for a specific instance:**
```powershell
(Get-SSMCommandInvocation `
    -CommandId $runPSCommand.CommandId `
    -Details $true `
    -InstanceId i-0ded60d486f784339 | Select -ExpandProperty CommandPlugins).output
```

**c) Via AWS Console:**

Navigate to: **AWS Systems Manager → Run Command → Command history**

> ⚠️ Repeat this status check after **every** step before proceeding.

---

### 2. 📦 Install PV Drivers

Downloads and silently installs the latest **AWS PV drivers**. Files are stored in
`C:\t3mp132`. Marker file `done-pv-drivers.txt` is created on completion.

```powershell
$runPSCommand = Send-SSMCommand `
    -InstanceIds $instances `
    -DocumentName "AWS-RunPowerShellScript" `
    -Comment "Install PV drivers" `
    -Parameter @{'commands'=@(
        'New-Item -Type Directory -Path C:\t3mp132',
        'Start-Sleep 1',
        '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12',
        'Start-Sleep 1',
        'Invoke-WebRequest -Uri "https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/Latest/AWSPVDriver.zip" -OutFile C:\t3mp132\AWSPVDriver.zip',
        'Start-Sleep 1',
        'Expand-Archive -LiteralPath C:\t3mp132\AWSPVDriver.zip -DestinationPath "C:\t3mp132\AWSPVDriver"',
        'Start-Sleep 1',
        'C:\t3mp132\AWSPVDriver\install.ps1 -quiet',
        'Start-Sleep 1',
        'New-Item -Type file -Path C:\t3mp132\done-pv-drivers.txt'
    )}

Get-SSMCommandInvocation -CommandId $runPSCommand.CommandId
```

---

### 3. 🌐 Install ENA and NVMe Drivers

Downloads and installs the latest **AWS ENA Network Driver** and **AWS NVMe Driver**.
Marker file `done-ena-nvme.txt` is created upon completion.

```powershell
$runPSCommand = Send-SSMCommand `
    -InstanceIds $instances `
    -DocumentName "AWS-RunPowerShellScript" `
    -Comment "Install ENA and NVME drivers" `
    -Parameter @{'commands'=@(
        '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12',
        'Start-Sleep 1',
        'Invoke-WebRequest -Uri "https://s3.amazonaws.com/ec2-windows-drivers-downloads/ENA/Latest/AwsEnaNetworkDriver.zip" -OutFile C:\t3mp132\AwsEnaNetworkDriver.zip',
        'Start-Sleep 1',
        'Expand-Archive -LiteralPath C:\t3mp132\AwsEnaNetworkDriver.zip -DestinationPath "C:\t3mp132\AwsEnaNetworkDriver"',
        'Start-Sleep 1',
        'C:\t3mp132\AwsEnaNetworkDriver\install.ps1',
        'Start-Sleep 1',
        'Invoke-WebRequest -Uri "https://s3.amazonaws.com/ec2-windows-drivers-downloads/NVMe/Latest/AWSNVMe.zip" -OutFile C:\t3mp132\AWSNVMe.zip',
        'Start-Sleep 1',
        'Expand-Archive -LiteralPath C:\t3mp132\AWSNVMe.zip -DestinationPath "C:\t3mp132\AWSNVMe"',
        'Start-Sleep 1',
        'C:\t3mp132\AWSNVMe\install.ps1 -force',
        'Start-Sleep 1',
        'New-Item -Type file -Path C:\t3mp132\done-ena-nvme.txt'
    )}
```

---

### 4. 🔄 Reboot Instances

Triggers a remote reboot to apply all installed drivers. Wait for instances to come
back online before proceeding.

```powershell
$runPSCommand = Send-SSMCommand `
    -InstanceIds $instances `
    -DocumentName "AWS-RunPowerShellScript" `
    -Comment "Reboot instance" `
    -Parameter @{'commands'=@('shutdown -r -t 10')}
```

---

### 5. 🧹 Remove Temporary Files

Cleans up the `C:\t3mp132` working directory from all instances.

```powershell
$runPSCommand = Send-SSMCommand `
    -InstanceIds $instances `
    -DocumentName "AWS-RunPowerShellScript" `
    -Comment "Remove files from C:\ drive" `
    -Parameter @{'commands'=@('Remove-Item -Force -Recurse C:\t3mp132')}
```

---

### 6. 🔀 Change Instance Type

Stops each instance, modifies the instance type, and starts it back up.

```powershell
foreach ($instance in $instances) {
    Stop-EC2Instance -InstanceId $instance
    Edit-EC2InstanceAttribute -InstanceId $instance -InstanceType t3.medium
    Start-EC2Instance -InstanceId $instance
}
```

---

## ✅ Pre-run Checklist

- [ ] 🔍 ENA support flag verified and set on all instances (must be **stopped**)
- [ ] 🔗 SSM connectivity tested successfully for all instances
- [ ] 🪪 IAM Instance Profile with `AmazonSSMManagedInstanceCore` attached
- [ ] 📝 `$instances` array updated with correct Instance IDs
- [ ] 🌍 Target instance type confirmed to be ENA/NVMe compatible (e.g., `t3`)
- [ ] 🔄 Post-reboot: instances confirmed back online before changing instance type
- [ ] ✔️ Command status checked after **each** step before proceeding
