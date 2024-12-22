#!/bin/bash

# Base paths and files
BASE_DIR="/update/upgrade"
LOG_DIR="${BASE_DIR}/logs"
LOCK_DIR="${BASE_DIR}/locks"
BACKUP_DIR="${BASE_DIR}/backups"

# State and lock files
STATE_FILE="${BASE_DIR}/.upgrade_state"
LOCK_FILE="${LOCK_DIR}/upgrade.lock"

# Logging files
MAIN_LOG="${LOG_DIR}/upgrade.log"
ERROR_LOG="${LOG_DIR}/error.log"
DEBUG_LOG="${LOG_DIR}/debug.log"

# Database configurations
DB_NAME="bobe"
DB_USER="${DB_NAME}"
DB_PASSWORD="${DB_NAME}"

# Initialize directories
initialize_directories() {
    local dirs=("${BASE_DIR}" "${LOG_DIR}" "${LOCK_DIR}" "${BACKUP_DIR}")
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "${dir}"; then
            echo "Failed to create directory: ${dir}" >&2
            exit 1
        fi
        chmod 700 "${dir}"
    done
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        exit 1
    fi
}

# Set secure umask
set_secure_environment() {
    umask 077
    export DEBIAN_FRONTEND=noninteractive
    export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
    export NEEDRESTART_MODE=a
}

# System checks
check_system_requirements() {
    # Check disk space (10GB minimum)
    local required_space=10000000
    local available_space=$(df /usr -k | awk 'NR==2 {print $4}')
    if [ "${available_space}" -lt "${required_space}" ]; then
        echo "Insufficient disk space. Required: 10GB, Available: $(( available_space / 1024 / 1024 ))GB" >&2
        exit 1
    fi

    # Check memory
    local available_mem=$(free -m | awk '/^Mem:/ {print $4}')
    if [ "${available_mem}" -lt 1024 ]; then
        echo "Warning: Less than 1GB of free memory available" >&2
    fi

    # Check network connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "No network connectivity" >&2
        exit 1
    fi
}

# Initialize environment
initialize() {
    check_root
    set_secure_environment
    initialize_directories
    check_system_requirements
}