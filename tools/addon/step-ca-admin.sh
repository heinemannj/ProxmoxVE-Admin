#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/admin-core.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/smallstep-core.func)

APP="step-cli"
APP_TITLE="step-ca Admin"
APP_BACKTITLE="Proxmox VE Helper Scripts"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/etc/step"
CA_PATH="/etc/step-ca"
CERT_PATH="${CONFIG_PATH}/certs"
KEY_PATH="${CONFIG_PATH}/private"

function header_info() {
  clear
  cat <<"EOF"
         __                                 ___       __          _     
   _____/ /____  ____        _________ _   /   | ____/ /___ ___  (_)___ 
  / ___/ __/ _ \/ __ \______/ ___/ __ `/  / /| |/ __  / __ `__ \/ / __ \
 (__  ) /_/  __/ /_/ /_____/ /__/ /_/ /  / ___ / /_/ / / / / / / / / / /
/____/\__/\___/ .___/      \___/\__,_/  /_/  |_\__,_/_/ /_/ /_/_/_/ /_/ 
             /_/                                                            

EOF
}

function x509_list() {
  DB_EXPORT=""
  CERT_LIST=()
  local LIST=""
  cp --recursive --force "$CA_PATH/db/"* "$CONFIG_PATH/db-copy/"
  cp --recursive --force "$CA_PATH/certs/"* "$CONFIG_PATH/certs/ca/"
  if [[ $(step-badger x509Certs "${CONFIG_PATH}/db-copy" 2>/dev/null) ]]; then
    DB_EXPORT=$(step-badger x509Certs "${CONFIG_PATH}/db-copy" 2>/dev/null)
    LIST=$(echo "$DB_EXPORT" | awk 'NR>1 {print $1 " " $2 "|" $3 "|" $4 "|" $5}')
  fi
  while read -r TAG ITEM; do
    CERT_LIST+=("$TAG" "$ITEM")
  done < <(echo "$LIST")
}

#function ssh_list() {
#  CERT_LIST=""
#  cp --recursive --force "$CA_PATH/db/"* "$CONFIG_PATH/db-copy/"
#  cp --recursive --force "$CA_PATH/certs/"* "$CONFIG_PATH/certs/ca/"
#  if [[ $(step-badger sshCerts "${CONFIG_PATH}/db-copy" 2>/dev/null) ]]; then
#    CERT_LIST=$(step-badgersshCerts ${CONFIG_PATH}/db-copy 2>/dev/null)
#  fi
#}

function x509_serial_to_cn() {
  CN="$(echo "${DB_EXPORT}" | grep "${SERIAL_NUMBER}" | awk '{print $2}' | sed 's/CN=//g')"
  CRT="$CERT_PATH/x509/$CN.crt"
  KEY="$KEY_PATH/$CN.key"
  if ! [[ -f ${CRT} ]]; then
    die "Certificate ${CRT} not found on localhost!"
  elif ! [[ -f ${KEY} ]]; then
    die "Private Key ${KEY} not found on localhost!"
  fi
}

function x509_inspect() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Inspect"
  msg_info "Inspecting Certificate(s)"
  for SERIAL_NUMBER in "${CERT_ARRAY[@]}"; do
    echo -e "${BL}[Info]${GN} Inspect x509 Certificate with Serial Number ${BL}${SERIAL_NUMBER}${GN}:${CL}\n"
    x509_serial_to_cn
    step certificate inspect "${CRT}" || die "Failed to inspect certificate!"
    if ! [[ $(step certificate inspect "${CRT}" | grep "${SERIAL_NUMBER}") ]]; then
      die "Serial Number ${SERIAL_NUMBER} mismatch!"
    fi
    echo -e "\n${BL}[Info]${GN} Public Key:${CL}\n"
    cat "${CRT}"
    echo -e "\n${BL}[Info]${GN} Private Key:${CL}\n"
    cat "${KEY}"
  done
  msg_ok "Inspected Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_renew() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Renew"
  msg_info "Renewing Certificate(s)"
  for SERIAL_NUMBER in "${CERT_ARRAY[@]}"; do
    echo -e "${BL}[Info]${GN} Renew x509 Certificate with Serial Number ${BL}${SERIAL_NUMBER}${GN}:${CL}"
    echo
    x509_serial_to_cn
    step ca renew "${CRT}" "${KEY}" --force || die "Failed to renew certificate!"
    echo
  done
  msg_ok "Renewed Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_revoke() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Revoke"
  msg_info "Revoking Certificate(s)"
  for SERIAL_NUMBER in "${CERT_ARRAY[@]}"; do
    echo -e "${BL}[Info]${GN} Revoke x509 Certificate with Serial Number ${BL}${SERIAL_NUMBER}${GN}:${CL}"
    echo
    TOKEN=$(step ca token --provisioner="$PROVISIONER" --provisioner-password-file="$PROVISIONER_PASSWORD" --revoke "${SERIAL_NUMBER}")
    step ca revoke --token "$TOKEN" "${SERIAL_NUMBER}" || die "Failed to revoke certificate!"
    echo
  done
  msg_ok "Revoked Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_certs_menu() {
  local CERT_ACTION=$1
  #local CERT_FILE_ARRAY=("${CERT_PATH}"/x509/*.crt)
  #local CERT_FILE
  #local CERT_FQDN
  #local CERT_LIST=()
  local CHOICE
  #for CERT_FILE in "${CERT_FILE_ARRAY[@]}"; do
  #  CERT_FQDN=$(echo "$CERT_FILE" | awk -F '/' '{print $5}' | sed 's/.crt//g')
  #  CERT_LIST+=("${CERT_FQDN}" "${CERT_FILE}")
  #done

  x509_list

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
