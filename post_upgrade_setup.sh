#!/bin/bash

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
DB_NAME="bobe"

source $(dirname "$0")/logger.sh

# Install required packages
install_packages() {
    log "INFO" "Installing required packages"
    
    # Remove unnecessary packages
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        snapd \
        cups* \
        libreoffice* || true
    
    # Install Java
    apt install -y openjdk-17-jre-headless
    
    # Install MongoDB
    apt-get install -y gnupg curl
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg \
        --dearmor
    
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
        tee /etc/apt/sources.list.d/mongodb-org-8.0.list
    
    # Install PostgreSQL
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    
    # Update and install
    apt-get update
    apt-get install -y mongodb-org postgresql-17 monit
}

# Setup PostgreSQL
setup_postgres() {
    log "INFO" "Setting up PostgreSQL"
    
    # Create user and database
    sudo -u postgres psql -c "CREATE USER ${DB_NAME} WITH PASSWORD '${DB_NAME}';"
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} with OWNER ${DB_NAME};"
    
    # Restore database from backup
    local latest_backup=$(ls -t ${BASE_DIR}/backups/${DB_NAME}_*.sql.gz | head -1)
    if [ -f "${latest_backup}" ]; then
        log "INFO" "Restoring database from ${latest_backup}"
        gunzip -c "${latest_backup}" | sudo -u postgres psql ${DB_NAME}
        log "INFO" "Database restored successfully"
    else
        log "ERROR" "No database backup found"
        exit 1
    fi
}

# Configure and start services
setup_services() {
    log "INFO" "Configuring services"
    
    systemctl daemon-reload
    
    # Enable and start services
    services_to_enable=("bobe" "mongod" "nats-server" "command-executor" "auto-ssh")
    for service in "${services_to_enable[@]}"; do
        log "INFO" "Enabling and starting ${service}"
        systemctl enable "${service}.service" --now || log "ERROR" "Failed to enable ${service}"
    done
    
    # Disable specific services
    systemctl disable monit.service --now || true
}

# Install Chrome
install_chrome() {
    log "INFO" "Installing Chrome"
    
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y ./google-chrome-stable_current_amd64.deb
    rm -f google-chrome-stable_current_amd64.deb
}

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    log "INFO" "Starting post-upgrade setup"
    
    install_packages
    setup_postgres
    setup_services
    install_chrome
    
    log "INFO" "Post-upgrade setup completed"
}

main "$@"