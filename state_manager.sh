#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Valid states
VALID_STATES=("initial" "22.04" "24.04" "setup")

# State management functions
get_state() {
    local state
    
    if [ ! -f "${STATE_FILE}" ]; then
        echo "initial"
        return 0
    fi

    # Read state with proper error handling
    if ! state=$(tr -d '\n\r' < "${STATE_FILE}" 2>/dev/null); then
        log "ERROR" "STATE" "Failed to read state file"
        return 1
    fi

    # Validate state
    if [ -z "${state}" ]; then
        log "ERROR" "STATE" "Empty state file"
        return 1
    fi

    # Check if state is valid
    local valid=false
    for valid_state in "${VALID_STATES[@]}"; do
        if [ "${state}" = "${valid_state}" ]; then
            valid=true
            break
        fi
    done

    if ! $valid; then
        log "ERROR" "STATE" "Invalid state: ${state}"
        return 1
    fi

    echo "${state}"
    return 0
}

save_state() {
    local new_state=$1
    local temp_file="${STATE_FILE}.tmp"
    
    # Validate new state
    local valid=false
    for valid_state in "${VALID_STATES[@]}"; do
        if [ "${new_state}" = "${valid_state}" ]; then
            valid=true
            break
        fi
    done

    if ! $valid; then
        log "ERROR" "STATE" "Attempting to save invalid state: ${new_state}"
        return 1
    fi

    # Write to temporary file first
    if ! echo "${new_state}" > "${temp_file}"; then
        log "ERROR" "STATE" "Failed to write to temporary state file"
        return 1
    fi

    # Use atomic move to update state file
    if ! mv "${temp_file}" "${STATE_FILE}"; then
        log "ERROR" "STATE" "Failed to update state file"
        rm -f "${temp_file}"
        return 1
    fi

    # Set proper permissions
    chmod 600 "${STATE_FILE}"

    log "INFO" "STATE" "State updated to: ${new_state}"
    return 0
}

# Lock file management
acquire_lock() {
    local pid
    
    # Create lock directory if it doesn't exist
    mkdir -p "$(dirname "${LOCK_FILE}")"

    # Check for existing lock
    if [ -f "${LOCK_FILE}" ]; then
        pid=$(cat "${LOCK_FILE}" 2>/dev/null)
        if [ -n "${pid}" ]; then
            if kill -0 "${pid}" 2>/dev/null; then
                log "ERROR" "LOCK" "Another upgrade process is running (PID: ${pid})"
                return 1
            else
                log "WARN" "LOCK" "Removing stale lock file from PID ${pid}"
            fi
        fi
        rm -f "${LOCK_FILE}"
    fi

    # Create new lock file
    if ! echo $$ > "${LOCK_FILE}"; then
        log "ERROR" "LOCK" "Failed to create lock file"
        return 1
    fi

    chmod 600 "${LOCK_FILE}"
    return 0
}

release_lock() {
    if [ -f "${LOCK_FILE}" ]; then
        local pid=$(cat "${LOCK_FILE}" 2>/dev/null)
        if [ "${pid}" = "$$" ]; then
            rm -f "${LOCK_FILE}"
        fi
    fi
}

# Cleanup function
cleanup() {
    release_lock
    log "INFO" "STATE" "Cleanup completed"
}