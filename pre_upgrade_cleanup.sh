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
    log "INFO" "${COMPONENT}" "Starting PostgreSQL backup"
    
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

# Service cleanup
cleanup_services() {
    log "INFO" "${COMPONENT}" "Starting services cleanup"
    
    # Services to manage
    local services_to_stop=(
        "command-executor"
        "flexicore"
        "listensor"
        "recognition"
        "cups"
        "mongod"
        "monit"
        "snapd"
        "postgresql"
    )

    # Keep auto-ssh running
    if ! systemctl is-active --quiet auto-ssh; then
        log "INFO" "${COMPONENT}" "Starting auto-ssh service"
        systemctl start auto-ssh || true
    fi
    systemctl enable auto-ssh || true

    # Stop and disable other services
    for service in "${services_to_stop[@]}"; do
        if systemctl list-unit-files | grep -q "${service}"; then
            log "INFO" "${COMPONENT}" "Stopping and disabling ${service}"
            systemctl stop "${service}" 2>/dev/null || true
            systemctl disable "${service}" 2>/dev/null || true
            systemctl mask "${service}" 2>/dev/null || true
        fi
    done
}

# Package cleanup
cleanup_packages() {
    log "INFO" "${COMPONENT}" "Starting package cleanup"
    
    # Packages to remove
    local packages=(
        "postgresql*"
        "monit*"
        "mongodb*"
        "mongo-tools"
        "openjdk*"
        "cups*"
        "printer-driver-*"
        "hplip*"
        "google-chrome*"
        "chromium*"
        "snapd"
        "libreoffice*"
    )
    
    # Remove snaps first
    log "INFO" "${COMPONENT}" "Removing snap packages"
    snap list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r pkg; do
        log "INFO" "${COMPONENT}" "Removing snap: ${pkg}"
        snap remove --purge "${pkg}" || true
    done
    
    # Log initial space
    local initial_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "${COMPONENT}" "Initial free space: ${initial_space}"
    
    # Remove packages
    for pkg in "${packages[@]}"; do
        log "INFO" "${COMPONENT}" "Processing package pattern: ${pkg}"
        dpkg-query -W -f='${Package}\n' "${pkg}" 2>/dev/null | while read -r package; do
            if [ -n "${package}" ]; then
                local size=$(dpkg-query -W -f='${Installed-Size}\n' "${package}" 2>/dev/null || echo "unknown")
                log "INFO" "${COMPONENT}" "Removing package: ${package} (${size} KB)"
                DEBIAN_FRONTEND=noninteractive apt-get purge -y "${package}" || true
            fi
        done
    done
    
    # Cleanup
    apt-get autoremove -y || true
    apt-get clean
    
    # Remove snap directories
    rm -rf /snap /var/snap /var/lib/snapd
    
    # Log space freed
    local final_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "${COMPONENT}" "Final free space: ${final_space}"
}

# Source cleanup
cleanup_sources() {
    log "INFO" "${COMPONENT}" "Cleaning up package sources"
    
    # Remove repository configurations
    rm -f /etc/apt/sources.list.d/pgdg*.list
    rm -f /etc/apt/sources.list.d/postgresql*.list
    rm -f /etc/apt/sources.list.d/mongodb*.list
    rm -f /etc/apt/sources.list.d/google*.list
    
    # Clean up sources.list
    local sources=(
        "postgresql"
        "mongodb"
        "openjdk"
        "google"
    )
    
    for source in "${sources[@]}"; do
        if [ -f "/etc/apt/sources.list" ]; then
            sed -i "/${source}/d" /etc/apt/sources.list
        fi
    done
    
    # Clean package lists
    rm -f /var/lib/apt/lists/*
    
    apt-get update || true
}

# Main execution
main() {
    log "INFO" "${COMPONENT}" "Starting pre-upgrade cleanup"
    
    # Initialize
    initialize
    
    # Run cleanup steps
    pre_configure
    backup_postgres
    cleanup_services
    cleanup_packages
    cleanup_sources
    
    log "INFO" "${COMPONENT}" "Pre-upgrade cleanup completed"
}

# Set up error handling
trap 'log "ERROR" "${COMPONENT}" "Script failed on line $LINENO"' ERR

# Run main
main "$@"