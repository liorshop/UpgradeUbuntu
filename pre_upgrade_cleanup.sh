#!/bin/bash

# ... [previous content remains the same until cleanup_services] ...

# Service cleanup
cleanup_services() {
    log "INFO" "${COMPONENT}" "Starting services cleanup"
    
    # Stop and disable snapd services first
    log "INFO" "${COMPONENT}" "Stopping and disabling snapd services"
    local snapd_services=(
        "snapd.socket"
        "snapd.service"
        "snapd.seeded.service"
        "snapd.snap-repair.service"
        "snapd.snap-repair.timer"
        "snapd.refresh.timer"
        "snapd.refresh.service"
    )
    
    for service in "${snapd_services[@]}"; do
        log "INFO" "${COMPONENT}" "Processing snapd service: ${service}"
        systemctl stop "${service}" 2>/dev/null || true
        systemctl disable "${service}" 2>/dev/null || true
        systemctl mask "${service}" 2>/dev/null || true
        systemctl reset-failed "${service}" 2>/dev/null || true
    done
    
    # Kill any remaining snapd processes
    pkill -9 snapd || true
    
    # Other services to stop
    local services_to_stop=(
        "command-executor"
        "flexicore"
        "listensor"
        "recognition"
        "cups"
        "mongod"
        "monit"
        "postgresql"
    )

    # Keep auto-ssh running
    if ! systemctl is-active --quiet auto-ssh; then
        log "INFO" "${COMPONENT}" "Starting auto-ssh service"
        systemctl start auto-ssh || true
    fi
    systemctl enable auto-ssh || true

    # Stop and disable other services with verification
    for service in "${services_to_stop[@]}"; do
        if systemctl list-unit-files | grep -q "${service}"; then
            log "INFO" "${COMPONENT}" "Processing service: ${service}"
            
            # Stop the service
            if systemctl is-active --quiet "${service}"; then
                log "INFO" "${COMPONENT}" "Stopping ${service}"
                systemctl stop "${service}" 2>/dev/null || true
                sleep 2  # Give service time to stop
                
                # Verify it's stopped
                if systemctl is-active --quiet "${service}"; then
                    log "WARN" "${COMPONENT}" "Service ${service} still active, forcing stop"
                    systemctl kill "${service}" 2>/dev/null || true
                    sleep 1
                fi
            fi
            
            # Disable and mask
            if systemctl is-enabled --quiet "${service}" 2>/dev/null; then
                log "INFO" "${COMPONENT}" "Disabling ${service}"
                systemctl disable "${service}" 2>/dev/null || true
            fi
            systemctl mask "${service}" 2>/dev/null || true
            
            # Reset failed state if any
            systemctl reset-failed "${service}" 2>/dev/null || true
        fi
    done
    
    # Final verification
    for service in "${services_to_stop[@]}" "${snapd_services[@]}"; do
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            log "ERROR" "${COMPONENT}" "Service ${service} is still active"
        fi
    done
}

# Enhance package cleanup for snapd
cleanup_packages() {
    log "INFO" "${COMPONENT}" "Starting package cleanup"
    
    # Remove snaps first with verification
    log "INFO" "${COMPONENT}" "Removing snap packages"
    if command -v snap >/dev/null; then
        # List all snaps before removal
        local snap_list=$(snap list 2>/dev/null)
        log "INFO" "${COMPONENT}" "Current snap packages:\n${snap_list}"
        
        # Remove each snap
        snap list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r pkg; do
            log "INFO" "${COMPONENT}" "Removing snap: ${pkg}"
            snap remove --purge "${pkg}" || true
            sleep 2  # Give time for snap removal
        done
        
        # Verify all snaps are removed
        if snap list 2>/dev/null | grep -v "^Name"; then
            log "WARN" "${COMPONENT}" "Some snaps still present after removal"
        fi
    fi
    
    # Remove snapd package and verify
    log "INFO" "${COMPONENT}" "Removing snapd package"
    apt-get purge -y snapd || true
    if dpkg -l | grep -q snapd; then
        log "WARN" "${COMPONENT}" "snapd package still present, forcing removal"
        dpkg --force-all --purge snapd || true
    fi
    
    # Remove snap directories
    log "INFO" "${COMPONENT}" "Removing snap directories"
    rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /etc/snapd
    
    # Rest of package cleanup...
    
    [Previous package cleanup code continues...]
}

# ... [rest of the script remains the same] ...
