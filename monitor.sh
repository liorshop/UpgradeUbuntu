#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Monitoring configuration
MONITORING_INTERVAL=60    # Check more frequently (1 minute)
ALERT_DISK_THRESHOLD=85   # Alert if disk usage > 85%
ALERT_MEM_THRESHOLD=90    # Alert if memory usage > 90%
ALERT_LOAD_THRESHOLD=8    # Alert if load average > 8
MAX_RESTART_ATTEMPTS=5    # Maximum service restart attempts
RESTART_DELAY=10         # Initial delay between restart attempts

# Service recovery function
recover_service() {
    local service="$1"
    local component="MONITOR"
    local attempt=1
    
    log "WARN" "$component" "Attempting recovery of $service"
    
    # Special handling for critical services
    case "$service" in
        "systemd")
            # Backup systemd state
            cp -a /run/systemd/system /run/systemd/system.bak
            systemctl daemon-reexec
            if systemctl is-active --quiet systemd; then
                rm -rf /run/systemd/system.bak
                return 0
            fi
            mv /run/systemd/system.bak /run/systemd/system
            ;;
            
        "networking")
            # Stop networking cleanly
            systemctl stop networking
            
            # Reset network interfaces
            for iface in $(ip link show | grep -o '^[0-9]\+: \+[^:]\+' | cut -d' ' -f2); do
                ip link set dev "$iface" down 2>/dev/null || true
                ip link set dev "$iface" up 2>/dev/null || true
            done
            
            # Restart DNS first
            systemctl restart systemd-resolved
            
            # Try to restart networking
            if systemctl restart networking; then
                sleep 5
                if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
                    return 0
                fi
            fi
            ;;
            
        *)
            # Standard service restart with retry
            while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
                log "INFO" "$component" "Attempting restart of $service (attempt $attempt/$MAX_RESTART_ATTEMPTS)"
                
                systemctl reset-failed "$service" 2>/dev/null || true
                if systemctl restart "$service"; then
                    sleep 5
                    if systemctl is-active --quiet "$service"; then
                        return 0
                    fi
                fi
                
                sleep $((RESTART_DELAY * attempt))
                attempt=$((attempt + 1))
            done
            ;;
    esac
    
    return 1
}

# Check and monitor services
check_services() {
    local component="MONITOR"
    local critical_services=("systemd" "networking" "ssh")
    local failed=0
    
    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "$component" "Critical service $service is not running"
            
            if recover_service "$service"; then
                log "INFO" "$component" "Successfully recovered $service"
            else
                log "ERROR" "$component" "Failed to recover $service"
                failed=$((failed + 1))
            fi
        fi
    done
    
    return $failed
}

# Network connectivity check
check_network() {
    local component="MONITOR"
    local targets=("archive.ubuntu.com" "security.ubuntu.com")
    local failed=0
    
    # Check DNS resolution first
    if ! host archive.ubuntu.com >/dev/null 2>&1; then
        log "WARN" "$component" "DNS resolution failed, restarting systemd-resolved"
        systemctl restart systemd-resolved
        sleep 5
    fi
    
    # Check if networking service is running
    if ! systemctl is-active --quiet networking; then
        if ! recover_service "networking"; then
            return 1
        fi
    fi
    
    # Check connectivity to repositories
    for target in "${targets[@]}"; do
        if ! ping -c 1 -W 5 "$target" >/dev/null 2>&1; then
            log "ERROR" "$component" "Network connectivity failed to $target"
            failed=$((failed + 1))
        fi
    done
    
    return $failed
}

# System metrics collection
collect_metrics() {
    local component="MONITOR"
    local cpu_load=$(cat /proc/loadavg | awk '{print $1}')
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    log "STAT" "$component" "METRICS cpu_load=${cpu_load},mem_used=${mem_percent}%,disk_used=${disk_percent}%"
    
    local failed=0
    
    if [ "${disk_percent}" -gt "${ALERT_DISK_THRESHOLD}" ]; then
        log "ERROR" "$component" "Disk usage critical: ${disk_percent}%"
        failed=1
    fi
    
    if [ "${mem_percent}" -gt "${ALERT_MEM_THRESHOLD}" ]; then
        log "ERROR" "$component" "Memory usage critical: ${mem_percent}%"
        failed=1
    fi
    
    if (( $(echo "${cpu_load} > ${ALERT_LOAD_THRESHOLD}" | bc -l) )); then
        log "ERROR" "$component" "System load critical: ${cpu_load}"
        failed=1
    fi
    
    return $failed
}

# Main monitoring loop
monitor_loop() {
    local component="MONITOR"
    log "INFO" "$component" "Starting system monitoring"
    
    while true; do
        local failed=0
        
        check_services || failed=1
        sleep 2  # Small delay between checks
        check_network || failed=1
        sleep 2
        collect_metrics || failed=1
        
        if [ $failed -eq 1 ]; then
            log "WARN" "$component" "One or more checks failed"
        fi
        
        sleep $MONITORING_INTERVAL
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

# Run monitoring if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap stop_monitoring EXIT INT TERM
    start_monitoring
fi