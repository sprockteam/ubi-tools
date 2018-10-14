#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2143
script_version="v0.3.1"
##############################################################################
# Easy UBNT: UniFi Installer                                                 #
##############################################################################
# A guided script to install and upgrade the UniFi Controller
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018 SprockTech, LLC and contributors
##############################################################################
# Copyrights and Contributors                                                #
##############################################################################
# BASH3 Boilerplate
# https://github.com/kvz/bash3boilerplate
# MIT License
# Copyright (c) 2013 Kevin van Zonneveld and contributors
###
# UniFi Linux Utils
# https://github.com/stevejenkins/unifi-linux-utils
# MIT License
# Copyright (c) 2017 Jenkins Holdings LLC.
###
script_contributors="Contributors to this script:\\n
Klint Van Tassel (SprockTech)
Glenn Rietveld (AmazedMender16)
Frank Gabriel (Frankedinven)"

# Only run this script with bash
if [ ! "$BASH_VERSION" ]
then
  exec bash "$0" "$@"
fi

# This script has not been tested when sourced by another script
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]
then
  echo -e "\\nPlease run this script directly\\n"
  echo -e "Example: bash ${0}\\n"
  exit
fi

clear
if [[ $(id --user) -ne 0 ]]
then
  echo -e "\\nYou must run as root or use sudo\\n"
  exit
fi

# Exit on error, append "|| true" if an error is expected
set -o errexit
# Exit on error inside any functions or subshells
set -o errtrace
# Do not allow use of undefined vars, use ${var:-} if a variable might be undefined
set -o nounset

while getopts ":x" options
do
  case "${options}" in
    x)
      set -o xtrace
      __script_debug="1"
      break;;
    *)
      break;;
  esac
done

# Setup text colors to use
colors_script_background=$(tput setab 7)
colors_warning_text=$(tput setaf 1)
colors_notice_text=$(tput setaf 4)
colors_success_text=$(tput setaf 2)
colors_script_text=$(tput setaf 0)
colors_default=$(tput sgr0)

function script_colors()
{
  echo "${colors_script_background}${colors_script_text}"
}

function cleanup()
{
  if [[ "${restart_ssh_server:-}" == "1" ]]
  then
    service ssh restart
  fi
  if [[ "${run_autoremove:-}" == "1" ]]
  then
    apt-get clean --yes
    apt-get autoremove --yes
  fi
  echo "${colors_default}"
  clear
  if [[ -f "/lib/systemd/system/unifi.service" ]]
  then
    echo "Dumping current UniFi Controller status..."
    service unifi status | cat
  else
    echo -e "UniFi Controller does not appear to be installed\\n"
  fi
}
trap cleanup EXIT

# Show an error message and exit
function abort()
{
  echo -e "${colors_warning_text}##############################################################################\\n"
  error_message="ERROR!"
  if [[ "${1:-}" ]]; then
    error_message+=" ${1}"
  fi
  echo -e "${error_message}\\n"
  exit 1
}

# Used to pause and ask if the user wants to continue the script
function question_prompt()
{
  if [[ -n "${1:-}" ]]; then
    question="${1}"
  else
    question="Do you want to proceed?"
  fi
  read -r -p "${colors_notice_text}${question} (y/n) ${colors_script_text}" yes_no
  case "${yes_no}" in
    [Nn]*)
      echo
      if [[ "${2:-}" = "return" ]]; then
        return 1
      else
        exit
      fi;;
    *)
      echo
      return 0;;
  esac
}

function get_user_input()
{
  user_input=''
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    while [[ -z "${user_input:-}" ]]; do
      read -r -p "${colors_notice_text}${1}${colors_script_text}" user_input
      if [[ "${3:-}" = "optional" ]]; then
        break
      fi
    done
    eval "${2}=\"${user_input}\""
  fi
}

# Clears the screen and informs the user what task is running
function print_header()
{
  clear
  echo "${colors_notice_text}##############################################################################"
  echo "# Easy UBNT: UniFi Installer ${script_version}                                          #"
  echo -e "##############################################################################${colors_script_text}\\n"
  if [[ "${1:-}" ]]; then
    show_notice "\\n${1}"
  fi
}

# Show the license and disclaimer for this script
function print_license()
{
  echo -e "${colors_warning_text}MIT License: THIS SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND"
  echo -e "Copyright (c) 2018 SprockTech, LLC and contributors\\n"
  echo -e "${colors_notice_text}${script_contributors:-}${colors_script_text}"
}

# Print a notice to the screen
function show_notice()
{
  if [[ "${1:-}" ]]; then
    echo -e "${colors_notice_text}${1}${colors_script_text}"
  fi
}

# Print a success message to the screen
function show_success()
{
  if [[ "${1:-}" ]]; then
    echo -e "${colors_success_text}${1}${colors_script_text}"
  fi
}

# Print a warning to the screen
function show_warning()
{
  if [[ "${1:-}" ]]; then
    echo -e "${colors_warning_text}WARNING: ${1}${colors_script_text}"
  fi
}

# What UBNT currently recommends
os_bit_recommended="64-bit"
java_version_recommended="8"
java_version_recommended_regx='^8'
mongo_version_recommended="3.4"
mongo_version_recommended_regx='^3\.4'

# UniFi specific variables
unifi_supported_versions=(5.6 5.8 5.9)
unifi_historical_versions=(5.2 5.3 5.4 5.5 5.6 5.8 5.9)
unifi_repo_source_list="/etc/apt/sources.list.d/100-ubnt-unifi.list"
unifi_base_dir="/usr/lib/unifi"
unifi_data_dir="${unifi_base_dir}/data"
unifi_system_properties="${unifi_data_dir}/system.properties"

# Get architecture and OS information
architecture=$(uname --machine)
os_all_info=$(uname --all)
os_version=$(lsb_release --release --short)

# Initialize other variables
is_32=''
is_64=''
is_ubuntu=''
is_debian=''
os_bit=''
os_name=''
os_name_lower=''
os_version_name=''
os_version_name_lower=''
os_version_alt_name_lower=''
restart_ssh_server=''
run_autoremove=''
java_version_installed=''
mongo_version_installed=''
mongo_repo_url=''
unifi_version_installed=''
unifi_version_recommended=''
unifi_version_recommended_regex=''
script_time=$(date +%s)
sshd_config="/etc/ssh/sshd_config"
apt_sources="/etc/apt/sources.list.d/"
apt_sources_backup="/etc/apt/sources.list.backup-${script_time}"

function setup_ssh_server()
{
  if ! dpkg --list | grep " openssh-server "; then
    echo
    if question_prompt "Do you want to install the OpenSSH server?" "return"; then
      apt-get install --yes openssh-server
    fi
  fi
  if [[ $(dpkg --list | grep "openssh-server") && -f "${sshd_config}" ]]; then
    # Hardening the OpenSSH Server config according to best practices
    # https://gist.github.com/nvnmo/91a20f9e72dffb9922a01d499628040f
    # https://linux-audit.com/audit-and-harden-your-ssh-configuration/
    cp "${sshd_config}" "${sshd_config}.bak-${script_time}"
    show_notice "\\nChecking OpenSSH server settings for recommended changes...\\n"
    if [[ $(grep ".*Port 22$" "${sshd_config}") || ! $(grep ".*Port.*" "${sshd_config}") ]]; then
      if question_prompt "Change SSH port from the default 22?" "return"; then
        ssh_port=""
        while [[ ! $ssh_port =~ ^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$ ]]; do
          read -r -p "Port number: " ssh_port
        done
        if grep --quiet ".*Port.*" "${sshd_config}"; then
          sed -i "s/^.*Port.*$/Port ${ssh_port}/" "${sshd_config}"
        else
          echo "Port ${ssh_port}" | tee -a "${sshd_config}"
        fi
      fi
    fi
    declare -A ssh_changes=(
      ['Protocol 2']='Use SSH protocol version 2 (recommended)?'
      ['UsePrivilegeSeparation yes']='Enable privilege separation (recommended)?'
      ['StrictModes yes']='Enforce strict security checks for SSH server (recommended)?'
      ['PermitEmptyPasswords no']='Disallow empty passwords (recommended)?'
      ['PermitRootLogin no']='Disallow root user to log into SSH (optional)?'
      ['IgnoreRhosts yes']='Disable legacy rhosts authentication (recommended)?'
      ['MaxAuthTries 5']='Limit authentication attempts to 5 (recommended)?'
      #['TCPKeepAlive yes']='Enable TCP keep alive (optional)?'
    )
    for recommended_setting in "${!ssh_changes[@]}"; do
      if ! grep --quiet "^${recommended_setting}" "${sshd_config}"; then
        setting_name=$(echo "${recommended_setting}" | awk '{print $1}')
        echo
        if question_prompt "${ssh_changes[$recommended_setting]}" "return"; then
          if grep --quiet ".*${setting_name}.*" "${sshd_config}"; then
            sed -i "s/^.*${setting_name}.*$/${recommended_setting}/" "${sshd_config}"
          else
            echo "${recommended_setting}" | tee -a "${sshd_config}"
          fi
        fi
      fi
    done
    # Deduplicate lines in the SSH server config
    # https://stackoverflow.com/questions/1444406/how-can-i-delete-duplicate-lines-in-a-file-in-unix
    awk '!seen[$0]++' "${sshd_config}" >/dev/null
    restart_ssh_server=true
  fi
}

function setup_sources()
{
  # Fix for stale sources in some cases
  rm -rf /var/lib/apt/lists/*
  apt-get clean --yes
  apt-get update
  # Install basic package for repository management if necessary
  dpkg --list | grep " software-properties-common " --quiet || apt-get install --yes software-properties-common
  # Add source lists if needed
  if [[ $is_ubuntu ]]; then
    # Add archive and security sources for certain packages
    apt-cache policy | grep "archive.ubuntu.com.*${os_version_name_ubuntu}/main" || \
      echo "deb http://archive.ubuntu.com/ubuntu ${os_version_name_ubuntu} main universe" | tee "/etc/apt/sources.list.d/${os_version_name_ubuntu}-archive.list"
    apt-cache policy | grep "security.ubuntu.com.*${os_version_name_ubuntu}-security/main" || \
      echo "deb http://security.ubuntu.com/ubuntu ${os_version_name_ubuntu}-security main universe" | tee "/etc/apt/sources.list.d/${os_version_name_ubuntu}-security.list"
    # Add repository for Certbot (Let's Encrypt)
    if [[ "${os_version_name}" != "Precise" ]]; then
      add-apt-repository ppa:certbot/certbot
    fi
  elif [[ $is_debian ]]; then 
    apt-cache policy | grep "debian.*${os_version_name_debian}-backports/main" || \
      echo "deb http://ftp.debian.org/debian ${os_version_name_debian}-backports main" | tee "/etc/apt/sources.list.d/${os_version_name_debian}-backports.list"
  fi
  # Use WebUpd8 PPA to get Java 8 on certain OS versions
  # https://gist.github.com/pyk/19a619b0763d6de06786
  if [[ "${os_version_name_ubuntu}" != "xenial" && "${os_version_name_ubuntu}" != "bionic" ]]; then
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
    apt-cache policy | grep "ppa.launchpad.net/webupd8team/java/ubuntu.*${os_version_name_ubuntu}/main" || \
      echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu ${os_version_name_ubuntu} main" | tee /etc/apt/sources.list.d/webupd8team-java.list; \
      echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu ${os_version_name_ubuntu} main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list
    # Silently accept the license for Java
    # https://askubuntu.com/questions/190582/installing-java-automatically-with-silent-option
    echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
  fi
  # Setup Mongo package repository
  # Mongo only distributes 64-bit packages
  if [[ $is_64 && $is_ubuntu ]]; then
    # For Precise and Bionic, use closest available repo
    if [[ "${os_version_name}" = "Precise" ]]; then
      mongo_repo_distro="trusty"
    elif [[ "${os_version_name}" = "Bionic" ]]; then
      mongo_repo_distro="xenial"
    else
      mongo_repo_distro="${os_version_name_ubuntu}"
    fi
    mongo_repo_url="deb [ arch=amd64 ] http://repo.mongodb.org/apt/ubuntu ${mongo_repo_distro}/mongodb-org/3.4 multiverse"
  elif [[ $is_64 && $is_debian ]]; then
    # Mongo 3.4 isn't compatible with Wheezy
    if [[ "${os_version_name}" != "Wheezy" ]]; then
      mongo_repo_url="deb http://repo.mongodb.org/apt/debian jessie/mongodb-org/3.4 main"
    fi
  fi
  if [[ "${mongo_repo_url:-}" ]]; then
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
    apt-cache policy | grep "repo.mongodb.org/apt/.*mongodb-org/3.4" || \
      echo "${mongo_repo_url}" | tee /etc/apt/sources.list.d/mongodb-org-3.4.list
  fi
  # Add UBNT package signing key
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 06E85760C0A52C50
  apt-get update
}

# Installs updates and basic system software
function install_updates_dependencies()
{
  print_header "Checking updates, installing dependencies...\\n"
  apt-get dist-upgrade --yes
  dpkg --list | grep " unattended-upgrades " --quiet || apt-get install --yes unattended-upgrades
  dpkg --list | grep " dirmngr " --quiet|| apt-get install --yes dirmngr
  dpkg --list | grep " curl " --quiet || apt-get install --yes curl
  dpkg --list | grep " dnsutils " --quiet || apt-get install --yes dnsutils
  # Better random number generator, improves performance
  # https://community.ubnt.com/t5/UniFi-Wireless/UniFi-Controller-Linux-Install-Issues/m-p/1324455/highlight/true#M116452
  dpkg --list | grep " haveged " --quiet || apt-get install --yes haveged
  run_autoremove=true
}

function install_java()
{
  print_header "Installing Java...\\n"
  if [[ "${os_version_name_ubuntu}" == "xenial" || "${os_version_name_ubuntu}" == "bionic" ]]
  then
    apt-get install --yes openjdk-8-jre-headless
  else
    apt-get install --yes oracle-java8-installer
    apt-get install --yes oracle-java8-set-default
  fi
  dpkg --list | grep " jsvc " --quiet || apt-get install --yes jsvc
  dpkg --list | grep " libcommons-daemon-java " --quiet || apt-get install --yes libcommons-daemon-java
}

function install_mongo()
{
  # Currently this will only install Mongo 3.4 for 64-bit
  # Skip if 32-bit and go with Mongo 2.6 bundled in the UniFi controller package
  if [[ $is_64 && $mongo_repo_url ]]
  then
    print_header "Installing MongoDB...\\n"
    dpkg --list | grep " mongodb-org " --quiet || apt-get install --yes mongodb-org
  fi
}

function install_certbot()
{
  if [[ $is_debian && "${os_version_name}" = "Jessie" ]]; then
    source_backports="--target-release ${os_version_name_debian}-backports"
  fi
  if [[ "${os_version_name_ubuntu}" != "precise" ]]; then
    print_header "Setting up Let's Encrypt...\\n"
    dpkg --list | grep " certbot " --quiet || apt-get install --yes certbot "${source_backports:-}"
    echo; get_user_input "Domain name to use for the SSL certificate: " "domain_name"
    echo; get_user_input "Email address for renewal notifications (optional): " "email_address" "optional"
    machine_ip_address=$(hostname -I | awk '{print $1}')
    resolved_domain_name=$(dig +short "${domain_name:-}")
    if [[ "${machine_ip_address}" != "${resolved_domain_name}" ]]; then
      echo; show_warning "The domain ${domain_name} resolves to ${resolved_domain_name}\\n"
      if ! question_prompt "" "return"; then
        return
      fi
    fi
    if [[ -z "${email_address:-}" ]]
    then
      email_option="--register-unsafely-without-email"
    else
      email_option="--email ${email_address}"
    fi
    if [[ -n "${domain_name:-}" ]]; then
      pre_hook_script="/usr/local/sbin/pre-hook_${domain_name}.sh"
      post_hook_script="/usr/local/sbin/post-hook_${domain_name}.sh"
      letsencrypt_folder="/etc/letsencrypt/live/${domain_name}"
      letsencrypt_privkey="${letsencrypt_folder}/privkey.pem"
      letsencrypt_fullchain="${letsencrypt_folder}/fullchain.pem"
      tee "${pre_hook_script}" >/dev/null <<EOF
#!/usr/bin/env bash
ufw allow http
ufw allow https
EOF
# End of output to file
      chmod +x "${pre_hook_script}"
      tee "${post_hook_script}" >/dev/null <<EOF
#!/usr/bin/env bash
ufw delete allow http
ufw delete allow https
if [[ -f ${letsencrypt_privkey} && -f ${letsencrypt_fullchain} ]]; then
  cp ${unifi_data_dir}/keystore ${unifi_data_dir}/keystore.backup.$(date +%s)
  openssl pkcs12 -export -inkey ${letsencrypt_privkey} -in ${letsencrypt_fullchain} -out ${letsencrypt_folder}/fullchain.p12 -name unifi -password pass:aircontrolenterprise
  keytool -delete -alias unifi -keystore ${unifi_data_dir}/keystore -deststorepass aircontrolenterprise
  keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${unifi_data_dir}/keystore -srckeystore ${letsencrypt_folder}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt
  service unifi restart
fi
EOF
# End of output to file
      chmod +x "${post_hook_script}"
      echo
      if question_prompt "Do you want to force certificate renewal?" "return"; then
        force_renewal="--force-renewal"
      else
        force_renewal="--keep-until-expiring"
      fi
      if [[ "${__script_debug:-}" ]]; then
        run_mode="--dry-run"
      else
        run_mode="--quiet"
      fi
      certbot certonly --standalone --agree-tos --pre-hook "${pre_hook_script}" --post-hook "${post_hook_script}" --domain "${domain_name}" "${email_option}" "${force_renewal}" "${run_mode}" || \
        show_warning "Certbot failed for domain name: ${domain_name}"
      sleep 3
    fi
  fi
}

function install_unifi()
{
  print_header "Installing UniFi Controller...\\n"
  declare -a unifi_versions_to_select=()
  declare -a unifi_versions_to_install=()
  if [[ $unifi_version_installed ]]
  then
    show_notice "Version ${unifi_version_installed} is currently installed\\n"
    for version in "${!unifi_supported_versions[@]}"
    do
      if [[ "${unifi_supported_versions[$version]:2:1}" -ge "${unifi_version_installed:2:1}" ]]
      then
        unifi_versions_to_select+=("${unifi_supported_versions[$version]}")
      fi
    done
  else
    if [[ $unifi_version_recommended ]]
    then
      #show_notice "Version ${unifi_version_recommended}.x is recommended\\n"
      echo
    fi
    unifi_versions_to_select=("${unifi_supported_versions[@]}")
  fi
  if [[ "${#unifi_versions_to_select[@]}" -eq 1 ]]
  then
    selected_unifi_version="${unifi_versions_to_select[0]}"
  elif [[ "${#unifi_versions_to_select[@]}" -gt 1 ]]
  then
    show_notice "Which controller do you want to install?\\n"
    select version in "${unifi_versions_to_select[@]}"
    do
      case "${version}" in
        "")
          selected_unifi_version="${unifi_version_recommended}"
          break;;
        *)
          selected_unifi_version="${version}"
          break;;
      esac
    done
  else
    abort "Unable to find any possible UniFi versions to install"
  fi
  if [[ $unifi_version_installed ]]
  then
    for step in "${!unifi_historical_versions[@]}"
    do
      if [[ "${unifi_historical_versions[$step]:2:1}" -ge "${unifi_version_installed:2:1}" && "${unifi_historical_versions[$step]:2:1}" -le "${selected_unifi_version:2:1}" ]]
      then
        unifi_versions_to_install+=("${unifi_historical_versions[$step]}")
     fi
    done
  else
    unifi_versions_to_install=("${selected_unifi_version}")
  fi
  for version in "${!unifi_versions_to_install[@]}"
  do
    install_unifi_version "${unifi_versions_to_install[$version]}"
  done
}

function install_unifi_version()
{
  if [[ "${1:-}" ]]
  then
    unifi_install_this_version="${1}"
  else
    abort "No UniFi version specified to install"
  fi
  echo "deb http://www.ubnt.com/downloads/unifi/debian unifi-${unifi_install_this_version} ubiquiti" | tee "${unifi_repo_source_list}"
  apt-get update
  unifi_updated_version=$(apt-cache policy unifi | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
  if [[ "${unifi_version_installed}" == "${unifi_updated_version}" ]]
  then
    show_notice "\\nUniFi ${unifi_version_installed} is already installed\\n"
    sleep 1
    return
  fi
  print_header "Installing UniFi version ${unifi_updated_version}...\\n"
  if [[ $unifi_version_installed ]]
  then
    # TODO: Add API call to make a backup
    show_warning "Make sure you have a backup!\\n"
  fi
  question_prompt
  apt-get install --yes unifi
  script_colors
  # TODO: Add error handling in case install fails
  tail --follow /var/log/unifi/server.log --lines=50 | while read -r log_line
  do
    if [[ "${log_line}" == *"${unifi_updated_version}"* ]]
    then
      show_notice "\\n${log_line}\\n"
      pkill --full tail
      # pkill --parent $$ tail # This doesn't work as expected
    fi
  done
  sleep 1
}

function setup_ufw()
{
  print_header "Setting up UFW (Uncomplicated Firewall)\\n"
  # Use UFW for basic firewall protection
  # TODO: Get ports from system.properties
  dpkg --list | grep " ufw " --quiet || apt-get install --yes ufw
  unifi_http_port=$(grep "unifi.http.port" "${unifi_system_properties}" | sed 's/.*=//g') || "8080"
  unifi_https_port=$(grep "unifi.https.port" "${unifi_system_properties}" | sed 's/.*=//g') || "8443"
  unifi_portal_http_port=$(grep "portal.http.port" "${unifi_system_properties}" | sed 's/.*=//g') || "8880"
  unifi_portal_https_port=$(grep "portal.https.port" "${unifi_system_properties}" | sed 's/.*=//g') || "8843"
  unifi_throughput_port=$(grep "unifi.throughput.port" "${unifi_system_properties}" | sed 's/.*=//g') || "6789"
  unifi_stun_port=$(grep "unifi.stun.port" "${unifi_system_properties}" | sed 's/.*=//g') || "3478"
  ssh_port=$(grep "Port" "${sshd_config}" --max-count=1 | awk '{print $NF}')
  tee "/etc/ufw/applications.d/unifi" >/dev/null <<EOF
[unifi]
title=UniFi Ports
description=Default ports used by the UniFi Controller
ports=${unifi_http_port},${unifi_https_port},${unifi_portal_http_port},${unifi_portal_https_port},${unifi_throughput_port}/tcp|${unifi_stun_port}/udp

[unifi-local]
title=UniFi Ports for Local Discovery
description=Ports used for discovery of devices on the local network by the UniFi Controller
ports=1900,10001/udp
EOF
# End of output to file
  show_notice "\\nCurrent UFW status:\\n"
  ufw status
  echo
  if question_prompt "Do you want to reset your current UFW rules?" "return"; then
    ufw --force reset
  fi
  if [[ $(dpkg --list | grep "openssh-server") ]]; then
    ufw allow "${ssh_port}/tcp"
  fi
  ufw allow from any to any app unifi
  echo
  if question_prompt "Is this controller on your local network?" "return"
  then
    ufw allow from any to any app unifi-local
  else
    ufw --force delete allow from any to any app unifi-local
  fi
  echo "y" | ufw enable
  ufw reload
  show_notice "\\nUpdated UFW status:\\n"
  ufw status
  sleep 1
}

function check_system()
{
  print_header "Checking system...\\n"

  # Only 32-bit and 64-bit are supported (i.e. not ARM)
  if [[ "${architecture}" = "i686" ]]
  then
    is_32=true
    os_bit="32-bit"
  elif [[ "${architecture}" = "x86_64" ]]
  then
    is_64=true
    os_bit="64-bit"
  else
    abort "${architecture} is not supported"
  fi

  # Only Debian and Ubuntu are supported
  # Setup version name variables for later use
  if [[ $(echo "${os_all_info}" | grep "Ubuntu") != "" ]]
  then
    is_ubuntu=true
    os_name="Ubuntu"
    os_name_lower="ubuntu"
    if [[ $os_version =~ ^12\.04 ]]
    then
      os_version_name="Precise"
      os_version_name_ubuntu="precise"
      os_version_name_debian="wheezy"
    elif [[ $os_version =~ ^14\.04 ]]
    then
      os_version_name="Trusty"
      os_version_name_ubuntu="trusty"
      os_version_name_debian="jessie"
    elif [[ $os_version =~ ^16\.04 ]]
    then
      os_version_name="Xenial"
      os_version_name_ubuntu="xenial"
      os_version_name_debian="stretch"
    elif [[ $os_version =~ ^18\.04 ]]
    then
      os_version_name="Bionic"
      os_version_name_ubuntu="bionic"
      os_version_name_debian="buster"
    else
      abort "${os_name} ${os_version} is not supported"
    fi
    # What UBNT recommends
    os_version_recommended="16.04 Xenial"
    os_version_recommended_regx='^16\.04'
  elif [[ $(echo "${os_all_info}" | grep "Debian") != "" ]]
  then
    is_debian=true
    os_name="Debian"
    os_name_lower="debian"
    if [[ $os_version =~ ^7 ]]
    then
      os_version_name="Wheezy"
      os_version_name_debian="wheezy"
      os_version_name_ubuntu="precise"
    elif [[ $os_version =~ ^8 ]]
    then
      os_version_name="Jessie"
      os_version_name_debian="jessie"
      os_version_name_ubuntu="trusty"
    elif [[ $os_version =~ ^9 ]]
    then
      os_version_name="Stretch"
      os_version_name_debian="stretch"
      os_version_name_ubuntu="xenial"
#   Buster is still in testing
#   elif [[ $os_version =~ ^10 ]]
#   then
#     os_version_name="Buster"
#     os_version_name_debian="buster"
#     os_version_name_ubuntu="bionic"
    else
      abort "${os_name} ${os_version} is not supported"
    fi
    # What UBNT recommends
    os_version_recommended="9.x Stretch"
    os_version_recommended_regx='^9'
  else
    abort "This script is for Debian or Ubuntu\\n\\nYou appear to have: ${os_all_info}"
  fi

  # Unable to gather information about the OS
  if [[ ! $os_version || ( ! $is_ubuntu && ! $is_debian ) ]]
  then
    abort "Unable to detect system information"
  fi

  # Display information gathered about the OS
  show_notice "System is ${os_name} ${os_version} ${os_version_name} ${os_bit}\\n"

  if [[ ! $os_version =~ $os_version_recommended_regx || "${os_bit}" != "${os_bit_recommended}" ]]
  then
    show_warning "UBNT recommends ${os_name} ${os_version_recommended} ${os_bit_recommended}\\n"
  fi

  # Detect if Java is installed and what version
  if [[ "$(dpkg --list | grep --extended-regexp '(jdk|JDK)(.*)?(8)\W' --max-count=1)" ]]
  then
    # shellcheck disable=SC1117
    java_version_installed=$(dpkg --list | grep --extended-regexp "(jdk|JDK)(.*)?(8)\W" --max-count=1 | awk '{print $3}' | sed 's/-.*//g')
    # shellcheck disable=SC1117
    java_package_installed=$(dpkg --list | grep --extended-regexp "(jdk|JDK)(.*)?(8)\W" --max-count=1 | awk '{print $2}')
  fi
  
  if [[ $java_version_installed ]]
  then
    show_notice "Java ${java_version_installed} is installed\\n"
    java_update_available=$(apt-cache policy "${java_package_installed}" | grep 'Candidate' | awk '{print $2}' | sed 's/-.*//g')
    if [[ "${java_update_available}" != '' && "${java_update_available}" != "${java_version_installed}" ]]
    then
      show_success "Java ${java_update_available} is available\\n"
    elif [[ "${java_update_available}" != '' && "${java_update_available}" == "${java_version_installed}" ]]
    then
      show_success "Java ${java_version_installed} is current!\\n"
    fi
  else
    show_notice "Java is not installed\\n"
  fi

  # Detect if Mongo is installed and what version
  if [[ "$(dpkg --list | grep 'mongo.*server')" ]]
  then
    mongo_version_installed=$(dpkg --list | grep "mongo.*-server" --max-count=1 | awk '{print $3}' | sed 's/.*://' | sed 's/-.*//g')
    mongo_package_installed=$(dpkg --list | grep "mongo.*-server" --max-count=1 | awk '{print $2}')
  fi

  if [[ $mongo_version_installed ]]
  then
    show_notice "Mongo ${mongo_version_installed} is installed\\n"
    mongo_update_available=$(apt-cache policy "${mongo_package_installed}" | grep 'Candidate' | awk '{print $2}' | sed 's/.*://' | sed 's/-.*//g')
    if [[ "${mongo_update_available}" != '' && "${mongo_update_available}" != "${mongo_version_installed}" ]]
    then
      show_success "Mongo ${mongo_update_available} is available\\n"
    elif [[ "${mongo_update_available}" != '' && "${mongo_update_available}" == "${mongo_version_installed}" ]]
    then
      show_success "Mongo ${mongo_version_installed} is current!\\n"
    fi
  else
    show_notice "Mongo is not installed\\n"
    if [[ $is_32 ]]
    then
      show_warning "Mongo only distributes 64-bit packages\\n"
    fi
  fi

  # Detect if UniFi is installed and what version
  if [[ -f "/lib/systemd/system/unifi.service" ]]
  then
    unifi_version_installed=$(dpkg --list | grep "unifi" | awk '{print $3}' | sed 's/-.*//g')
    show_notice "UniFi ${unifi_version_installed} is installed\\n"
    unifi_update_available=$(apt-cache policy "unifi" | grep 'Candidate' | awk '{print $2}' | sed 's/-.*//g')
    if [[ "${unifi_update_available}" != '' && "${unifi_update_available}" != "${unifi_version_installed}" ]]
    then
      show_success "UniFi ${unifi_update_available} is available\\n"
    elif [[ "${unifi_update_available}" != '' && "${unifi_update_available}" == "${unifi_version_installed}" ]]
    then
      show_success "UniFi ${unifi_version_installed} is current!\\n"
    fi
  else
    show_notice "UniFi is not installed\\n"
    if [[ -f "${unifi_repo_source_list}" ]]
    then
      rm ${unifi_repo_source_list}
    fi
    # TODO: Add API checks for legacy APs to recommend 5.6
    if [[ $os_version =~ $os_version_recommended_regx ]]
    then
      unifi_version_recommended="5.8"
      unifi_version_recommended_regx='^5\.8'
    fi
  fi
  # Check to proceed after system information is displayed
  question_prompt
}

# Do initial package source update before running system check
apt-get update
script_colors
print_header
print_license
sleep 2
check_system
setup_sources
install_updates_dependencies
setup_ssh_server
install_certbot
install_java
install_mongo
install_unifi
setup_ufw

show_success "\\nDone!"
sleep 2