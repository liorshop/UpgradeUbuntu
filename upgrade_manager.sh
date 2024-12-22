#!/bin/bash

set -euo pipefail

# Base paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPONENT="UPGRADE"

# Source required modules
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"

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
    if ! systemctl daemon-reload; then
        log "ERROR" "${COMPONENT}" "Failed to reload systemd configuration"
        return 1
    fi
    
    # Enable service
    log "INFO" "${COMPONENT}" "Enabling upgrade service"
    if ! systemctl enable ubuntu-upgrade.service; then
        log "ERROR" "${COMPONENT}" "Failed to enable upgrade service"
        return 1
    fi
    
    log "INFO" "${COMPONENT}" "Next boot configuration completed successfully"
    return 0
}

# Rest of upgrade_manager.sh functions...

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

# Process final setup
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

# Error handler
handle_error() {
    local exit_code=$1
    local line_number=$2
    local source_file=$3
    shift 3
    local func_stack=("$@")
    
    log_stack_trace "ERROR" "${COMPONENT}" "Error in ${source_file} line ${line_number}"
    
    # Attempt recovery
    dpkg --configure -a || true
    apt-get install -f -y || true
    
    exit "${exit_code}"
}

trap 'handle_error $? ${LINENO} ${BASH_SOURCE} ${FUNCNAME[*]}' ERR

# Run main
main "$@"