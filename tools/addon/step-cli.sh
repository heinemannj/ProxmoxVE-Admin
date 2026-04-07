#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/smallstep/cli

#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/main/misc/core.func)
#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/main/misc/tools.func)

source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/admin-core.func)

APP="step-cli"
APP_TITLE="step-cli ACME Client"
APP_BACKTITLE="Proxmox VE Helper Scripts"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/etc/step"
CERT_PATH="${CONFIG_PATH}/certs"
KEY_PATH="${CONFIG_PATH}/private"
PROVISIONER_TYPE="ACME"
export STEPPATH=${CONFIG_PATH}
sed  -i '1i export STEPPATH=/etc/step' /etc/profile

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

function renew() {
  local BACK_TO_MENU="$1"
  certs_menu "Renew"

  msg_info "Renewing Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Renew x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step ca renew --force "${CRT}" "${KEY}" || die "Failed to renew certificate!"
    inspect "$CERT_SUBJECT"
  done
  msg_ok "Renewed Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function revoke() {
  local BACK_TO_MENU="$1"
  certs_menu "Revoke"
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

function inspect() {
  CERT_ARRAY=("$1")
  [[ -z ${CERT_ARRAY[*]} ]] && certs_menu "Inspect"
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

function bootstrap_fqdn_check() {
  if [[ -z $CA_FQDN ]]; then
    CA_FQDN="Please change!"
    return 1
  else
    CA_IP=$(resolve_ip "${CA_FQDN}")
    if [[ -z $CA_IP ]]; then
      CA_FQDN="DNS Resolution failed - Please change!"
      return 1
    fi
  fi
}

function bootstrap_fingerprint_check() {
  if [[ -z $CA_FINGERPRINT ]]; then
    CA_FINGERPRINT="Please change!"
    return 1
  fi
}

function bootstrap() {
  local BACK_TO_MENU="$1"
  CA_FQDN="step-ca.$(hostname -d)"
  bootstrap_menu
  msg_info "Installing step-ca Root Certificate"
  $STD step ca bootstrap -f --ca-url https://"$CA_FQDN" --install --fingerprint "$CA_FINGERPRINT"  || die "step-ca Bootstrapping failed!"
  $STD step certificate install --all "${CERT_PATH}"/root_ca.crt || die "Installation of step-ca Root Certificate failed!"
  $STD update-ca-certificates  || die "Update of System CA Certificates failed!"
  $STD step certificate inspect https://"$CA_FQDN" || die "Inspection of step-ca Root Certificate failed!"
  msg_ok "Installed step-ca Root Certificate"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function request() {
  local BACK_TO_MENU="$1"
  VALID_TO="168h"
  FQDN=$(hostname -f)
  HOST=$(hostname)
  DOMAINNAME=$(hostname -d)
  IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
  PROVISIONER="acme@$DOMAINNAME"
  SAN=""

  request_menu

  msg_info "Requesting System Certificate by $PROVISIONER"
  local SAN_ITEMS=("$FQDN" "$HOST" "$IP" "$SAN")
  local SAN_FLAGS=()
  for item in "${SAN_ITEMS[@]}"; do
    SAN_FLAGS+=(--san "$item")
  done

  step ca certificate "$FQDN" \
    "${CERT_PATH}"/"$FQDN".crt \
    "${KEY_PATH}"/"$FQDN".key \
    --provisioner="$PROVISIONER" \
    --not-after="$VALID_TO" \
    -f \
    "${SAN_FLAGS[@]}" || die "Certificate Signing Request (CSR) by $PROVISIONER failed!"

  inspect "$FQDN"
  msg_ok "Requested System Certificate by $PROVISIONER"

  msg_info "Starting Certificate Renewal as a Daemon"
  $STD systemctl enable --now cert-renewer@"${FQDN}".timer
  systemctl list-units cert-renewer@\*.timer
  msg_ok "Started Certificate Renewal as a Daemon"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function detect_os() {
  if grep -qi "alpine" /etc/os-release; then
    #OS="Alpine"
    PKG_UPDATE=""
    PKG_INSTALL="apk add --no-cache"
    PKG_UPGRADE="apk update"
    PKG_UNINSTALL="apk del"
    PKG_AUTOREMOVE=""
  elif grep -qi "arch" /etc/os-release; then
    #OS="Arch"
    PKG_UPDATE=""
    PKG_INSTALL="pacman -S"
    PKG_UPGRADE="pacman -Syu"
    PKG_UNINSTALL="pacman -Rs"
    PKG_AUTOREMOVE=""
  elif grep -qi "debian" /etc/os-release; then
    #OS="Debian"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    if ! [[ -f /etc/apt/sources.list.d/smallstep.sources ]]; then
      setup_deb822_repo \
        "smallstep" \
        "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
        "https://packages.smallstep.com/stable/debian" \
        "debs" \
        "main"
    fi
  elif grep -qi "ubuntu" /etc/os-release; then
    #OS="Ubuntu"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    if ! [[ -f /etc/apt/sources.list.d/smallstep.sources ]]; then
      setup_deb822_repo \
        "smallstep" \
        "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
        "https://packages.smallstep.com/stable/debian" \
        "debs" \
        "main"
    fi
  else
    die "Unsupported OS. Exiting."
  fi
}

function uninstall() {
  msg_info "Uninstalling $APP"
  systemctl disable cert-renewer@.timer
  systemctl disable cert-renewer@.service
  systemctl stop cert-renewer@*.timer
  systemctl stop cert-renewer@*.service
  $PKG_UNINSTALL $APP
  $PKG_AUTOREMOVE
  rm -rf "${CONFIG_PATH}"
  rm -f "/usr/local/bin/update_${APP,,}"
  rm -f "/etc/systemd/system/cert-renewer@.service"
  rm -f "/etc/systemd/system/cert-renewer@.timer"
  $STD systemctl daemon-reload
  msg_ok "Uninstalled $APP"
}

function update() {
  if [[ ! -e $BINARY_PATH ]]; then
    die "$APP is not installed"
  fi
  msg_info "Updating $APP"
  $PKG_UPDATE
  $PKG_UPGRADE $APP
  msg_ok "Updated $APP successfully"
}

function install() {
  msg_info "Installing dependencies"
  $PKG_UPDATE
  $PKG_INSTALL curl whiptail dnsutils jq
  msg_ok "Installed dependencies"

  msg_info "Installing $APP"
  $PKG_INSTALL $APP
  if [[ ! -e $BINARY_PATH ]]; then
    ln -s /usr/bin/step-cli $BINARY_PATH
  fi
  mkdir -p "$CONFIG_PATH"/certs
  mkdir -p "$CONFIG_PATH"/private
  
  cat <<'EOF' >/etc/systemd/system/cert-renewer@.service
[Unit]
Description=Certificate renewer for %i
After=network-online.target
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
StartLimitIntervalSec=0
; PartOf=cert-renewer.target

[Service]
Type=oneshot
User=root

Environment=STEPPATH="/etc/step" CERT_LOCATION="/etc/step/certs/%i.crt" KEY_LOCATION="/etc/step/private/%i.key"

; ExecCondition checks if the certificate is ready for renewal,
; based on the exit status of the command.
; (In systemd <242, you can use ExecStartPre= here.)
ExecCondition=/usr/bin/step certificate needs-renewal "${CERT_LOCATION}"

; ExecStart renews the certificate, if ExecStartPre was successful.
ExecStart=/usr/bin/step ca renew --force "${CERT_LOCATION}" "${KEY_LOCATION}"

; Try to reload or restart the systemd service that relies on this cert-renewer
; If the relying service doesn't exist, forge ahead.
; (In systemd <229, use 'reload-or-try-restart' instead of 'try-reload-or-restart')
ExecStartPost=/usr/bin/env sh -c "! systemctl --quiet is-active %i.service || systemctl try-reload-or-restart %i"

[Install]
WantedBy=multi-user.target
EOF

  cat <<'EOF' >/etc/systemd/system/cert-renewer@.timer
[Unit]
Description=Timer for certificate renewal of %i
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
; PartOf=cert-renewer.target

[Timer]
Persistent=true

; Run the timer unit every 2 minutes.
OnCalendar=*:1/2

; Always run the timer on time.
AccuracySec=1us

; Add jitter to prevent a "thundering hurd" of simultaneous certificate renewals.
RandomizedDelaySec=12s

[Install]
WantedBy=timers.target
EOF
  $STD systemctl daemon-reload
  msg_ok "Installed $APP"

  $STD bootstrap "" || die "Installation of step-ca Root Certificate failed!"
  $STD request "" || die "Main - Request System Certificate failed!"
}

function certs_menu() {
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
    maintenance_menu
  else
    # shellcheck disable=SC2206
    CERT_ARRAY=(${CHOICE})
  fi
}

function request_menu() {
  local CHOICE
  OPTIONS=("FQDN" "$FQDN"
    "Hostname" "$HOST"
    "IP Address" "$IP"
    "Subject Alternative Name(s) (SANs)" "$SAN"
    "Validity" "$VALID_TO"
    "Provisioner" "$PROVISIONER"
	" " " "
    "<Continue>" "Request Certificate by $PROVISIONER")
  local TITLE="Certificate Signing Request (CSR) by $PROVISIONER_TYPE"

  CHOICE=$(whiptail_menu "$TITLE")
  case "$CHOICE" in
    "FQDN")
      FQDN=$(whiptail_inputbox "$TITLE" "FQDN (e.g. $FQDN)" "$FQDN")
      request_menu
      ;;
    "Hostname")
      HOST=$(whiptail_inputbox "$TITLE" "Hostname (e.g. $HOST)" "$HOST")
      request_menu
      ;;
    "IP Address")
      IP=$(whiptail_inputbox "$TITLE" "IP Address (e.g. $IP)" "$IP")
      request_menu
      ;;
    "Subject Alternative Name(s) (SANs)")
      SAN=$(whiptail_inputbox "$TITLE" "Subject Alternative Name(s) (SAN) (e.g. MyApp.$DOMAINNAME)" "$SAN")
      request_menu
      ;;
    "Validity")
      VALID_TO=$(whiptail_inputbox "$TITLE" "Validity (e.g. 168h)" "$VALID_TO")
      request_menu
      ;;
    "Provisioner")
      PROVISIONER=$(whiptail_inputbox "$TITLE" "Provisioner (e.g. $PROVISIONER)" "$PROVISIONER")
      request_menu
      ;;
    " ")
      request_menu
      ;;
    "<Continue>") ;;
    *) maintenance_menu ;;
    esac
}

function bootstrap_menu() {
  local CHOICE
  bootstrap_fqdn_check
  bootstrap_fingerprint_check

  OPTIONS=("step-ca FQDN" "$CA_FQDN"
    "step-ca Fingerprint" "$CA_FINGERPRINT"
	  " " " "
    "<Continue>" "Install step-ca Root Certificate")
  local TITLE="step-ca Bootstrap Options"

  CHOICE=$(whiptail_menu "$TITLE")
  case "$CHOICE" in
    "step-ca FQDN")
      CA_FQDN=$(whiptail_inputbox "$TITLE" "step-ca FQDN (e.g. $CA_FQDN)" "$CA_FQDN")
      bootstrap_menu
      ;;
    "step-ca Fingerprint")
      CA_FINGERPRINT=$(whiptail_inputbox "$TITLE" "step-ca Fingerprint" "$CA_FINGERPRINT")
      bootstrap_menu
      ;;
    " ")
      bootstrap_menu
      ;;
    "<Continue>")
      bootstrap_fqdn_check || bootstrap_menu
      ;;
    *) maintenance_menu ;;
    esac
}

function maintenance_menu() {
  if [[ ! -e $BINARY_PATH ]]; then
    die "$APP is not installed"
  fi
  local CHOICE
  OPTIONS=(Bootstrap "Install step-ca Root Certificate"
    Request "Certificate Signing Request (CSR) by $PROVISIONER_TYPE"
    Renew "Renew Certificate by $PROVISIONER_TYPE"
    Revoke "Revoke Certificate by $PROVISIONER_TYPE"
    Inspect "Inspect Certificate by $PROVISIONER_TYPE")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Bootstrap) bootstrap "maintenance_menu" ;;
    Request) request "maintenance_menu" ;;
    Renew) renew "maintenance_menu" ;;
    Revoke) revoke "maintenance_menu" ;;
    Inspect) inspect "" "maintenance_menu" ;;
    *) exit 0 ;;
  esac
}

function main_menu() {
  local CHOICE
  OPTIONS=(Install "Install $APP"
    Update "Update $APP"
    Uninstall "Uninstall $APP"
    Maintenance "Maintain Certificates")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Install) install ;;
    Update) update ;;
    Uninstall) uninstall ;;
    Maintenance) maintenance_menu ;;
    *) exit 0 ;;
  esac
}

header_info
detect_os
main_menu
