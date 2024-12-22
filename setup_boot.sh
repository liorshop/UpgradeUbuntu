#!/bin/bash

# Source common configuration
SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SOURCE_DIR}/common.sh"
source "${SOURCE_DIR}/logger.sh"

COMPONENT="BOOT"

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

    # Check if service file was created successfully
    if [ ! -f "${service_file}" ]; then
        log "ERROR" "${COMPONENT}" "Failed to create service file"
        return 1
    fi

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

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_next_boot
    exit $?
fi