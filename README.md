# Ubuntu LTS Upgrade Scripts

Automated upgrade scripts for Ubuntu LTS versions (20.04 -> 22.04 -> 24.04)

## Features

- Fully automated, unattended upgrade process
- Pre-upgrade cleanup and database backup
- Handles multiple reboots automatically
- Comprehensive error handling and logging
- System verification at each step

## Installation

```bash
git clone https://github.com/liorshop/UpgradeUbuntu.git /update/upgrade
cd /update/upgrade
chmod +x *.sh
```

## Usage

```bash
sudo ./main.sh
```
