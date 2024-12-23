#!/bin/bash

set -euo pipefail

# Base paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPONENT="UPGRADE"

# Source required modules
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"
source "${SCRIPT_DIR}/monitor.sh"

# Add retry mechanism for apt operations
apt_retry() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    local delay=30
    
    while [ $attempt -le $max_attempts ]; do
        log "INFO" "${COMPONENT}" "Attempt $attempt of $max_attempts: $cmd"
        
        # Clear possible locks first
        rm -f /var/lib/apt/lists/lock
        rm -f /var/lib/dpkg/lock
        rm -f /var/lib/dpkg/lock-frontend
        
        # Kill any stuck apt/dpkg processes
        killall apt apt-get dpkg 2>/dev/null || true
        
        # Wait for any existing apt/dpkg processes to finish
        while pgrep -f "^apt|^apt-get|^dpkg" >/dev/null; do
            log "WARN" "${COMPONENT}" "Waiting for other package operations to complete..."
            sleep 10
        done
        
        # Try to repair package system
        dpkg --configure -a || true
        
        if eval "$cmd"; then
            return 0
        else
            log "WARN" "${COMPONENT}" "Command failed, attempt $attempt of $max_attempts"
            if [ $attempt -lt $max_attempts ]; then
                log "INFO" "${COMPONENT}" "Waiting ${delay} seconds before retry..."
                sleep $delay
            fi
        fi
        
        attempt=$((attempt + 1))
        delay=$((delay * 2))  # Exponential backoff
    done
    
    log "ERROR" "${COMPONENT}" "Command failed after $max_attempts attempts: $cmd"
    return 1
}

# Perform upgrade with detailed logging
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
    
    # Update package lists with retry mechanism
    log "INFO" "${COMPONENT}" "Updating package lists"
    
    # Fix sources.list if needed
    if ! grep -q '^deb.*main' /etc/apt/sources.list; then
        log "WARN" "${COMPONENT}" "Fixing sources.list"
        cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ focal-security main restricted universe multiverse
EOF
    fi
    
    # Clean and update package lists
    if ! apt_retry "apt-get clean && apt-get update"; then
        log "ERROR" "${COMPONENT}" "Failed to update package lists"
        return 1
    fi
    
    # Fix any broken packages before upgrade
    log "INFO" "${COMPONENT}" "Checking for broken packages"
    apt_retry "dpkg --configure -a"
    apt_retry "apt-get install -f -y"
    
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
            stop_monitoring
            return 1
        fi
    else
        log "ERROR" "${COMPONENT}" "Upgrade command failed"
        stop_monitoring
        return 1
    fi
}

# Rest of the file remains unchanged...
