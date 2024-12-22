#!/bin/bash

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

backup_postgres() {
    if command -v pg_dump >/dev/null; then
        mkdir -p "${BASE_DIR}/backups"
        BACKUP_FILE="${BASE_DIR}/backups/bobe_$(date +%Y%m%d_%H%M%S).sql"
        if sudo -u postgres pg_dump bobe > "${BACKUP_FILE}"; then
            gzip -c "${BACKUP_FILE}" > "${BACKUP_FILE}.gz"
            log "INFO" "Database backup completed: ${BACKUP_FILE}.gz"
        else
            log "ERROR" "Database backup failed"
            exit 1
        fi
    fi
}

cleanup_packages() {
    services=("postgresql" "mongod" "monit")
    for service in "${services[@]}"; do
        systemctl stop ${service} 2>/dev/null || true
    done

    packages=(
        "postgresql*"
        "monit*"
        "mongodb*"
        "mongo-tools"
        "openjdk*"
    )

    for pkg in "${packages[@]}"; do
        apt-get purge -y ${pkg} || true
    done

    apt-get autoremove -y
    apt-get clean
}

cleanup_sources() {
    sources=(
        "postgresql"
        "mongodb"
        "openjdk"
    )

    for source in "${sources[@]}"; do
        sed -i "/${source}/d" /etc/apt/sources.list
        rm -f /etc/apt/sources.list.d/*${source}*
    done

    rm -f /var/lib/apt/lists/*postgresql*
    rm -f /var/lib/apt/lists/*mongodb*
    rm -f /var/lib/apt/lists/*openjdk*

    apt-get update
}

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi

    mkdir -p "${BASE_DIR}"
    
    backup_postgres
    cleanup_packages
    cleanup_sources
}

main "$@"