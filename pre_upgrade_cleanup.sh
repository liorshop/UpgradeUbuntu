#!/bin/bash

set -euo pipefail

# Source required modules
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"

# Component name for logging
COMPONENT="CLEANUP"

# Cleanup handler for exit
cleanup_and_exit() {
    local exit_code=$1
    log "INFO" "${COMPONENT}" "Running cleanup before exit"
    
    # Cleanup any temporary changes
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # If we're exiting due to error, disable the upgrade service
    if [ ${exit_code} -ne 0 ]; then
        systemctl disable ubuntu-upgrade.service 2>/dev/null || true
        rm -f /etc/systemd/system/ubuntu-upgrade.service 2>/dev/null || true
        rm -f "${STATE_FILE}" 2>/dev/null || true
    fi
    
    exit ${exit_code}
}

# Backup PostgreSQL database
backup_postgres() {
    log "INFO" "${COMPONENT}" "Starting PostgreSQL backup for ${DB_NAME}"
    
    # Initial checks
    if ! command -v pg_dump >/dev/null; then
        log "ERROR" "${COMPONENT}" "pg_dump not found - PostgreSQL not installed?"
        return 1
    fi

    # Verify PostgreSQL is running
    if ! systemctl is-active --quiet postgresql; then
        log "ERROR" "${COMPONENT}" "PostgreSQL service is not running"
        return 1
    fi

    # Verify database exists
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw ${DB_NAME}; then
        log "ERROR" "${COMPONENT}" "Database ${DB_NAME} does not exist"
        return 1
    fi
    
    # Create backup directory with proper permissions
    mkdir -p "${BACKUP_DIR}"
    chmod 777 "${BACKUP_DIR}"  # Temporarily allow postgres to write
    
    local BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"
    
    # Perform backup
    log "INFO" "${COMPONENT}" "Creating database backup at: ${BACKUP_FILE}"
    if timeout 3600 sudo -u postgres pg_dump ${DB_NAME} > "${BACKUP_FILE}"; then
        gzip -9 "${BACKUP_FILE}"
        log "INFO" "${COMPONENT}" "Database backup completed: ${BACKUP_FILE}.gz"
        
        # Verify backup file exists and has size
        if [ ! -s "${BACKUP_FILE}.gz" ]; then
            log "ERROR" "${COMPONENT}" "Backup file is empty or missing"
            return 1
        fi
        
        # Fix permissions
        chmod 600 "${BACKUP_FILE}.gz"
        chmod 700 "${BACKUP_DIR}"
        chown -R root:root "${BACKUP_DIR}"
        
        # Double check backup exists
        if [ ! -s "${BACKUP_FILE}.gz" ]; then
            log "ERROR" "${COMPONENT}" "Backup verification failed after permission change"
            return 1
        fi
        
        return 0
    else
        log "ERROR" "${COMPONENT}" "Database backup failed"
        chmod 700 "${BACKUP_DIR}"  # Restore permissions even on failure
        return 1
    fi
}

# Rest of the functions remain the same...

# Main execution
main() {
    log "INFO" "${COMPONENT}" "Starting pre-upgrade cleanup"
    
    # Initialize
    initialize
    
    # Critical: Backup database first
    if ! backup_postgres; then
        log "ERROR" "${COMPONENT}" "Database backup failed - STOPPING UPGRADE"
        cleanup_and_exit 1
    fi
    
    # Verify backup exists
    local backup_count=$(ls -1 "${BACKUP_DIR}"/${DB_NAME}_*.sql.gz 2>/dev/null | wc -l)
    if [ "${backup_count}" -eq 0 ]; then
        log "ERROR" "${COMPONENT}" "No backup file found after backup - STOPPING UPGRADE"
        cleanup_and_exit 1
    fi
    
    log "INFO" "${COMPONENT}" "Database backup verified successful. Proceeding with upgrade."
    
    # Continue with other steps only if backup is successful
    pre_configure || cleanup_and_exit 1
    cleanup_services || cleanup_and_exit 1
    cleanup_packages || cleanup_and_exit 1
    
    log "INFO" "${COMPONENT}" "Pre-upgrade cleanup completed successfully"
}

# Set up error handling
trap 'cleanup_and_exit $?' ERR

# Run main
main "$@"
