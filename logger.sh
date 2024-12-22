#!/bin/bash

# Enterprise logging configuration
BASE_DIR="/update/upgrade"
LOG_DIR="${BASE_DIR}/logs"
MAIN_LOG="${LOG_DIR}/upgrade.log"
ERROR_LOG="${LOG_DIR}/error.log"
DEBUG_LOG="${LOG_DIR}/debug.log"
STATS_LOG="${LOG_DIR}/stats.log"

# Log rotation settings
MAX_LOG_SIZE=100M
MAX_LOG_FILES=5

# Initialize logging
init_logging() {
    # Create log directories with proper permissions
    mkdir -p "${LOG_DIR}"
    chmod 750 "${LOG_DIR}"

    # Initialize log files with headers
    for log_file in "${MAIN_LOG}" "${ERROR_LOG}" "${DEBUG_LOG}" "${STATS_LOG}"; do
        if [ ! -f "${log_file}" ]; then
            echo "=== Log initialized $(date '+%Y-%m-%d %H:%M:%S') ===" > "${log_file}"
            chmod 640 "${log_file}"
        fi
    done

    # Set up log rotation
    cat > /etc/logrotate.d/ubuntu-upgrade << EOF
${LOG_DIR}/*.log {
    size ${MAX_LOG_SIZE}
    rotate ${MAX_LOG_FILES}
    compress
    delaycompress
    notifempty
    missingok
    create 640 root root
    su root root
}
EOF
}

# Enhanced logging function
log() {
    local level=$1
    local component=$2
    shift 2
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local pid=$$

    # Format message
    local formatted_msg="${timestamp} [${level}] [${hostname}] [${component}] [PID:${pid}] ${message}"

    # Write to appropriate logs
    case ${level} in
        ERROR)
            echo "${formatted_msg}" | tee -a "${MAIN_LOG}" "${ERROR_LOG}"
            ;;
        DEBUG)
            echo "${formatted_msg}" >> "${DEBUG_LOG}"
            ;;
        STAT)
            echo "${formatted_msg}" >> "${STATS_LOG}"
            ;;
        *)
            echo "${formatted_msg}" | tee -a "${MAIN_LOG}"
            ;;
    esac

    # Log to syslog for centralized logging
    logger -t "ubuntu-upgrade" "${level} ${component}: ${message}"
}

# Performance monitoring
log_system_stats() {
    local component=$1
    
    # System stats
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    local mem_usage=$(free -m | awk '/Mem:/ {print $3}')
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    
    log "STAT" "${component}" "CPU: ${cpu_usage}%, MEM: ${mem_usage}MB, DISK: ${disk_usage}"
}

# Error tracking with stack trace
log_error() {
    local component=$1
    local error_msg=$2
    local line_number=$3
    
    local stack_trace=$(caller)
    log "ERROR" "${component}" "${error_msg} at line ${line_number}\nStack Trace:\n${stack_trace}"
}

# Progress tracking
log_progress() {
    local component=$1
    local stage=$2
    local status=$3
    
    log "INFO" "${component}" "Stage: ${stage}, Status: ${status}"
    log_system_stats "${component}"
}

# Health check logging
log_health_check() {
    local component=$1
    
    # Check system health
    local services_status=$(systemctl list-units --state=failed --no-pager)
    local disk_space=$(df -h /)
    local memory_info=$(free -h)
    
    log "DEBUG" "${component}" "Health Check Results:\nFailed Services:\n${services_status}\n\nDisk Space:\n${disk_space}\n\nMemory Info:\n${memory_info}"
}

# Audit logging
log_audit() {
    local component=$1
    local action=$2
    local details=$3
    
    log "AUDIT" "${component}" "Action: ${action}, Details: ${details}"
}
