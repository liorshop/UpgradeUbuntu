#!/bin/bash

set -euo pipefail

# Ensure we can find the common functions regardless of how we're called
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
STATE_FILE="${BASE_DIR}/.upgrade_state"

# Source common functions with absolute path
if [ -f "${SCRIPT_DIR}/common.sh" ]; then
    source "${SCRIPT_DIR}/common.sh"
else
    echo "ERROR: common.sh not found in ${SCRIPT_DIR}" >&2
    exit 1
fi

# Function to manage upgrade state
get_state() {
    if [ -f "${STATE_FILE}" ]; then
        cat "${STATE_FILE}"
    else
        echo "initial"
    fi
}

save_state() {
    echo "$1" > "${STATE_FILE}"
    log "INFO" "State saved: $1"
}

# Configure APT for non-interactive upgrades
configure_apt() {
    log "INFO" "Configuring APT for non-interactive upgrades"
    
    # Ensure directory exists
    mkdir -p /etc/apt/apt.conf.d

    cat > /etc/apt/apt.conf.d/99automatic-upgrades << EOF
APT::Get::Assume-Yes "true";
APT::Get::allow-downgrades "true";
APT::Get::allow-remove-essential "true";
DPkg::Options {
   "--force-confdef";
   "--force-confnew";
   "--force-confmiss";
}
DPkg::Lock::Timeout "60";
EOF
}

# Configure and start upgrade
prepare_upgrade() {
    log "INFO" "Preparing system for upgrade"
    
    # Update current system
    apt-get update || log "WARN" "apt-get update failed, continuing anyway"
    apt-get -y upgrade || log "WARN" "apt-get upgrade failed, continuing anyway"
    apt-get -y dist-upgrade || log "WARN" "apt-get dist-upgrade failed, continuing anyway"
    apt-get -y autoremove || true
    apt-get clean || true
    
    # Install required packages
    apt-get install -y update-manager-core || {
        log "ERROR" "Failed to install update-manager-core"
        exit 1
    }
}

# Configure GRUB for non-interactive updates
configure_grub() {
    log "INFO" "Configuring GRUB"
    DEVICE=$(grub-probe --target=device /)
    echo "grub-pc grub-pc/install_devices multiselect $DEVICE" | debconf-set-selections
}

# Perform the actual upgrade
perform_upgrade() {
    local target_version=$1
    log "INFO" "Starting upgrade to $target_version"
    
    sed -i 's/Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades
    
    # Run upgrade with maximum timeout and retries
    DEBIAN_FRONTEND=noninteractive \
    do-release-upgrade -f DistUpgradeViewNonInteractive -m server

    # Verify upgrade success
    if [[ $(lsb_release -rs) == "${target_version}" ]]; then
        log "INFO" "Successfully upgraded to ${target_version}"
        return 0
    else
        log "ERROR" "Failed to upgrade to ${target_version}. Current version: $(lsb_release -rs)"
        return 1
    fi
}

# Setup systemd service for next boot
setup_next_boot() {
    log "INFO" "Setting up next boot service"
    
    cat > /etc/systemd/system/ubuntu-upgrade.service << EOF
[Unit]
Description=Ubuntu Upgrade Process
After=network-online.target
Wants=network-online.target
ConditionPathExists=${BASE_DIR}/upgrade_manager.sh

[Service]
Type=oneshot
ExecStart=/bin/bash ${BASE_DIR}/upgrade_manager.sh
RemainAfterExit=yes
TimeoutStartSec=3600
WorkingDirectory=${BASE_DIR}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ubuntu-upgrade.service
}

# Main execution
main() {
    # Ensure we're root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        exit 1
    fi

    # Create required directories
    mkdir -p "${BASE_DIR}"
    
    # Get current state
    current_state=$(get_state)
    log "INFO" "Current upgrade state: ${current_state}"
    
    case "${current_state}" in
        "initial")
            log "INFO" "Starting initial upgrade process"
            # Ensure cleanup script exists and is executable
            if [ ! -x "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" ]; then
                log "ERROR" "pre_upgrade_cleanup.sh not found or not executable"
                exit 1
            fi
            
            "${SCRIPT_DIR}/pre_upgrade_cleanup.sh"
            configure_apt
            prepare_upgrade
            configure_grub
            save_state "22.04"
            setup_next_boot
            log "INFO" "Initial preparation complete. Rebooting in 1 minute..."
            shutdown -r +1 "Rebooting for upgrade to 22.04"
            ;;
            
        "22.04")
            if perform_upgrade "22.04"; then
                save_state "24.04"
                log "INFO" "22.04 upgrade complete. Rebooting in 1 minute..."
                shutdown -r +1 "Rebooting after 22.04 upgrade"
            else
                log "ERROR" "Failed to upgrade to 22.04"
                exit 1
            fi
            ;;
            
        "24.04")
            if perform_upgrade "24.04"; then
                log "INFO" "24.04 upgrade complete. Cleaning up..."
                systemctl disable ubuntu-upgrade.service
                rm -f /etc/systemd/system/ubuntu-upgrade.service
                rm -f "${STATE_FILE}"
                log "INFO" "Upgrade process completed successfully. Final reboot in 1 minute..."
                shutdown -r +1 "Final reboot after completing upgrade to 24.04"
            else
                log "ERROR" "Failed to upgrade to 24.04"
                exit 1
            fi
            ;;
            
        *)
            log "ERROR" "Unknown state: ${current_state}"
            exit 1
            ;;
    esac
}

# Set up error handling
trap 'log "ERROR" "Script failed on line $LINENO"' ERR

# Run main function
main "$@"
