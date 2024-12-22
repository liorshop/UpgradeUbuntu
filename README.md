# Ubuntu LTS Upgrade Scripts

Automated upgrade scripts for Ubuntu LTS versions (20.04 -> 22.04 -> 24.04)

## Active Script Components

- `upgrade_manager.sh` - **Main Entry Point**
  - Controls the entire upgrade process
  - Handles state management and reboots
  - Coordinates all other scripts

- `pre_upgrade_cleanup.sh`
  - Performs database backup (PostgreSQL - bobe database)
  - Removes unnecessary packages
  - Cleans up system services
  - Ensures auto-ssh remains active

- `logger.sh`
  - Enterprise-grade logging
  - Log rotation
  - Multi-level logging (INFO, ERROR, DEBUG, STAT)

- `monitor.sh`
  - System resource monitoring
  - Service health checks
  - Performance tracking

- `common.sh`
  - Shared functions and variables
  - Common utilities

## Legacy Files (Reference Only)
These files remain in the repository for reference but are not used in the upgrade process:
- `phase2_upgrade.sh` - Original phase 2 script (functionality now in upgrade_manager.sh)
- `main.sh` - Original main script (replaced by upgrade_manager.sh)

## Prerequisites

- Ubuntu 20.04 LTS
- Root access
- Minimum 10GB free space
- Stable internet connection

## Pre-upgrade Actions

The script will automatically:
1. Backup PostgreSQL database 'bobe'
2. Remove packages:
   - postgresql*
   - monit*
   - mongodb*
   - openjdk*
   - cups*
   - printer-driver-*
   - hplip*

3. Manage services:
   - Stops and disables most services
   - Preserves auto-ssh service (keeps running)
   - Cleanups service configurations

## Installation

```bash
git clone https://github.com/liorshop/UpgradeUbuntu.git /update/upgrade
cd /update/upgrade
chmod +x *.sh
```

## Usage

Start the upgrade process:
```bash
sudo /update/upgrade/upgrade_manager.sh
```

### Process Flow
1. Pre-upgrade cleanup
2. System preparation
3. Upgrade to 22.04
4. System verification
5. Upgrade to 24.04
6. Final verification

### Logs
- Main log: `/update/upgrade/logs/upgrade.log`
- Error log: `/update/upgrade/logs/error.log`
- Debug log: `/update/upgrade/logs/debug.log`
- Stats log: `/update/upgrade/logs/stats.log`

### Backups
Database backups are stored in `/update/upgrade/backups/`

## Notes
- The upgrade process is fully automated and unattended
- Multiple reboots will occur automatically
- auto-ssh service remains active throughout the process
- All operations are logged for tracking and debugging