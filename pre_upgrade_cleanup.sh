#!/bin/bash

set -euo pipefail

# Source required modules
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"

# Component name for logging
COMPONENT="CLEANUP"

# Pre-configure all possible prompts
pre_configure() {
    log "INFO" "${COMPONENT}" "Pre-configuring package removal options"
    
    # PostgreSQL configurations
    echo "postgresql-common postgresql-common/purge-data boolean true" | debconf-set-selections
    for version in {11..17}; do
        echo "postgresql-${version} postgresql-${version}/purge-data boolean true" | debconf-set-selections
    done
    
    # System configurations
    echo "libc6 libraries/restart-without-asking boolean true" | debconf-set-selections
    echo "grub-pc grub-pc/install_devices_empty boolean false" | debconf-set-selections
    echo "mdadm mdadm/boot_degraded boolean true" | debconf-set-selections
    
    # Force package configuration
    mkdir -p /etc/dpkg/dpkg.cfg.d
    cat > /etc/dpkg/dpkg.cfg.d/force-noninteractive << EOF
force-confdef
force-confnew
force-confmiss
EOF
}

# Backup PostgreSQL database
backup_postgres() {
    log "INFO" "${COMPONENT}" "Starting PostgreSQL backup for ${DB_NAME}"
    
    if command -v pg_dump >/dev/null; then
        mkdir -p "${BACKUP_DIR}"
        local BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"
        
        if timeout 3600 sudo -u postgres pg_dump ${DB_NAME} > "${BACKUP_FILE}"; then
            gzip -9 "${BACKUP_FILE}"
            log "INFO" "${COMPONENT}" "Database backup completed: ${BACKUP_FILE}.gz"
            chmod 600 "${BACKUP_FILE}.gz"
        else
            log "ERROR" "${COMPONENT}" "Database backup failed"
            return 1
        fi
    else
        log "WARN" "${COMPONENT}" "pg_dump not found - skipping backup"
    fi
}

# Rest of the script remains the same...