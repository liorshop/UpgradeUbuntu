#!/bin/bash

set -euo pipefail

BASE_DIR="/update/upgrade"
LOG_FILE="${BASE_DIR}/upgrade.log"
STATE_FILE="${BASE_DIR}/.upgrade_state"

source $(dirname "$0")/common.sh

setup_unattended_env() {
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export UCF_FORCE_CONFFNEW=1
    export APT_LISTCHANGES_FRONTEND=none

    cat > /etc/apt/apt.conf.d/99upgrade-settings << EOF
Dpkg::Options {
   "--force-confdef";
   "--force-confnew";
}
EOF

    sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
}

prepare_upgrade() {
    apt-get update
    apt-get -y upgrade
    apt-get -y dist-upgrade
    apt-get -y autoremove
    apt-get clean
    apt-get install -y update-manager-core
}

configure_grub() {
    DEVICE=$(grub-probe --target=device /)
    echo "grub-pc grub-pc/install_devices multiselect $DEVICE" | debconf-set-selections
}

perform_upgrade() {
    local target_version=$1
    sed -i 's/Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades
    
    do-release-upgrade -f DistUpgradeViewNonInteractive -m server -d

    if [[ $(lsb_release -rs) == "${target_version}" ]]; then
        return 0
    else
        return 1
    fi
}

save_state() {
    echo "$1" > "${STATE_FILE}"
}

get_state() {
    if [ -f "${STATE_FILE}" ]; then
        cat "${STATE_FILE}"
    else
        echo "initial"
    fi
}

setup_next_boot() {
    cat > /etc/systemd/system/ubuntu-upgrade.service << EOF
[Unit]
Description=Ubuntu Upgrade Process
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${BASE_DIR}/upgrade_manager.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable ubuntu-upgrade.service
}

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi

    mkdir -p "${BASE_DIR}"
    
    case "$(get_state)" in
        "initial")
            ./pre_upgrade_cleanup.sh
            setup_unattended_env
            prepare_upgrade
            configure_grub
            save_state "22.04"
            setup_next_boot
            shutdown -r +1 "Rebooting for upgrade to 22.04"
            ;;
        "22.04")
            if perform_upgrade "22.04"; then
                save_state "24.04"
                shutdown -r +1 "Rebooting after 22.04 upgrade"
            else
                exit 1
            fi
            ;;
        "24.04")
            if perform_upgrade "24.04"; then
                systemctl disable ubuntu-upgrade.service
                rm -f /etc/systemd/system/ubuntu-upgrade.service
                rm -f "${STATE_FILE}"
                shutdown -r +1 "Final reboot after completing upgrade to 24.04"
            else
                exit 1
            fi
            ;;
    esac
}

main "$@"