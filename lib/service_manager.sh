#!/bin/bash

# Service management utilities
# Author: Added by Claude for liorshop/UpgradeUbuntu
# Version: 1.0.0
# Description: Enterprise-grade service management functions

source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../logger.sh"

# Constants
readonly MAX_RESTART_ATTEMPTS=3
readonly RESTART_DELAY=10
readonly SERVICE_TIMEOUT=30

# Service status check with timeout
# Args:
#   $1 - Service name
# Returns:
#   0 if service is active, 1 otherwise
check_service_status() {
    local service_name="$1"
    local timeout="$SERVICE_TIMEOUT"
    
    if ! timeout "$timeout" systemctl is-active --quiet "$service_name"; then
        log "ERROR" "SERVICE" "Service $service_name is not running"
        return 1
    fi
    return 0
}

# Restart service with retry mechanism
# Args:
#   $1 - Service name
# Returns:
#   0 on successful restart, 1 on failure
restart_service() {
    local service_name="$1"
    local attempt=1
    local component="SERVICE"
    
    while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
        log "INFO" "$component" "Attempting to restart $service_name (attempt $attempt/$MAX_RESTART_ATTEMPTS)"
        
        if systemctl restart "$service_name"; then
            # Wait for service to stabilize
            sleep 2
            if check_service_status "$service_name"; then
                log "INFO" "$component" "Successfully restarted $service_name"
                return 0
            fi
        fi
        
        log "WARN" "$component" "Failed to restart $service_name on attempt $attempt"
        sleep "$RESTART_DELAY"
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "$component" "Failed to restart $service_name after $MAX_RESTART_ATTEMPTS attempts"
    return 1
}

# Systemd recovery attempt
# Returns:
#   0 on successful recovery, 1 on failure
recover_systemd() {
    local component="SERVICE"
    log "WARN" "$component" "Attempting systemd recovery"
    
    if systemctl daemon-reexec; then
        log "INFO" "$component" "Successfully re-executed systemd"
        return 0
    else
        log "ERROR" "$component" "Failed to re-execute systemd"
        return 1
    fi
}

# Network service recovery with additional checks
# Returns:
#   0 on successful recovery, 1 on failure
recover_networking() {
    local component="SERVICE"
    log "WARN" "$component" "Attempting networking recovery"
    
    # Stop networking cleanly
    systemctl stop networking
    
    # Reset network interfaces
    ip link set dev eth0 down 2>/dev/null || true
    ip link set dev eth0 up 2>/dev/null || true
    
    # Restart networking service
    if restart_service "networking"; then
        # Verify network connectivity
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log "INFO" "$component" "Network connectivity restored"
            return 0
        else
            log "ERROR" "$component" "Network connectivity check failed after service restart"
        fi
    fi
    
    return 1
}

# Service health check and recovery
# Args:
#   $1 - Array of critical services
# Returns:
#   0 if all services are running, 1 if any service failed
check_and_recover_services() {
    local -a services=("$@")
    local failed=0
    local component="SERVICE"
    
    for service in "${services[@]}"; do
        if ! check_service_status "$service"; then
            log "WARN" "$component" "Attempting recovery of $service"
            
            case "$service" in
                "systemd")
                    recover_systemd || ((failed++))
                    ;;
                "networking")
                    recover_networking || ((failed++))
                    ;;
                *)
                    restart_service "$service" || ((failed++))
                    ;;
            esac
        fi
    done
    
    return "$failed"
}
