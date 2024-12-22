#!/bin/bash

set -euo pipefail

# Base paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPONENT="UPGRADE"

# Source required modules
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"

# Pre-upgrade system validation
validate_system() {
    log "INFO" "${COMPONENT}" "Validating system state"
    local checks_failed=0
    
    # Check system state with more detail
    local system_state=$(systemctl is-system-running)
    log "INFO" "${COMPONENT}" "Current system state: ${system_state}"
    
    # List any failed units
    local failed_units=$(systemctl list-units --state=failed --no-pager)
    if [ -n "${failed_units}" ]; then
        log "WARN" "${COMPONENT}" "Failed units found:\n${failed_units}"
        # Don't fail for this, just warn
    fi
    
    # Check package system
    if ! dpkg --audit; then
        log "ERROR" "${COMPONENT}" "Package system has issues"
        ((checks_failed++))
    fi
    
    # Verify no package operations are in progress
    if fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
        log "ERROR" "${COMPONENT}" "Package system is locked"
        ((checks_failed++))
    fi
    
    # Check disk space
    local required_space=10000000  # 10GB
    local available_space=$(df /usr -k | awk 'NR==2 {print $4}')
    if [ "${available_space}" -lt "${required_space}" ]; then
        log "ERROR" "${COMPONENT}" "Insufficient disk space"
        ((checks_failed++))
    fi

    # Network connectivity check
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "ERROR" "${COMPONENT}" "No network connectivity"
        ((checks_failed++))
    fi

    # Package system checks
    if dpkg -l | grep -q '^.H'; then
        log "ERROR" "${COMPONENT}" "Found packages on hold"
        ((checks_failed++))
    fi

    if dpkg -l | grep -q '^.F'; then
        log "ERROR" "${COMPONENT}" "Found failed package installations"
        ((checks_failed++))
    fi

    # Allow degraded state but log it
    if ! systemctl is-system-running | grep -qE 'running|degraded'; then
        log "WARN" "${COMPONENT}" "System state is: ${system_state} - this is acceptable for upgrade"
    fi
    
    if [ ${checks_failed} -gt 0 ]; then
        log "ERROR" "${COMPONENT}" "System validation failed with ${checks_failed} errors"
        return 1
    fi
    
    log "INFO" "${COMPONENT}" "System validation passed"
    return 0
}

# Rest of the script remains the same...