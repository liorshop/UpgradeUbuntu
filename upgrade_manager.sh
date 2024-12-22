#!/bin/bash

set -euo pipefail

# Base configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="/update/upgrade"
STATE_FILE="${BASE_DIR}/.upgrade_state"
LOCK_FILE="${BASE_DIR}/.upgrade.lock"
COMPONENT="UPGRADE"
DB_NAME="bobe"

# Source required modules
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/monitor.sh"

# Initialize logging
init_logging

# Lock file management
acquire_lock() {
    local pid
    if [ -f "${LOCK_FILE}" ]; then
        pid=$(cat "${LOCK_FILE}" 2>/dev/null)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            log "ERROR" "${COMPONENT}" "Another upgrade process is running (PID: ${pid})"
            exit 1
        fi
        log "WARN" "${COMPONENT}" "Removing stale lock file"
        rm -f "${LOCK_FILE}"
    fi
    echo $$ > "${LOCK_FILE}"
}

release_lock() {
    rm -f "${LOCK_FILE}"
}

# State management
get_state() {
    local state
    if [ ! -f "${STATE_FILE}" ]; then
        state="initial"
    elif ! state=$(tr -d '\n\r' < "${STATE_FILE}" 2>/dev/null); then
        log "ERROR" "${COMPONENT}" "Failed to read state file"
        return 1
    elif [ -z "${state}" ]; then
        log "ERROR" "${COMPONENT}" "State file empty"
        return 1
    elif ! echo "${state}" | grep -qE '^(initial|22\.04|24\.04|setup)$'; then
        log "ERROR" "${COMPONENT}" "Invalid state: ${state}"
        return 1
    fi
    echo "${state}"
}

save_state() {
    local new_state=$1
    if ! echo "${new_state}" | grep -qE '^(initial|22\.04|24\.04|setup)$'; then
        log "ERROR" "${COMPONENT}" "Attempting to save invalid state: ${new_state}"
        return 1
    fi
    
    if ! echo "${new_state}" > "${STATE_FILE}.tmp"; then
        log "ERROR" "${COMPONENT}" "Failed to write temporary state file"
        return 1
    fi
    
    if ! mv "${STATE_FILE}.tmp" "${STATE_FILE}"; then
        log "ERROR" "${COMPONENT}" "Failed to update state file"
        return 1
    fi
    
    log "INFO" "${COMPONENT}" "State updated to: ${new_state}"
}

# System state validation
check_system_state() {
    local checks=(
        "! dpkg -l | grep -q '^.H'"  # No packages on hold
        "! dpkg -l | grep -q '^.F'"  # No failed installations
        "! ps aux | grep -v grep | grep -q 'apt\|dpkg'"  # No package operations running
        "systemctl is-system-running | grep -qE 'running|degraded'"  # System is operational
    )

    for check in "${checks[@]}"; do
        if ! eval "${check}"; then
            log "ERROR" "${COMPONENT}" "System state check failed: ${check}"
            return 1
        fi
    done
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    local source_file=$3
    shift 3
    local func_stack=("$@")
    
    log "ERROR" "${COMPONENT}" "Error in ${source_file} line ${line_number} (exit code: ${exit_code})"
    log "ERROR" "${COMPONENT}" "Function stack: ${func_stack[*]}"
    
    # Attempt recovery
    dpkg --configure -a || true
    apt-get install -f -y || true
    
    release_lock
    exit "${exit_code}"
}

# Environment initialization
initialize_environment() {
    export DEBIAN_FRONTEND=noninteractive
    export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
    export NEEDRESTART_MODE=a
    mkdir -p "${BASE_DIR}"
    chmod 700 "${BASE_DIR}"
}

# Rest of the script...

# Main execution
main() {
    # Initialize
    acquire_lock
    initialize_environment
    
    # Get and validate state
    current_state=$(get_state) || exit 1
    
    # System checks
    check_system_state || {
        log "ERROR" "${COMPONENT}" "System is not in a clean state"
        exit 1
    }
    
    # Process state
    case "${current_state}" in
        "initial")
            process_initial_state
            ;;
        "22.04")
            process_2204_state
            ;;
        "24.04")
            process_2404_state
            ;;
        "setup")
            process_setup_state
            ;;
        *)
            log "ERROR" "${COMPONENT}" "Unknown state: ${current_state}"
            exit 1
            ;;
    esac
}

# Set up error handling
trap 'handle_error $? ${LINENO} ${BASH_SOURCE} ${FUNCNAME[*]}' ERR
trap 'release_lock' EXIT

# Run main
main "$@"
