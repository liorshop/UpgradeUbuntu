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
        "google-chrome*"
        "snapd"
        "snap"
        "chromium*"
    )
    
    # Stop and remove snap
    log "INFO" "Removing snap packages"
    snap list | awk 'NR>1 {print $1}' | while read pkg; do
        log "INFO" "Removing snap package: ${pkg}"
        snap remove --purge "${pkg}" || true
    done
    
    # Stop snapd services
    systemctl stop snapd.service snapd.socket snapd.seeded.service || true
    systemctl disable snapd.service snapd.socket snapd.seeded.service || true
    
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
    
    # Remove snap directories
    rm -rf /snap
    rm -rf /var/snap
    rm -rf /var/lib/snapd
    
    apt-get autoremove -y || true
    apt-get clean
    
    # Log space freed
    final_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "Final free space: ${final_space}"
}

# Rest of the script remains the same
