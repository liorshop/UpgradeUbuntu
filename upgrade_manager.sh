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