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

# Constants
MAX_APT_ATTEMPTS=5
APT_RETRY_DELAY=30
UPGRADE_TIMEOUT=7200  # 2 hours

# Clean package locks and processes
clean_package_system() {
    local component="$COMPONENT"
    log "INFO" "$component" "Cleaning package management system"
    
    # Kill stuck processes
    for pid in $(lsof /var/lib/dpkg/lock-frontend 2>/dev/null | awk 'NR>1 {print $2}'); do
        kill -9 "$pid" 2>/dev/null || true
    done
    
    # Remove locks
    rm -f /var/lib/apt/lists/lock
    rm -f /var/lib/dpkg/lock*
    rm -f /var/cache/apt/archives/lock
    
    # Wait for processes to finish
    local wait_count=0
    while pgrep -f "^apt|^apt-get|^dpkg" >/dev/null; do
        log "WARN" "$component" "Waiting for package operations to complete..."
        sleep 5
        wait_count=$((wait_count + 1))
        if [ $wait_count -ge 12 ]; then  # 1 minute max wait
            log "WARN" "$component" "Forcefully killing package processes"
            pkill -9 -f "^apt|^apt-get|^dpkg" || true
            break
        fi
    done
    
    # Fix interrupted dpkg
    dpkg --configure -a || true
}

# Verify system services
verify_system_state() {
    local component="$COMPONENT"
    local critical_services=("systemd" "networking")
    local failed=0

    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "$component" "Critical service $service is not running"
            failed=1
        fi
    done

    return $failed
}

# Retry mechanism for apt operations
apt_retry() {
    local cmd="$1"
    local attempt=1
    local component="$COMPONENT"
    local delay=$APT_RETRY_DELAY
    
    while [ $attempt -le $MAX_APT_ATTEMPTS ]; do
        log "INFO" "$component" "Attempt $attempt of $MAX_APT_ATTEMPTS: $cmd"
        
        clean_package_system
        
        # Try the command with timeout
        if timeout 300 bash -c "$cmd"; then
            log "INFO" "$component" "Command succeeded"
            return 0
        fi
        
        log "WARN" "$component" "Command failed, retrying in $delay seconds"
        sleep $delay
        delay=$((delay * 2))  # Exponential backoff
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "$component" "Command failed after $MAX_APT_ATTEMPTS attempts: $cmd"
    return 1
}

# Fix sources.list if needed
fix_sources_list() {
    local component="$COMPONENT"
    local fixed=0
    
    if ! grep -q '^deb.*main' /etc/apt/sources.list; then
        log "WARN" "$component" "Fixing sources.list"
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        
        cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ focal-security main restricted universe multiverse
EOF
        fixed=1
    fi
    
    # Verify the sources list works
    if ! timeout 30 apt-get update --print-uris > /dev/null; then
        log "ERROR" "$component" "Sources list verification failed"
        if [ $fixed -eq 1 ] && [ -f /etc/apt/sources.list.bak ]; then
            mv /etc/apt/sources.list.bak /etc/apt/sources.list
        fi
        return 1
    fi
    
    return 0
}

# Perform upgrade with detailed logging
perform_upgrade() {
    local target_version="$1"
    local component="$COMPONENT"
    log "INFO" "$component" "Starting upgrade to ${target_version}"
    
    # Configure release upgrades
    sed -i 's/Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades
    
    # Start system monitoring
    start_monitoring
    
    # Set environment variables
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export UCF_FORCE_CONFFNEW=1
    export APT_LISTCHANGES_FRONTEND=none
    
    # Verify system state
    if ! verify_system_state; then
        log "ERROR" "$component" "System state verification failed"
        stop_monitoring
        return 1
    fi
    
    # Fix sources.list
    if ! fix_sources_list; then
        log "ERROR" "$component" "Failed to fix sources.list"
        stop_monitoring
        return 1
    fi
    
    # Update package lists with retry
    log "INFO" "$component" "Updating package lists"
    if ! apt_retry "apt-get update"; then
        log "ERROR" "$component" "Failed to update package lists"
        stop_monitoring
        return 1
    fi
    
    # Fix broken packages
    log "INFO" "$component" "Fixing broken packages"
    if ! apt_retry "dpkg --configure -a && apt-get install -f -y"; then
        log "ERROR" "$component" "Failed to fix broken packages"
        stop_monitoring
        return 1
    fi
    
    # Create upgrade log directory
    local upgrade_log_dir="${LOG_DIR}/upgrade_details"
    mkdir -p "${upgrade_log_dir}"
    local upgrade_log="${upgrade_log_dir}/upgrade_$(date +%Y%m%d_%H%M%S).log"
    
    # Perform upgrade
    log "INFO" "$component" "Running do-release-upgrade"
    if timeout $UPGRADE_TIMEOUT do-release-upgrade -f DistUpgradeViewNonInteractive -m server > "${upgrade_log}" 2>&1; then
        if [[ $(lsb_release -rs) == "${target_version}" ]]; then
            log "INFO" "$component" "Successfully upgraded to ${target_version}"
            stop_monitoring
            return 0
        else
            local current_version=$(lsb_release -rs)
            log "ERROR" "$component" "Version mismatch after upgrade. Expected: ${target_version}, Got: ${current_version}"
            tail -n 50 "${upgrade_log}" | while read -r line; do
                log "ERROR" "$component" "  ${line}"
            done
            stop_monitoring
            return 1
        fi
    fi
    
    log "ERROR" "$component" "Upgrade command failed"
    tail -n 50 "${upgrade_log}" | while read -r line; do
        log "ERROR" "$component" "  ${line}"
    done
    stop_monitoring
    return 1
}

# Main execution
main() {
    local component="$COMPONENT"
    log "INFO" "$component" "Starting upgrade process"
    
    # Check if we are root
    if [ "$(id -u)" != "0" ]; then
        log "ERROR" "$component" "This script must be run as root"
        exit 1
    fi
    
    # Check current version
    local current_version=$(lsb_release -rs)
    if [[ "$current_version" != "20.04" ]]; then
        log "ERROR" "$component" "This script is only for upgrading from Ubuntu 20.04"
        exit 1
    fi
    
    # Perform upgrade
    if ! perform_upgrade "22.04"; then
        log "ERROR" "$component" "Upgrade to 22.04 failed"
        exit 1
    fi
    
    log "INFO" "$component" "Upgrade process completed successfully"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi