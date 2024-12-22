#!/bin/bash

# Common variables
BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
STATE_FILE="${BASE_DIR}/.upgrade_state"
LOCK_FILE="${BASE_DIR}/.upgrade_lock"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        exit 1
    fi
}

# Create required directories
setup_directories() {
    mkdir -p "${BASE_DIR}/backups"
    chmod 700 "${BASE_DIR}"
}

# Configure unattended upgrade environment
setup_unattended_env() {
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export UCF_FORCE_CONFFNEW=1
    export APT_LISTCHANGES_FRONTEND=none

    # Configure dpkg
    cat > /etc/apt/apt.conf.d/99upgrade-settings << EOF
Dpkg::Options {
   "--force-confdef";
   "--force-confnew";
}
APT::Get::Assume-Yes "true";
APT::Get::allow-downgrades "true";
APT::Get::allow-remove-essential "true";
EOF

    # Disable service restarts prompt
    sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
}