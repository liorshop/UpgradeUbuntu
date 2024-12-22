#!/bin/bash

source $(dirname "${BASH_SOURCE[0]}")/logger.sh

# Monitoring configuration
MONITORING_INTERVAL=300  # 5 minutes
ALERT_DISK_THRESHOLD=85  # Alert if disk usage > 85%
ALERT_MEM_THRESHOLD=90   # Alert if memory usage > 90%

# System metrics collection
collect_metrics() {
    local component="MONITOR"
    
    # Collect system metrics
    local cpu_load=$(cat /proc/loadavg | awk '{print $1}')
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # Log metrics
    log "STAT" "${component}" "METRICS cpu_load=${cpu_load},mem_used=${mem_percent}%,disk_used=${disk_percent}%"
    
    # Check thresholds and alert if necessary
    if [ ${disk_percent} -gt ${ALERT_DISK_THRESHOLD} ]; then
        log "ERROR" "${component}" "Disk usage critical: ${disk_percent}%"
    fi
    
    if [ ${mem_percent} -gt ${ALERT_MEM_THRESHOLD} ]; then
        log "ERROR" "${component}" "Memory usage critical: ${mem_percent}%"
    fi
}

# Process monitoring
check_processes() {
    local component="MONITOR"
    
    # Check upgrade-related processes
    local processes=("apt" "dpkg" "do-release-upgrade")
    for proc in "${processes[@]}"; do
        if pgrep -f "${proc}" > /dev/null; then
            local pid=$(pgrep -f "${proc}")
            local cpu=$(ps -p ${pid} -o %cpu=)
            local mem=$(ps -p ${pid} -o %mem=)
            log "DEBUG" "${component}" "Process ${proc} running (PID: ${pid}, CPU: ${cpu}%, MEM: ${mem}%)"
        fi
    done
}

# Network connectivity check
check_network() {
    local component="MONITOR"
    local targets=("archive.ubuntu.com" "security.ubuntu.com")
    
    for target in "${targets[@]}"; do
        if ! ping -c 1 ${target} &>/dev/null; then
            log "ERROR" "${component}" "Network connectivity failed to ${target}"
        else
            log "DEBUG" "${component}" "Network connectivity OK to ${target}"
        fi
    done
}

# Package operation monitoring
monitor_package_operations() {
    local component="MONITOR"
    
    # Check for locked dpkg/apt
    if lsof /var/lib/dpkg/lock-frontend &>/dev/null; then
        log "DEBUG" "${component}" "Package system is locked (normal during upgrade)"
    fi
    
    # Check for interrupted upgrades
    if [ -f "/var/lib/dpkg/updates/" ]; then
        log "ERROR" "${component}" "Detected interrupted package operations"
    fi
}

# Service health monitoring
check_services() {
    local component="MONITOR"
    local critical_services=("systemd" "networking" "ssh")
    
    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet ${service}; then
            log "ERROR" "${component}" "Critical service ${service} is not running"
        fi
    done
}

# Main monitoring loop
monitor_loop() {
    while true; do
        collect_metrics
        check_processes
        check_network
        monitor_package_operations
        check_services
        
        sleep ${MONITORING_INTERVAL}
    done
}

# Start monitoring in background
start_monitoring() {
    monitor_loop & echo $! > "/var/run/upgrade-monitor.pid"
}

# Stop monitoring
stop_monitoring() {
    if [ -f "/var/run/upgrade-monitor.pid" ]; then
        kill $(cat "/var/run/upgrade-monitor.pid")
        rm -f "/var/run/upgrade-monitor.pid"
    fi
}
