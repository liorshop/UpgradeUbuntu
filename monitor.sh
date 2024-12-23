#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Monitoring configuration
MONITORING_INTERVAL=60  # Reduced to 1 minute for faster recovery
ALERT_DISK_THRESHOLD=85  # Alert if disk usage > 85%
ALERT_MEM_THRESHOLD=90   # Alert if memory usage > 90%
ALERT_LOAD_THRESHOLD=8   # Alert if load average > 8
MAX_RESTART_ATTEMPTS=5   # Increased restart attempts
RESTART_DELAY=10        # Shorter initial delay for faster recovery

# System metrics collection
collect_metrics() {
    local cpu_load=$(cat /proc/loadavg | awk '{print $1}')
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # Log metrics
    log "STAT" "MONITOR" "METRICS cpu_load=${cpu_load},mem_used=${mem_percent}%,disk_used=${disk_percent}%"
    
    # Check thresholds
    local failed=0
    
    if [ ${disk_percent} -gt ${ALERT_DISK_THRESHOLD} ]; then
        log "ERROR" "MONITOR" "Disk usage critical: ${disk_percent}%"
        failed=1
    fi
    
    if [ ${mem_percent} -gt ${ALERT_MEM_THRESHOLD} ]; then
        log "ERROR" "MONITOR" "Memory usage critical: ${mem_percent}%"
        failed=1
    fi
    
    if (( $(echo "${cpu_load} > ${ALERT_LOAD_THRESHOLD}" | bc -l) )); then
        log "ERROR" "MONITOR" "System load critical: ${cpu_load}"
        failed=1
    fi
    
    return $failed
}

# Aggressive service recovery
aggressive_service_recovery() {
    local service="$1"
    local component="MONITOR"
    
    log "WARN" "$component" "Performing aggressive recovery for $service"
    
    # Stop and cleanup
    systemctl stop "$service" 2>/dev/null || true
    systemctl reset-failed "$service" 2>/dev/null || true
    rm -f "/var/run/$service.pid" 2>/dev/null || true
    
    # For systemd, additional cleanup
    if [ "$service" = "systemd" ]; then
        # Backup and cleanup systemd state
        cp -a /run/systemd/system /run/systemd/system.bak
        systemctl daemon-reexec
        if systemctl is-active --quiet systemd; then
            rm -rf /run/systemd/system.bak
            return 0
        fi
        mv /run/systemd/system.bak /run/systemd/system
        return 1
    fi
    
    # For networking, reset interfaces
    if [ "$service" = "networking" ]; then
        ip link set dev eth0 down 2>/dev/null || true
        ip link set dev eth0 up 2>/dev/null || true
        sleep 2
    fi
    
    # Try to start the service
    systemctl start "$service"
    sleep 5
    
    # Verify service status
    if systemctl is-active --quiet "$service"; then
        log "INFO" "$component" "Aggressive recovery successful for $service"
        return 0
    else
        log "ERROR" "$component" "Aggressive recovery failed for $service"
        return 1
    fi
}

# Service restart with retry mechanism
restart_service_with_retry() {
    local service="$1"
    local component="MONITOR"
    local attempt=1
    
    while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
        log "WARN" "$component" "Attempting to restart $service (attempt $attempt/$MAX_RESTART_ATTEMPTS)"
        
        if systemctl restart "$service"; then
            sleep 5
            if systemctl is-active --quiet "$service"; then
                log "INFO" "$component" "Successfully restarted $service"
                return 0
            fi
        fi
        
        log "ERROR" "$component" "Failed to restart $service on attempt $attempt"
        
        if [ $attempt -eq $((MAX_RESTART_ATTEMPTS - 1)) ]; then
            # Try aggressive recovery on second-to-last attempt
            aggressive_service_recovery "$service" && return 0
        fi
        
        sleep $((RESTART_DELAY * attempt))
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Network connectivity check with recovery
check_network() {
    local component="MONITOR"
    local targets=("archive.ubuntu.com" "security.ubuntu.com")
    local failed=0
    
    # First ensure DNS resolution is working
    if ! host archive.ubuntu.com >/dev/null 2>&1; then
        log "WARN" "$component" "DNS resolution failed, attempting to restart systemd-resolved"
        systemctl restart systemd-resolved
        sleep 5
    fi
    
    # Check if networking service is running
    if ! systemctl is-active --quiet networking; then
        restart_service_with_retry "networking" || {
            log "ERROR" "$component" "Failed to restore networking service"
            return 1
        }
        sleep 10
    fi
    
    # Check connectivity
    for target in "${targets[@]}"; do
        if ! ping -c 1 -W 5 ${target} >/dev/null 2>&1; then
            log "ERROR" "$component" "Network connectivity failed to ${target}"
            failed=$((failed + 1))
            
            # On first failure, try to recover networking
            if [ $failed -eq 1 ]; then
                log "WARN" "$component" "Attempting network recovery"
                aggressive_service_recovery "networking"
                sleep 10
                # Retry ping after recovery
                if ping -c 1 -W 5 ${target} >/dev/null 2>&1; then
                    log "INFO" "$component" "Network connectivity restored to ${target}"
                    failed=$((failed - 1))
                fi
            fi
        fi
    done
    
    return ${failed}
}

# Service health monitoring
check_services() {
    local component="MONITOR"
    local critical_services=("systemd" "networking" "ssh")
    local failed=0
    
    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet ${service}; then
            log "ERROR" "$component" "Critical service ${service} is not running"
            
            if ! restart_service_with_retry "${service}"; then
                log "ERROR" "$component" "Failed to recover ${service} after ${MAX_RESTART_ATTEMPTS} attempts"
                failed=$((failed + 1))
            fi
        fi
    done
    
    return ${failed}
}

# Main monitoring loop
monitor_loop() {
    local component="MONITOR"
    log "INFO" "$component" "Starting system monitoring"
    
    while true; do
        local check_failed=0
        
        check_services || check_failed=1
        check_network || check_failed=1
        collect_metrics || check_failed=1
        
        if [ $check_failed -eq 1 ]; then
            log "WARN" "$component" "One or more checks failed, continuing monitoring"
        fi
        
        sleep ${MONITORING_INTERVAL}
    done
}

# Start monitoring in background
start_monitoring() {
    monitor_loop & 
    echo $! > "${LOCK_DIR}/monitor.pid"
    log "INFO" "MONITOR" "Monitoring started with PID $(cat "${LOCK_DIR}/monitor.pid")"
}

# Stop monitoring
stop_monitoring() {
    if [ -f "${LOCK_DIR}/monitor.pid" ]; then
        kill $(cat "${LOCK_DIR}/monitor.pid") 2>/dev/null || true
        rm -f "${LOCK_DIR}/monitor.pid"
        log "INFO" "MONITOR" "Monitoring stopped"
    fi
}