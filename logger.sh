#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Log levels
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [FATAL]=4
)

# Initialize logging
init_logging() {
    # Create log directory with proper permissions
    if ! mkdir -p "${LOG_DIR}"; then
        echo "Failed to create log directory" >&2
        exit 1
    fi
    chmod 700 "${LOG_DIR}"

    # Initialize log files
    local log_files=("${MAIN_LOG}" "${ERROR_LOG}" "${DEBUG_LOG}")
    for log_file in "${log_files[@]}"; do
        if [ ! -f "${log_file}" ]; then
            echo "=== Log initialized $(date '+%Y-%m-%d %H:%M:%S') ===" > "${log_file}"
        fi
        chmod 600 "${log_file}"
    done

    # Set up log rotation
    setup_log_rotation
}

# Configure log rotation
setup_log_rotation() {
    cat > /etc/logrotate.d/ubuntu-upgrade << EOF
${LOG_DIR}/*.log {
    size 100M
    rotate 5
    compress
    delaycompress
    notifempty
    missingok
    create 600 root root
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
        ERROR|FATAL)
            echo "${formatted_msg}" | tee -a "${MAIN_LOG}" "${ERROR_LOG}" >&2
            ;;
        DEBUG)
            echo "${formatted_msg}" >> "${DEBUG_LOG}"
            ;;
        *)
            echo "${formatted_msg}" | tee -a "${MAIN_LOG}"
            ;;
    esac

    # Send to syslog for critical errors
    if [[ ${level} == "ERROR" || ${level} == "FATAL" ]]; then
        logger -p user.err -t "ubuntu-upgrade" "${level} ${component}: ${message}"
    fi

    # Exit on FATAL
    if [[ ${level} == "FATAL" ]]; then
        exit 1
    fi
}

# Function to log system metrics
log_system_metrics() {
    local component=$1
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    local mem_usage=$(free -m | awk '/Mem:/ {print $3}')
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    
    log "INFO" "${component}" "System Metrics - CPU: ${cpu_usage}%, Memory: ${mem_usage}MB, Disk: ${disk_usage}"
}

# Function to log stack trace
log_stack_trace() {
    local level=$1
    local component=$2
    local message=$3
    local frame=0
    local file line func
    
    log "${level}" "${component}" "${message}"
    while caller $frame; do
        ((frame++))
    done | awk '{ print "  at " $3 ":" $1 " (" $2 ")" }' | while read -r stack_frame; do
        log "${level}" "${component}" "${stack_frame}"
    done
}