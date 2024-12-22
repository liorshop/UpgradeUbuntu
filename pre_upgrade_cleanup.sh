#!/bin/bash

# Pre-upgrade cleanup script
set -euo pipefail

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Backup PostgreSQL database
backup_postgres() {
    log "INFO" "Starting PostgreSQL backup for database 'bobe'"
    
    if command -v pg_dump >/dev/null; then
        mkdir -p "${BASE_DIR}/backups"
        BACKUP_FILE="${BASE_DIR}/backups/bobe_$(date +%Y%m%d_%H%M%S).sql"
        
        if sudo -u postgres pg_dump bobe > "${BACKUP_FILE}"; then
            log "INFO" "PostgreSQL backup completed successfully: ${BACKUP_FILE}"
            gzip -c "${BACKUP_FILE}" > "${BACKUP_FILE}.gz"
            log "INFO" "Compressed backup created: ${BACKUP_FILE}.gz"
        else
            log "ERROR" "PostgreSQL backup failed"
            exit 1
        fi
    else
        log "WARN" "pg_dump not found - PostgreSQL might not be installed"
    fi
}

# Remove specified packages and their configurations
cleanup_packages() {
    log "INFO" "Starting package cleanup"
    
    # Stop services first
    services=("postgresql" "mongod" "monit")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet ${service}; then
            log "INFO" "Stopping ${service} service"
            systemctl stop ${service}
        fi
    done
    
    # Create list of packages to remove
    packages=(
        "postgresql*"
        "monit*"
        "mongodb*"
        "mongo-tools"
        "openjdk*"
    )
    
    # Purge packages
    for pkg in "${packages[@]}"; do
        log "INFO" "Purging packages matching: ${pkg}"
        apt-get purge -y ${pkg} || log "WARN" "Some packages matching ${pkg} could not be purged"
    done
    
    apt-get autoremove -y
    apt-get clean
}

# Remove third-party source lists
cleanup_sources() {
    log "INFO" "Cleaning up package sources"
    
    sources=(
        "postgresql"
        "mongodb"
        "openjdk"
    )
    
    for source in "${sources[@]}"; do
        if [ -f "/etc/apt/sources.list" ]; then
            sed -i "/${source}/d" /etc/apt/sources.list
        fi
        rm -f /etc/apt/sources.list.d/*${source}*
    done
    
    rm -f /var/lib/apt/lists/*postgresql*
    rm -f /var/lib/apt/lists/*mongodb*
    rm -f /var/lib/apt/lists/*openjdk*
    
    apt-get update
}

main() {
    log "INFO" "Starting pre-upgrade cleanup process"
    
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        exit 1
    fi
    
    mkdir -p "${BASE_DIR}"
    
    backup_postgres
    cleanup_packages
    cleanup_sources
    
    log "INFO" "Pre-upgrade cleanup completed successfully"
}

main "$@"