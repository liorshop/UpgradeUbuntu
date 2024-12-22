#!/bin/bash

set -euo pipefail

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
STATE_FILE="${BASE_DIR}/.upgrade_state"

source $(dirname "$0")/common.sh

# ... [previous functions remain the same] ...

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi

    mkdir -p "${BASE_DIR}"
    
    case "$(get_state)" in
        "initial")
            # Check cleanup script exists and is executable
            CLEANUP_SCRIPT="${BASE_DIR}/pre_upgrade_cleanup.sh"
            if [ ! -x "$CLEANUP_SCRIPT" ]; then
                log "ERROR" "Cleanup script not found or not executable: $CLEANUP_SCRIPT"
                exit 1
            fi
            
            log "INFO" "Starting pre-upgrade cleanup"
            $CLEANUP_SCRIPT
            
            setup_unattended_env
            prepare_upgrade
            configure_grub
            save_state "22.04"
            setup_next_boot
            shutdown -r +1 "Rebooting for upgrade to 22.04"
            ;;
        # ... [rest of the cases remain the same] ...
    esac
}

main "$@"