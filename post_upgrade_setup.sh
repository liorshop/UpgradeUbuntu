#!/bin/bash

set -euo pipefail

# Source required modules
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logger.sh"

# Component name for logging
COMPONENT="SETUP"

# Install required packages
install_packages() {
    log "INFO" "${COMPONENT}" "Installing required packages"
    
    # Remove unnecessary packages first
    log "INFO" "${COMPONENT}" "Removing unnecessary packages"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        snapd \
        cups* \
        libreoffice* || true
    
    # Install Java
    log "INFO" "${COMPONENT}" "Installing OpenJDK"
    apt-get install -y openjdk-17-jre-headless
    
    # Install MongoDB
    log "INFO" "${COMPONENT}" "Setting up MongoDB repository"
    apt-get install -y gnupg curl
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg \
        --dearmor
    
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
        tee /etc/apt/sources.list.d/mongodb-org-8.0.list
    
    # Install PostgreSQL
    log "INFO" "${COMPONENT}" "Setting up PostgreSQL repository"
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    
    # Update and install packages
    log "INFO" "${COMPONENT}" "Installing packages"
    apt-get update
    apt-get install -y mongodb-org postgresql-17 monit
    
    # Install Chrome
    log "INFO" "${COMPONENT}" "Installing Chrome"
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt-get install -y ./google-chrome-stable_current_amd64.deb
    rm -f google-chrome-stable_current_amd64.deb
}

# Setup PostgreSQL
setup_postgres() {
    log "INFO" "${COMPONENT}" "Setting up PostgreSQL for ${DB_NAME}"
    
    # Create user and database
    sudo -u postgres psql -c "DROP USER IF EXISTS ${DB_USER};"
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};"
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER};"
    
    # Restore database from backup
    local latest_backup=$(ls -t "${BACKUP_DIR}/${DB_NAME}"_*.sql.gz 2>/dev/null | head -1)
    if [ -n "${latest_backup}" ]; then
        log "INFO" "${COMPONENT}" "Restoring database from ${latest_backup}"
        gunzip -c "${latest_backup}" | sudo -u postgres psql "${DB_NAME}"
        log "INFO" "${COMPONENT}" "Database restored successfully"
    else
        log "WARN" "${COMPONENT}" "No database backup found to restore"
    fi
}

# Configure and start services
setup_services() {
    log "INFO" "${COMPONENT}" "Configuring services"
    
    systemctl daemon-reload
    
    # Services to enable and start
    local services_enable=(
        "bobe"
        "mongod"
        "nats-server"
        "command-executor"
        "auto-ssh"
    )
    
    # Enable and start services
    for service in "${services_enable[@]}"; do
        log "INFO" "${COMPONENT}" "Enabling and starting ${service}"
        systemctl enable "${service}.service" || log "WARN" "${COMPONENT}" "Failed to enable ${service}"
        systemctl start "${service}.service" || log "WARN" "${COMPONENT}" "Failed to start ${service}"
    done
    
    # Disable specific services
    systemctl disable monit.service
    systemctl stop monit.service
}

# Main execution
main() {
    log "INFO" "${COMPONENT}" "Starting post-upgrade setup"
    
    # Initialize
    initialize
    
    # Run setup steps
    install_packages
    setup_postgres
    setup_services
    
    log "INFO" "${COMPONENT}" "Post-upgrade setup completed"
}

# Set up error handling
trap 'log "ERROR" "${COMPONENT}" "Script failed on line $LINENO"' ERR

# Run main
main "$@"