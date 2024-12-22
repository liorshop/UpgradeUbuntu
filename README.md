# Ubuntu LTS Upgrade Scripts

Automated upgrade scripts for Ubuntu LTS versions (20.04 -> 22.04 -> 24.04)

## Core Components

### Main Scripts
- `upgrade_manager.sh` - Main controller
- `pre_upgrade_cleanup.sh` - Pre-upgrade cleanup
- `post_upgrade_setup.sh` - Post-upgrade setup

### Support Modules
- `common.sh` - Shared configurations
- `logger.sh` - Enterprise logging system
- `state_manager.sh` - State management
- `monitor.sh` - System monitoring

## Pre-upgrade Actions

Before starting the upgrade, the script will:
1. Back up PostgreSQL database 'bobe'
   - Verifies backup success
   - Stops if backup fails

2. Remove packages:
   - postgresql*
   - monit*
   - mongodb*
   - openjdk*
   - cups*
   - snap*

3. Manage services:
   - Stops and disables most services
   - Preserves auto-ssh service
   - Cleanups service configurations

## Installation

```bash
git clone https://github.com/liorshop/UpgradeUbuntu.git /update/upgrade
cd /update/upgrade
chmod +x *.sh
```

## Usage

Start the upgrade:
```bash
sudo /update/upgrade/upgrade_manager.sh
```

### Process Flow
1. Pre-upgrade verification
2. Database backup (required)
3. System cleanup
4. Upgrade to 22.04
5. System verification
6. Upgrade to 24.04
7. Final setup

### Logs
- Main log: `/update/upgrade/logs/upgrade.log`
- Error log: `/update/upgrade/logs/error.log`
- Debug log: `/update/upgrade/logs/debug.log`
- Stats log: `/update/upgrade/logs/stats.log`

### Backups
Database backups are stored in `/update/upgrade/backups/`

## Safety Features

1. Backup Verification
   - Checks backup existence
   - Verifies backup size
   - Stops if backup fails

2. Service Protection
   - Preserves critical services
   - Maintains SSH access
   - Handles service dependencies

3. Error Recovery
   - Automatic cleanup on failure
   - State preservation
   - Service restoration

## Enterprise Features

1. Comprehensive Logging
   - Multi-level logging
   - Error tracking
   - Performance monitoring

2. State Management
   - Atomic state updates
   - Progress tracking
   - Recovery points

3. Process Control
   - Lock management
   - Resource monitoring
   - Service orchestration

## Notes
- The upgrade process is fully automated and unattended
- Multiple reboots will occur automatically
- auto-ssh service remains active throughout
- All operations are logged for audit