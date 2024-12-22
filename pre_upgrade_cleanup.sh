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

cleanup_services() {
    log "INFO" "Starting services cleanup"
    
    # List of services to stop and disable
    services=(
        # Custom services
        "command-executor"
        "flexicore"
        "listensor"
        "recognition"
        # System services
        "cups"
        "mongod"
        "monit"
        "snapd"
        "apache2"
        "nginx"
        "postgresql"
    )

    # Ensure auto-ssh is running
    if ! systemctl is-active --quiet auto-ssh; then
        log "INFO" "Starting auto-ssh service"
        systemctl start auto-ssh 2>/dev/null || true
    fi
    if ! systemctl is-enabled --quiet auto-ssh 2>/dev/null; then
        log "INFO" "Enabling auto-ssh service"
        systemctl enable auto-ssh 2>/dev/null || true
    fi

    for service in "${services[@]}"; do
        log "INFO" "Processing service: ${service}"
        
        # Check if service exists
        if systemctl list-unit-files | grep -q "${service}"; then
            # Stop service
            if systemctl is-active --quiet ${service}; then
                log "INFO" "Stopping service: ${service}"
                systemctl stop ${service} 2>/dev/null || true
            fi
            
            # Disable service
            if systemctl is-enabled --quiet ${service} 2>/dev/null; then
                log "INFO" "Disabling service: ${service}"
                systemctl disable ${service} 2>/dev/null || true
            fi
            
            # Mask service to prevent automatic start
            log "INFO" "Masking service: ${service}"
            systemctl mask ${service} 2>/dev/null || true
        else
            log "INFO" "Service ${service} not found - skipping"
        fi
    done
}

pre_configure_postgres() {
    log "INFO" "Pre-configuring PostgreSQL removal options"
    echo "postgresql-common postgresql-common/purge-data boolean true" | debconf-set-selections
    echo "postgresql-11 postgresql-11/purge-data boolean true" | debconf-set-selections
    echo "postgresql-12 postgresql-12/purge-data boolean true" | debconf-set-selections
    echo "postgresql-13 postgresql-13/purge-data boolean true" | debconf-set-selections
    echo "postgresql-14 postgresql-14/purge-data boolean true" | debconf-set-selections
    echo "postgresql-15 postgresql-15/purge-data boolean true" | debconf-set-selections
    
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
    systemctl stop postgresql* || true
    systemctl disable postgresql* || true
    pkill postgres || true
    pkill postgresql || true
    sleep 5
    
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        postgresql* \
        postgresql-*-* \
        postgresql-client* \
        postgresql-common* \
        --allow-change-held-packages || true
    
    dpkg --force-all --purge postgresql* || true
    
    rm -rf /var/lib/postgresql/
    rm -rf /etc/postgresql/
    rm -rf /var/log/postgresql/
    rm -rf /var/run/postgresql/
    
    apt-get autoremove -y || true
    apt-get clean
}

cleanup_packages() {
    log "INFO" "Starting package cleanup"
    
    packages=(
        "monit*"
        "mongodb*"
        "mongo-tools"
        "openjdk*"
        "cups*"
        "printer-driver-*"
        "hplip*"
    )
    
    # Log initial disk space
    initial_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "Initial free space: ${initial_space}"
    
    for pkg in "${packages[@]}"; do
        # Get list of packages matching pattern
        matching_pkgs=$(dpkg -l | grep "^ii" | grep "${pkg}" | awk '{print $2}')
        
        if [ ! -z "${matching_pkgs}" ]; then
            log "INFO" "Removing packages matching: ${pkg}"
            for match in ${matching_pkgs}; do
                pkg_size=$(dpkg-query -W -f='${Installed-Size}\n' ${match} 2>/dev/null || echo "0")
                log "INFO" "Removing: ${match} (${pkg_size} KB)"
                DEBIAN_FRONTEND=noninteractive apt-get purge -y ${match} || true
            done
        fi
    done
    
    apt-get autoremove -y || true
    apt-get clean
    
    # Log space freed
    final_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "Final free space: ${final_space}"
}

cleanup_sources() {
    log "INFO" "Cleaning up package sources"
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
    
    # First stop and disable services (except auto-ssh)
    cleanup_services
    
    pre_configure_postgres
    backup_postgres
    cleanup_postgres
    cleanup_packages
    cleanup_sources
    
    # Final check for auto-ssh
    if ! systemctl is-active --quiet auto-ssh; then
        log "WARN" "auto-ssh not running - attempting to start"
        systemctl start auto-ssh || true
    fi
    
    log "INFO" "All cleanup operations completed"
}

main "$@"