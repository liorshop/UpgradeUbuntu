#!/bin/bash

# Phase 2: Perform the upgrade
set -euo pipefail

source $(dirname "$0")/common.sh

# Set up error handling
trap 'handle_error ${LINENO}' ERR

log "INFO" "Starting upgrade phase"

# Pre-configure debconf selections to avoid prompts
log "INFO" "Setting up unattended upgrade configurations"
cat > /tmp/debconf-selections << EOF
grub-pc grub-pc/install_devices_empty boolean false
grub-pc grub-pc/install_devices multiselect $(grub-probe --target=device /)
EOF

# Load debconf selections
debconf-set-selections /tmp/debconf-selections

# Export environment variables for unattended upgrade
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export UCF_FORCE_CONFFNEW=1
export APT_LISTCHANGES_FRONTEND=none

# Create config file for unattended-upgrades
cat > /etc/apt/apt.conf.d/99upgrade-settings << EOF
Dpkg::Options {
   "--force-confdef";
   "--force-confnew";
}
EOF

# Check if we can download the upgrade
log "INFO" "Checking upgrade availability"
if ! do-release-upgrade -c; then
    log "ERROR" "Upgrade to 22.04 not available"
    exit 1
fi

# Start the upgrade process
log "INFO" "Starting do-release-upgrade"
DEBIAN_FRONTEND=noninteractive \
do-release-upgrade -f DistUpgradeViewNonInteractive -m server -d << EOF
y
EOF

# Check if upgrade completed successfully
if [[ $(lsb_release -rs) == "22.04" ]]; then
    log "INFO" "Upgrade to Ubuntu 22.04 completed successfully"
    # Set up next phase
    bash "$(dirname "$0")/setup_next_boot.sh" phase3
    
    log "INFO" "Rebooting system in 1 minute to complete upgrade"
    shutdown -r +1 "System will reboot to complete Ubuntu upgrade process"
else
    log "ERROR" "Upgrade seems to have failed. Current version: $(lsb_release -rs)"
    exit 1
fi