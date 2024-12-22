#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="/update/upgrade"
STATE_FILE="${BASE_DIR}/.upgrade_state"
COMPONENT="UPGRADE"

source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/monitor.sh"

# Initialize logging
init_logging

# Get current state
get_state() {
    local current_state
    if [ -f "${STATE_FILE}" ]; then
        current_state=$(cat "${STATE_FILE}")
    else
        current_state="initial"
    fi
    log "INFO" "${COMPONENT}" "Current system state: ${current_state}"
    echo "${current_state}"
}

# Save state
save_state() {
    local new_state=$1
    echo "${new_state}" > "${STATE_FILE}"
    log "INFO" "${COMPONENT}" "State updated to: ${new_state}"
}

# Pre-upgrade checks
pre_upgrade_checks() {
    log "INFO" "${COMPONENT}" "Performing pre-upgrade checks"
    
    # Check disk space
    local required_space=10000000  # 10GB in KB
    local available_space=$(df /usr -k | awk 'NR==2 {print $4}')
    
    if [ "${available_space}" -lt "${required_space}" ]; then
        log "ERROR" "${COMPONENT}" "Insufficient disk space. Required: 10GB, Available: $(( available_space / 1024 / 1024 ))GB"
        exit 1
    fi
    
    # Check network connectivity
    if ! check_network; then
        log "ERROR" "${COMPONENT}" "Network check failed"
        exit 1
    fi
}

# Setup next boot
setup_next_boot() {
    log "INFO" "${COMPONENT}" "Setting up next boot configuration"
    
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

# Perform upgrade
perform_upgrade() {
    local target_version=$1
    log "INFO" "${COMPONENT}" "Starting upgrade to ${target_version}"
    
    sed -i 's/Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades
    
    DEBIAN_FRONTEND=noninteractive \
    do-release-upgrade -f DistUpgradeViewNonInteractive -m server

    if [[ $(lsb_release -rs) == "${target_version}" ]]; then
        log "INFO" "${COMPONENT}" "Successfully upgraded to ${target_version}"
        return 0
    else
        log "ERROR" "${COMPONENT}" "Failed to upgrade to ${target_version}. Current version: $(lsb_release -rs)"
        return 1
    fi
}

# Main execution
main() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "${COMPONENT}" "Script must be run as root"
        exit 1
    fi

    mkdir -p "${BASE_DIR}"
    
    current_state=$(get_state)
    
    case "${current_state}" in
        "initial")
            pre_upgrade_checks
            if [ ! -x "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" ]; then
                log "ERROR" "${COMPONENT}" "pre_upgrade_cleanup.sh not found or not executable"
                exit 1
            fi
            
            "${SCRIPT_DIR}/pre_upgrade_cleanup.sh"
            save_state "22.04"
            setup_next_boot
            log "INFO" "${COMPONENT}" "Initial preparation complete. Rebooting in 1 minute..."
            shutdown -r +1 "Rebooting for upgrade to 22.04"
            ;;
            
        "22.04")
            if perform_upgrade "22.04"; then
                save_state "24.04"
                log "INFO" "${COMPONENT}" "22.04 upgrade complete. Rebooting in 1 minute..."
                shutdown -r +1 "Rebooting after 22.04 upgrade"
            else
                log "ERROR" "${COMPONENT}" "Failed to upgrade to 22.04"
                exit 1
            fi
            ;;
            
        "24.04")
            if perform_upgrade "24.04"; then
                save_state "setup"
                log "INFO" "${COMPONENT}" "24.04 upgrade complete. Rebooting in 1 minute..."
                shutdown -r +1 "Rebooting for post-upgrade setup"
            else
                log "ERROR" "${COMPONENT}" "Failed to upgrade to 24.04"
                exit 1
            fi
            ;;
            
        "setup")
            log "INFO" "${COMPONENT}" "Starting post-upgrade setup"
            if [ ! -x "${SCRIPT_DIR}/post_upgrade_setup.sh" ]; then
                log "ERROR" "${COMPONENT}" "post_upgrade_setup.sh not found or not executable"
                exit 1
            fi
            
            "${SCRIPT_DIR}/post_upgrade_setup.sh"
            rm -f "${STATE_FILE}"
            systemctl disable ubuntu-upgrade.service
            rm -f /etc/systemd/system/ubuntu-upgrade.service
            log "INFO" "${COMPONENT}" "Upgrade process completed. Final reboot in 1 minute..."
            shutdown -r +1 "Final reboot after setup"
            ;;
            
        *)
            log "ERROR" "${COMPONENT}" "Unknown state: ${current_state}"
            exit 1
            ;;
    esac
}

# Run main function with error handling
trap 'log "ERROR" "${COMPONENT}" "Script failed on line $LINENO"' ERR
main "$@"