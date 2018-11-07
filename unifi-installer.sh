#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2143

### Easy UBNT: UniFi Installer
##############################################################################
# A guided script to install/upgrade the UniFi Controller, and secure the
# the server using best practices.
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018 SprockTech, LLC and contributors
__script_version="v0.5.2"
__script_contributors="Contributors (UBNT Community Username):
Klint Van Tassel (SprockTech), Glenn Rietveld (AmazedMender16),
Frank Gabriel (Frankedinven), Sam Sawyer (ssawyer), Adrian
Miller (adrianmmiller)"

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
  echo -e "\\nPlease run this script as root or use sudo\\n"
  echo -e "For example in Debian:"
  echo -e "su root\\nbash unifi-installer.sh\\n"
  echo -e "\\nFor example in Ubuntu (or Debian with sudo installed):"
  echo -e "sudo bash unifi-installer.sh\\n"
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

# Set magic variables for script and environment
__script_time=$(date +%s)
__script_name=$(basename "${0}" .sh)
__dir=$(cd "$(dirname "${0}")" && pwd)
__file="${__dir}/${__script_name}"
__base=$(basename "${__file}" .sh)
__eubnt_dir=$(mkdir --parents /usr/lib/easy-ubnt && echo "/usr/lib/easy-ubnt")
__script_log_dir=$(mkdir --parents /var/log/easy-ubnt && echo "/var/log/easy-ubnt")
__script_log=$(touch "${__script_log_dir}/${__script_name}-${__script_time}.log" && echo "${__script_log_dir}/${__script_name}-${__script_time}.log")

# Set script time, get system information
__architecture=$(uname --machine)
__os_all_info=$(uname --all)
__os_kernel=$(uname --release)
__os_kernel_version=$(uname --release | sed 's/[-][a-z].*//g')
__os_version=$(lsb_release --release --short)
__os_version_name=$(lsb_release --codename --short)
__os_name=$(lsb_release --id --short)
__machine_ip_address=$(hostname -I | awk '{print $1}')
__disk_total_space="$(df . | awk '/\//{printf "%.0fGB", $2/1024/1024}')"
__disk_free_space="$(df . | awk '/\//{printf "%.0fGB", $4/1024/1024}')"
__memory_total="$(grep "MemTotal" /proc/meminfo | awk '{printf "%.0fMB", $2/1024}')"
__swap_total="$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.0fMB", $2/1024}')"
__nameservers=$(awk '/nameserver/{print $2}' /etc/resolv.conf | xargs)

# Initialize miscellaneous variables
__os_version_name_ubuntu_equivalent=
__unifi_version_installed=
__unifi_update_available=
__unifi_domain_name=
__unifi_https_port=

# Set various base folders and files
# TODO: Make these dynamic
__apt_sources_dir=$(find /etc -type d -name "sources.list.d")
__unifi_base_dir="/usr/lib/unifi"
__unifi_data_dir="${__unifi_base_dir}/data"
__letsencrypt_dir="/etc/letsencrypt"
__sshd_config="/etc/ssh/sshd_config"

# Recommendations and minimum requirements and misc variables
__recommended_disk_free_space="10GB"
__recommended_memory_total="2048MB"
__recommended_memory_total_gb="2GB"
__recommended_swap_total="4096MB"
__recommended_swap_total_gb="2GB"
__os_bit_recommended="64-bit"
__java_version_recommended="8"
__mongo_version_recommended="3.4.x"
__unifi_version_stable="5.8"
__recommended_nameserver="9.9.9.9"
__ubnt_dns="dl.ubnt.com"

# Initialize "boolean" variables as "false"
__is_32=
__is_64=
__is_ubuntu=
__is_debian=
__is_unifi_installed=
__setup_source_java=
__setup_source_mongo=
__purge_mongo=
__hold_java=
__hold_mongo=
__hold_unifi=
__install_mongo=
__install_java=
__install_webupd8_java=
__accept_license=
__quick_mode=
__verbose_output=
__script_debug=
__restart_ssh_server=
__run_autoremove=
__reboot_system=

# Setup script colors and special text to use
__colors_bold_text="$(tput bold)"
__colors_warning_text="${__colors_bold_text}$(tput setaf 1)"
__colors_error_text="${__colors_bold_text}$(tput setaf 1)"
__colors_notice_text="${__colors_bold_text}$(tput setaf 6)"
__colors_success_text="${__colors_bold_text}$(tput setaf 2)"
__colors_default="$(tput sgr0)"
__spinner="-\\|/"

### Error/cleanup handling
##############################################################################

# Run miscellaneous tasks before exiting
###
# Restart services if needed
# Clean up source lists if needed
# Remove un-needed packages if any
# Show UniFi Controller information post-setup
# Unset script variables
function __eubnt_cleanup_before_exit() {
  local log_files_to_delete
  echo -e "${__colors_default}\\nCleaning up script, please wait...\\n"
  if [[ $__restart_ssh_server ]]; then
    __eubnt_run_command "service ssh restart"
  fi
  if [[ $__unifi_version_installed ]]; then
    __unifi_update_available=$(apt-cache policy "unifi" | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
    if [[ "${__unifi_update_available:0:3}" != "${__unifi_version_installed:0:3}" ]]; then
      __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list"
      __eubnt_run_command "apt-get update"
    fi
  fi
  if [[ $__run_autoremove ]]; then
    __eubnt_run_command "apt-get clean --yes"
    __eubnt_run_command "apt-get autoremove --yes"
  fi
  if [[ -f "/lib/systemd/system/unifi.service" && ! $__reboot_system ]]; then
    __eubnt_show_header "Collecting UniFi Controller info..."
    local controller_status
    if [[ $(service unifi status | wc --lines) -gt 1 ]]; then
      controller_status=$(service unifi status | grep --only-matching "Active: .*" | sed 's/Active:/Service status:/')
    else
      controller_status="Service status: $(service unifi status)"
    fi
    __eubnt_show_notice "\\n${controller_status}"
    if [[ -n "${__unifi_https_port:-}" ]]; then
      local controller_address
      if [[ -n "${__unifi_domain_name:-}" ]]; then
        controller_address="${__unifi_domain_name}"
      else
        controller_address="${__machine_ip_address}"
      fi
      __eubnt_show_notice "\\nWeb address: https://${controller_address}:${__unifi_https_port}/manage/\\n"
    fi
  fi
  if [[ -d "${__script_log_dir}" && -f "${__script_log}" ]]; then
    log_files_to_delete=$(find "${__script_log_dir}" -maxdepth 1 -type f -print0 | xargs -0 --exit ls -t | awk 'NR>6')
    if [[ -n "${log_files_to_delete}" ]]; then
      echo "${log_files_to_delete}" | xargs --max-lines=1 rm
    fi
  fi
  for var_name in ${!__*}; do
    if [[ "${var_name}" != "__reboot_system" ]]; then
      unset -v "${var_name}"
    fi
  done
  if [[ $__reboot_system ]]; then
    shutdown -r now
  fi
}
trap __eubnt_cleanup_before_exit EXIT
trap '__script_debug=true' ERR

### Utility functions
##############################################################################

# Setup initial script colors
function __eubnt_script_colors() {
  echo "${__colors_default}"
}

# Show a basic error message and exit
# $1: The error text to display
function __eubnt_show_error() {
  echo -e "${__colors_error_text}##############################################################################\\n"
  __eubnt_echo_and_log "ERROR! ${1:-}${__colors_default}\\n"
  return 1
}

# Display a yes or know question and proceed accordingly
# $1: The question to use instead of the default question
# $2: Can be set to "return" if an error should be returned instead of exiting
# $3: Can be set to "n" if the default answer should be no instead of yes
###
# If no answer is given, the default answer is used
# If the script it running in "quiet mode" then the default answer is used without prompting
function __eubnt_question_prompt() {
  local yes_no=""
  local default_question="Do you want to proceed?"
  local default_answer="y"
  if [[ "${3:-}" = "n" ]]; then
    default_answer="n"
  fi
  if [[ "${__quick_mode}" ]]; then
    yes_no="${default_answer}"
  fi
  while [[ ! "${yes_no}" =~ (^[Yy]([Ee]?|[Ee][Ss])?$)|(^[Nn][Oo]?$) ]]; do
    echo -e -n "${__colors_notice_text}${1:-$default_question} (y/n, default ${default_answer})${__colors_default} "
    read -r yes_no
    echo -e -n "\\r"
    if [[ "${yes_no}" = "" ]]; then
      yes_no="${default_answer}"
    fi
  done
  __eubnt_add_to_log "${1:-$default_question} ${yes_no}"
  case "${yes_no}" in
    [Nn]*)
      echo
      if [[ "${2:-}" = "return" ]]; then
        return 1
      else
        exit
      fi;;
    [Yy]*)
      echo
      return 0;;
  esac
}

# Display a question and return full user input
# $1: The question to ask, there is no default question so one must be set
# $2: The variable to assign the answer to, this must also be set
# $3: Can be set to "optional" to allow for an empty response to bypass the question
###
# No checks on the input are done within this function, must be done after the answer has been returned
function __eubnt_get_user_input() {
  local user_input=""
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    while [[ -z "${user_input}" ]]; do
      echo -e -n "${__colors_notice_text}${1}${__colors_default} "
      read -r user_input
      echo -e -n "\\r"
      if [[ "${3:-}" = "optional" ]]; then
        break
      fi
    done
    __eubnt_add_to_log "${1} ${user_input}"
    eval "${2}=\"${user_input}\""
  fi
}

# Print a header that informs the user what task is running
# $1: Can be set in order to display additional details about the current task
###
# If the script is not in debug mode, then the screen will be cleared first
# The script header will then be displayed
# If $1 is set then it will be displayed under the header
function __eubnt_show_header() {
  if [[ ! $__script_debug ]]; then
    clear
  fi
  echo -e "${__colors_notice_text}### Easy UBNT: UniFi Installer ${__script_version}"
  echo -e "##############################################################################${__colors_default}\\n"
  if [[ -n "${1:-}" ]]; then
    __eubnt_show_notice "${1}"
  fi
}

# Show the license and disclaimer for this script
function __eubnt_show_license() {
  __eubnt_show_text "MIT License\\nCopyright (c) 2018 SprockTech, LLC and contributors\\n"
  __eubnt_show_notice "${__script_contributors:-}\\n"
  __eubnt_show_warning "This script will guide you through installing and upgrading
the UniFi Controller from UBNT, and securing this system using best
practices. It is intended to work on systems that will be dedicated
to running the UniFi Controller.\\n
THIS SCRIPT IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND!\\n"
  __eubnt_show_text "Read the full MIT License for this script here:
https://raw.githubusercontent.com/sprockteam/easy-ubnt/master/LICENSE\\n"
}

# Print text to the screen
# $1: The text to display
function __eubnt_show_text() {
  if [[ -n "${1:-}" ]]; then
    __eubnt_echo_and_log "${__colors_default}${1}${__colors_default}\\n"
  fi
}

# Print a notice to the screen
# $1: The text to display
function __eubnt_show_notice() {
  if [[ -n "${1:-}" ]]; then
    __eubnt_echo_and_log "${__colors_notice_text}${1}${__colors_default}\\n"
  fi
}

# Print a success message to the screen
# $1: The text to display
function __eubnt_show_success() {
  if [[ -n "${1:-}" ]]; then
    __eubnt_echo_and_log "${__colors_success_text}${1}${__colors_default}\\n"
  fi
}

# Print a warning to the screen
# $1: The text to display
# $2: Can be set to "none" to not show the "WARNING:" prefix
function __eubnt_show_warning() {
  local warning_prefix
  if [[ -n "${1:-}" ]]; then
    if [[ "${2:-}" = "none" ]]; then
      warning_prefix=""
    else
      warning_prefix="WARNING: "
    fi
    __eubnt_echo_and_log "${__colors_warning_text}${warning_prefix}${1}${__colors_default}\\n"
  fi
}

# Add to the log file
# $1: The text to log
function __eubnt_add_to_log() {
  if [[ -n "${1:-}" ]]; then
    echo -e "${1}" >>"${__script_log}"
  fi
}

# Echo to the screen and log file
# $1: The text to echo
# $2: Optional file to pipe echo output to
# $3: Can be set to append if appending to $2 is needed
function __eubnt_echo_and_log() {
  if [[ -n "${1:-}" && -z "${2:-}" ]]; then
    echo -e -n "${1}" | tee -a "${__script_log}"
  elif [[ -n "${1:-}" && -n "${2:-}" ]]; then
    if [[ "${3:-}" = "append" ]]; then
      echo "${1}" | tee -a "${2}" | tee -a "${__script_log}" 
    else
      echo "${1}" | tee "${2}" | tee -a "${__script_log}" 
    fi
  fi
}


# A wrapper to run commands, display a nice message and handle errors gracefully
# $1: The full command to run as a string
# $2: If set to "foreground" then the command will run in the foreground, if set to "quiet" the output will be directed to the log file
###
# Make sure the command seems valid
# Run the command in the background and show a spinner (https://unix.stackexchange.com/a/225183)
# Run the command in the foreground when in verbose mode
function __eubnt_run_command() {
  if [[ -z "${1:-}" ]]; then
    return 0
  fi
  local background_pid
  declare -a full_command=()
  IFS=' ' read -r -a full_command <<< "${1}"
  if [[ ! $(command -v "${full_command[0]}") ]]; then
    __eubnt_show_error "Unknown command ${full_command[0]} at $(caller)"
  fi
  if [[ "${full_command[1]}" != "echo" ]]; then
    __eubnt_add_to_log "${1}"
  fi
  if [[ ( "${__verbose_output:-}" && "${2:-}" != "quiet" ) || "${2:-}" = "foreground" || "${full_command[1]}" = "echo" ]]; then
    "${full_command[@]}" | tee -a "${__script_log}"
  elif [[ "${2:-}" = "quiet" ]]; then
    "${full_command[@]}" &>>"${__script_log}"
  else
    "${full_command[@]}" &>>"${__script_log}" &
    background_pid=$!
  fi
  if [[ -n "${background_pid:-}" ]]; then
    local i=0
    while [[ -d /proc/$background_pid ]]; do
      echo -e -n "\\rRunning ${1} [${__spinner:i++%${#__spinner}:1}]"
      sleep 0.5
      if [[ $i -gt 360 ]]; then
        break
      fi
    done
    __eubnt_echo_and_log "\\rRunning ${1} [\\xE2\\x9C\\x93]\\n"
  fi
  return 0
}

# Add a source list to the system
# $1: The source information to use
# $2: The name of the source list file to make on the local machine
# $3: A search term to use when checking if the source list should be added
function __eubnt_add_source() {
  if [[ "${1:-}" && "${2:-}" && "${3:-}" ]]; then
    if [[ ! $(find /etc/apt -name "*.list" -exec grep "${3}" {} \;) ]]; then
      __eubnt_echo_and_log "deb ${1}" "${__apt_sources_dir}/${2}"
    else
      __eubnt_add_to_log "Skipping add source for ${1}"
    fi
  fi
}

# Add a package signing key to the system
# $1: The 32-bit hex fingerprint of the key to add
function __eubnt_add_key() {
  if [[ "${1:-}" ]]; then
    if ! apt-key list 2>/dev/null | grep --quiet "${1:0:4}.*${1:4:4}"; then
      __eubnt_run_command "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys ${1}"
    fi
  fi
}

# Check if is package is installed
# $1: The name of the package to check
function __eubnt_is_package_installed() {
  if [[ -z "${1:-}" ]]; then
    return 1
  fi
  local package_name
  # shellcheck disable=SC2001
  package_name=$(echo "${1}" | sed 's/=.*//')
  if dpkg --list 2>/dev/null | grep --quiet "^i.*${package_name}.*"; then
    return 0
  else
    return 1
  fi
}

# Install package if needed and handle errors gracefully
# $1: The name of the package to install
# $2: An optional target release to use
function __eubnt_install_package() {
  if [[ "${1:-}" ]]; then
    local target_release
    if ! apt-get install --simulate "${1}" &>/dev/null; then
      __eubnt_add_ubuntu_sources
      __eubnt_run_command "apt-get update"
      __eubnt_run_command "apt-get install --fix-broken --yes"
    fi
    if apt-get install --simulate "${1}" &>/dev/null; then
      if ! __eubnt_is_package_installed "${1}"; then
        local i=0
        while lsof /var/lib/dpkg/lock &>/dev/null; do
          echo -e -n "\\rWaiting for package manager to become available... [${__spinner:i++%${#__spinner}:1}]"
          sleep 0.5
        done
        __eubnt_echo_and_log "\\rWaiting for package manager to become available... [\\xE2\\x9C\\x93]\\n"
        if [[ -n "${2:-}" ]]; then
          target_release="--target-release ${2} "
        fi
        __eubnt_run_command "apt-get install --yes ${target_release:-}${1}"
      else
        __eubnt_echo_and_log "Package ${1} already installed [\\xE2\\x9C\\x93]\\n"
      fi
    else
      __eubnt_show_error "Unable to install package ${1} at $(caller)"
    fi
  fi
}

### Parse commandline options
##############################################################################

# Basic way to get command line options
# TODO: Incorporate B3BP methods here
while getopts ":aqvx" options; do
  case "${options}" in
    a)
      __eubnt_add_to_log "Accepted license via command line option"
      __accept_license=true;;
    q)
      __eubnt_add_to_log "Running script in quick mode"
      __quick_mode=true;;
    v)
      __eubnt_add_to_log "Running script with verbose screen output"
      __verbose_output=true;;
    x)
      __eubnt_add_to_log "Running script with tracing turned on for debugging"
      set -o xtrace
      __script_debug=true;;
    *)
      break;;
  esac
done

### Main script functions
##############################################################################

# Setup source lists for later use in the script
###
# General: Clear list caches
# Debian: Make sure the dirmngr package is installed so keys can be validated
# Ubuntu: Setup alternative source lists to get certain packages
# Certbot: Debian distribution sources include it, sources are available for Ubuntu except Precise
# Java: Use WebUpd8 repository for Precise and Trust era OSes (https://gist.github.com/pyk/19a619b0763d6de06786 | https://askubuntu.com/a/190674)
# Java: Use the distribution sources to get Java for all others
# Mongo: Official repository only distributes 64-bit packages, not compatible with Wheezy
# Mongo: UniFi will install it from distribution sources if needed
# UniFi: Add UBNT package signing key here, add source list later depending on the chosen version
function __eubnt_setup_sources() {
  __eubnt_show_header "Setting up repository source lists...\\n"
  if [[ $__is_debian ]]; then
    __eubnt_install_package "dirmngr"
  fi
  if [[ $__is_ubuntu ]]; then
    __eubnt_add_ubuntu_sources
    if [[ "${__os_version_name}" != "precise" ]]; then
      __eubnt_add_source "http://ppa.launchpad.net/certbot/certbot/ubuntu ${__os_version_name} main" "ppa\\.laundpad\\.net.*${__os_version_name}.*main"
      __eubnt_add_key "75BCA694"
    fi
  elif [[ $__is_debian ]]; then 
    __eubnt_add_source "http://ftp.debian.org/debian ${__os_version_name}-backports main" "${__os_version_name}-backports.list" "ftp\\.debian\\.org.*${__os_version_name}-backports.*main"
  fi
  if [[ $__setup_source_java ]]; then
    if [[ "${__os_version_name_ubuntu_equivalent}" = "precise" || "${__os_version_name}" = "trusty" ]]; then
      __eubnt_add_key "EEA14886"
      __eubnt_add_source "http://ppa.launchpad.net/webupd8team/java/ubuntu ${__os_version_name_ubuntu_equivalent} main" "webupd8team-java.list" "ppa\\.launchpad\\.net.*${__os_version_name_ubuntu_equivalent}.*main"
      echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
      __install_webupd8_java=true
    else
      __install_java=true
    fi
  fi
  if [[ $__setup_source_mongo ]]; then
    local mongo_repo_distro=
    local mongo_repo_url=
    if [[ $__is_64 && $__is_ubuntu ]]; then
      if [[ "${__os_version_name}" = "precise" ]]; then
        mongo_repo_distro="trusty"
      elif [[ "${__os_version_name}" = "bionic" ]]; then
        mongo_repo_distro="xenial"
      else
        mongo_repo_distro="${__os_version_name}"
      fi
      mongo_repo_url="http://repo.mongodb.org/apt/ubuntu ${mongo_repo_distro}/mongodb-org/3.4 multiverse"
    elif [[ $__is_64 && $__is_debian ]]; then
      if [[ "${__os_version_name}" != "wheezy" ]]; then
        mongo_repo_url="http://repo.mongodb.org/apt/debian jessie/mongodb-org/3.4 main"
      fi
    fi
    if [[ $mongo_repo_url ]]; then
      __eubnt_add_source "${mongo_repo_url}" "mongodb-org-3.4.list" "repo\\.mongodb\\.org.*3\\.4"
      __eubnt_add_key "A15703C6"
      __install_mongo=true
    fi
  fi
  __eubnt_add_key "C0A52C50"
  __eubnt_run_command "apt-get update"
}

function __eubnt_add_ubuntu_sources() {
  __eubnt_add_source "http://archive.ubuntu.com/ubuntu ${__os_version_name} main universe" "${__os_version_name}-archive.list" "archive\\.ubuntu\\.com.*${__os_version_name}.*main"
  __eubnt_add_source "http://security.ubuntu.com/ubuntu ${__os_version_name}-security main universe" "${__os_version_name}-security.list" "security\\.ubuntu\\.com.*${__os_version_name}-security main"
  __eubnt_add_source "http://mirrors.kernel.org/ubuntu ${__os_version_name} main universe" "${__os_version_name}-mirror.list" "mirrors\\.kernel\\.org.*${__os_version_name}.*main"
}

# Collection of different fixes to do pre/post apt install/upgrade
###
# First issue "fix-broken" and "autoremove" commands
# Fix for kernel files filling /boot based on solution found here -  https://askubuntu.com/a/90219
function __eubnt_install_fixes {
  __eubnt_show_header "Running common pre-install fixes...\\n"
  __eubnt_run_command "apt-get install --fix-broken --yes"
  __eubnt_run_command "apt-get autoremove --yes"
  __eubnt_run_command "rm -rf /var/lib/apt/lists/*"
  if [[ -d /boot ]]; then
    if [[ $(df /boot | awk '/\/boot/{gsub("%", ""); print $5}') -gt 50 ]]; then
      declare -a files_in_boot=()
      declare -a kernel_packages=()
      __eubnt_show_text "Removing old kernel files from /boot"
      while IFS=$'\n' read -r found_file; do files_in_boot+=("$found_file"); done < <(find /boot -maxdepth 1 -type f)
      for boot_file in "${!files_in_boot[@]}"; do
        kernel_version=$(echo "${files_in_boot[$boot_file]}" | grep --extended-regexp --only-matching "[0-9]+\\.[0-9]+(\\.[0-9]+)?(\\-{1}[0-9]+)?")
        if [[ "${kernel_version}" = *"-"* && "${__os_kernel_version}" = *"-"* && "${kernel_version//-*/}" = "${__os_kernel_version//-*/}" && "${kernel_version//*-/}" -lt "${__os_kernel_version//*-/}" ]]; then
          # shellcheck disable=SC2227
          find /boot -maxdepth 1 -type f -name "*${kernel_version}*" -exec rm {} \; -exec echo Removing {} >>"${__script_log}" \;
        fi
      done
      __eubnt_run_command "apt-get install --fix-broken --yes"
      __eubnt_run_command "apt-get autoremove --yes"
      while IFS=$'\n' read -r found_package; do kernel_packages+=("$found_package"); done < <(dpkg --list linux-{image,headers}-"[0-9]*" | awk '/linux/{print $2}')
      for kernel in "${!kernel_packages[@]}"; do
        kernel_version=$(echo "${kernel_packages[$kernel]}" | sed --regexp-extended 's/linux-(image|headers)-//g' | sed 's/[-][a-z].*//g')
        if [[ "${kernel_version}" = *"-"* && "${__os_kernel_version}" = *"-"* && "${kernel_version//-*/}" = "${__os_kernel_version//-*/}" && "${kernel_version//*-/}" -lt "${__os_kernel_version//*-/}" ]]; then
          __eubnt_run_command "apt-get purge --yes ${kernel_packages[$kernel]}"
        fi
      done
    fi
  fi
}

# Install basic system utilities needed for successful script run
function __eubnt_install_updates_utils() {
  __eubnt_show_header "Installing utilities and updates...\\n"
  __eubnt_install_package "software-properties-common"
  __eubnt_install_package "unattended-upgrades"
  __eubnt_install_package "curl"
  __eubnt_install_package "psmisc"
  __eubnt_install_package "binutils"
  __eubnt_install_package "dnsutils"
  if [[ $__hold_java ]]; then
    __eubnt_run_command "apt-mark hold ${__hold_java}"
  fi
  if [[ $__hold_mongo ]]; then
    __eubnt_run_command "apt-mark hold ${__hold_mongo}"
  fi
  if [[ $__hold_unifi ]]; then
    __eubnt_run_command "apt-mark hold ${__hold_unifi}"
  fi
  __eubnt_run_command "apt-get dist-upgrade --yes"
  __eubnt_run_command "apt-get install --fix-broken --yes"
  if [[ $__hold_java ]]; then
    __eubnt_run_command "apt-mark unhold ${__hold_java}"
  fi
  if [[ $__hold_mongo ]]; then
    __eubnt_run_command "apt-mark unhold ${__hold_mongo}"
  fi
  if [[ $__hold_unifi ]]; then
    __eubnt_run_command "apt-mark unhold ${__hold_unifi}"
  fi
  __run_autoremove=true
}

# Better random number generator from ssawyer (https://community.ubnt.com/t5/UniFi-Wireless/UniFi-Controller-Linux-Install-Issues/m-p/1324455/highlight/true#M116452)
# Virtual memory tweaks from adrianmmiller
function __eubnt_system_tweaks() {
  __eubnt_install_package "haveged"
  __eubnt_run_command "sysctl vm.swappiness=10"
  __eubnt_run_command "sysctl vm.vfs_cache_pressure=50"
}

function __eubnt_install_java() {
  if [[ $__install_webupd8_java || $__install_java ]]; then
    __eubnt_show_header "Installing Java...\\n"
    local set_java_alternative target_release
    if [[ $__install_webupd8_java ]]; then
      __eubnt_install_package "oracle-java8-installer"
      __eubnt_install_package "oracle-java8-set-default"
    else
      if [[ "${__os_version_name}" = "jessie" ]]; then
        target_release="${__os_version_name}-backports"
      fi
      __eubnt_install_package "ca-certificates-java" "${target_release:-}"
      __eubnt_install_package "openjdk-8-jre-headless" "${target_release:-}"
      set_java_alternative=$(update-java-alternatives --list | awk '/^java-.*-openjdk-/{print $1}')
      __eubnt_run_command "update-java-alternatives --set ${set_java_alternative}"
    fi
    __eubnt_install_package "jsvc"
    __eubnt_install_package "libcommons-daemon-java"
  fi
}

function __eubnt_purge_mongo() {
  if [[ "${__purge_mongo:-}" && ! "${__is_unifi_installed:-}" ]]; then
    __eubnt_show_header "Purging MongoDB...\\n"
    apt-get purge --yes "mongodb*"
    rm "${__apt_sources_dir}/mongodb"*
    __eubnt_run_command "apt-get update"
  fi
}

function __eubnt_install_mongo()
{
  if [[ $__is_64 && $__install_mongo ]]; then
    __eubnt_show_header "Installing MongoDB...\\n"
    __eubnt_install_package "mongodb-org=3.4.*"
  fi
}

function __eubnt_install_unifi()
{
  __eubnt_show_header "Installing UniFi Controller...\\n"
  local selected_unifi_version
  declare -a unifi_supported_versions=(5.6 5.8 5.9)
  declare -a unifi_historical_versions=(5.2 5.3 5.4 5.5 5.6 5.8 5.9)
  declare -a unifi_versions_to_install=()
  declare -a unifi_versions_to_select=()
  if [[ $__unifi_version_installed ]]; then
    __eubnt_show_notice "Version ${__unifi_version_installed} is currently installed\\n"
  fi
  if [[ "${__quick_mode:-}" ]]; then
    if [[ $__unifi_version_installed ]]; then
      selected_unifi_version="${__unifi_version_installed:0:3}"
    else
      selected_unifi_version="${__unifi_version_stable}"
    fi
  else
    for version in "${!unifi_supported_versions[@]}"; do
      if [[ $__unifi_version_installed ]]; then
        if [[ "${unifi_supported_versions[$version]:0:3}" = "${__unifi_version_installed:0:3}" ]]; then
          if [[ $__unifi_update_available ]]; then
            unifi_versions_to_select+=("${__unifi_update_available}")
          else
            unifi_versions_to_select+=("${__unifi_version_installed}")
          fi
        elif [[ "${unifi_supported_versions[$version]:2:1}" -gt "${__unifi_version_installed:2:1}" ]]; then
          unifi_versions_to_select+=("${unifi_supported_versions[$version]}.x")
        fi
      else
        unifi_versions_to_select+=("${unifi_supported_versions[$version]}.x")
      fi
    done
    unifi_versions_to_select+=("None")
    __eubnt_show_notice "Which controller do you want to install or upgrade to?\\n"
    select version in "${unifi_versions_to_select[@]}"; do
      case "${version}" in
        "")
          selected_unifi_version="${__unifi_version_stable}"
          break;;
        *)
          if [[ "${version}" = "None" ]]; then
            return 0
          fi
          selected_unifi_version="${version%.*}"
          break;;
      esac
    done
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
  __eubnt_run_command "service unifi start"
}

# TODO: Add API call to make a backup
# TODO: Add error handling in case install fails
function __eubnt_install_unifi_version()
{
  if [[ "${1:-}" ]]; then
    unifi_install_this_version="${1}"
  else
    __eubnt_show_error "No UniFi version specified to install"
  fi
  __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${unifi_install_this_version} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${unifi_install_this_version}"
  __eubnt_run_command "apt-get update"
  unifi_updated_version=$(apt-cache policy unifi | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
  if [[ "${__unifi_version_installed}" = "${unifi_updated_version}" ]]; then
    __eubnt_show_notice "\\nUniFi ${__unifi_version_installed} is already installed\\n"
    sleep 1
    return 0
  fi
  __eubnt_show_header "Installing UniFi version ${unifi_updated_version}...\\n"
  if [[ $__unifi_version_installed ]]; then
    __eubnt_show_warning "Make sure you have a backup!\\n"
  fi
  if __eubnt_question_prompt "" "return"; then
    echo "unifi unifi/has_backup boolean true" | debconf-set-selections
    apt-get install --yes unifi
    __unifi_version_installed="${unifi_updated_version}"
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
    __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${__unifi_version_installed:0:3}"
    __eubnt_run_command "apt-get update"
  fi
}

# TODO: Add Cloud Key support - https://www.naschenweng.info/2017/01/06/securing-ubiquiti-unifi-cloud-key-encrypt-automatic-dns-01-challenge/
# TODO: Add DNS challenge support for Cloudflare
###
# Based on solution by Frankedinven (https://community.ubnt.com/t5/UniFi-Wireless/Lets-Encrypt-on-Hosted-Controller/m-p/2463220/highlight/true#M318272)
function __eubnt_setup_certbot() {
  if [[ "${__os_version_name}" = "precise" || "${__os_version_name}" = "wheezy" ]]; then
    return 0
  fi
  local source_backports skip_certbot_questions domain_name email_address resolved_domain_name email_option days_to_renewal
  __eubnt_show_header "Setting up Let's Encrypt...\\n"
  if [[ "${__os_version_name}" = "jessie" ]]; then
    target_release="${__os_version_name}-backports"
  fi
  if __eubnt_question_prompt "Do you want to setup or re-setup Let's Encrypt?" "return" "n"; then
    __eubnt_install_package "certbot" "${target_release:-}"
  else
    return 0
  fi
  __eubnt_get_user_input "\\nDomain name to use for the UniFi Controller: " "domain_name"
  days_to_renewal=0
  if certbot certificates --domain "${domain_name:-}" | grep --quiet "Domains: "; then
    __eubnt_run_command "certbot certificates --domain ${domain_name}" "foreground"
    if __eubnt_question_prompt "Do you want to use the existing Let's Encrypt certificate?" "return"; then
      days_to_renewal=$(certbot certificates --domain "${domain_name}" | grep --only-matching --max-count=1 "VALID: .*" | awk '{print $2}')
      skip_certbot_questions=true
    fi
  fi
  if [[ -z "${skip_certbot_questions:-}" ]]; then
    __eubnt_get_user_input "\\nEmail address for renewal notifications (optional): " "email_address" "optional"
  fi
  resolved_domain_name=$(dig +short "${domain_name}")
  if [[ "${__machine_ip_address}" != "${resolved_domain_name}" ]]; then
    echo; __eubnt_show_warning "The domain ${domain_name} does not resolve to ${__machine_ip_address}\\n"
    if ! __eubnt_question_prompt "" "return"; then
      return 0
    fi
  fi
  if [[ -n "${email_address:-}" ]]; then
    email_option="--email ${email_address}"
  else
    email_option="--register-unsafely-without-email"
  fi
  if [[ -n "${domain_name:-}" ]]; then
    local letsencrypt_scripts_dir pre_hook_script post_hook_script letscript_live_dir letscript_renewal_dir letscript_renewal_conf letsencrypt_privkey letsencrypt_fullchain force_renewal run_mode
    letsencrypt_scripts_dir=$(mkdir --parents "${__eubnt_dir}/letsencrypt" && echo "${__eubnt_dir}/letsencrypt")
    pre_hook_script="${letsencrypt_scripts_dir}/pre-hook_${domain_name}.sh"
    post_hook_script="${letsencrypt_scripts_dir}/post-hook_${domain_name}.sh"
    letscript_live_dir="${__letsencrypt_dir}/live/${domain_name}"
    letscript_renewal_dir="${__letsencrypt_dir}/renewal"
    letscript_renewal_conf="${letscript_renewal_dir}/${domain_name}.conf"
    letsencrypt_privkey="${letscript_live_dir}/privkey.pem"
    letsencrypt_fullchain="${letscript_live_dir}/fullchain.pem"
    tee "${pre_hook_script}" &>/dev/null <<EOF
#!/usr/bin/env bash
http_process_file="${letsencrypt_scripts_dir}/http_process"
rm "\${http_process_file}" &>/dev/null
if netstat -tulpn | grep ":80 " --quiet; then
  http_process=$(netstat -tulpn | awk '/:80 /{print $7}' | sed 's/[0-9]*\///')
  service "\${http_process}" stop &>/dev/null
  echo "\${http_process}" >"\${http_process_file}"
fi
if [[ \$(dpkg --status "ufw" 2>/dev/null | grep "ok installed") && \$(ufw status | grep " active") ]]; then
  ufw allow http &>/dev/null
fi
EOF
# End of output to file
    chmod +x "${pre_hook_script}"
    tee "${post_hook_script}" &>/dev/null <<EOF
#!/usr/bin/env bash
http_process_file="${letsencrypt_scripts_dir}/http_process"
if [[ -s "\${http_process_file}" ]]; then
  http_process=$(cat "\${http_process_file}")
  service "\${http_process}" start &>/dev/null
fi
rm "\${http_process_file}" &>/dev/null
if [[ \$(dpkg --status "ufw" 2>/dev/null | grep "ok installed") && \$(ufw status | grep " active") && ! \$(netstat -tulpn | grep ":80 ") ]]; then
  ufw delete allow http &>/dev/null
fi
if [[ -f ${letsencrypt_privkey} && -f ${letsencrypt_fullchain} ]]; then
  if ! md5sum -c ${letsencrypt_fullchain}.md5 &>/dev/null; then
    md5sum ${letsencrypt_fullchain} >${letsencrypt_fullchain}.md5
    cp ${__unifi_data_dir}/keystore ${__unifi_data_dir}/keystore.backup.$(date +%s) &>/dev/null
    openssl pkcs12 -export -inkey ${letsencrypt_privkey} -in ${letsencrypt_fullchain} -out ${letscript_live_dir}/fullchain.p12 -name unifi -password pass:aircontrolenterprise &>/dev/null
    keytool -delete -alias unifi -keystore ${__unifi_data_dir}/keystore -deststorepass aircontrolenterprise &>/dev/null
    keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${__unifi_data_dir}/keystore -srckeystore ${letscript_live_dir}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt &>/dev/null
    service unifi restart &>/dev/null
  fi
fi
EOF
# End of output to file
    chmod +x "${post_hook_script}"
    force_renewal="--keep-until-expiring"
    run_mode="--keep-until-expiring"
    if [[ "${days_to_renewal}" -ge 30 ]]; then
      if __eubnt_question_prompt "\\nDo you want to force certificate renewal?" "return" "n"; then
        force_renewal="--force-renewal"
      fi
    fi
    if [[ $__script_debug ]]; then
      run_mode="--dry-run"
    else
      if __eubnt_question_prompt "Do you want to do a dry run?" "return" "n"; then
        run_mode="--dry-run"
      fi
    fi
    # shellcheck disable=SC2086
    if certbot certonly --non-interactive --standalone --agree-tos --noninteractive --pre-hook ${pre_hook_script} --post-hook ${post_hook_script} --domain ${domain_name} ${email_option} ${force_renewal} ${run_mode} 2>/dev/null; then
      __eubnt_show_success "\\nCertbot succeeded for domain name: ${domain_name}"
      __unifi_domain_name="${domain_name}"
      sleep 3
    else
      __eubnt_show_warning "\\nCertbot failed for domain name: ${domain_name}"
      sleep 3
    fi
    if [[ -f "${letscript_renewal_conf}" ]]; then
      sed -i "s|^pre_hook.*$|pre_hook = ${pre_hook_script}|" "${letscript_renewal_conf}"
      sed -i "s|^post_hook.*$|post_hook = ${post_hook_script}|" "${letscript_renewal_conf}"
      if crontab -l | grep --quiet "^[^#]"; then
        local found_file crontab_file
        declare -a files_in_crontab
        while IFS=$'\n' read -r found_file; do files_in_crontab+=("$found_file"); done < <(crontab -l | awk '/^[^#]/{print $6}')
        for crontab_file in "${!files_in_crontab[@]}"; do
          if grep --quiet "keystore" "${crontab_file}"; then
            __eubnt_show_warning "Please check your crontab to make sure there aren't any conflicting Let's Encrypt renewal scripts"
            sleep 3
          fi
        done
      fi
    fi
  fi
}

# Install OpenSSH server and harden the configuration
###
# Hardening the OpenSSH Server config according to best practices (https://gist.github.com/nvnmo/91a20f9e72dffb9922a01d499628040f | https://linux-audit.com/audit-and-harden-your-ssh-configuration/)
function __eubnt_setup_ssh_server() {
  __eubnt_show_header "Setting up OpenSSH Server..."
  if ! __eubnt_is_package_installed "openssh-server"; then
    echo
    if __eubnt_question_prompt "Do you want to install the OpenSSH server?" "return"; then
      __eubnt_run_command "apt-get install --yes openssh-server"
    fi
  fi
  if [[ $(dpkg --list | grep "openssh-server") && -f "${__sshd_config}" ]]; then
    cp "${__sshd_config}" "${__sshd_config}.bak-${__script_time}"
    __eubnt_show_notice "\\nChecking OpenSSH server settings for recommended changes...\\n"
    if [[ $(grep ".*Port 22$" "${__sshd_config}") || ! $(grep ".*Port.*" "${__sshd_config}") ]]; then
      if __eubnt_question_prompt "Change SSH port from the default 22?" "return" "n"; then
        local ssh_port=""
        while [[ ! $ssh_port =~ ^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$ ]]; do
          read -r -p "Port number: " ssh_port
        done
        if grep --quiet ".*Port.*" "${__sshd_config}"; then
          sed -i "s/^.*Port.*$/Port ${ssh_port}/" "${__sshd_config}"
        else
          echo "Port ${ssh_port}" | tee -a "${__sshd_config}"
        fi
        __restart_ssh_server=true
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
          __restart_ssh_server=true
        fi
      fi
    done
    awk '!seen[$0]++' "${__sshd_config}" &>/dev/null # https://stackoverflow.com/a/1444448
  fi
}

function __eubnt_setup_ufw() {
  __eubnt_show_header "Setting up UFW (Uncomplicated Firewall)...\\n"
  local unifi_system_properties unifi_http_port unifi_https_port unifi_portal_http_port unifi_portal_https_port unifi_throughput_port unifi_stun_port ssh_port
  unifi_system_properties="${__unifi_data_dir}/system.properties"
  if [[ -f "${unifi_system_properties}" ]]; then
    unifi_http_port=$(grep "^unifi.http.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_http_port ]]; then
      unifi_http_port="8080"
    fi
    unifi_https_port=$(grep "^unifi.https.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_https_port ]]; then
      unifi_https_port="8443"
    fi
    unifi_portal_http_port=$(grep "^portal.http.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_portal_http_port ]]; then
      unifi_portal_http_port="8880"
    fi
    unifi_portal_https_port=$(grep "^portal.https.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_portal_https_port ]]; then
      unifi_portal_https_port="8843"
    fi
    unifi_throughput_port=$(grep "^unifi.throughput.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_throughput_port ]]; then
      unifi_throughput_port="6789"
    fi
    unifi_stun_port=$(grep "^unifi.stun.port" "${unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_stun_port ]]; then
      unifi_stun_port="3478"
    fi
  fi
  if [[ ! $(dpkg --list "ufw" | grep "^i") || ( $(command -v ufw) && $(ufw status | grep "inactive") ) ]]; then
    if ! __eubnt_question_prompt "Do you want to use UFW?" "return"; then
      return 0
    fi
  fi
  __eubnt_install_package "ufw"
  if [[ -f "${__sshd_config}" ]]; then
    ssh_port=$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')
  fi
  if [[ -n "${unifi_http_port:-}" && -n "${unifi_https_port:-}" && -n "${unifi_portal_http_port:-}" && -n "${unifi_portal_https_port:-}" && -n "${unifi_throughput_port:-}" && -n "${unifi_stun_port:-}" ]]; then
    tee "/etc/ufw/applications.d/unifi" &>/dev/null <<EOF
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
  __eubnt_run_command "ufw status" "foreground"
  echo
  if __eubnt_question_prompt "Do you want to reset your current UFW rules?" "return" "n"; then
    __eubnt_run_command "ufw --force reset"
  fi
  if [[ -n "${ssh_port:-}" ]]; then
    if __eubnt_question_prompt "Do you want to allow access to SSH from any host?" "return"; then
      __eubnt_run_command "ufw allow ${ssh_port}/tcp"
    else
      __eubnt_run_command "ufw --force delete allow ${ssh_port}/tcp" "quiet"
    fi
    echo
  fi
  if [[ "${unifi_http_port:-}" && "${unifi_https_port:-}" ]]; then
    __unifi_https_port="${unifi_https_port}"
    if __eubnt_question_prompt "Do you want to allow access to the UniFi ports from any host?" "return"; then
      __eubnt_run_command "ufw allow from any to any app unifi"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app unifi" "quiet"
    fi
    echo
    if __eubnt_question_prompt "Is this controller on your local network?" "return" "n"; then
      __eubnt_run_command "ufw allow from any to any app unifi-local"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app unifi-local" "quiet"
    fi
    echo
  else
    __eubnt_show_warning "Unable to determine UniFi ports to allow. Is it installed?\\n"
  fi
  echo "y" | ufw enable >>"${__script_log}"
  __eubnt_run_command "ufw reload"
  __eubnt_show_notice "\\nUpdated UFW status:\\n"
  __eubnt_run_command "ufw status" "foreground"
  sleep 1
}

# Recommended by CrossTalk Solutions (https://crosstalksolutions.com/15-minute-hosted-unifi-controller-setup/)
function __eubnt_setup_swap_file() {
  __eubnt_run_command "fallocate -l 2G /swapfile"
  __eubnt_run_command "chmod 600 /swapfile"
  __eubnt_run_command "mkswap /swapfile"
  if swapon /swapfile; then
    if grep --quiet "^/swapfile " "/etc/fstab"; then
      sed -i "s|^/swapfile.*$|/swapfile none swap sw 0 0|" "/etc/fstab"
    else
      echo "/swapfile none swap sw 0 0" >>/etc/fstab
    fi
    __eubnt_show_success "\\nCreated swap file!\\n"
  else
    rm -rf /swapfile
    __eubnt_show_warning "Unable to create swap file!\\n"
  fi
  echo
}

function __eubnt_check_system() {
  local os_version_name_display os_version_supported os_version_recommended_display os_version_recommended os_bit have_space_for_swap
  declare -a ubuntu_supported_versions=("precise" "trusty" "xenial" "bionic")
  declare -a debian_supported_versions=("wheezy" "jessie" "stretch")
  __eubnt_show_header "Checking system...\\n"
  __eubnt_run_command "apt-get clean --yes"
  __eubnt_run_command "apt-get update"
  echo
  if [[ "${__architecture}" = "i686" ]]; then
    __is_32=true
    os_bit="32-bit"
  elif [[ "${__architecture}" = "x86_64" ]]; then
    __is_64=true
    os_bit="64-bit"
  else
    __eubnt_show_error "${__architecture} is not supported"
  fi
  if [[ "${__os_name}" = "Ubuntu" ]]; then
    __is_ubuntu=true
    os_version_recommended_display="16.04 Xenial"
    os_version_recommended="xenial"
    for version in "${!ubuntu_supported_versions[@]}"; do
      if [[ "${ubuntu_supported_versions[$version]}" = "${__os_version_name}" ]]; then
        __os_version_name_ubuntu_equivalent="${__os_version_name}"
        # shellcheck disable=SC2001
        os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
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
        __os_version_name_ubuntu_equivalent="${ubuntu_supported_versions[$version]}"
        # shellcheck disable=SC2001
        os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
        os_version_supported=true
        break
      fi
    done
  else
    __eubnt_show_error "This script is for Debian or Ubuntu\\nYou appear to have: ${__os_all_info}\\n"
  fi
  if [[ -z "${os_version_supported:-}" ]]; then
    __eubnt_show_warning "${__os_name} ${__os_version} is not officially supported\\n"
    __eubnt_question_prompt
    # shellcheck disable=SC2001
    os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
    if [[ $__is_debian ]]; then
      __os_version_name="stretch"
      __os_version_name_ubuntu_equivalent="xenial"
    else
      __os_version_name="bionic"
      __os_version_name_ubuntu_equivalent="bionic"
    fi
  fi
  if [[ -z "${__os_version}" || ( ! $__is_ubuntu && ! $__is_debian ) ]]; then
    __eubnt_show_error "Unable to detect system information\\n"
  fi
  __eubnt_show_text "Disk free space is ${__colors_bold_text}${__disk_free_space}${__colors_default}\\n"
  if [[ "${__disk_free_space%G*}" -lt "${__recommended_disk_free_space%G*}" ]]; then
    __eubnt_show_warning "UBNT recommends at least ${__recommended_disk_free_space} of free space\\n"
  else
    if [[ "${__disk_free_space%G*}" -gt $(( ${__recommended_disk_free_space%G*} + ${__recommended_swap_total_gb%G*} )) ]]; then
      have_space_for_swap=true
    fi
  fi
  __eubnt_show_text "Memory total size is ${__colors_bold_text}${__memory_total}${__colors_default}\\n"
  if [[ "${__memory_total%M*}" -lt "${__recommended_memory_total%M*}" ]]; then
    __eubnt_show_warning "UBNT recommends at least ${__recommended_memory_total_gb} of memory\\n"
  fi
  __eubnt_show_text "Swap total size is ${__colors_bold_text}${__swap_total}\\n"
  if [[ "${__swap_total%M*}" -eq 0 && "${have_space_for_swap:-}" ]]; then
    if __eubnt_question_prompt "Do you want to setup a ${__recommended_swap_total_gb} swap file?" "return"; then
      __eubnt_setup_swap_file
    fi
  fi
  __eubnt_show_text "Operating system is ${__colors_bold_text}${__os_name} ${__os_version} ${os_version_name_display} ${os_bit}\\n"
  if [[ "${__os_version_name}" != "${os_version_recommended}" || "${os_bit}" != "${__os_bit_recommended}" ]]; then
    __eubnt_show_warning "UBNT recommends ${__os_name} ${os_version_recommended_display} ${__os_bit_recommended}\\n"
  fi
  if [[ $(echo "${__nameservers}" | awk '{print $2}') ]]; then
    __eubnt_show_text "Current nameservers in use are ${__colors_bold_text}${__nameservers}${__colors_default}\\n"
  else
    __eubnt_show_text "Current nameserver in use is ${__colors_bold_text}${__nameservers}${__colors_default}\\n"
  fi
  if ! dig +short "${__ubnt_dns}" &>/dev/null; then
    if __eubnt_question_prompt "Unable to resolve ${__ubnt_dns}, do you want to add the ${__recommended_nameserver} nameserver?" "return"; then
      echo "nameserver ${__recommended_nameserver}" | tee /etc/resolvconf/resolv.conf.d/base
      
      __eubnt_run_command "resolvconf -u"
      __nameservers=$(awk '/nameserver/{print $2}' /etc/resolv.conf | xargs)
    fi
  fi
  __eubnt_show_text "Current time is ${__colors_bold_text}$(date)${__colors_default}\\n"
  if ! __eubnt_question_prompt "Does the current time and timezone look correct?" "return"; then
    __eubnt_install_package "ntp"
    __eubnt_install_package "ntpdate"
    __eubnt_run_command "service ntp stop"
    __eubnt_run_command "ntpdate 0.ubnt.pool.ntp.org"
    __eubnt_run_command "service ntp start"
    dpkg-reconfigure tzdata
    __eubnt_show_success "Updated time is $(date)\\n"
    sleep 3
  fi
  if [[ $(command -v java) ]]; then
    local java_version_installed java_package_installed set_java_alternative
    if __eubnt_is_package_installed "oracle-java8-installer"; then
      java_version_installed=$(dpkg --list "oracle-java8-installer" | awk '/^i/{print $3}' | sed 's/-.*//')
      java_package_installed="oracle-java8-installer"
      set_java_alternative=$(update-java-alternatives --list | awk '/^java-.*oracle/{print $1}')
    fi
    if __eubnt_is_package_installed "openjdk-8-jre-headless"; then
      java_version_installed=$(dpkg --list "openjdk-8-jre-headless" | awk '/^i/{print $3}' | sed 's/-.*//')
      java_package_installed="openjdk-8-jre-headless"
      set_java_alternative=$(update-java-alternatives --list | awk '/^java-.*-openjdk/{print $1}')
    fi
    __eubnt_run_command "update-java-alternatives --set ${set_java_alternative}" "quiet"
  fi
  if [[ -n "${java_version_installed:-}" ]]; then
    java_update_available=$(apt-cache policy "${java_package_installed}" | awk '/Candidate/{print $2}' | sed 's/-.*//')
    if [[ -n "${java_update_available}" && "${java_update_available}" != "${java_version_installed}" ]]; then
      __eubnt_show_text "Java ${java_version_installed} is installed, ${__colors_warning_text}version ${java_update_available} is available\\n"
      if ! __eubnt_question_prompt "Do you want to update Java to ${java_update_available}?" "return"; then
        __hold_java="${java_package_installed}"
      fi
      echo
    elif [[ "${java_update_available}" != '' && "${java_update_available}" = "${java_version_installed}" ]]; then
      __eubnt_show_success "Java ${java_version_installed} is good!\\n"
    fi
  else
    __eubnt_show_text "Java will be installed\\n"
    __setup_source_java=true
  fi
  if __eubnt_is_package_installed "mongodb.*-server"; then
    local mongo_version_installed mongo_package_installed mongo_update_available mongo_version_check
    if __eubnt_is_package_installed "mongodb-org-server"; then
      mongo_version_installed=$(dpkg --list | awk '/^i.*mongodb-org-server/{print $3}' | sed 's/.*://' | sed 's/-.*//')
      mongo_package_installed="mongodb-org-server"
    fi
    if __eubnt_is_package_installed "mongodb-server"; then
      mongo_version_installed=$(dpkg --list | awk '/^i.*mongodb-server/{print $3}' | sed 's/.*://' | sed 's/-.*//')
      mongo_package_installed="mongodb-server"
    fi
    if [[ "${mongo_package_installed:-}" = "mongodb-server" && $__is_64 && ! -f "/lib/systemd/system/unifi.service" ]]; then
      __eubnt_show_notice "Mongo officially maintains 'mongodb-org' packages but you have 'mongodb' packages installed\\n"
      if __eubnt_question_prompt "Do you want to remove the 'mongodb' packages and install 'mongodb-org' packages instead?" "return"; then
        __purge_mongo=true
        __setup_source_mongo=true
      fi
    fi
  fi
  if [[ -n "${mongo_version_installed:-}" && -n "${mongo_package_installed:-}" && ! $__purge_mongo ]]; then
    mongo_update_available=$(apt-cache policy "${mongo_package_installed}" | awk '/Candidate/{print $2}' | sed 's/.*://' | sed 's/-.*//')
    # shellcheck disable=SC2001
    mongo_version_check=$(echo "${mongo_version_installed:0:3}" | sed 's/\.//')
    if [[ "${mongo_version_check:-}" -gt "34" && ! $(dpkg --list 2>/dev/null | grep "^i.*unifi.*") ]]; then
      __eubnt_show_warning "UBNT recommends Mongo ${__mongo_version_recommended}\\n"
      if __eubnt_question_prompt "Do you want to downgrade Mongo to ${__mongo_version_recommended}?" "return"; then
        __purge_mongo=true
        __setup_source_mongo=true
      fi
    fi
    if [[ ! $__purge_mongo && -n "${mongo_update_available:-}" && "${mongo_update_available:-}" != "${mongo_version_installed}" ]]; then
      __eubnt_show_text "Mongo ${mongo_version_installed} is installed, ${__colors_warning_text}version ${mongo_update_available} is available\\n"
      if ! __eubnt_question_prompt "Do you want to update Mongo to ${mongo_update_available}?" "return"; then
        __hold_mongo="${mongo_package_installed}"
      fi
      echo
    elif [[ ! $__purge_mongo && -n "${mongo_update_available:-}" && "${mongo_update_available:-}" = "${mongo_version_installed}" ]]; then
      __eubnt_show_success "Mongo ${mongo_version_installed} is good!\\n"
    fi
  else
    __eubnt_show_text "Mongo will be installed\\n"
    __setup_source_mongo=true
  fi
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    __is_unifi_installed=true
    __unifi_version_installed=$(dpkg --list "unifi" | awk '/^i/{print $3}' | sed 's/-.*//')
    __unifi_update_available=$(apt-cache policy "unifi" | awk '/Candidate/{print $2}' | sed 's/-.*//')
    if [[ "${__unifi_update_available:0:3}" != "${__unifi_version_installed:0:3}" ]]; then
      __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${__unifi_version_installed:0:3}"
      __eubnt_run_command "apt-get update" "quiet"
      __unifi_update_available=$(apt-cache policy "unifi" | awk '/Candidate/{print $2}' | sed 's/-.*//')
    fi
    if [[ -n "${__unifi_update_available}" && "${__unifi_update_available}" != "${__unifi_version_installed}" ]]; then
      __eubnt_show_text "UniFi ${__unifi_version_installed} is installed, ${__colors_warning_text}version ${__unifi_update_available} is available\\n"
      __hold_unifi="unifi"
    elif [[ -n "${__unifi_update_available}" && "${__unifi_update_available}" = "${__unifi_version_installed}" ]]; then
      __eubnt_show_success "UniFi ${__unifi_version_installed} is good!\\n"
      __unifi_update_available=
      if ! __eubnt_question_prompt "Have you made a current backup of your UniFi Controller?" "return"; then
        __eubnt_show_error "A backup is required when UniFi is currently installed!"
      fi
    fi
  else
    __eubnt_show_text "UniFi does not appear to be installed yet\\n"
  fi
}

### Execution of script
##############################################################################

ln --force --symbolic "${__script_log}" "${__script_log_dir}/${__script_name}-latest.log"
__eubnt_script_colors
__eubnt_show_header
__eubnt_show_license
if [[ "${__accept_license:-}" ]]; then
  sleep 3
else
  __eubnt_question_prompt "Do you agree to the MIT License and want to proceed?" "exit" "n"
fi
__eubnt_check_system
__eubnt_question_prompt
__eubnt_install_fixes
__eubnt_purge_mongo
__eubnt_setup_sources
__eubnt_install_updates_utils
if [[ -f /var/run/reboot-required ]]; then
  echo
  __eubnt_show_warning "A reboot is recommended.\\nRun this script again after reboot.\\n"
  # TODO: Restart the script automatically after reboot
  if [[ "${__quick_mode:-}" ]]; then
    __eubnt_show_warning "The system will automatically reboot in 10 seconds.\\n"
    sleep 10
  fi
  if __eubnt_question_prompt "Do you want to reboot now?" "return"; then
    __eubnt_show_warning "Exiting script and rebooting system now!"
    __reboot_system=true
    exit 0
  fi
fi
__eubnt_system_tweaks
__eubnt_install_java
__eubnt_install_mongo
__eubnt_install_unifi
__eubnt_setup_ssh_server
__eubnt_setup_certbot
__eubnt_setup_ufw
__eubnt_show_success "\\nDone!\\n"
sleep 3
