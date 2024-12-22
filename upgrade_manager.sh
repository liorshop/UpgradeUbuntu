#!/bin/bash

set -euo pipefail

# Base paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPONENT="UPGRADE"

# Source required modules
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"

# Pre-upgrade system validation
validate_system() {
    log "INFO" "${COMPONENT}" "Validating system state"
    local checks_failed=0
    
    # Check system state with more detail
    local system_state=$(systemctl is-system-running)
    log "INFO" "${COMPONENT}" "Current system state: ${system_state}"
    
    # List any failed units
    local failed_units=$(systemctl list-units --state=failed --no-pager)
    if [ -n "${failed_units}" ]; then
        log "WARN" "${COMPONENT}" "Failed units found:\n${failed_units}"
        # Don't fail for this, just warn
    fi
    
    # Check package system
    if ! dpkg --audit >/dev/null 2>&1; then
        log "ERROR" "${COMPONENT}" "Package system has issues"
        ((checks_failed++))
    fi
    
    # Verify no package operations are in progress
    if fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
        log "ERROR" "${COMPONENT}" "Package system is locked"
        ((checks_failed++))
    fi
    
    # Check disk space
    local required_space=10000000  # 10GB
    local available_space=$(df /usr -k | awk 'NR==2 {print $4}')
    if [ "${available_space}" -lt "${required_space}" ]; then
        log "ERROR" "${COMPONENT}" "Insufficient disk space"
        ((checks_failed++))
    fi

    # Network connectivity check
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "ERROR" "${COMPONENT}" "No network connectivity"
        ((checks_failed++))
    fi

    # Package system checks
    if dpkg -l | grep -q '^.H'; then
        log "ERROR" "${COMPONENT}" "Found packages on hold"
        ((checks_failed++))
    fi

    if dpkg -l | grep -q '^.F'; then
        log "ERROR" "${COMPONENT}" "Found failed package installations"
        ((checks_failed++))
    fi

    # Allow degraded state but log it
    if ! systemctl is-system-running | grep -qE 'running|degraded'; then
        log "WARN" "${COMPONENT}" "System state is: ${system_state} - this is acceptable for upgrade"
    fi
    
    if [ ${checks_failed} -gt 0 ]; then
        log "ERROR" "${COMPONENT}" "System validation failed with ${checks_failed} errors"
        return 1
    fi
    
    log "INFO" "${COMPONENT}" "System validation passed"
    return 0
}

# Setup next boot configuration
setup_next_boot() {
    log "INFO" "${COMPONENT}" "Setting up next boot configuration"
    
    # Ensure systemd directory exists
    mkdir -p /etc/systemd/system
    
    # Create service file
    local service_file="/etc/systemd/system/ubuntu-upgrade.service"
    
    log "INFO" "${COMPONENT}" "Creating systemd service file"
    cat > "${service_file}" << EOF
[Unit]
Description=Ubuntu Upgrade Process
After=network-online.target postgresql.service
Wants=network-online.target
ConditionPathExists=${BASE_DIR}/upgrade_manager.sh

[Service]
Type=oneshot
ExecStart=/bin/bash ${BASE_DIR}/upgrade_manager.sh
RemainAfterExit=yes
TimeoutStartSec=3600
WorkingDirectory=${BASE_DIR}
KillMode=process
Restart=no

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chmod 644 "${service_file}"
    
    # Reload systemd
    log "INFO" "${COMPONENT}" "Reloading systemd configuration"
    systemctl daemon-reload || return 1
    
    # Enable service
    log "INFO" "${COMPONENT}" "Enabling upgrade service"
    systemctl enable ubuntu-upgrade.service || return 1
    
    log "INFO" "${COMPONENT}" "Next boot configuration completed successfully"
    return 0
}

# Process initial state
process_initial_state() {
    log "INFO" "${COMPONENT}" "Processing initial state"
    
    # Verify cleanup script exists and is executable
    if [ ! -x "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" ]; then
        log "ERROR" "${COMPONENT}" "pre_upgrade_cleanup.sh not found or not executable"
        return 1
    fi

    # Run cleanup with timeout and capture output
    local cleanup_output
    if ! cleanup_output=$(timeout 3600 "${SCRIPT_DIR}/pre_upgrade_cleanup.sh" 2>&1); then
        log "ERROR" "${COMPONENT}" "Cleanup script failed or timed out with output:\n${cleanup_output}"
        return 1
    fi

    save_state "22.04" || return 1
    setup_next_boot || return 1
    
    log "INFO" "${COMPONENT}" "Initial preparation complete"
    shutdown -r +1 "Rebooting for upgrade to 22.04"
}

# Process 22.04 upgrade
process_2204_state() {
    log "INFO" "${COMPONENT}" "Processing 22.04 upgrade"
    
    if perform_upgrade "22.04"; then
        save_state "24.04" || return 1
        log "INFO" "${COMPONENT}" "22.04 upgrade complete"
        shutdown -r +1 "Rebooting for 24.04 upgrade"
    else
        log "ERROR" "${COMPONENT}" "Failed to upgrade to 22.04"
        return 1
    fi
}

# Process 24.04 upgrade
process_2404_state() {
    log "INFO" "${COMPONENT}" "Processing 24.04 upgrade"
    
    if perform_upgrade "24.04"; then
        save_state "setup" || return 1
        log "INFO" "${COMPONENT}" "24.04 upgrade complete"
        shutdown -r +1 "Rebooting for post-upgrade setup"
    else
        log "ERROR" "${COMPONENT}" "Failed to upgrade to 24.04"
        return 1
    fi
}

# Process setup state
process_setup_state() {
    log "INFO" "${COMPONENT}" "Processing post-upgrade setup"
    
    if [ ! -x "${SCRIPT_DIR}/post_upgrade_setup.sh" ]; then
        log "ERROR" "${COMPONENT}" "post_upgrade_setup.sh not found or not executable"
        return 1
    fi

    "${SCRIPT_DIR}/post_upgrade_setup.sh" || return 1
    
    # Cleanup
    rm -f "${STATE_FILE}"
    systemctl disable ubuntu-upgrade.service
    rm -f /etc/systemd/system/ubuntu-upgrade.service
    
    log "INFO" "${COMPONENT}" "Upgrade process completed"
    shutdown -r +1 "Final reboot after setup"
}

# Main execution
main() {
    # Initialize
    initialize
    acquire_lock || exit 1
    trap cleanup EXIT
    
    # Get current state
    current_state=$(get_state) || exit 1
    log "INFO" "${COMPONENT}" "Starting upgrade process in state: ${current_state}"
    
    # Validate system
    validate_system || exit 1
    
    # Process state
    case "${current_state}" in
        "initial")
            process_initial_state
            ;;
        "22.04")
            process_2204_state
            ;;
        "24.04")
            process_2404_state
            ;;
        "setup")
            process_setup_state
            ;;
        *)
            log "ERROR" "${COMPONENT}" "Invalid state: ${current_state}"
            exit 1
            ;;
    esac
}

# Set up error handling
trap 'log "ERROR" "${COMPONENT}" "Script failed on line $LINENO"' ERR

# Run main
main "$@"
