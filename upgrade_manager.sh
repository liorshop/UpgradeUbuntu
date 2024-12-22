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
    if [ -f "${STATE_FILE}" ]; then
        local state=$(cat "${STATE_FILE}")
        log "INFO" "System ready for upgrade to: ${state}"
        echo "${state}"
    else
        log "INFO" "Starting initial upgrade process"
        echo "initial"
    fi
}

# Save state
save_state() {
    echo "$1" > "${STATE_FILE}"
    log "INFO" "System ready for upgrade to: $1"
}

# Main execution
main() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Script must be run as root"
        exit 1
    fi

    mkdir -p "${BASE_DIR}"
    
    current_state=$(get_state)
    
    case "${current_state}" in
        "initial")
            pre_upgrade_checks
            if [ ! -x "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" ]; then
                log "ERROR" "pre_upgrade_cleanup.sh not found or not executable"
                exit 1
            fi
            
            "${SCRIPT_DIR}/pre_upgrade_cleanup.sh"
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
                save_state "setup"
                log "INFO" "24.04 upgrade complete. Rebooting in 1 minute..."
                shutdown -r +1 "Rebooting for post-upgrade setup"
            else
                log "ERROR" "Failed to upgrade to 24.04"
                exit 1
            fi
            ;;
            
        "setup")
            log "INFO" "Starting post-upgrade setup"
            if [ ! -x "${SCRIPT_DIR}/post_upgrade_setup.sh" ]; then
                log "ERROR" "post_upgrade_setup.sh not found or not executable"
                exit 1
            fi
            
            "${SCRIPT_DIR}/post_upgrade_setup.sh"
            rm -f "${STATE_FILE}"
            systemctl disable ubuntu-upgrade.service
            rm -f /etc/systemd/system/ubuntu-upgrade.service
            log "INFO" "Upgrade process completed. Final reboot in 1 minute..."
            shutdown -r +1 "Final reboot after setup"
            ;;
            
        *)
            log "ERROR" "Unknown state: ${current_state}"
            exit 1
            ;;
    esac
}

# Run main function with error handling
trap 'log "ERROR" "Script failed on line $LINENO"' ERR
main "$@"