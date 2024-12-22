#!/bin/bash

set -euo pipefail

# Base paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPONENT="UPGRADE"

# Source required modules
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"
source "${SCRIPT_DIR}/setup_boot.sh"

# Pre-upgrade system validation
validate_system() {
    log "INFO" "${COMPONENT}" "Validating system state"
    
    local checks=(
        "! dpkg -l | grep -q '^.H'"  # No packages on hold
        "! dpkg -l | grep -q '^.F'"  # No failed installations
        "! ps aux | grep -v grep | grep -q 'apt\|dpkg'"  # No package operations
        "systemctl is-system-running | grep -qE 'running|degraded'"  # System operational
    )

    for check in "${checks[@]}"; do
        if ! eval "${check}"; then
            log "ERROR" "${COMPONENT}" "System validation failed: ${check}"
            return 1
        fi
    done

    return 0
}

# Process initial state
process_initial_state() {
    log "INFO" "${COMPONENT}" "Processing initial state"
    
    # Verify cleanup script
    if [ ! -x "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" ]; then
        log "ERROR" "${COMPONENT}" "pre_upgrade_cleanup.sh not found or not executable"
        return 1
    fi

    # Run cleanup with timeout
    timeout 3600 "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" || {
        log "ERROR" "${COMPONENT}" "Cleanup script failed or timed out"
        return 1
    }

    save_state "22.04" || return 1
    
    if ! setup_next_boot; then
        log "ERROR" "${COMPONENT}" "Failed to setup next boot configuration"
        return 1
    fi
    
    log "INFO" "${COMPONENT}" "Initial preparation complete"
    shutdown -r +1 "Rebooting for upgrade to 22.04"
}

# Rest of the script remains the same...