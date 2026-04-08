#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/smallstep/cli

source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/admin-core.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/smallstep-core.func)

APP="step-cli"
APP_TITLE="step-cli ACME Client"
APP_BACKTITLE="Proxmox VE Helper Scripts"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/etc/step"
CA_PATH="/etc/step-ca"
CERT_PATH="${CONFIG_PATH}/certs"
KEY_PATH="${CONFIG_PATH}/private"

function header_info {
  clear
  cat <<"EOF"
         __                        ___    ___   ________  _________   _________            __ 
   _____/ /____  ____        _____/ (_)  /   | / ____/  |/  / ____/  / ____/ (_)__  ____  / /_
  / ___/ __/ _ \/ __ \______/ ___/ / /  / /| |/ /   / /|_/ / __/    / /   / / / _ \/ __ \/ __/
 (__  ) /_/  __/ /_/ /_____/ /__/ / /  / ___ / /___/ /  / / /___   / /___/ / /  __/ / / / /_  
/____/\__/\___/ .___/      \___/_/_/  /_/  |_\____/_/  /_/_____/   \____/_/_/\___/_/ /_/\__/  
             /_/                                                                              

EOF
}

function x509_renew() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Renew"

  msg_info "Renewing Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Renew x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step ca renew --force "${CRT}" "${KEY}" || die "Failed to renew certificate!"
    x509_inspect "$CERT_SUBJECT"
  done
  msg_ok "Renewed Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_revoke() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Revoke"
  msg_info "Revoking Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Revoke x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step ca revoke --cert "${CRT}" --key "${KEY}" || die "Failed to revoke certificate!"
    rm -f "${CRT}" || die "Failed to delete ${CRT}!"
    rm -f "${KEY}" || die "Failed to delete ${KEY}!"
  done
  msg_ok "Revoked Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_inspect() {
  CERT_ARRAY=("$1")
  [[ -z ${CERT_ARRAY[*]} ]] && x509_certs_menu "Inspect"
  local BACK_TO_MENU="$2"

  msg_info "Inspecting Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Inspect x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step certificate inspect "${CRT}" || die "Failed to inspect certificate!"
    echo -e "${BL}[Info]${GN} Public Key:${CL}"
    cat "${CRT}"
    echo -e "${BL}[Info]${GN} Private Key:${CL}"
    cat "${KEY}"
  done
  msg_ok "Inspected Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_certs_menu() {
  local CERT_ACTION=$1
  local CERT_FILE_ARRAY=("${CERT_PATH}"/*.crt)
  local CERT_FILE
  local CERT_FQDN
  local CERT_LIST=()
  local CHOICE
  for CERT_FILE in "${CERT_FILE_ARRAY[@]}"; do
    CERT_FQDN=$(echo "$CERT_FILE" | awk -F '/' '{print $5}' | sed 's/.crt//g')
    CERT_LIST+=("${CERT_FQDN}" "${CERT_FILE}")
  done
  CHOICE=$(whiptail_checklist "Certificates by step" "\nSelect Certificate(s) to ${CERT_ACTION}:" "CERT_LIST")
  if [[ -z $CHOICE ]]; then
    x509_maintenance_menu
  else
    # shellcheck disable=SC2206
    CERT_ARRAY=(${CHOICE})
  fi
}

header_info
detect_os
app_init
main_menu
