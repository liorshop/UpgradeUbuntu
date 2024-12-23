#!/bin/bash

# ... [previous content remains the same until perform_upgrade function] ...

# Core upgrade function
perform_upgrade() {
    local target_version=$1
    log "INFO" "${COMPONENT}" "Starting upgrade to ${target_version}"
    
    # Configure release upgrades
    sed -i 's/Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades
    
    # Start system monitoring
    start_monitoring
    
    # Set environment variables
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export UCF_FORCE_CONFFNEW=1
    export APT_LISTCHANGES_FRONTEND=none
    
    # Update package lists first
    log "INFO" "${COMPONENT}" "Updating package lists"
    apt-get update || {
        log "ERROR" "${COMPONENT}" "Failed to update package lists"
        return 1
    }
    
    # Fix any broken packages before upgrade
    log "INFO" "${COMPONENT}" "Checking for broken packages"
    dpkg --configure -a || true
    apt-get install -f -y || true
    
    # Create upgrade log directory
    local upgrade_log_dir="${LOG_DIR}/upgrade_details"
    mkdir -p "${upgrade_log_dir}"
    local upgrade_log="${upgrade_log_dir}/upgrade_$(date +%Y%m%d_%H%M%S).log"
    
    # Perform upgrade with detailed logging
    log "INFO" "${COMPONENT}" "Running do-release-upgrade"
    if timeout 7200 do-release-upgrade -f DistUpgradeViewNonInteractive -m server > "${upgrade_log}" 2>&1; then
        # Verify upgrade success
        if [[ $(lsb_release -rs) == "${target_version}" ]]; then
            log "INFO" "${COMPONENT}" "Successfully upgraded to ${target_version}"
            stop_monitoring
            return 0
        else
            local current_version=$(lsb_release -rs)
            log "ERROR" "${COMPONENT}" "Version mismatch after upgrade. Expected: ${target_version}, Got: ${current_version}"
            log "ERROR" "${COMPONENT}" "Upgrade log available at: ${upgrade_log}"
            
            # Extract relevant error information
            if [ -f "${upgrade_log}" ]; then
                log "ERROR" "${COMPONENT}" "Last 50 lines of upgrade log:"
                tail -n 50 "${upgrade_log}" | while read -r line; do
                    log "ERROR" "${COMPONENT}" "  ${line}"
                done
            fi
            
            stop_monitoring
            return 1
        fi
    else
        local exit_code=$?
        log "ERROR" "${COMPONENT}" "Upgrade command failed with exit code: ${exit_code}"
        log "ERROR" "${COMPONENT}" "Upgrade log available at: ${upgrade_log}"
        
        # Extract relevant error information
        if [ -f "${upgrade_log}" ]; then
            log "ERROR" "${COMPONENT}" "Last 50 lines of upgrade log:"
            tail -n 50 "${upgrade_log}" | while read -r line; do
                log "ERROR" "${COMPONENT}" "  ${line}"
            done
        fi
        
        # Check for common issues
        log "INFO" "${COMPONENT}" "Checking for common upgrade issues"
        
        # Check disk space
        local disk_space=$(df -h / | awk 'NR==2 {print $4}')
        log "INFO" "${COMPONENT}" "Available disk space: ${disk_space}"
        
        # Check package state
        local held_packages=$(dpkg -l | grep ^hi)
        if [ -n "${held_packages}" ]; then
            log "ERROR" "${COMPONENT}" "Found held packages:\n${held_packages}"
        fi
        
        # Check for locked dpkg
        if fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
            log "ERROR" "${COMPONENT}" "dpkg is locked by another process"
        fi
        
        # Check sources.list
        if ! grep -q '^deb.*main' /etc/apt/sources.list; then
            log "ERROR" "${COMPONENT}" "Main repository not found in sources.list"
        fi
        
        stop_monitoring
        return 1
    fi
}

# ... [rest of the script remains the same] ...
