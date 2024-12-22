# Ubuntu LTS Upgrade Scripts

Automated upgrade scripts for Ubuntu LTS versions (20.04 -> 22.04 -> 24.04)

## Pre-upgrade Actions

Before starting the upgrade, the script will:
1. Backup PostgreSQL database 'bobe'
2. Remove packages:
   - postgresql*
   - monit*
   - mongodb*
   - openjdk*
3. Clean up source lists
4. Prepare for upgrade

## Installation

```bash
git clone https://github.com/liorshop/UpgradeUbuntu.git /update/upgrade
cd /update/upgrade
chmod +x *.sh
```

## Usage

Start the upgrade:
```bash
sudo ./upgrade_manager.sh
```

### Process
1. Pre-upgrade cleanup
2. Upgrade to 22.04
3. System verification
4. Upgrade to 24.04
5. Final verification

### Logs
All operations are logged to `/update/upgrade/upgrade.log`

### Backups
Database backups are stored in `/update/upgrade/backups/`