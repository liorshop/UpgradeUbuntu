# Ubuntu LTS Upgrade Scripts

This repository contains a set of scripts to automate the upgrade process for Ubuntu LTS versions. The upgrade process is divided into multiple phases to handle system reboots and ensure a reliable upgrade.

## Important Note About LTS Upgrades

Ubuntu LTS upgrades must be performed sequentially:
- To upgrade from 20.04 to 24.04, you must first upgrade to 22.04
- After reaching 22.04, you can then upgrade to 24.04

This script package handles the 20.04 to 22.04 upgrade. For 24.04, you'll need to run the upgrade process again after successfully reaching 22.04.

## Features

- Fully unattended upgrade process
- Automatic handling of all prompts and configurations
- Phased upgrade process with automatic resume after reboots
- Comprehensive error handling and logging
- System health checks before upgrade
- Automatic backup of critical configurations
- Post-upgrade verification and cleanup

## Prerequisites

- Ubuntu 20.04 LTS system
- Root access
- At least 10GB of free disk space
- Stable internet connection

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/liorshop/UpgradeUbuntu.git /update/upgrade
   ```

2. Make scripts executable:
   ```bash
   chmod +x /update/upgrade/*.sh
   ```

## Usage

Start the upgrade process by running:
```bash
sudo /update/upgrade/main.sh
```

The upgrade process will:
1. Prepare the system and perform initial checks
2. Configure for unattended upgrade
3. Upgrade the system to Ubuntu 22.04
4. Perform post-upgrade cleanup and verification

Logs are written to `/update/upgrade/upgrade.log`

## Error Handling

If an error occurs during the upgrade process:
1. The error will be logged to the upgrade log file
2. The script will terminate with an appropriate error message
3. The system will remain in a consistent state

## Next Steps After 22.04

After successfully upgrading to 22.04, wait until Ubuntu 24.04.1 is released (typically a few months after 24.04) before upgrading to 24.04. This ensures a more stable upgrade path.

## License

MIT License