#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2143

### Easy UBNT: UniFi Installer
##############################################################################
# A guided script to install/upgrade the UniFi Controller, and secure the
# the server using best practices.
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018 SprockTech, LLC and contributors
__script_version="v0.3.7"
__script_contributors="Contributors (UBNT Community Username):
Klint Van Tassel (SprockTech), Glenn Rietveld (AmazedMender16),
Frank Gabriel (Frankedinven), (ssawyer)"

### Copyrights and Mentions
##############################################################################
# BASH3 Boilerplate
# https://github.com/kvz/bash3boilerplate
# MIT License
# Copyright (c) 2013 Kevin van Zonneveld and contributors


### Initial startup checks
##############################################################################

# Only run this script with bash
if [ ! "$BASH_VERSION" ]; then
  exec bash "$0" "$@"
fi

# This script has not been tested when called by another program
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo -e "\\nPlease run this script directly\\n"
  exit
fi

# This script requires root or sudo privilege to run properly
if [[ $(id --user) -ne 0 ]]; then
  echo -e "\\nPlease run this script as root or use sudo, for example:\\n"
  if [[ $(lsb_release --id --short) = "Debian" ]]; then
    echo -e "su root\\nbash unifi-installer.sh\\n"
  else
    echo -e "sudo bash unifi-installer.sh\\n"
  fi
  exit
fi

### Setup options and initialize variables
##############################################################################

# Exit on error, append "|| true" if an error is expected
set -o errexit
# Exit on error inside any functions or subshells
set -o errtrace
# Do not allow use of undefined vars, use ${var:-} if a variable might be undefined
set -o nounset

# Set magic variables for current file and directory
__dir=$(cd "$(dirname "${0}")" && pwd)
__file="${__dir}/$(basename "${0}")"
__base=$(basename "${__file}" .sh)

# Set script time, get system information
__script_time=$(date +%s)
__architecture=$(uname --machine)
__os_all_info=$(uname --all)
__os_version=$(lsb_release --release --short)
__os_version_name=$(lsb_release --codename --short)
__os_version_name_ubuntu_equivalent=""
__os_name=$(lsb_release --id --short)
__machine_ip_address=$(hostname -I | awk '{print $1}')
__disk_total_space="$(df --human-readable . | grep "/" | awk '{print $2}')B"
__disk_free_space="$(df --human-readable . | grep "/" | awk '{print $4}')B"
__memory_total="$(grep "MemTotal" /proc/meminfo | awk '{printf "%.0fM", $2/1024}')B"
__swap_total="$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.0fM", $2/1024}')B"

# Initialize miscellaneous variables
__unifi_version_installed=
__unifi_update_available=
__unifi_domain_name=
__unifi_https_port=

# Set various base folders
# TODO: Make these dynamic
__apt_sources_dir="/etc/apt/sources.list.d"
__unifi_base_dir="/usr/lib/unifi"
__unifi_data_dir="${__unifi_base_dir}/data"
__letsencrypt_dir="/etc/letsencrypt"
__sshd_config="/etc/ssh/sshd_config"

# Recommendations and minimum requirements
__unifi_version_stable="5.8"
__recommended_disk_free_space="10GB"
__recommended_memory_total="2048MB"
__recommended_memory_total_gb="2GB"
__recommended_swap_total="4096MB"
__recommended_swap_total_gb="4GB"

# Initialize "boolean" variables as "false"
__is_32=
__is_64=
__is_ubuntu=
__is_debian=
__is_unifi_installed=
__cleanup_restart_ssh_server=
__cleanup_run_autoremove=
__setup_source_java=
__setup_source_mongo=
__purge_mongo=
__downgrade_mongo=
__hold_java=
__hold_mongo=
__hold_unifi=
__install_mongo=
__install_java=
__install_webupd8_java=
__script_debug=

# Setup script colors to use
__colors_script_background=$(tput sgr0)
__colors_warning_text=$(tput setaf 1)
__colors_notice_text=$(tput sgr0)
__colors_success_text=$(tput setaf 5)
__colors_script_text=$(tput sgr0)
__colors_default=$(tput sgr0)

### Error/cleanup handling and trace/debugging option
##############################################################################

# Run miscellaneous tasks before exiting
function __eubnt_cleanup_before_exit() {
  echo "Cleaning up script, please wait..."
  if [[ $__cleanup_restart_ssh_server ]]; then
    service ssh restart
  fi
  if [[ $__unifi_version_installed ]]; then
    __unifi_update_available=$(apt-cache policy "unifi" | grep 'Candidate' | awk '{print $2}' | sed 's/-.*//g')
    if [[ "${__unifi_update_available:0:3}" != "${__unifi_version_installed:0:3}" ]]; then
      echo "deb http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" >/dev/null | tee "${__apt_sources_dir}/100-ubnt-unifi.list"
      apt-get update &>/dev/null
    fi
  fi
  if [[ $__cleanup_run_autoremove ]]; then
    apt-get clean --yes &>/dev/null
    apt-get autoremove --yes &>/dev/null
  fi
  echo "${__colors_default}"
  if [[ -f "/lib/systemd/system/unifi.service" && ! $__script_debug ]]; then
    clear
    echo -e "Dumping current UniFi Controller status...\\n"
    service unifi status | cat
    echo
  fi
}
trap __eubnt_cleanup_before_exit EXIT

# Display a detailed message if an error is encountered
function __eubnt_error_report() {
    local error_code
    error_code=${?}
    echo "Error in ${__file} in function ${1} on line ${2}"
    sleep 5
    exit ${error_code}
}

while getopts ":x" options; do
  case "${options}" in
    x)
      set -o xtrace
      __script_debug=true
      trap '__eubnt_error_report "${FUNCNAME:-.}" ${LINENO}' ERR
      break;;
    *)
      break;;
  esac
done

### Utility functions
##############################################################################

# Setup initial script colors
function __eubnt_script_colors() {
  echo "${__colors_script_background}${__colors_script_text}"
}

# Show a basic error message and exit
function __eubnt_abort() {
  echo -e "${__colors_warning_text}##############################################################################\\n"
  echo -e "ERROR! ${1:-}\\n${__colors_script_text}"
  # TODO: Use __eubnt_error_report here
  __script_debug=true
  exit 1
}

# Display a yes or know question and proceed accordingly
function __eubnt_question_prompt() {
  local yes_no=""
  local default_question="Do you want to proceed?"
  local default_answer="y"
  if [[ "${3:-}" = "n" ]]; then
    default_answer="n"
  fi
  while [[ ! "${yes_no}" =~ (^[Yy]([Ee]?|[Ee][Ss])?$)|(^[Nn][Oo]?$) ]]; do
    read -r -p "${__colors_notice_text}${1:-$default_question} (y/n, default ${default_answer}) ${__colors_script_text}" yes_no
    if [[ "${yes_no}" = "" ]]; then
      yes_no="${default_answer}"
    fi
  done
  case "${yes_no}" in
    [Nn]*)
      echo
      # If the "return" option is specified, then return an error
      if [[ "${2:-}" = "return" ]]; then
        return 1
      # Else, exit the script
      else
        exit
      fi;;
    [Yy]*)
      # The default is to return true (yes) and continue
      echo
      return 0;;
  esac
}

# Display a question and return full user input
function __eubnt_get_user_input() {
  local user_input=""
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    while [[ -z "${user_input}" ]]; do
      read -r -p "${__colors_notice_text}${1}${__colors_script_text}" user_input
      # Allow an empty response if "optional" is specified
      if [[ "${3:-}" = "optional" ]]; then
        break
      fi
    done
    eval "${2}=\"${user_input}\""
  fi
}

# Print a header that informs the user what task is running
function __eubnt_print_header() {
  if [[ ! $__script_debug ]]; then
    clear
  fi
  echo "${__colors_notice_text}##############################################################################"
  echo "# Easy UBNT: UniFi Installer ${__script_version}                                          #"
  echo -e "##############################################################################${__colors_script_text}\\n"
  if [[ "${1:-}" ]]; then
    __eubnt_show_notice "${1}"
  fi
}

# Show the license and disclaimer for this script
function __eubnt_print_license() {
  __eubnt_show_notice "MIT License\\nCopyright (c) 2018 SprockTech, LLC and contributors\\n"
  __eubnt_show_notice "${__script_contributors:-}\\n"
  __eubnt_show_warning "This script will guide you through installing and upgrading
the UniFi Controller from UBNT, and securing this system using best
practices. It is intended to work on systems that will be dedicated
to running the UniFi Controller.\\n
THIS SCRIPT IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND!\\n"
  __eubnt_show_notice "Read the full MIT License for this script here:
https://raw.githubusercontent.com/sprockteam/easy-ubnt/master/LICENSE\\n"
}

# Print a notice to the screen
function __eubnt_show_notice() {
  if [[ "${1:-}" ]]; then
    echo -e "${__colors_notice_text}${1}${__colors_script_text}"
  fi
}

# Print a success message to the screen
function __eubnt_show_success() {
  if [[ "${1:-}" ]]; then
    echo -e "${__colors_success_text}${1}${__colors_script_text}"
  fi
}

# Print a warning to the screen
function __eubnt_show_warning() {
  local warning_prefix="WARNING: "
  if [[ "${1:-}" ]]; then
    if [[ "${2:-}" = "none" ]]; then
      warning_prefix=""
    fi
    echo -e "${__colors_warning_text}${warning_prefix}${1}${__colors_script_text}"
  fi
}

### Main script functions
##############################################################################

### Setup source lists for later use when installing and upgrading
function __eubnt_setup_sources() {
  # Make sure dirmngr is installed for Debian
  if [[ $__is_debian ]]; then
    dpkg --list | grep " dirmngr " --quiet || apt-get install --yes dirmngr
  fi
  # Install basic package for repository management if necessary
  dpkg --list | grep " software-properties-common " --quiet || apt-get install --yes software-properties-common
  # Add source lists if needed
  if [[ $__is_ubuntu ]]; then
    # Add archive and security sources for certain packages
    apt-cache policy | grep "archive.ubuntu.com.*${__os_version_name}/main" || \
      echo "deb http://archive.ubuntu.com/ubuntu ${__os_version_name} main universe" | tee "${__apt_sources_dir}/${__os_version_name}-archive.list"
    apt-cache policy | grep "security.ubuntu.com.*${__os_version_name}-security/main" || \
      echo "deb http://security.ubuntu.com/ubuntu ${__os_version_name}-security main universe" | tee "${__apt_sources_dir}/${__os_version_name}-security.list"
    # Add repository for Certbot (Let's Encrypt)
    if [[ "${__os_version_name}" != "precise" ]]; then
      add-apt-repository ppa:certbot/certbot --yes
    fi
  elif [[ $__is_debian ]]; then 
    apt-cache policy | grep "debian.*${__os_version_name}-backports/main" || \
      echo "deb http://ftp.debian.org/debian ${__os_version_name}-backports main" | tee "${__apt_sources_dir}/${__os_version_name}-backports.list"
  fi
  if [[ $__setup_source_java ]]; then
    # Use WebUpd8 PPA to get Java 8 on older OS versions
    # https://gist.github.com/pyk/19a619b0763d6de06786
    if [[ "${__os_version_name_ubuntu_equivalent}" = "precise" || "${__os_version_name_ubuntu_equivalent}" = "trusty" ]]; then
      apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
      apt-cache policy | grep "ppa.launchpad.net/webupd8team/java/ubuntu.*${__os_version_name_ubuntu_equivalent}/main" || \
        echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu ${__os_version_name_ubuntu_equivalent} main" | tee "${__apt_sources_dir}/webupd8team-java.list"; \
        echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu ${__os_version_name_ubuntu_equivalent} main" | tee -a "${__apt_sources_dir}/webupd8team-java.list"
      # Silently accept the license for Java
      # https://askubuntu.com/questions/190582/installing-java-automatically-with-silent-option
      echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
      __install_webupd8_java=true
    else
      __install_java=true
    fi
  fi
  if [[ $__setup_source_mongo ]]; then
    # Setup Mongo package repository
    # Mongo only distributes 64-bit packages
    local mongo_repo_distro=""
    local mongo_repo_url=""
    if [[ $__is_64 && $__is_ubuntu ]]; then
      # For Precise and Bionic, use closest available repo
      if [[ "${__os_version_name}" = "precise" ]]; then
        mongo_repo_distro="trusty"
      elif [[ "${__os_version_name}" = "bionic" ]]; then
        mongo_repo_distro="xenial"
      else
        mongo_repo_distro="${__os_version_name}"
      fi
      mongo_repo_url="deb [ arch=amd64 ] http://repo.mongodb.org/apt/ubuntu ${mongo_repo_distro}/mongodb-org/3.4 multiverse"
    elif [[ $__is_64 && $__is_debian ]]; then
      # Mongo 3.4 isn't compatible with Wheezy
      if [[ "${__os_version_name}" != "wheezy" ]]; then
        mongo_repo_url="deb http://repo.mongodb.org/apt/debian jessie/mongodb-org/3.4 main"
      fi
    fi
    if [[ "${mongo_repo_url:-}" ]]; then
      apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
      apt-cache policy | grep "repo.mongodb.org/apt/.*mongodb-org/3.4" || \
        echo "${mongo_repo_url}" | tee "${__apt_sources_dir}/mongodb-org-3.4.list"
      __install_mongo=true
    fi
  fi
  # Add UBNT package signing key
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 06E85760C0A52C50
  apt-get update
}

# Install basic system utilities needed for successful installation
function __eubnt_install_updates_dependencies() {
  __eubnt_print_header "Checking updates, installing dependencies...\\n"
  if [[ $__hold_java ]]; then
    apt-mark hold "${__hold_java}"
  fi
  if [[ $__hold_mongo ]]; then
    apt-mark hold "${__hold_mongo}"
  fi
  if [[ $__hold_unifi ]]; then
    apt-mark hold "${__hold_unifi}"
  fi
  apt-get dist-upgrade --yes
  dpkg --list | grep " unattended-upgrades " --quiet || apt-get install --yes unattended-upgrades
  dpkg --list | grep " dirmngr " --quiet || apt-get install --yes dirmngr
  dpkg --list | grep " curl " --quiet || apt-get install --yes curl
  dpkg --list | grep " dnsutils " --quiet || apt-get install --yes dnsutils
  # Better random number generator, improves performance
  # https://community.ubnt.com/t5/UniFi-Wireless/UniFi-Controller-Linux-Install-Issues/m-p/1324455/highlight/true#M116452
  dpkg --list | grep " haveged " --quiet || apt-get install --yes haveged
  if [[ $__hold_java ]]; then
    apt-mark unhold "${__hold_java}"
  fi
  if [[ $__hold_mongo ]]; then
    apt-mark unhold "${__hold_mongo}"
  fi
  if [[ $__hold_unifi ]]; then
    apt-mark unhold "${__hold_unifi}"
  fi
  __cleanup_run_autoremove=true
}

function __eubnt_install_java() {
  if [[ $__install_webupd8_java || $__install_java ]]; then
    __eubnt_print_header "Installing Java...\\n"
    # Install WebUpd8 team's Java for certain OS versions
    if [[ $__install_webupd8_java ]]; then
      apt-get install --yes oracle-java8-installer
      apt-get install --yes oracle-java8-set-default
    # Install regular Java for all others
    else
      dpkg --list | grep " ca-certificates-java " --quiet || apt-get install --yes ca-certificates-java
      apt-get install --yes openjdk-8-jre-headless
      local set_java_alternative="java-1.8.0-openjdk-amd64"
      if [[ $__is_32 ]]; then
        set_java_alternative="java-1.8.0-openjdk-i386"
      fi
      java -version 2>&1 | grep --quiet "1.8.0" || update-java-alternatives --set "${set_java_alternative}"
    fi
    dpkg --list | grep " jsvc " --quiet || apt-get install --yes jsvc
    dpkg --list | grep " libcommons-daemon-java " --quiet || apt-get install --yes libcommons-daemon-java
  fi
}

function __eubnt_install_mongo()
{
  # Currently this is intended to install Mongo 3.4 for 64-bit
  # Skip if 32-bit and go with Mongo bundled in the UniFi controller package
  if [[ $__is_64 && $__install_mongo ]]; then
    __eubnt_print_header "Installing MongoDB...\\n"
    if [[ $__purge_mongo ]]; then
      if [[ $__is_unifi_installed ]]; then
        service unifi stop
      fi
      apt-get purge "mongodb-server" --yes
      apt-get autoremove --yes
    fi
    dpkg --list | grep " mongo.*-server " --quiet || apt-get install --yes mongodb-org
    if [[ $__purge_mongo && $__is_unifi_installed ]]; then
      service unifi start
    fi
  fi
}

function __eubnt_install_unifi()
{
  __eubnt_print_header "Installing UniFi Controller...\\n"
  local unifi_supported_versions=(5.6 5.8 5.9)
  local unifi_historical_versions=(5.2 5.3 5.4 5.5 5.6 5.8 5.9)
  local selected_unifi_version=
  declare -a unifi_versions_to_install=()
  declare -a unifi_versions_to_select=()
  if [[ $__unifi_version_installed ]]; then
    __eubnt_show_notice "Version ${__unifi_version_installed} is currently installed\\n"
  fi
  for version in "${!unifi_supported_versions[@]}"; do
    if [[ $__unifi_version_installed ]]; then
      if [[ "${unifi_supported_versions[$version]:0:3}" = "${__unifi_version_installed:0:3}" && $__unifi_update_available ]]; then
        unifi_versions_to_select+=("${__unifi_update_available}")
      elif [[ "${unifi_supported_versions[$version]:2:1}" -gt "${__unifi_version_installed:2:1}" ]]; then
        unifi_versions_to_select+=("${unifi_supported_versions[$version]}.x")
      fi
    else
      unifi_versions_to_select+=("${unifi_supported_versions[$version]}.x")
    fi
  done
  if [[ "${#unifi_versions_to_select[@]}" -eq 1 ]]; then
    selected_unifi_version="${unifi_versions_to_select[0]%.*}"
  elif [[ "${#unifi_versions_to_select[@]}" -gt 1 ]]; then
    unifi_versions_to_select+=("None")
    __eubnt_show_notice "Which controller do you want to install or upgrade to?\\n"
    select version in "${unifi_versions_to_select[@]}"; do
      case "${version}" in
        "")
          selected_unifi_version="${__unifi_version_stable}"
          break;;
        *)
          if [[ "${version}" = "None" ]]; then
            return
          fi
          selected_unifi_version="${version%.*}"
          break;;
      esac
    done
  else
    return
  fi
  if [[ $__unifi_version_installed ]]; then
    for step in "${!unifi_historical_versions[@]}"; do
      if [[ "${unifi_historical_versions[$step]:2:1}" -ge "${__unifi_version_installed:2:1}" && "${unifi_historical_versions[$step]:2:1}" -le "${selected_unifi_version:2:1}" ]]
      then
        unifi_versions_to_install+=("${unifi_historical_versions[$step]}")
     fi
    done
  else
    unifi_versions_to_install=("${selected_unifi_version}")
  fi
  for version in "${!unifi_versions_to_install[@]}"; do
    __eubnt_install_unifi_version "${unifi_versions_to_install[$version]}"
  done
}

function __eubnt_install_unifi_version()
{
  if [[ "${1:-}" ]]; then
    unifi_install_this_version="${1}"
  else
    __eubnt_abort "No UniFi version specified to install"
  fi
  echo "deb http://www.ubnt.com/downloads/unifi/debian unifi-${unifi_install_this_version} ubiquiti" | tee "${__apt_sources_dir}/100-ubnt-unifi.list"
  apt-get update
  unifi_updated_version=$(apt-cache policy unifi | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
  if [[ "${__unifi_version_installed}" = "${unifi_updated_version}" ]]; then
    __eubnt_show_notice "\\nUniFi ${__unifi_version_installed} is already installed\\n"
    sleep 1
    return
  fi
  __eubnt_print_header "Installing UniFi version ${unifi_updated_version}...\\n"
  if [[ $__unifi_version_installed ]]; then
    # TODO: Add API call to make a backup
    __eubnt_show_warning "Make sure you have a backup!\\n"
  fi
  if __eubnt_question_prompt "" "return"; then
    apt-get install --yes unifi
    __unifi_version_installed="${unifi_updated_version}"
    __eubnt_script_colors
    # TODO: Add error handling in case install fails
    tail --follow /var/log/unifi/server.log --lines=50 | while read -r log_line
    do
      if [[ "${log_line}" = *"${unifi_updated_version}"* ]]
      then
        __eubnt_show_success "\\n${log_line}\\n"
        pkill --full tail
        # pkill --parent $$ tail # TODO: This doesn't work as expected
      fi
    done
    sleep 1
  else
    echo "deb http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" | tee "${__apt_sources_dir}/100-ubnt-unifi.list"
    apt-get update
  fi
}

function __eubnt_tweak_unifi() {
  # TODO: Force more secure HTTPS connections
  # unifi.https.ciphers=TLS_RSA_WITH_AES_256_CBC_SHA
  # unifi.https.sslEnabledProtocols=TLSv1.2
  # https://community.ubnt.com/t5/UniFi-Wireless/UniFI-Controller-TLS-1-2/m-p/1580362/highlight/true#M163612
  # TODO: Tweak Java settings
  # https://help.ubnt.com/hc/en-us/articles/115005159588-UniFi-How-to-Tune-the-Controller-for-High-Number-of-UniFi-Devices
  true
}

function __eubnt_install_certbot() {
  local source_backports domain_name email_address resolved_domain_name email_option run_certbot
  if [[ "${__os_version_name}" = "jessie" ]]; then
    source_backports="--target-release ${__os_version_name}-backports"
  fi
  if [[ "${__os_version_name}" != "precise" && "${__os_version_name}" != "wheezy" ]]; then
    __eubnt_print_header "Setting up Let's Encrypt...\\n"
    if [[ $(dpkg --list | grep " certbot ") && ! $(certbot certificates | grep "No certs found") ]]; then
      certbot certificates
      if __eubnt_question_prompt "Does your current Let's Encrypt setup look correct?" "return"; then
        __unifi_domain_name=$(certbot certificates | grep "Domains: " | sed 's/.*:\ //')
        return
      fi
    else
      if ! __eubnt_question_prompt "Do you want to use Let's Encrypt?" "return"; then
      return
      fi
    fi
    dpkg --list | grep " certbot " --quiet || apt-get install --yes certbot "${source_backports}"
    echo; __eubnt_get_user_input "Domain name to use for the SSL certificate: " "domain_name"
    echo; __eubnt_get_user_input "Email address for renewal notifications (optional): " "email_address" "optional"
    resolved_domain_name=$(dig +short "${domain_name}")
    if [[ "${__machine_ip_address}" != "${resolved_domain_name}" ]]; then
      echo; __eubnt_show_warning "The domain ${domain_name} resolves to ${resolved_domain_name}\\n"
      if ! __eubnt_question_prompt "" "return"; then
        return
      fi
    fi
    if [[ -n "${email_address}" ]]
    then
      email_option="--email ${email_address}"
    else
      email_option="--register-unsafely-without-email"
    fi
    if [[ -n "${domain_name}" ]]; then
      local letsencrypt_scripts_dir="/usr/local/sbin/easy-ubnt"
      [[ -d "${letsencrypt_scripts_dir}" ]] || mkdir "${letsencrypt_scripts_dir}"
      local pre_hook_script="${letsencrypt_scripts_dir}/pre-hook_${domain_name}.sh"
      local post_hook_script="${letsencrypt_scripts_dir}/post-hook_${domain_name}.sh"
      local letscript_live_dir="${__letsencrypt_dir}/live/${domain_name}"
      local letsencrypt_privkey="${letscript_live_dir}/privkey.pem"
      local letsencrypt_fullchain="${letscript_live_dir}/fullchain.pem"
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
  cp ${__unifi_data_dir}/keystore ${__unifi_data_dir}/keystore.backup.$(date +%s)
  openssl pkcs12 -export -inkey ${letsencrypt_privkey} -in ${letsencrypt_fullchain} -out ${letscript_live_dir}/fullchain.p12 -name unifi -password pass:aircontrolenterprise
  keytool -delete -alias unifi -keystore ${__unifi_data_dir}/keystore -deststorepass aircontrolenterprise
  keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${__unifi_data_dir}/keystore -srckeystore ${letscript_live_dir}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt
  service unifi restart
fi
EOF
# End of output to file
      chmod +x "${post_hook_script}"
      local force_renewal="--keep-until-expiring"
      local run_mode="--quiet"
      echo
      if __eubnt_question_prompt "Do you want to force certificate renewal?" "return"; then
        force_renewal="--force-renewal"
      fi
      if [[ $__script_debug ]]; then
        run_mode="--dry-run"
      fi
      # TODO: Add checks for existing certbot setup
      certbot certonly --standalone --agree-tos --pre-hook "${pre_hook_script}" --post-hook "${post_hook_script}" --domain "${domain_name}" "${email_option}" "${force_renewal}" "${run_mode}"
      # shellcheck disable=SC2181
      if [[ $? -gt 0 ]]; then
        __eubnt_show_warning "Certbot failed for domain name: ${domain_name}"
        sleep 3
      else
        __unifi_domain_name="${domain_name}"
      fi
    fi
  fi
}

# Install OpenSSH server and harden the configuration
function __eubnt_setup_ssh_server() {
  __eubnt_print_header "Setting up OpenSSH Server..."
  if [[ ! $(dpkg --list | grep " openssh-server ") ]]; then
    echo
    if __eubnt_question_prompt "Do you want to install the OpenSSH server?" "return"; then
      apt-get install --yes openssh-server
    fi
  fi
  if [[ $(dpkg --list | grep "openssh-server") && -f "${__sshd_config}" ]]; then
    # Hardening the OpenSSH Server config according to best practices
    # https://gist.github.com/nvnmo/91a20f9e72dffb9922a01d499628040f
    # https://linux-audit.com/audit-and-harden-your-ssh-configuration/
    cp "${__sshd_config}" "${__sshd_config}.bak-${__script_time}"
    __eubnt_show_notice "\\nChecking OpenSSH server settings for recommended changes...\\n"
    if [[ $(grep ".*Port 22$" "${__sshd_config}") || ! $(grep ".*Port.*" "${__sshd_config}") ]]; then
      if __eubnt_question_prompt "Change SSH port from the default 22?" "return"; then
        local ssh_port=""
        while [[ ! $ssh_port =~ ^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$ ]]; do
          read -r -p "Port number: " ssh_port
        done
        if grep --quiet ".*Port.*" "${__sshd_config}"; then
          sed -i "s/^.*Port.*$/Port ${ssh_port}/" "${__sshd_config}"
        else
          echo "Port ${ssh_port}" | tee -a "${__sshd_config}"
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
      if ! grep --quiet "^${recommended_setting}" "${__sshd_config}"; then
        setting_name=$(echo "${recommended_setting}" | awk '{print $1}')
        echo
        if __eubnt_question_prompt "${ssh_changes[$recommended_setting]}" "return"; then
          if grep --quiet ".*${setting_name}.*" "${__sshd_config}"; then
            sed -i "s/^.*${setting_name}.*$/${recommended_setting}/" "${__sshd_config}"
          else
            echo "${recommended_setting}" | tee -a "${__sshd_config}"
          fi
        fi
      fi
    done
    # Deduplicate lines in the SSH server config
    # https://stackoverflow.com/questions/1444406/how-can-i-delete-duplicate-lines-in-a-file-in-unix
    awk '!seen[$0]++' "${__sshd_config}" >/dev/null
    __cleanup_restart_ssh_server=true
  fi
}

function __eubnt_setup_ufw() {
  __eubnt_print_header "Setting up UFW (Uncomplicated Firewall)..."
  echo
  if [[ ! $(dpkg --list | grep " ufw ") || $(ufw status | grep "inactive") ]]; then
    if ! __eubnt_question_prompt "Do you want to use UFW?" "return"; then
      return
    fi
  fi
  # Use UFW for basic firewall protection
  dpkg --list | grep " ufw " --quiet || apt-get install --yes ufw
  local unifi_system_properties="${__unifi_data_dir}/system.properties"
  if [[ -f "${__sshd_config}" ]]; then
    local ssh_port=$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')
  fi
  if [[ -f "${unifi_system_properties}" ]]; then
    local unifi_http_port=$(grep "^unifi.http.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_http_port ]]; then
      unifi_http_port="8080"
    fi
    local unifi_https_port=$(grep "^unifi.https.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_https_port ]]; then
      unifi_https_port="8443"
    fi
    local unifi_portal_http_port=$(grep "^portal.http.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_portal_http_port ]]; then
      unifi_portal_http_port="8880"
    fi
    local unifi_portal_https_port=$(grep "^portal.https.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_portal_https_port ]]; then
      unifi_portal_https_port="8843"
    fi
    local unifi_throughput_port=$(grep "^unifi.throughput.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_throughput_port ]]; then
      unifi_throughput_port="6789"
    fi
    local unifi_stun_port=$(grep "^unifi.stun.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_stun_port ]]; then
      unifi_stun_port="3478"
    fi
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
  fi
  __eubnt_show_notice "\\nCurrent UFW status:\\n"
  ufw status
  echo
  if __eubnt_question_prompt "Do you want to reset your current UFW rules?" "return" "n"; then
    ufw --force reset
  fi
  if [[ "${ssh_port:-}" ]]; then
    ufw allow "${ssh_port}/tcp" >/dev/null
  fi
  if [[ "${unifi_http_port:-}" && "${unifi_https_port:-}" ]]; then
    __unifi_https_port="${unifi_https_port}"
    ufw allow from any to any app unifi >/dev/null
    echo
    if __eubnt_question_prompt "Is this controller on your local network?" "return" "n"; then
      ufw allow from any to any app unifi-local >/dev/null
    else
      ufw --force delete allow from any to any app unifi-local >/dev/null
    fi
  else
    __eubnt_show_warning "Unable to determine UniFi ports to allow. Is it installed?\\n"
  fi
  echo "y" | ufw enable >/dev/null
  ufw reload
  __eubnt_show_notice "\\nUpdated UFW status:\\n"
  ufw status
  sleep 1
}

function __eubnt_setup_swap_file() {
  # Recommended by CrossTalk Solutions
  # https://crosstalksolutions.com/15-minute-hosted-unifi-controller-setup/
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  if swapon /swapfile; then
    echo "/swapfile none swap sw 0 0" | tee -a /etc/fstab
  else
    rm -rf /swapfile
    __eubnt_show_warning "Unable to create swap file"
  fi
  echo
}

function __eubnt_check_system() {
  # Fix for stale sources in some cases
  rm -rf /var/lib/apt/lists/*
  echo -e "Checking for existing package updates, please wait...\\n"
  apt-get clean --yes
  apt-get update &>/dev/null
  __eubnt_print_header "Checking system...\\n"
  # What UBNT currently recommends
  local os_version_name_display os_version_supported
  local os_bit_recommended="64-bit"
  local java_version_recommended="8"
  local mongo_version_recommended="3.4.x"
  local ubuntu_supported_versions=("precise" "trusty" "xenial" "bionic")
  local debian_supported_versions=("wheezy" "jessie" "stretch")
  local have_space_for_swap=
  # Only 32-bit and 64-bit are supported (i.e. not ARM)
  if [[ "${__architecture}" = "i686" ]]; then
    __is_32=true
    os_bit="32-bit"
  elif [[ "${__architecture}" = "x86_64" ]]; then
    __is_64=true
    os_bit="64-bit"
  else
    __eubnt_abort "${__architecture} is not supported"
  fi
  # Only Debian and Ubuntu are supported
  if [[ "${__os_name}" = "Ubuntu" ]]; then
    __is_ubuntu=true
    os_version_recommended_display="16.04 Xenial"
    os_version_recommended="xenial"
    for version in "${!ubuntu_supported_versions[@]}"; do
      if [[ "${ubuntu_supported_versions[$version]}" = "${__os_version_name}" ]]; then
        # shellcheck disable=SC2001
        os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
        __os_version_name_ubuntu_equivalent="${__os_version_name}"
        os_version_supported=true
        break
      fi
    done
  elif [[ "${__os_name}" = "Debian" ]]; then
    __is_debian=true
    os_version_recommended_display="9.x Stretch"
    os_version_recommended="stretch"
    for version in "${!debian_supported_versions[@]}"; do
      if [[ "${debian_supported_versions[$version]}" = "${__os_version_name}" ]]; then
        # shellcheck disable=SC2001
        os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
        __os_version_name_ubuntu_equivalent="${ubuntu_supported_versions[$version]}"
        os_version_supported=true
        break
      fi
    done
  else
    __eubnt_abort "This script is for Debian or Ubuntu\\n\\nYou appear to have: ${__os_all_info}"
  fi
  if [[ ! $os_version_supported ]]; then
    __eubnt_abort "${__os_name} ${__os_version} is not supported"
  fi
  # Unable to gather information about the OS
  if [[ -z "${__os_version}" || ( ! $__is_ubuntu && ! $__is_debian ) ]]; then
    __eubnt_abort "Unable to detect system information"
  fi
  # Display disk and memory space information
  __eubnt_show_notice "System Vitals\\nDisk free space: ${__disk_free_space}\\nMemory total size: ${__memory_total}\\nSwap total size: ${__swap_total}\\n"
  # Display information gathered about the OS
  __eubnt_show_notice "System is ${__os_name} ${__os_version} ${os_version_name_display} ${os_bit}\\n"
  # Show warnings if detected system information is outside of recommendations from UBNT
  if [[ "${__os_version_name}" != "${os_version_recommended}" || "${os_bit}" != "${os_bit_recommended}" ]]; then
    __eubnt_show_warning "UBNT recommends ${__os_name} ${os_version_recommended_display} ${os_bit_recommended}\\n"
  fi
  if [[ "${__disk_free_space%G*}" -lt "${__recommended_disk_free_space%G*}" ]]; then
    __eubnt_show_warning "UBNT recommends at least ${__recommended_disk_free_space} of disk free space\\n"
  else
    if [[ "${__disk_free_space%G*}" -gt $(( ${__recommended_disk_free_space%G*} + ${__recommended_swap_total_gb%G*} )) ]]; then
      have_space_for_swap=true
    fi
  fi
  if [[ "${__memory_total%M*}" -lt "${__recommended_memory_total%M*}" ]]; then
    __eubnt_show_warning "UBNT recommends at least ${__recommended_memory_total_gb} of memory\\n"
  fi
  if [[ "${__swap_total%M*}" -eq 0 && $have_space_for_swap ]]; then
    if __eubnt_question_prompt "Do you want to setup a ${__recommended_swap_total_gb} swap file?" "return"; then
      __eubnt_setup_swap_file
    fi
  fi
  # Detect if Java is installed and what package and version
  if [[ $(command -v java) ]]; then
    if [[ $(dpkg --list | grep " oracle-java8-installer ") ]]; then
      java_version_installed=$(dpkg --list | grep " oracle-java8-installer " | awk '{print $3}' | sed 's/-.*//g')
      java_package_installed="oracle-java8-installer"
    elif [[ $(dpkg --list | grep " openjdk-8-jre-headless") ]]; then
      java_version_installed=$(dpkg --list | grep " openjdk-8-jre-headless" | awk '{print $3}' | sed 's/-.*//g')
      java_package_installed="openjdk-8-jre-headless"
    fi
  fi
  # Check to see if any Java updates are available and report install/update status
  if [[ -n "${java_version_installed:-}" ]]; then
    java_update_available=$(apt-cache policy "${java_package_installed}" | grep 'Candidate' | awk '{print $2}' | sed 's/-.*//g')
    if [[ -n "${java_update_available}" && "${java_update_available}" != "${java_version_installed}" ]]; then
      __eubnt_show_notice "Java ${java_version_installed} is installed, ${__colors_warning_text}version ${java_update_available} is available\\n"
      if ! __eubnt_question_prompt "Do you want to update Java to ${java_update_available}?" "return"; then
        __hold_java="${java_package_installed}"
      fi
      echo
    elif [[ "${java_update_available}" != '' && "${java_update_available}" = "${java_version_installed}" ]]; then
      __eubnt_show_success "Java ${java_version_installed} is good!\\n"
    fi
  else
    __eubnt_show_notice "Java 8 will be installed\\n"
    __setup_source_java=true
  fi
  # Detect if Mongo is installed and what version
  if [[ $(dpkg --list | grep " mongodb.*-server ") ]]; then
    mongo_version_installed=$(dpkg --list | grep " mongodb.*-server " | awk '{print $3}' | sed 's/.*://' | sed 's/-.*//g')
    mongo_package_installed=$(dpkg --list | grep " mongodb.*-server " | awk '{print $2}')
    if [[ $(dpkg --list | grep " mongodb-server ") && $__is_64 ]]; then
      __eubnt_show_warning "Mongo officially maintains 'mongodb-org' packages but you have 'mongodb' packages installed\\n"
      if __eubnt_question_prompt "Do you want to remove the 'mongodb' packages and install 'mongodb-org' packages instead?" "return"; then
        __purge_mongo=true
      else
        __eubnt_show_warning "UniFi may not install correctly!\\n"
        __eubnt_question_prompt
      fi
    fi
  fi
  # Check to see if Mongo is a recommended version and if there are any updates
  if [[ -n "${mongo_version_installed:-}" && ! $__purge_mongo ]]; then
    mongo_update_available=$(apt-cache policy "${mongo_package_installed}" | grep 'Candidate' | awk '{print $2}' | sed 's/.*://' | sed 's/-.*//g')
    # shellcheck disable=SC2001
    mongo_version_check=$(echo "${mongo_version_installed:0:3}" | sed 's/\.//')
    if [[ "${mongo_version_check}" -gt "34" ]]; then
      __eubnt_show_warning "UBNT recommends Mongo ${mongo_version_recommended}\\n"
      if __eubnt_question_prompt "Do you want to downgrade Mongo to ${mongo_version_recommended}?" "return"; then
        __downgrade_mongo=true
        __setup_source_mongo=true
      else
        __eubnt_show_warning "UniFi may not install correctly!\\n"
        __eubnt_question_prompt
      fi
    fi
    if [[ ! $__downgrade_mongo && -n "${mongo_update_available}" && "${mongo_update_available}" != "${mongo_version_installed}" ]]; then
      __eubnt_show_notice "Mongo ${mongo_version_installed} is installed, ${__colors_warning_text}version ${mongo_update_available} is available\\n"
      if ! __eubnt_question_prompt "Do you want to update Mongo to ${mongo_update_available}?" "return"; then
        __hold_mongo="${mongo_package_installed}"
      fi
      echo
    elif [[ ! $__downgrade_mongo && -n "${mongo_update_available}" && "${mongo_update_available}" = "${mongo_version_installed}" ]]; then
      __eubnt_show_success "Mongo ${mongo_version_installed} is good!\\n"
    fi
  else
    __eubnt_show_notice "Mongo will be installed\\n"
    __setup_source_mongo=true
  fi
  # Detect if UniFi is installed and what version
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    __is_unifi_installed=true
    __unifi_version_installed=$(dpkg --list | grep " unifi " | awk '{print $3}' | sed 's/-.*//g')
    __unifi_update_available=$(apt-cache policy "unifi" | grep 'Candidate' | awk '{print $2}' | sed 's/-.*//g')
    if [[ "${__unifi_update_available:0:3}" != "${__unifi_version_installed:0:3}" ]]; then
      echo "deb http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" >/dev/null | tee "${__apt_sources_dir}/100-ubnt-unifi.list"
      apt-get update &>/dev/null
      __unifi_update_available=$(apt-cache policy "unifi" | grep 'Candidate' | awk '{print $2}' | sed 's/-.*//g')
    fi
    if [[ -n "${__unifi_update_available}" && "${__unifi_update_available}" != "${__unifi_version_installed}" ]]; then
      __eubnt_show_notice "UniFi ${__unifi_version_installed} is installed, ${__colors_warning_text}version ${__unifi_update_available} is available\\n"
      if ! __eubnt_question_prompt "Do you want to update UniFi to ${__unifi_update_available}?" "return"; then
        __hold_unifi="unifi"
      fi
      echo
    elif [[ -n "${__unifi_update_available}" && "${__unifi_update_available}" = "${__unifi_version_installed}" ]]
    then
      __eubnt_show_success "UniFi ${__unifi_version_installed} is good!\\n"
      __unifi_update_available=
    fi
  else
    __eubnt_show_notice "UniFi does not appear to be installed yet\n"
  fi
}

### Execution of script
##############################################################################

__eubnt_script_colors
__eubnt_print_header
__eubnt_print_license
__eubnt_question_prompt "Do you agree to the MIT License and want to proceed?" "exit" "n"
__eubnt_check_system
__eubnt_question_prompt
__eubnt_setup_sources
__eubnt_install_updates_dependencies
__eubnt_install_java
__eubnt_install_mongo
__eubnt_install_unifi
__eubnt_setup_ssh_server
__eubnt_install_certbot
__eubnt_setup_ufw
__eubnt_show_success "\\nDone!"
if [[ $__unifi_https_port ]]; then
  if [[ $__unifi_domain_name ]]; then
    controller_address="${__unifi_domain_name}"
  else
    controller_address="${__machine_ip_address}"
  fi
  __eubnt_show_notice "\\nController URL: https://${controller_address}:${__unifi_https_port}/manage/\\n"
fi
__eubnt_question_prompt "Are you ready to exit?"
