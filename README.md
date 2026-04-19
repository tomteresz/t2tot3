# t2tot3
# 🪟 aws-ec2-windows-driver-upgrade

PowerShell scripts for remotely installing and upgrading **AWS PV**, **ENA**,
and **NVMe** drivers on Windows EC2 instances via **AWS Systems Manager Run Command** —
enabling seamless migration from older instance generations (e.g., `t2`) to
modern ones (e.g., `t3`) without any RDP access or manual intervention.

## 🎯 Use Case

Preparing Windows EC2 instances for instance type upgrades requires the correct
drivers to be installed at the OS level beforehand. This toolset automates the
full process — from verifying ENA support and testing SSM connectivity, through
driver installation and reboot, to cleanup and final instance type change —
across multiple instances in a single run.
