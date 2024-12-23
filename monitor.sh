#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Monitoring configuration
MONITORING_INTERVAL=300  # 5 minutes
ALERT_DISK_THRESHOLD=85  # Alert if disk usage > 85%
ALERT_MEM_THRESHOLD=90   # Alert if memory usage > 90%
ALERT_LOAD_THRESHOLD=8   # Alert if load average > 8
MAX_RESTART_ATTEMPTS=3   # Maximum number of restart attempts
RESTART_DELAY=30        # Delay between restart attempts

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
    if [ ${disk_percent} -gt ${ALERT_DISK_THRESHOLD} ]; then
        log "ERROR" "MONITOR" "Disk usage critical: ${disk_percent}%"
        return 1
    fi
    
    if [ ${mem_percent} -gt ${ALERT_MEM_THRESHOLD} ]; then
        log "ERROR" "MONITOR" "Memory usage critical: ${mem_percent}%"
        return 1
    fi
    
    if (( $(echo "${cpu_load} > ${ALERT_LOAD_THRESHOLD}" | bc -l) )); then
        log "ERROR" "MONITOR" "System load critical: ${cpu_load}"
        return 1
    fi
    
    return 0
}

# Process monitoring
check_processes() {
    local component="MONITOR"
    local critical_processes=("apt" "dpkg" "do-release-upgrade")
    
    for proc in "${critical_processes[@]}"; do
        if pgrep -f "${proc}" >/dev/null; then
            local pid=$(pgrep -f "${proc}")
            local cpu=$(ps -p ${pid} -o %cpu= 2>/dev/null || echo "N/A")
            local mem=$(ps -p ${pid} -o %mem= 2>/dev/null || echo "N/A")
            log "DEBUG" "${component}" "Process ${proc} running (PID: ${pid}, CPU: ${cpu}%, MEM: ${mem}%)"
        fi
    done
}

# Attempt to restart a service with retries
restart_service_with_retry() {
    local service="$1"
    local component="MONITOR"
    local attempt=1
    
    while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
        log "WARN" "${component}" "Attempting to restart ${service} (attempt ${attempt}/${MAX_RESTART_ATTEMPTS})"
        
        if [ "${service}" = "systemd" ]; then
            # Special handling for systemd
            if systemctl daemon-reexec; then
                log "INFO" "${component}" "Successfully re-executed systemd"
                return 0
            fi
        else
            # For other services, try standard restart
            if systemctl restart "${service}"; then
                # Verify service is actually running after restart
                sleep 5  # Wait for service to stabilize
                if systemctl is-active --quiet "${service}"; then
                    log "INFO" "${component}" "Successfully restarted ${service}"
                    return 0
                fi
            fi
        fi
        
        log "ERROR" "${component}" "Failed to restart ${service} on attempt ${attempt}"
        
        # Wait before next attempt with increased delay
        sleep $((RESTART_DELAY * attempt))
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Network connectivity check with recovery attempt
check_network() {
    local component="MONITOR"
    local targets=("archive.ubuntu.com" "security.ubuntu.com")
    local failed=0
    
    # First check if networking service is running
    if ! systemctl is-active --quiet networking; then
        restart_service_with_retry "networking" || {
            log "ERROR" "${component}" "Failed to restore networking service"
            return 1
        }
        sleep 10  # Wait for network to stabilize
    fi
    
    for target in "${targets[@]}"; do
        if ! ping -c 1 -W 5 ${target} >/dev/null 2>&1; then
            log "ERROR" "${component}" "Network connectivity failed to ${target}"
            failed=$((failed + 1))
        fi
    done
    
    if [ ${failed} -gt 0 ]; then
        # If ping fails, try to restart networking again
        log "WARN" "${component}" "Network connectivity issues detected, attempting recovery"
        systemctl restart networking
        sleep 10
        
        # Check connectivity again
        failed=0
        for target in "${targets[@]}"; do
            if ! ping -c 1 -W 5 ${target} >/dev/null 2>&1; then
                log "ERROR" "${component}" "Network connectivity still failed to ${target} after recovery attempt"
                failed=$((failed + 1))
            fi
        done
    fi
    
    return ${failed}
}

# Service health monitoring with recovery attempts
check_services() {
    local component="MONITOR"
    local critical_services=("systemd" "networking" "ssh")
    local failed=0
    
    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet ${service}; then
            log "ERROR" "${component}" "Critical service ${service} is not running"
            
            if ! restart_service_with_retry "${service}"; then
                log "ERROR" "${component}" "Failed to recover ${service} after ${MAX_RESTART_ATTEMPTS} attempts"
                failed=$((failed + 1))
                
                # For critical services, try more aggressive recovery
                if [ "${service}" = "systemd" ] || [ "${service}" = "networking" ]; then
                    log "WARN" "${component}" "Attempting aggressive recovery for ${service}"
                    systemctl reset-failed ${service}
                    systemctl stop ${service} 2>/dev/null || true
                    sleep 5
                    systemctl start ${service} || {
                        log "ERROR" "${component}" "Aggressive recovery failed for ${service}"
                        ((failed++))
                    }
                fi
            fi
        fi
    done
    
    return ${failed}
}

# Main monitoring loop
monitor_loop() {
    local component="MONITOR"
    log "INFO" "${component}" "Starting system monitoring"
    
    while true; do
        collect_metrics || log "WARN" "${component}" "Metrics collection failed"
        check_processes
        check_network || log "WARN" "${component}" "Network check failed"
        check_services || log "WARN" "${component}" "Service check failed"
        
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