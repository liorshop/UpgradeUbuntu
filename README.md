# Ubuntu LTS Upgrade Scripts

Automated upgrade scripts for Ubuntu LTS versions (20.04 -> 22.04 -> 24.04)

## Features

- Fully automated, unattended upgrade process
- Pre-upgrade cleanup and database backup
- Handles multiple reboots automatically
- Comprehensive error handling and logging
- System verification at each step
- Automatic service and package management

## Prerequisites

- Ubuntu 20.04 LTS
- Root access
- Minimum 10GB free space
- Stable internet connection

## Pre-upgrade Actions

The script will automatically:
1. Backup PostgreSQL database 'bobe'
2. Remove specified packages:
   - postgresql*
   - monit*
   - mongodb*
   - openjdk*
3. Clean up related source lists
4. Prepare system for upgrade

## Installation

```bash
git clone https://github.com/liorshop/UpgradeUbuntu.git /update/upgrade
cd /update/upgrade
chmod +x *.sh
```

## Usage

Start the upgrade process:
```bash
sudo ./main.sh
```

### Logs

All operations are logged to `/update/upgrade/upgrade.log`

### Backups

Database backups are stored in `/update/upgrade/backups/`

## Safety Features

- Automatic rollback on failure
- Service state verification
- Package dependency checks
- Database backup verification
- Disk space monitoring

## License

MIT License