#!/bin/bash

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
DB_NAME="bobe"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Pre-configure all PostgreSQL-related prompts
pre_configure_postgres() {
    log "INFO" "Pre-configuring PostgreSQL removal options"
    
    # Set all possible PostgreSQL prompts to non-interactive
    echo "postgresql-common postgresql-common/purge-data boolean true" | debconf-set-selections
    echo "postgresql-11 postgresql-11/purge-data boolean true" | debconf-set-selections
    echo "postgresql-12 postgresql-12/purge-data boolean true" | debconf-set-selections
    echo "postgresql-13 postgresql-13/purge-data boolean true" | debconf-set-selections
    echo "postgresql-14 postgresql-14/purge-data boolean true" | debconf-set-selections
    echo "postgresql-15 postgresql-15/purge-data boolean true" | debconf-set-selections
    
    # Force removal configuration
    mkdir -p /etc/dpkg/dpkg.cfg.d
    cat > /etc/dpkg/dpkg.cfg.d/postgresql-noninteractive << EOF
force-confdef
force-confnew
EOF
}

backup_postgres() {
    if command -v pg_dump >/dev/null; then
        mkdir -p "${BASE_DIR}/backups"
        BACKUP_FILE="${BASE_DIR}/backups/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"
        if sudo -u postgres pg_dump ${DB_NAME} > "${BACKUP_FILE}"; then
            gzip -c "${BACKUP_FILE}" > "${BACKUP_FILE}.gz"
            log "INFO" "Database backup completed: ${BACKUP_FILE}.gz"
        else
            log "ERROR" "Database backup failed"
            exit 1
        fi
    fi
}

cleanup_postgres() {
    log "INFO" "Starting PostgreSQL cleanup"
    
    # Stop PostgreSQL services first
    systemctl stop postgresql* || true
    systemctl disable postgresql* || true
    
    # Kill any remaining PostgreSQL processes
    pkill postgres || true
    pkill postgresql || true
    
    sleep 5  # Give processes time to stop
    
    # Force remove all PostgreSQL packages
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        postgresql* \
        postgresql-*-* \
        postgresql-client* \
        postgresql-common* \
        --allow-change-held-packages || true
        
    # Force remove any remaining packages
    dpkg --force-all --purge postgresql* || true
    
    # Remove all PostgreSQL directories
    rm -rf /var/lib/postgresql/
    rm -rf /etc/postgresql/
    rm -rf /var/log/postgresql/
    rm -rf /var/run/postgresql/
    
    # Clean package system
    apt-get autoremove -y || true
    apt-get clean
}

cleanup_packages() {
    log "INFO" "Starting package cleanup"
    
    services=("mongod" "monit")
    for service in "${services[@]}"; do
        systemctl stop ${service} 2>/dev/null || true
        systemctl disable ${service} 2>/dev/null || true
    done
    
    packages=(
        "monit*"
        "mongodb*"
        "mongo-tools"
        "openjdk*"
    )
    
    for pkg in "${packages[@]}"; do
        DEBIAN_FRONTEND=noninteractive apt-get purge -y ${pkg} || true
    done
    
    apt-get autoremove -y || true
    apt-get clean
}

cleanup_sources() {
    log "INFO" "Cleaning up package sources"
    
    # Remove repository configurations
    rm -f /etc/apt/sources.list.d/pgdg*.list
    rm -f /etc/apt/sources.list.d/postgresql*.list
    
    sources=(
        "postgresql"
        "mongodb"
        "openjdk"
    )
    
    for source in "${sources[@]}"; do
        if [ -f "/etc/apt/sources.list" ]; then
            sed -i "/${source}/d" /etc/apt/sources.list
        fi
        rm -f /etc/apt/sources.list.d/*${source}* || true
    done
    
    rm -f /var/lib/apt/lists/*postgresql*
    rm -f /var/lib/apt/lists/*mongodb*
    rm -f /var/lib/apt/lists/*openjdk*
    
    apt-get update -o Acquire::AllowInsecureRepositories=true || true
}

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    mkdir -p "${BASE_DIR}"
    
    # First pre-configure everything
    pre_configure_postgres
    
    # Then backup the database
    backup_postgres
    
    # Clean up PostgreSQL completely
    cleanup_postgres
    
    # Continue with other cleanups
    cleanup_packages
    cleanup_sources
    
    log "INFO" "All cleanup operations completed"
}

main "$@"