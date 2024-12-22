#!/bin/bash

set -euo pipefail

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
STATE_FILE="${BASE_DIR}/.upgrade_state"
LOCK_FILE="${BASE_DIR}/.upgrade_lock"

source $(dirname "$0")/common.sh

# Main upgrade logic
main() {
    check_root
    setup_directories
    setup_unattended_env
    
    case "$(get_state)" in
        "initial")
            log "INFO" "Starting initial upgrade process"
            pre_upgrade_cleanup
            prepare_22_04
            ;;
        "22.04")
            upgrade_to_22_04
            ;;
        "22.04-verification")
            verify_22_04
            prepare_24_04
            ;;
        "24.04")
            upgrade_to_24_04
            ;;
        *)
            log "ERROR" "Unknown state"
            exit 1
            ;;
    esac
}

main "$@"