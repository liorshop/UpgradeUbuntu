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
    
    # Perform backup with timeout
    if timeout 3600 sudo -u postgres pg_dump ${DB_NAME} > "${BACKUP_FILE}"; then
        gzip -9 "${BACKUP_FILE}"
        log "INFO" "${COMPONENT}" "Database backup completed: ${BACKUP_FILE}.gz"
        
        # Verify backup file exists and has size
        if [ ! -s "${BACKUP_FILE}.gz" ]; then
            log "ERROR" "${COMPONENT}" "Backup file is empty or missing"
            return 1
        fi
        
        # Fix permissions after backup
        chmod 600 "${BACKUP_FILE}.gz"
        chmod 700 "${BACKUP_DIR}"
        chown -R root:root "${BACKUP_DIR}"
    else
        log "ERROR" "${COMPONENT}" "Database backup failed"
        chmod 700 "${BACKUP_DIR}"  # Restore permissions even on failure
        return 1
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
            sleep 2  # Give service time to stop
            systemctl disable "${service}" 2>/dev/null || true
            systemctl mask "${service}" 2>/dev/null || true
        fi
    done
}

# Package cleanup
cleanup_packages() {
    log "INFO" "${COMPONENT}" "Starting package cleanup"
    
    # Log initial state
    log "INFO" "${COMPONENT}" "Initial package state:"
    dpkg -l | grep -E 'postgresql|mongodb|monit|cups|snap|openjdk' || true
    
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
    
    # Remove snaps first with verification
    log "INFO" "${COMPONENT}" "Removing snap packages"
    if command -v snap >/dev/null; then
        snap list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r pkg; do
            log "INFO" "${COMPONENT}" "Removing snap: ${pkg}"
            snap remove --purge "${pkg}" || true
            sleep 2  # Give time for snap removal
        done
    fi
    
    # Log initial space
    local initial_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "${COMPONENT}" "Initial free space: ${initial_space}"
    
    # Remove packages with verification
    for pkg in "${packages[@]}"; do
        log "INFO" "${COMPONENT}" "Processing package pattern: ${pkg}"
        dpkg-query -W -f='${Package}\n' "${pkg}" 2>/dev/null | while read -r package; do
            if [ -n "${package}" ]; then
                local size=$(dpkg-query -W -f='${Installed-Size}\n' "${package}" 2>/dev/null || echo "unknown")
                log "INFO" "${COMPONENT}" "Removing package: ${package} (${size} KB)"
                DEBIAN_FRONTEND=noninteractive apt-get purge -y "${package}" || true
                sleep 2  # Give time for package removal
            fi
        done
    done
    
    # Cleanup with verification
    apt-get autoremove -y || true
    apt-get clean
    
    # Remove snap directories
    rm -rf /snap /var/snap /var/lib/snapd
    
    # Log final state
    local final_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "${COMPONENT}" "Final free space: ${final_space}"
    log "INFO" "${COMPONENT}" "Final package state:"
    dpkg -l | grep -E 'postgresql|mongodb|monit|cups|snap|openjdk' || true
}

# Main execution
main() {
    log "INFO" "${COMPONENT}" "Starting pre-upgrade cleanup"
    
    # Initialize
    initialize
    
    # Run cleanup steps with verification
    pre_configure
    log "INFO" "${COMPONENT}" "Pre-configuration completed"
    sleep 2
    
    backup_postgres || log "ERROR" "${COMPONENT}" "Backup failed but continuing"
    sleep 2
    
    cleanup_services || log "ERROR" "${COMPONENT}" "Service cleanup failed but continuing"
    sleep 2
    
    cleanup_packages || log "ERROR" "${COMPONENT}" "Package cleanup failed but continuing"
    sleep 2
    
    log "INFO" "${COMPONENT}" "Pre-upgrade cleanup completed"
}

# Set up error handling
trap 'log "ERROR" "${COMPONENT}" "Script failed on line $LINENO"' ERR

# Run main
main "$@"