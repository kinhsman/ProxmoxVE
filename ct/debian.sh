#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)"
#source /dev/stdin <<< "$(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/community.func)"

function header_info {
clear
cat <<"EOF"
   ____       _          
  |  _ \     (_)         
  | | | | __  _  ___     
  | | | |/ _ \| |/ __|    
  | |_/ / (_) | |\__ \    
  |____/ \___/|_|___/    
EOF
}
header_info
echo -e "Loading..."

APP="Debian"
var_disk="4"
var_cpu="1"
var_ram="1024"
var_os="debian"
var_version="12"
NSAPP=$(echo $APP | tr '[:upper:]' '[:lower:]')
hostname=""
CTID=""

function msg_info() { echo -e "\e[32m[INFO]\e[0m $1"; }
function msg_ok() { echo -e "\e[32m[OK]\e[0m $1"; }
function msg_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$CTID
  HN=$hostname
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="yes"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="yes"
  TAGS="community-script;"
  echo_default
}

function update_script() {
header_info
if [[ ! -f /etc/os-release ]]; then msg_error "No updates available"; exit; fi
msg_ok "No updates available"
}

function start() {
  build_container
}

function pve_check() {
  if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This script requires Proxmox VE to run. Exiting."
    exit 1
  fi
}

function lxc_check() {
  if ! command -v lxc-start >/dev/null 2>&1; then
    msg_error "LXC is required to run this script. Exiting."
    exit 1
  fi
}

function check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root. Exiting."
    exit 1
  fi
}

function get_storage() {
  local STORAGE_LIST=($(pvesm status -content rootdir | awk 'NR>1 {print $1}'))
  if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    msg_error "No storage pools available for rootdir. Exiting."
    exit 1
  elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
    STORAGE=${STORAGE_LIST[0]}
  else
    STORAGE=""
  fi
}

function prompt_user() {
  header_info
  echo -e "Please provide the following details for the $APP container:\n"
  
  while [ -z "$CTID" ]; do
    read -p "Enter the Container ID: " CTID
    if ! [[ "$CTID" =~ ^[0-9]+$ ]]; then
      msg_error "Invalid Container ID. Please enter a number."
      CTID=""
    elif pct status $CTID >/dev/null 2>&1; then
      msg_error "Container ID $CTID already exists. Please choose another."
      CTID=""
    fi
  done
  
  while [ -z "$hostname" ]; do
    read -p "Enter the Hostname: " hostname
    if [ -z "$hostname" ]; then
      msg_error "Hostname cannot be empty."
    fi
  done
  
  while true; do
    read -p "Enter the Disk Size in GB [default: $var_disk]: " DISK_SIZE
    DISK_SIZE=${DISK_SIZE:-$var_disk}
    if [[ "$DISK_SIZE" =~ ^[0-9]+(\.[0-9]+)?$ && "$DISK_SIZE" -ge 1 ]]; then
      var_disk="$DISK_SIZE"
      break
    else
      msg_error "Invalid disk size. Please enter a number greater than or equal to 1."
    fi
  done
}

function build_container() {
  default_settings
  get_storage
  if [ -z "$STORAGE" ]; then
    msg_error "Unable to determine a valid storage pool automatically."
    exit 1
  fi
  
  PCT_OPTIONS=(
    -arch $(dpkg --print-architecture)
    -features nesting=1
    -hostname $HN
    -net0 name=eth0,bridge=$BRG,ip=$NET
    -cores $CORE_COUNT
    -memory $RAM_SIZE
    -onboot 1
    -ostype $var_os
    -rootfs $STORAGE:$DISK_SIZE
    -unprivileged $CT_TYPE
  )
  
  if [ "$DISABLEIP6" == "yes" ]; then
    PCT_OPTIONS+=(-cmode console)
  fi
  
  if [ ! -z "$MTU" ]; then
    PCT_OPTIONS+=(-mtu $MTU)
  fi
  
  msg_info "Creating $APP LXC Container"
  pct create $CT_ID $var_os-$var_version-cloud \
    "${PCT_OPTIONS[@]}" >/dev/null
  if [ $? -ne 0 ]; then
    msg_error "Failed to create container."
    exit 1
  fi
  msg_ok "Container $CT_ID created successfully"
  
  msg_info "Starting container..."
  pct start $CT_ID
  sleep 5
  
  msg_info "Configuring container..."
  pct exec $CT_ID -- bash -c "
    apt-get update && apt-get upgrade -y
    apt-get install -y curl
  "
  
  msg_ok "$APP LXC Container is ready!"
}

function main() {
  check_root
  pve_check
  lxc_check
  prompt_user
  start
}

main
