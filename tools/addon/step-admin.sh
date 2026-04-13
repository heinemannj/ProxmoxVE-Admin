#!/usr/bin/env bash

# Copyright (c) 2026 Joerg Heinemann (heinemannj)
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/heinemannj/step-admin/raw/main/LICENSE
# Source: https://raw.githubusercontent.com/heinemannj/step-admin/main/step-admin.sh

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)
#source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)

source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/admin-core.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE-Admin/main/misc/whiptail.func)

# ==============================================================================
# HEADER
# ==============================================================================
function header_info() {
  clear
  cat <<"EOF"
         __                             __          _     
   _____/ /____  ____        ____ _____/ /___ ___  (_)___ 
  / ___/ __/ _ \/ __ \______/ __ `/ __  / __ `__ \/ / __ \
 (__  ) /_/  __/ /_/ /_____/ /_/ / /_/ / / / / / / / / / /
/____/\__/\___/ .___/      \__,_/\__,_/_/ /_/ /_/_/_/ /_/ 
             /_/                                          

EOF
}

# ==============================================================================
# CONFIGURATION VARIABLES
# Set these variables to skip interactive prompts (Whiptail dialogs)
# ==============================================================================
# var_unattended: Run without user interaction
#   Options: "yes" | "no" | "" (empty = interactive prompt)
var_unattended="${var_unattended:-}"

# var_action: Skip initial dialog and directly perform an maintenance option
#   Options: "install" | "update" | "uninstall" | "maintain" | "" (default: empty = interactive prompt)
var_action="${var_action:-}"

# var_cert_type: Skip dialog and directly maintain selected certificate type
#   Options: "x509" | "ssh" | "" (default: empty = interactive prompt)
var_cert_type="${var_cert_type:-}"

# var_x509_action: Skip dialog and directly perform an maintenance option for x509 certificates
#   Options: "bootstrap" | "request" | "renew" | "revoke" | "inspect" | "list" | "" (default: empty = interactive prompt)
var_x509_action="${var_x509_action:-}"

# ==============================================================================
# OPTIONS
# Handle command line arguments
# ==============================================================================
case "${1:-}" in
  --help | -h)
    print_usage
    exit 0
    ;;
  --export-config)
    init_app
    export_config_json
    exit 0
    ;;
esac

# ==============================================================================
# JSON CONFIG EXPORT
# Run with --export-config to output current configuration as JSON
# ==============================================================================
function export_config_json() {
  cat <<EOF
{
  "var_unattended": "${var_unattended}",
  "var_action": "${var_action}",
  "var_cert_type": "${var_cert_type}",
  "var_x509_action": "${var_x509_action}",
  "APP": "${APP}",
  "APP_TYPE": "${APP_TYPE}",
  "APP_TITLE": "${APP_TITLE}",
  "APP_BACKTITLE": "${APP_BACKTITLE}",
  "BINARY_PATH": "${BINARY_PATH}",
  "CONFIG_PATH": "${CONFIG_PATH}",
  "STEPPATH": "${STEPPATH}",
  "STEPHOME": "${STEPHOME}",
  "CA_PATH": "${CA_PATH}",
  "CA_CONFIG": "${CA_CONFIG}",
  "CA_DEFAULTS": "${CA_DEFAULTS}",
  "CA_URL": "${CA_URL}",
  "CA_FQDN": "${CA_FQDN}",
  "CA_ROOT": "${CA_ROOT}",
  "CA_FINGERPRINT": "${CA_FINGERPRINT}",
  "PROVISIONER": "${PROVISIONER}",
  "PROVISIONER_TYPE": "${PROVISIONER_TYPE}",
  "PROVISIONER_PWD_FILE": "${PROVISIONER_PWD_FILE}",
  "CERT_PATH": "${CERT_PATH}",
  "KEY_PATH": "${KEY_PATH}"
}
EOF
}

# ==============================================================================
# USAGE
# Run with --help to output the script usage
# ==============================================================================
function print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Maintain certificate(s) issued by a Step certificate authority.

Options:
  --help              Show this help message
  --export-config     Export current configuration as JSON

Environment Variables:
  var_unattended      Run without user interaction (yes/no)
  var_action          Skip initial dialog and directly perform an maintenance option (install/update/uninstall/maintain)
  var_cert_type       Skip dialog and directly maintain selected certificate type (x509/ssh)
  var_x509_action     Skip dialog and directly perform an maintenance option for x509 certificates (bootstrap/request/renew/revoke/inspect/list)

Examples:
  # Run interactively
  $(basename "$0")

  # Install unattended
  var_unattended=yes var_action=install $(basename "$0")

  # Update unattended
  var_unattended=yes var_action=update $(basename "$0")

  # Renew system certificate unattended
  var_unattended=yes var_x509_action=renew $(basename "$0")

  # Export current configuration
  $(basename "$0") --export-config
EOF
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================
#
# step specific CONFIGURATION VARIABLES
function init_app() {
  if [ -d "$CA_PATH" ]; then
    APP_TITLE="step-ca Admin"
    APP_BACKTITLE="Proxmox VE Helper Scripts"
    export STEPPATH="${CA_PATH}"
    grep -q "export STEPPATH=" /etc/profile || echo "export STEPPATH=${CA_PATH}" >> /etc/profile
    sed -i "/export STEPPATH=/c\export STEPPATH=${CA_PATH}" /etc/profile

    export STEPHOME="${CONFIG_PATH}"
    grep -q "export STEPHOME=" /etc/profile || echo "export STEPHOME=${CONFIG_PATH}" >> /etc/profile
    sed -i "/export STEPHOME=/c\export STEPHOME=${CONFIG_PATH}" /etc/profile

    CA_DEFAULTS="$CA_PATH/config/defaults.json"
    CA_CONFIG="$CA_PATH/config/ca.json"
    PROVISIONER_TYPE="JWK"
    PROVISIONER=$(jq '.authority.provisioners.[] | select(.type=="JWK") | .name' "$CA_CONFIG")
    PROVISIONER="${PROVISIONER#\"}"
    PROVISIONER="${PROVISIONER%\"}"
    PROVISIONER_PWD_FILE="$CA_PATH/encryption/provisioner.pwd"

    mkdir -p "$CONFIG_PATH/db-copy/"
    mkdir -p "$CERT_PATH/ca/_archive/"
  else
    APP_TITLE="step ACME Client"
    APP_BACKTITLE="Proxmox VE Helper Scripts"
    export STEPPATH="${CONFIG_PATH}"
    grep -q "export STEPPATH=" /etc/profile || echo "export STEPPATH=${CONFIG_PATH}" >> /etc/profile
    sed -i "/export STEPPATH=/c\export STEPPATH=${CONFIG_PATH}" /etc/profile

    CA_DEFAULTS="$CONFIG_PATH/config/defaults.json"
    PROVISIONER_TYPE="ACME"
    PROVISIONER="acme@$(hostname -d)"
  fi

  CA_URL=$(grep "ca-url" "$CA_DEFAULTS" | awk -F'"ca-url": "' '{print $2}' | awk -F'"' '{print $1}')
  [[ -n $CA_URL ]] && CA_FQDN=$(echo "$CA_URL" | awk -F'https://' '{print $2}' | awk -F':' '{print $1}') || CA_FQDN="step-ca.$(hostname -d)"
  CA_FINGERPRINT=$(grep "fingerprint" "$CA_DEFAULTS" | awk -F'"fingerprint": "' '{print $2}' | awk -F'"' '{print $1}')
  CA_ROOT=$(grep "root" "$CA_DEFAULTS" | awk -F'"root": "' '{print $2}' | awk -F'"' '{print $1}')
  [ -z "$CA_ROOT" ] && CA_ROOT="${CERT_PATH}/root_ca.crt"

  mkdir -p "$CERT_PATH/ssh/_archive/"
  mkdir -p "$CERT_PATH/x509/_archive/"
  mkdir -p "$KEY_PATH/_archive/"
}

# GLOBAL CONFIGURATION VARIABLES
APP="step-cli"
APP_TYPE="addon"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/etc/step"
CA_PATH="/etc/step-ca"
CERT_PATH="${CONFIG_PATH}/certs"
KEY_PATH="${CONFIG_PATH}/private"

# Initialize all core functions (colors, formatting, icons, STD mode)
load_functions

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  msg_info "Installing dependencies"
  detect_os
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

Environment=STEPPATH="/etc/step" CERT_LOCATION="/etc/step/certs/x509/%i.crt" KEY_LOCATION="/etc/step/private/%i.key"

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
  #$STD systemctl daemon-reload
  systemctl daemon-reload
  msg_ok "Installed $APP"

  #$STD bootstrap "" || die "Installation of step-ca Root Certificate failed!"
  #$STD x509_request "" || die "Main - Request System Certificate failed!"
  bootstrap "" || die "Installation of step-ca Root Certificate failed!"
  x509_request "" || die "Main - Request System Certificate failed!"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  if [[ ! -e $BINARY_PATH ]]; then
    die "$APP is not installed"
  fi
  msg_info "Updating $APP"
  detect_os
  $PKG_UPDATE
  $PKG_UPGRADE $APP
  msg_ok "Updated $APP successfully"
}

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling $APP"
  detect_os
  systemctl disable cert-renewer@.timer
  systemctl disable cert-renewer@.service
  systemctl stop cert-renewer@*.timer
  systemctl stop cert-renewer@*.service
  $PKG_UNINSTALL $APP
  $PKG_AUTOREMOVE
  rm -rf "${CONFIG_PATH}"
  rm -f "/etc/apt/sources.list.d/smallstep.sources"
  rm -f "/usr/local/bin/update_${APP,,}"
  rm -f "/etc/systemd/system/cert-renewer@.service"
  rm -f "/etc/systemd/system/cert-renewer@.timer"
  $STD systemctl daemon-reload
  msg_ok "Uninstalled $APP"
}

# ==============================================================================
# STEP CORE FUNCTIONS
# ==============================================================================
function bootstrap() {
  local BACK_TO_MENU="$1"
  [[ $var_unattended == "yes" ]] && [[ -f $CA_DEFAULTS ]] || bootstrap_menu
  msg_info "Installing step-ca Root Certificate"
  #$STD step ca bootstrap -f --ca-url https://"$CA_FQDN" --install --fingerprint "$CA_FINGERPRINT"  || die "step-ca Bootstrapping failed!"
  #$STD step certificate install --all "$CA_ROOT" || die "Installation of step-ca Root Certificate failed!"
  #$STD update-ca-certificates  || die "Update of System CA Certificates failed!"
  #$STD step certificate inspect https://"$CA_FQDN" || die "Inspection of step-ca Root Certificate failed!"
  step ca bootstrap -f --ca-url https://"$CA_FQDN" --install --fingerprint "$CA_FINGERPRINT"  || die "step-ca Bootstrapping failed!"
  step certificate install --all "$CA_ROOT" || die "Installation of step-ca Root Certificate failed!"
  update-ca-certificates  || die "Update of System CA Certificates failed!"
  step certificate inspect https://"$CA_FQDN" || die "Inspection of step-ca Root Certificate failed!"
  msg_ok "Installed step-ca Root Certificate"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_request() {
  local BACK_TO_MENU="$1"
  FQDN="$(hostname -f)"
  HOST="$(hostname)"
  IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
  SAN=""
  VALID_TO="168h" # Default validity of 7 days (168 hours)

  [[ $var_unattended == "yes" ]] && [[ -f $CA_DEFAULTS ]] || x509_request_menu
  msg_info "Requesting x509 Certificate by $PROVISIONER"
  local FLAGS=(-f
    --not-after="$VALID_TO"
    --provisioner="$PROVISIONER")

  [ "$PROVISIONER_TYPE" = "JWK" ] && [ -f "$PROVISIONER_PWD_FILE" ] && FLAGS+=(--provisioner-password-file="$PROVISIONER_PWD_FILE")

  local SAN_ITEMS=("$FQDN" "$HOST" "$IP" "$SAN")
  for item in "${SAN_ITEMS[@]}"; do
    FLAGS+=(--san "$item")
  done

  step ca certificate "$FQDN" \
    "${CERT_PATH}"/x509/"$FQDN".crt \
    "${KEY_PATH}"/"$FQDN".key \
    "${FLAGS[@]}" || die "Certificate Signing Request (CSR) by $PROVISIONER failed!"

  msg_ok "Requested x509 Certificate by $PROVISIONER"

  if [ "$PROVISIONER_TYPE" = "ACME" ]; then
    msg_info "Starting Certificate Renewal as a Daemon"
    #$STD systemctl enable --now cert-renewer@"${FQDN}".timer
    systemctl enable --now cert-renewer@"${FQDN}".timer
    systemctl list-units cert-renewer@\*.timer
    msg_ok "Started Certificate Renewal as a Daemon"
  fi
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_renew() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Renew"
  msg_info "Renewing Certificate(s)"
  for SERIAL in "${CERT_ARRAY[@]}"; do
    echo -e "${BL}[Info]${GN} Renew x509 Certificate with CN ${BL}${CN}${GN} and Serial Number ${BL}${SERIAL}${GN}:${CL}\n"
    x509_query
    if [ -f "${CRT}" ] && [ -f "${KEY}" ]; then
      CRT_OLD="${CERT_PATH}/x509/_archive/${CN}_$(date +%Y%m%d%H%M%S).crt"
      KEY_OLD="${KEY_PATH}/_archive/${CN}_$(date +%Y%m%d%H%M%S).key"
      cp "${CRT}" "${CRT_OLD}" || die "Failed to backup ${CRT}!"
      cp "${KEY}" "${KEY_OLD}" || die "Failed to backup ${KEY}!"
      step ca renew --force "${CRT}" "${KEY}" || die "Failed to renew certificate!"
      step ca revoke --cert "${CRT_OLD}" --key "${KEY_OLD}"
    else
      die "Failed to renew certificate!"
    fi
    echo
  done
  msg_ok "Renewed Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_revoke() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Revoke"
  msg_info "Revoking Certificate(s)"
  for SERIAL in "${CERT_ARRAY[@]}"; do
    x509_query
    echo -e "${BL}[Info]${GN} Revoke x509 Certificate with CN ${BL}${CN}${GN} and Serial Number ${BL}${SERIAL}${GN}:${CL}\n"
    if [ -f "${CRT}" ] && [ -f "${KEY}" ]; then
      step ca revoke --cert "${CRT}" --key "${KEY}"
      rm -f "${CRT}" || die "Failed to delete ${CRT}!"
      rm -f "${KEY}" || die "Failed to delete ${KEY}!"
    elif [[ "$PROVISIONER_TYPE" == "JWK" ]] && [ -f "$PROVISIONER_PWD_FILE" ]; then
      TOKEN=$(step ca token --provisioner="$PROVISIONER" --provisioner-password-file="$PROVISIONER_PWD_FILE" --revoke "${SERIAL}")
      step ca revoke --token "$TOKEN" "${SERIAL}" || die "Failed to revoke certificate!"
    else
      die "Failed to revoke certificate!"
    fi
    echo
  done
  msg_ok "Revoked Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_inspect() {
  local BACK_TO_MENU="$1"
  x509_certs_menu "Inspect"
  msg_info "Inspecting Certificate(s)"
  for SERIAL in "${CERT_ARRAY[@]}"; do
    echo -e "${BL}[Info]${GN} Inspect x509 Certificate with CN ${BL}${CN}${GN} and Serial Number ${BL}${SERIAL}${GN}:${CL}\n"
    x509_query
    step certificate inspect "${CRT}" | grep -q "${SERIAL}" || die "Serial Number ${SERIAL} mismatch!"
    step certificate inspect "${CRT}" || die "Failed to inspect certificate!"
    echo -e "\n${BL}[Info]${GN} Public Key:${CL}\n"
    cat "${CRT}"
    echo -e "\n${BL}[Info]${GN} Private Key:${CL}\n"
    cat "${KEY}"
  done
  msg_ok "Inspected Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function x509_list() {
  local BACK_TO_MENU="$1"
  x509_view
  whiptail_textbox "Certificates Issued by $CA_FQDN" "$CERT_PATH/x509/x509Certs.txt"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_query() {
  CRT=""
  KEY=""
  #SERIAL CN TYPE FILE VALIDITY NotBefore NotAfter
  CN="$(cat "$CERT_PATH/x509/x509Certs.txt" | grep "${SERIAL}" | awk '{print $2}')"
  TYPE="$(cat "$CERT_PATH/x509/x509Certs.txt" | grep "${SERIAL}" | awk '{print $3}')"
  FILE="$(cat "$CERT_PATH/x509/x509Certs.txt" | grep "${SERIAL}" | awk '{print $4}')"
  if [[ "$FILE" == "local" ]]; then
    CRT="$CERT_PATH/x509/$CN.crt"
    KEY="$KEY_PATH/$CN.key"
  fi
}

function x509_view(){
  DB_EXPORT=""
  CERT_LIST=()
  local CERT_FILE_ARRAY=("$CERT_PATH/x509/"*.crt)
  local FLAGS=("--provisioner")

  echo "Serial Number|CN|Type|File|Validity|Not Before|Not After" > "$CERT_PATH/x509/x509Certs.txt"
  if [ -d "$CA_PATH/db" ]; then
    cp --recursive --force "$CA_PATH/db/"* "$CONFIG_PATH/db-copy/"
    cp --recursive --force "$CA_PATH/certs/"* "$CONFIG_PATH/certs/ca/"
    if [[ $(step-badger x509Certs "$CONFIG_PATH/db-copy" 2>/dev/null) ]]; then
      DB_EXPORT=$(step-badger x509Certs "$CONFIG_PATH/db-copy" "${FLAGS[@]}" 2>/dev/null)
      echo "$DB_EXPORT" | awk 'NR>1 {print $1 "|" $2 "|" $3 "|none|" $7 "|" $5 "|" $6}' | sed 's/CN=//g' >> "$CERT_PATH/x509/x509Certs.txt"
      while IFS='|' read -r SERIAL CN TYPE FILE VALIDITY NotBefore NotAfter; do
        local CRT="$CERT_PATH/x509/$CN.crt"
        if [ -f "${CRT}" ] && step certificate inspect "${CRT}" | grep -q "${SERIAL}"; then
          sed -i "/${SERIAL}/s/none/local/g" "$CERT_PATH/x509/x509Certs.txt"
          FILE="local"
        fi
        CERT_LIST+=("$SERIAL" "$CN|$TYPE|$FILE|$VALIDITY|$NotAfter")
      done < <(sed '1d' "$CERT_PATH/x509/x509Certs.txt")
    fi
  else
    for ITEM in "${CERT_FILE_ARRAY[@]}"; do
      [ -f "${ITEM}" ] || break
      SERIAL=$(step certificate inspect "${ITEM}" | grep "Serial Number:" | awk '{print $3}')
      CN=$(step certificate inspect "${ITEM}" | grep "Subject:" | awk '{print $2}')
      CN="${CN/CN=/}"
      TYPE=$(step certificate inspect "${ITEM}" | grep "Type:" | awk '{print $2}')
      FILE="local"
      NotBefore=$(step certificate inspect "${ITEM}" | grep "Not Before:" | awk -F 'Not Before: ' '{print $2}')
      NotAfter=$(step certificate inspect "${ITEM}" | grep "Not After :" | awk -F 'Not After : ' '{print $2}')
      [ "$(date -d "${NotAfter}" +%s)" -gt "$(date +%s)" ] && [ "$(date -d "${NotBefore}" +%s)" -lt "$(date +%s)" ] && VALIDITY="Valid" || VALIDITY="Expired"
      echo "$SERIAL|$CN|$TYPE|$FILE|$VALIDITY|$NotBefore|$NotAfter" >> "$CERT_PATH/x509/x509Certs.txt"
      CERT_LIST+=("$SERIAL" "$CN|$TYPE|$FILE|$VALIDITY|$NotAfter")
    done
  fi
  # shellcheck disable=SC2094
  cat "$CERT_PATH/x509/x509Certs.txt" | column -t -s '|' > "$CERT_PATH/x509/x509Certs.txt"
  TOTAL_CERTS=$(( $(wc -l < "$CERT_PATH/x509/x509Certs.txt") - 1 ))
  VALID_CERTS=$(( $(grep -c "Valid" "$CERT_PATH/x509/x509Certs.txt") - 1))
  EXPIRED_CERTS=$(( TOTAL_CERTS - VALID_CERTS ))
  echo -e "\n\nTotal Certificates  : ${TOTAL_CERTS}\nValid Certificates  : ${VALID_CERTS}\nExpired Certificates: ${EXPIRED_CERTS}" >> "$CERT_PATH/x509/x509Certs.txt"
}

#function ssh_badger_list() {
#  CERT_LIST=""
#  cp --recursive --force "$CA_PATH/db/"* "$CONFIG_PATH/db-copy/"
#  cp --recursive --force "$CA_PATH/certs/"* "$CONFIG_PATH/certs/ca/"
#  if [[ $(step-badger sshCerts "${CONFIG_PATH}/db-copy" 2>/dev/null) ]]; then
#    CERT_LIST=$(step-badgersshCerts ${CONFIG_PATH}/db-copy 2>/dev/null)
#  fi
#}

# ==============================================================================
# MENU FUNCTIONS
# Interactive prompts via Whiptail dialogs
# ==============================================================================
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

function maintenance_menu() {
  [[ ! -e $BINARY_PATH ]] && die "$APP is not installed"

  local CHOICE
  OPTIONS=(x509 "Maintain x509 Certificate"
    ssh "Maintain ssh Certificate")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    x509) x509_maintenance_menu ;;
    ssh) ssh_maintenance_menu ;;
    *) exit 0 ;;
  esac
}

function x509_maintenance_menu() {
  local CHOICE
  OPTIONS=()
  [ -d "$CA_PATH/config" ] || OPTIONS+=(Bootstrap "Install step-ca Root Certificate")
  OPTIONS+=(Request "Certificate Signing Request (CSR) by $PROVISIONER_TYPE"
    Renew "Renew Certificate by $PROVISIONER_TYPE"
    Revoke "Revoke Certificate by $PROVISIONER_TYPE"
    Inspect "Inspect Certificate by $PROVISIONER_TYPE"
    List "List Certificates")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Bootstrap) bootstrap "x509_maintenance_menu" ;;
    Request) x509_request "x509_maintenance_menu" ;;
    Renew) x509_renew "x509_maintenance_menu" ;;
    Revoke) x509_revoke "x509_maintenance_menu" ;;
    Inspect) x509_inspect "x509_maintenance_menu" ;;
    List) x509_list "x509_maintenance_menu" ;;
    *) exit 0 ;;
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
    *) x509_maintenance_menu ;;
  esac
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

function x509_request_menu() {
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
      FQDN=$(whiptail_inputbox "$TITLE" "FQDN (e.g. mylxc.example.com)" "$FQDN")
      HOST=$(echo "$FQDN" | awk -F'.' '{print $1}')
      IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
      x509_request_menu
      ;;
    "Hostname")
      HOST=$(whiptail_inputbox "$TITLE" "Hostname (e.g. mylxc)" "$HOST")
      x509_request_menu
      ;;
    "IP Address")
      IP=$(whiptail_inputbox "$TITLE" "IP Address (e.g. x.x.x.x)" "$IP")
      x509_request_menu
      ;;
    "Subject Alternative Name(s) (SANs)")
      SAN=$(whiptail_inputbox "$TITLE" "Subject Alternative Name(s) (SAN) (e.g. e.g. myapp-1.example.com, myapp-2.example.com)" "$SAN")
      x509_request_menu
      ;;
    "Validity")
      VALID_TO=$(whiptail_inputbox "$TITLE" "Validity (e.g. 168h, 30m0s or 2034-12-31T23:59:59Z)" "$VALID_TO")
      x509_request_menu
      ;;
    "Provisioner")
      PROVISIONER=$(whiptail_inputbox "$TITLE" "Provisioner (e.g. $PROVISIONER)" "$PROVISIONER")
      x509_request_menu
      ;;
    " ")
      x509_request_menu
      ;;
    "<Continue>") ;;
    *) x509_maintenance_menu ;;
  esac
}

function x509_certs_menu() {
  local CERT_ACTION=$1
  local CHOICE
  x509_view
  if [[ ${#CERT_LIST[@]} -gt 0 ]]; then
    CHOICE=$(whiptail_checklist "Certificates Issued by $CA_FQDN" "\nSelect Certificate(s) to ${CERT_ACTION}:" "CERT_LIST")
  else
    whiptail_msgbox "Certificates Issued by $CA_FQDN" "No certificate(s) found on localhost."
  fi
  # shellcheck disable=SC2206
  CERT_ARRAY=(${CHOICE})
  if [ ${#CERT_ARRAY[@]} -eq 0 ]; then
    if [ -z "$var_x509_action" ]; then
      x509_maintenance_menu
    else
      msg_warn "No certificate(s) selected or found on localhost."
      exit 1
    fi
  fi
}

function ssh_maintenance_menu() {
  die "Maintain ssh Certificate - To be implemented in future"
}

# ==============================================================================
# MAIN
# ==============================================================================
init_app
header_info

case "$var_x509_action" in
  bootstrap)
    bootstrap
    exit 0
    ;;
  request)
    x509_request
    exit 0
    ;;
  renew)
    x509_renew
    exit 0
    ;;
  revoke)
    x509_revoke
    exit 0
    ;;
  inspect)
    x509_inspect
    exit 0
    ;;
  list)
    x509_list
    exit 0
    ;;
esac

case "$var_cert_type" in
  x509) x509_maintenance_menu ;;
  ssh) ssh_maintenance_menu ;;
esac

#
# *) NO use of CONFIGURATION VARIABLES for interactive prompts via Whiptail dialogs
#
case "$var_action" in
  install) install ;;
  update) update ;;
  uninstall) uninstall ;;
  maintain) maintenance_menu ;;
  *) main_menu ;;
esac
