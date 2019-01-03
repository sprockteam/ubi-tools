#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2034,SC2143,SC2155

### Easy UBNT: UniFi SDN Installer
##############################################################################
# A guided script to install/upgrade the UniFi SDN Controller, and secure
# your server according to best practices.
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018 SprockTech, LLC and contributors
__script_version="v0.5.7"
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
###
# ShellCheck
# https://github.com/koalaman/shellcheck
# GNU General Public License v3.0
# Copyright (c) 2012-2018 Vidar 'koala_man' Holen and contributors


### Initial startup checks
##############################################################################

# Only run this script with bash
if [ ! "$BASH_VERSION" ]; then
  if command -v bash &>/dev/null; then
    exec bash "$0" "$@"
  else
    echo -e "\\nUnable to find Bash. Is it installed?\\n"
  fi
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
__is_user_sudo=$([[ -n "${SUDO_USER:-}" ]] && echo "true")
__disk_total_space="$(df . | awk '/\//{printf "%.0fGB", $2/1024/1024}')"
__disk_free_space="$(df . | awk '/\//{printf "%.0fGB", $4/1024/1024}')"
__disk_free_space_mb="$(df . | awk '/\//{printf "%.0fMB", $4/1024}')"
__memory_total="$(grep "MemTotal" /proc/meminfo | awk '{printf "%.0fMB", $2/1024}')"
__swap_total="$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.0fMB", $2/1024}')"
__nameservers=$(awk '/nameserver/{print $2}' /etc/resolv.conf | xargs)

# Initialize miscellaneous variables
__machine_ip_address=
__os_version_name_ubuntu_equivalent=
__unifi_version_installed=
__unifi_update_available=
__unifi_domain_name=
__unifi_tcp_port_admin=

# Set various base folders and files
# TODO: Make these dynamic
__apt_sources_dir=$(find /etc -type d -name "sources.list.d")
__unifi_base_dir="/usr/lib/unifi"
__unifi_data_dir="${__unifi_base_dir}/data"
__unifi_system_properties="${__unifi_data_dir}/system.properties"
__letsencrypt_dir="/etc/letsencrypt"
__sshd_config="/etc/ssh/sshd_config"

# Recommendations and minimum requirements and misc variables
__recommended_disk_free_space="10GB"
__recommended_memory_total="2048MB"
__recommended_memory_total_gb="2GB"
__recommended_swap_total="2048MB"
__recommended_swap_total_gb="2GB"
__os_bit_recommended="64-bit"
__java_version_recommended="8"
__mongo_version_recommended="3.4.x"
__unifi_version_stable="5.9"
__recommended_nameserver="9.9.9.9"
__ubnt_dns="dl.ubnt.com"

# Initialize "boolean" variables as "false"
__is_32=
__is_64=
__is_ubuntu=
__is_debian=
__is_experimental=
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
# Fix UniFi source list if needed
# Auto clean and remove un-needed apt-get info/packages
# Show UniFi SDN Controller information post-setup
# Unset script variables
# Reboot system if needed
function __eubnt_cleanup_before_exit() {
  local log_files_to_delete=
  echo -e "${__colors_default}\\nCleaning up script, please wait...\\n"
  if [[ -n "${__restart_ssh_server:-}" ]]; then
    __eubnt_run_command "service ssh restart"
  fi
  if [[ -n "${__unifi_version_installed:-}" ]]; then
    __unifi_update_available=$(apt-cache policy "unifi" | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
    if [[ "${__unifi_update_available:0:3}" != "${__unifi_version_installed:0:3}" ]]; then
      if __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list"; then
        __eubnt_run_command "apt-get update"
      fi
    fi
  fi
  __eubnt_run_command "apt-get autoclean --yes"
  if [[ -n "${__run_autoremove:-}" ]]; then
    __eubnt_run_command "apt-get autoremove --yes"
  fi
  if [[ -f "/lib/systemd/system/unifi.service" && -z "${__reboot_system:-}" ]]; then
    __eubnt_show_header "Collecting UniFi SDN Controller info..."
    local controller_status=
    if [[ $(service unifi status | wc --lines) -gt 1 ]]; then
      controller_status=$(service unifi status | grep --only-matching "Active: .*" | sed 's/Active:/Service status:/')
    else
      controller_status="Service status: $(service unifi status)"
    fi
    __eubnt_show_notice "\\n${controller_status}"
    if [[ -n "${__unifi_tcp_port_admin:-}" ]]; then
      local controller_address
      if [[ -n "${__unifi_domain_name:-}" ]]; then
        controller_address="${__unifi_domain_name}"
      else
        controller_address="${__machine_ip_address}"
      fi
      __eubnt_show_notice "\\nWeb address: https://${controller_address}:${__unifi_tcp_port_admin}/manage/"
    fi
    echo
  fi
  if [[ -d "${__script_log_dir:-}" ]]; then
    log_files_to_delete=$(find "${__script_log_dir}" -maxdepth 1 -type f -print0 | xargs -0 --exit ls -t | awk 'NR>5')
    if [[ -n "${log_files_to_delete:-}" ]]; then
      echo "${log_files_to_delete}" | xargs --max-lines=1 rm
    fi
  fi
  if [[ "${__script_debug:-}" != "true" ]]; then
    for var_name in ${!__*}; do
      if [[ "${var_name}" != "__reboot_system" ]]; then
        unset -v "${var_name}"
      fi
    done
  fi
  if [[ -n "${__reboot_system:-}" ]]; then
    shutdown -r now
  fi
}
trap __eubnt_cleanup_before_exit EXIT
trap '__script_debug=true' ERR

### Screen display functions
##############################################################################

# Set script colors
function __eubnt_script_colors() {
  echo "${__colors_default}"
}

# Print an error to the screen
# $1: The error text to display
function __eubnt_show_error() {
  echo -e "${__colors_error_text}##############################################################################\\n"
  __eubnt_echo_and_log "ERROR! ${1:-}${__colors_default}\\n"
}

# Print a header that informs the user what task is running
# $1: Can be set with a string to display additional details about the current task
###
# If the script is not in debug mode, then the screen will be cleared first
# The script header will then be displayed
# If $1 is set then it will be displayed under the header
function __eubnt_show_header() {
  if [[ -z "${__script_debug:-}" ]]; then
    clear
  fi
  echo -e "${__colors_notice_text}### Easy UBNT: UniFi SDN Installer ${__script_version}"
  echo -e "##############################################################################${__colors_default}\\n"
  __eubnt_show_notice "${1:-}"
}

# Print text to the screen
# $1: The text to display
function __eubnt_show_text() {
  if [[ -n "${1:-}" ]]; then
    __eubnt_echo_and_log "${__colors_default}${1}${__colors_default}\\n"
  fi
}

# Print a notice to the screen
# $1: The notice to display
function __eubnt_show_notice() {
  if [[ -n "${1:-}" ]]; then
    __eubnt_echo_and_log "${__colors_notice_text}${1}${__colors_default}\\n"
  fi
}

# Print a success message to the screen
# $1: The message to display
function __eubnt_show_success() {
  if [[ -n "${1:-}" ]]; then
    __eubnt_echo_and_log "${__colors_success_text}${1}${__colors_default}\\n"
  fi
}

# Print a warning to the screen
# $1: The warning to display
# $2: Can be set to "none" to not show the "WARNING:" prefix
function __eubnt_show_warning() {
  if [[ -n "${1:-}" ]]; then
    local warning_prefix=
    if [[ "${2:-}" != "none" ]]; then
      warning_prefix="WARNING: "
    fi
    __eubnt_echo_and_log "${__colors_warning_text}${warning_prefix}${1}${__colors_default}\\n"
  fi
}

# Print the license and disclaimer for this script to the screen
function __eubnt_show_license() {
  __eubnt_show_text "MIT License\\nCopyright (c) 2018 SprockTech, LLC and contributors\\n"
  __eubnt_show_notice "${__script_contributors:-}\\n"
  __eubnt_show_warning "This script will guide you through installing and upgrading
the UniFi SDN Controller from UBNT, and securing this system
according to best practices. It is intended to work on systems that
will be dedicated to running the UniFi SDN Controller.\\n
THIS SCRIPT IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND!\\n"
  __eubnt_show_text "Read the full MIT License for this script here:
https://github.com/sprockteam/easy-ubnt/raw/master/LICENSE\\n"
}

### User input functions
##############################################################################

# Display a yes or know question and proceed accordingly based on the answer
# $1: The question to use instead of the default question
# $2: Can be set to "return" if an error should be returned instead of exiting
# $3: Can be set to "n" if the default answer should be no instead of yes
###
# If no answer is given, the default answer is used
# If the script it running in "quiet mode" then the default answer is used without prompting
function __eubnt_question_prompt() {
  local yes_no=
  local default_question="Do you want to proceed?"
  local default_answer="y"
  if [[ "${3:-}" = "n" ]]; then
    default_answer="n"
  fi
  if [[ -n "${__quick_mode:-}" ]]; then
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
# No validation is done on use the input within this function, must be done after the answer has been returned
function __eubnt_get_user_input() {
  local user_input=
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

### Logging and task functions
##############################################################################

# Add to the log file
# $1: The message to log
function __eubnt_add_to_log() {
  if [[ -n "${1:-}" ]]; then
    echo "${1}" | sed -r 's/\^\[.*m//g' >>"${__script_log}"
  fi
}

# Echo to the screen and log file
# $1: The message to echo
# $2: Optional file to pipe echo output to
# $3: If set to "append" then the message is appended to file specified in $2
function __eubnt_echo_and_log() {
  if [[ -n "${1:-}" ]]; then
    if [[ -n "${2:-}" ]]; then
      if [[ "${3:-}" = "append" ]]; then
        echo "${1}" | tee -a "${2}"
      else
        echo "${1}" | tee "${2}"
      fi
    else
      echo -e -n "${1}"
    fi
    __eubnt_add_to_log "${1}"
  fi
}

# Get the latest UniFi SDN controller minor version for the major version given
# $1: The major version number to check (i.e. "5.9")
# $2: The variable to assign the returned minor version to
# $3: If set to "url" then return the full URL to the download file instead of just the version number
function __eubnt_get_latest_unifi_version() {
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    local ubnt_download="http://dl.ubnt.com/unifi/debian/dists"
    local unifi_version_full=$(wget --quiet --output-document - "${ubnt_download}/unifi-${1}/ubiquiti/binary-amd64/Packages" | grep "Version" | sed 's/Version: //')
    if [[ "${3:-}" = "url" ]]; then
      local deb_url="${ubnt_download}/pool/ubiquiti/u/unifi/unifi_${unifi_version_full}_all.deb"
      eval "${2}=\"${deb_url}\""
    else
      local unifi_version_short=$(echo "${unifi_version_full}" | sed 's/-.*//')
      eval "${2}=\"${unifi_version_short}\""
    fi
  fi
}

# Try to get the release notes for the given UniFi SDN version
# $1: The full version number to check (i.e. "5.9.29")
# $2: The variable to assign the filename with the release notes
function __eubnt_get_unifi_release_notes() {
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    local version="${1}"
    local ubnt_update_api="https://fw-update.ubnt.com/api/firmware"
    local unifi_version_release_notes_url=$(wget --quiet --output-document - "${ubnt_update_api}?filter=eq~~product~~unifi-controller&filter=eq~~platform~~document&filter=eq~~version_major~~${version:0:1}&filter=eq~~version_minor~~${version:2:1}&filter=eq~~version_patch~~${version:4:2}" | grep --max-count=1 "changelog/unifi-controller" | sed 's|.*"href": "||' | sed 's|"||')
    local release_notes_file=$(mktemp)
    if wget --quiet --output-document - "${unifi_version_release_notes_url:-}" | sed '/#### Recommended Firmware:/,$d' 1>"${release_notes_file}"; then
      if [[ -e "${release_notes_file:-}" && -s "${release_notes_file:-}" ]]; then
        eval "${2}=\"${release_notes_file}\""
        return 0
      fi
    else
      return 1
    fi
  fi
}

# A wrapper to run commands, display a nice message and handle errors gracefully
# $1: The full command to run as a string
# $2: If set to "foreground" then the command will run in the foreground, if set to "quiet" the output will be directed to the log file, if set to "return" then output will be assigned to variable named in $3
# $3: Name of variable to assign output value of the command if $2 is set to "return"
###
# Make sure the command seems valid
# Run the command in the background and show a spinner (https://unix.stackexchange.com/a/225183)
# Run the command in the foreground when in verbose mode
# Wait for the command to finish and get the exit code (https://stackoverflow.com/a/1570356)
function __eubnt_run_command() {
  if [[ -n "${1:-}" ]]; then
    local background_pid=
    local command_output=
    local command_return=
    declare -a full_command=()
    IFS=' ' read -r -a full_command <<< "${1}"
    if [[ ! $(command -v "${full_command[0]}") ]]; then
      local found_package=
      local unknown_command="${full_command[0]}"
      __eubnt_install_package "apt-file"
      __eubnt_run_command "apt-file update"
      __eubnt_run_command "apt-file --package-only --regexp search .*bin\\/${unknown_command}$" "return" "found_package"
      if [[ -n "${found_package:-}" ]]; then
        __eubnt_install_package "${found_package}"
      else
        __eubnt_show_error "Unknown command ${unknown_command} at $(caller)"
        return 1
      fi
    fi
    if [[ "${full_command[0]}" != "echo" ]]; then
      __eubnt_add_to_log "${1}"
    fi
    if [[ ( -n "${__verbose_output:-}" && "${2:-}" != "quiet" ) || "${2:-}" = "foreground" || "${full_command[1]}" = "echo" || ( "${2:-}" != "return" && -n "${__is_experimental:-}" ) ]]; then
      if [[ -n "${__is_experimental:-}" ]]; then
        echo "${1}"
      fi
      "${full_command[@]}" | tee -a "${__script_log}"
      command_return=$?
    elif [[ "${2:-}" = "quiet" ]]; then
      "${full_command[@]}" &>>"${__script_log}" || __eubnt_show_warning "Unable to run ${1} at $(caller)\\n"
      command_return=$?
    elif [[ "${2:-}" = "return" ]]; then
      command_output=$(mktemp)
      if [[ -n "${__is_experimental:-}" ]]; then
        echo "${1}"
        "${full_command[@]}" &>>"${command_output}"
        command_return=$?
      else
        "${full_command[@]}" &>>"${command_output}" &
        background_pid=$!
      fi
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
      wait $background_pid
      command_return=$?
      if [[ ${command_return} -gt 0 ]]; then
        __eubnt_echo_and_log "\\rRunning ${1} [x]\\n"
      else
        __eubnt_echo_and_log "\\rRunning ${1} [\\xE2\\x9C\\x93]\\n"
      fi
    fi
    if [[ "${2:-}" = "return" && -n "${3:-}" && -e "${command_output:-}" && -s "${command_output:-}" && ${command_return} -eq 0 ]]; then
      # shellcheck disable=SC2086
      eval "${3}=$(cat ${command_output})"
      rm "${command_output}"
    fi
    if [[ ${command_return} -gt 0 ]]; then
      return 1
    else
      return 0
    fi
  fi
  __eubnt_show_warning "No command given at $(caller)\\n"
  return 1
}

# Add a source list to the system
# $1: The source information to use
# $2: The name of the source list file to make on the local machine
# $3: A search term to use when checking if the source list should be added
function __eubnt_add_source() {
  if [[ "${1:-}" && "${2:-}" && "${3:-}" ]]; then
    if [[ ! $(find /etc/apt -name "*.list" -exec grep "${3}" {} \;) ]]; then
      __eubnt_echo_and_log "deb ${1}" "${__apt_sources_dir}/${2}"
      return 0
    else
      __eubnt_add_to_log "Skipping add source for ${1}"
      return 1
    fi
  fi
}

# Add a package signing key to the system if needed
# $1: The 32-bit hex fingerprint of the key to add
function __eubnt_add_key() {
  if [[ "${1:-}" ]]; then
    if ! apt-key list 2>/dev/null | grep --quiet "${1:0:4}.*${1:4:4}"; then
      __eubnt_run_command "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key ${1}"
    fi
  fi
}

# Check if is package is installed
# $1: The name of the package to check
function __eubnt_is_package_installed() {
  if [[ -z "${1:-}" ]]; then
    return 1
  fi
  local package_name=$(echo "${1}" | sed 's/=.*//')
  if dpkg --list "${package_name}" 2>/dev/null | grep --quiet "^i"; then
    return 0
  else
    return 1
  fi
}

# Install package if needed and handle errors gracefully
# $1: The name of the package to install
# $2: An optional target release to use
# $3: If set to "return" then return a status
function __eubnt_install_package() {
  if [[ "${1:-}" ]]; then
    local target_release
    if ! apt-get install --simulate "${1}" &>/dev/null; then
      __eubnt_setup_sources "os"
      __eubnt_run_command "apt-get update"
      __eubnt_run_command "apt-get install --fix-broken --yes"
      __eubnt_run_command "apt-get autoremove --yes"
    fi
    if apt-get install --simulate "${1}" &>/dev/null; then
      if ! __eubnt_is_package_installed "${1}"; then
        local i=0
        while lsof /var/lib/dpkg/lock &>/dev/null; do
          echo -e -n "\\rWaiting for package manager to become available... [${__spinner:i++%${#__spinner}:1}]"
          sleep 0.5
        done
        __eubnt_echo_and_log "\\rWaiting for package manager to become available... [\\xE2\\x9C\\x93]\\n"
        export DEBIAN_FRONTEND=noninteractive
        if [[ -n "${2:-}" ]]; then
          __eubnt_run_command "apt-get install --quiet --no-install-recommends --yes --target-release ${2} ${1}" "${3:-}"
        else
          __eubnt_run_command "apt-get install --quiet --no-install-recommends --yes ${1}" "${3:-}"
        fi
      else
        __eubnt_echo_and_log "Package ${1} already installed [\\xE2\\x9C\\x93]\\n"
        if [[ "${3:-}" = "return" ]]; then
          return 0
        fi
      fi
    else
      __eubnt_show_error "Unable to install package ${1} at $(caller)"
      if [[ "${3:-}" = "return" ]]; then
        return 1
      fi
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
# $1: If set to "os" then only setup core repos for the OS
###
# Ubuntu: Setup alternative source lists to get certain packages
# Debian: Make sure the dirmngr package is installed so keys can be validated
# Certbot: Debian distribution sources include it, add sources for Ubuntu except Precise
# Java: Use WebUpd8 repository for Precise and Trust era OSes (https://gist.github.com/pyk/19a619b0763d6de06786 | https://askubuntu.com/a/190674)
# Java: Use the core distribution sources to get Java for all others
# Mongo: Official repository only distributes 64-bit packages, not compatible with Wheezy
# Mongo: UniFi will install it from distribution sources if needed
# UniFi: Add UBNT package signing key here, add source list later depending on the chosen version
# shellcheck disable=SC2120
function __eubnt_setup_sources() {
  local do_apt_update=
  if [[ -n "${__is_ubuntu:-}" ]]; then
    __eubnt_add_source "http://archive.ubuntu.com/ubuntu ${__os_version_name} main universe" "${__os_version_name}-archive.list" "archive\\.ubuntu\\.com.*${__os_version_name}.*main" && do_apt_update=true
    __eubnt_add_source "http://security.ubuntu.com/ubuntu ${__os_version_name}-security main universe" "${__os_version_name}-security.list" "security\\.ubuntu\\.com.*${__os_version_name}-security main" && do_apt_update=true
    __eubnt_add_source "http://mirrors.kernel.org/ubuntu ${__os_version_name} main universe" "${__os_version_name}-mirror.list" "mirrors\\.kernel\\.org.*${__os_version_name}.*main" && do_apt_update=true
  elif [[ -n "${__is_debian:-}" ]]; then 
    __eubnt_install_package "dirmngr"
    __eubnt_add_source "http://ftp.debian.org/debian ${__os_version_name}-backports main" "${__os_version_name}-backports.list" "ftp\\.debian\\.org.*${__os_version_name}-backports.*main" && do_apt_update=true
  fi
  if [[ "${1:-}" != "os" ]]; then
    if [[ -n "${__setup_source_java:-}" ]]; then
      if [[ "${__os_version_name_ubuntu_equivalent:-}" = "precise" || "${__os_version_name:-}" = "trusty" ]]; then
        __install_webupd8_java=true
        echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
        __eubnt_add_source "http://ppa.launchpad.net/webupd8team/java/ubuntu ${__os_version_name_ubuntu_equivalent} main" "webupd8team-java.list" "ppa\\.launchpad\\.net.*${__os_version_name_ubuntu_equivalent}.*main" && do_apt_update=true
        __eubnt_add_key "EEA14886" # WebUpd8 package signing key
      else
        __install_java=true
      fi
    fi
    if [[ -n "${__setup_source_mongo:-}" ]]; then
      local mongo_repo_distro=
      local mongo_repo_url=
      if [[ -n "${__is_64:-}" && -n "${__is_ubuntu:-}" ]]; then
        if [[ "${__os_version_name}" = "precise" ]]; then
          mongo_repo_distro="trusty"
        elif [[ "${__os_version_name}" = "bionic" ]]; then
          mongo_repo_distro="xenial"
        else
          mongo_repo_distro="${__os_version_name}"
        fi
        mongo_repo_url="http://repo.mongodb.org/apt/ubuntu ${mongo_repo_distro}/mongodb-org/3.4 multiverse"
      elif [[ -n "${__is_64:-}" && -n "${__is_debian:-}" ]]; then
        if [[ "${__os_version_name:-}" != "wheezy" ]]; then
          mongo_repo_url="http://repo.mongodb.org/apt/debian jessie/mongodb-org/3.4 main"
          __eubnt_add_source "http://ftp.debian.org/debian jessie-backports main" "jessie-backports.list" "ftp\\.debian\\.org.*jessie-backports.*main" && do_apt_update=true
        fi
      fi
      if [[ -n "${mongo_repo_url:-}" ]]; then
        if __eubnt_add_source "${mongo_repo_url}" "mongodb-org-3.4.list" "repo\\.mongodb\\.org.*3\\.4"; then
          do_apt_update=true
        fi
        __eubnt_add_key "A15703C6" # Mongo package signing key
        __install_mongo=true
      fi
    fi
    __eubnt_add_key "C0A52C50" # UBNT package signing key
    if [[ -n "${__setup_certbot:-}" ]]; then
      if [[ -n "${__is_ubuntu:-}" && "${__os_version_name:-}" != "precise" ]]; then
        __eubnt_add_source "http://ppa.launchpad.net/certbot/certbot/ubuntu ${__os_version_name} main" "certbot-ubuntu-certbot-${__os_version_name}.list" "ppa\\.laundpad\\.net.*${__os_version_name}.*main" && do_apt_update=true
        __eubnt_add_key "75BCA694" # Certbot package signing key
      fi
    fi
  fi
  if [[ -n "${do_apt_update:-}" ]]; then
    __eubnt_run_command "apt-get update"
  fi
}

# Collection of different fixes to do pre/post apt install/upgrade
###
# Try to fix broken installs
# Remove un-needed packages
# Remove cached source list information
# Fix for kernel files filling /boot in Ubuntu (https://askubuntu.com/a/90219)
# Update apt-get and apt-file
function __eubnt_install_fixes {
  __eubnt_show_header "Running common pre-install fixes...\\n"
  __eubnt_run_command "apt-get install --fix-broken --yes"
  __eubnt_run_command "apt-get autoremove --yes"
  __eubnt_run_command "apt-get clean --yes"
  __eubnt_run_command "rm -rf /var/lib/apt/lists/*"
  if [[ -n "${__is_ubuntu:-}" && -d /boot ]]; then
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
  __eubnt_run_command "apt-get update"
  __eubnt_run_command "apt-file update"
}

# Install basic system utilities and dependencies needed for successful script run
function __eubnt_install_updates_utils() {
  __eubnt_show_header "Installing utilities and updates...\\n"
  __eubnt_install_package "software-properties-common"
  __eubnt_install_package "unattended-upgrades"
  __eubnt_install_package "sudo"
  __eubnt_install_package "curl"
  __eubnt_install_package "net-tools"
  __eubnt_install_package "dnsutils"
  __eubnt_install_package "psmisc"
  __eubnt_install_package "binutils"
  if [[ -n "${__hold_java:-}" ]]; then
    __eubnt_run_command "apt-mark hold ${__hold_java}"
  fi
  if [[ -n "${__hold_mongo:-}" ]]; then
    __eubnt_run_command "apt-mark hold ${__hold_mongo}"
  fi
  if [[ -n "${__hold_unifi:-}" ]]; then
    __eubnt_run_command "apt-mark hold ${__hold_unifi}"
  fi
  echo
  if __eubnt_question_prompt "Do you want to upgrade all currently installed packages?" "return"; then
    __eubnt_run_command "apt-get dist-upgrade --yes"
  fi
  if [[ -n "${__hold_java:-}" ]]; then
    __eubnt_run_command "apt-mark unhold ${__hold_java}"
  fi
  if [[ -n "${__hold_mongo:-}" ]]; then
    __eubnt_run_command "apt-mark unhold ${__hold_mongo}"
  fi
  if [[ -n "${__hold_unifi:-}" ]]; then
    __eubnt_run_command "apt-mark unhold ${__hold_unifi}"
  fi
  __run_autoremove=true
}

# Use haveged for better entropy generation from @ssawyer (https://community.ubnt.com/t5/UniFi-Wireless/UniFi-Controller-Linux-Install-Issues/m-p/1324455/highlight/true#M116452)
# Virtual memory tweaks from @adrianmmiller
function __eubnt_system_tweaks() {
  __eubnt_show_header "Tweaking system for performance and security...\\n"
  if ! __eubnt_is_package_installed "haveged"; then
    if __eubnt_question_prompt "Do you want to install a better entropy generator?" "return"; then
      __eubnt_install_package "haveged"
    fi
  fi
  echo
  if [[ $(cat /proc/sys/vm/swappiness) -ne 10 || $(cat /proc/sys/vm/vfs_cache_pressure) -ne 50 ]]; then
    if __eubnt_question_prompt "Do you want adjust the system to prefer RAM over virtual memory?" "return"; then
      __eubnt_run_command "sysctl vm.swappiness=10"
      __eubnt_run_command "sysctl vm.vfs_cache_pressure=50"
    fi
  fi
}

# Install OpenJDK Java 8 if available from distribution sources
# Install WebUpd8 Java if OpenJDK is not available from the distribution
function __eubnt_install_java() {
  if [[ -n "${__install_webupd8_java:-}" || -n "${__install_java:-}" ]]; then
    __eubnt_show_header "Installing Java...\\n"
    if [[ -n "${__install_webupd8_java:-}" ]]; then
      __eubnt_install_package "oracle-java8-installer"
      __eubnt_install_package "oracle-java8-set-default"
    else
      local target_release=
      if [[ "${__os_version_name:-}" = "jessie" ]]; then
        target_release="${__os_version_name}-backports"
      fi
      __eubnt_install_package "ca-certificates-java" "${target_release:-}"
      __eubnt_install_package "openjdk-8-jre-headless" "${target_release:-}"
    fi
    __eubnt_install_package "jsvc"
    __eubnt_install_package "libcommons-daemon-java"
  fi
}

# Purge MongoDB if desired and UniFi SDN is not installed
function __eubnt_purge_mongo() {
  if [[ -n "${__purge_mongo:-}" && -z "${__is_unifi_installed:-}" ]]; then
    __eubnt_show_header "Purging MongoDB...\\n"
    apt-get purge --yes "mongodb*"
    rm "${__apt_sources_dir}/mongodb"*
    __eubnt_run_command "apt-get update"
  fi
}

# Install MongoDB 3.4 from the official MongoDB repo
# Only available for 64-bit
function __eubnt_install_mongo()
{
  if [[ -n "${__is_64:-}" && -n "${__install_mongo:-}" ]]; then
    __eubnt_show_header "Installing MongoDB...\\n"
    __eubnt_install_package "mongodb-org=3.4.*"
  fi
}

# Show install/reinstall/update options for UniFi SDN
function __eubnt_install_unifi()
{
  __eubnt_show_header "Installing UniFi SDN Controller...\\n"
  local selected_unifi_version=
  local latest_unifi_version=
  declare -a unifi_supported_versions=(5.6 5.8 5.9)
  declare -a unifi_historical_versions=(5.4 5.5 5.6 5.8 5.9)
  declare -a unifi_versions_to_install=()
  declare -a unifi_versions_to_select=()
  if [[ -n "${__unifi_version_installed:-}" ]]; then
    __eubnt_show_notice "Version ${__unifi_version_installed} is currently installed\\n"
  fi
  if [[ -n "${__quick_mode:-}" ]]; then
    if [[ -n "${__unifi_version_installed:-}" ]]; then
      selected_unifi_version="${__unifi_version_installed:0:3}"
    else
      selected_unifi_version="${__unifi_version_stable}"
    fi
  else
    for version in "${!unifi_supported_versions[@]}"; do
      if [[ -n "${__unifi_version_installed:-}" ]]; then
        if [[ "${unifi_supported_versions[$version]:0:3}" = "${__unifi_version_installed:0:3}" ]]; then
          if [[ -n "${__unifi_update_available:-}" ]]; then
            unifi_versions_to_select+=("${__unifi_update_available}")
          else
            unifi_versions_to_select+=("${__unifi_version_installed}")
          fi
        elif [[ "${unifi_supported_versions[$version]:2:1}" -gt "${__unifi_version_installed:2:1}" ]]; then
          __eubnt_get_latest_unifi_version "${unifi_supported_versions[$version]}" "latest_unifi_version"
          unifi_versions_to_select+=("${latest_unifi_version}")
        fi
      else
        __eubnt_get_latest_unifi_version "${unifi_supported_versions[$version]}" "latest_unifi_version"
        unifi_versions_to_select+=("${latest_unifi_version}")
      fi
    done
    unifi_versions_to_select+=("Skip")
    __eubnt_show_notice "Which controller do you want to (re)install or upgrade to?\\n"
    select version in "${unifi_versions_to_select[@]}"; do
      case "${version}" in
        "")
          selected_unifi_version="${__unifi_version_stable}"
          break;;
        *)
          if [[ "${version}" = "Skip" ]]; then
            return 0
          fi
          selected_unifi_version="${version:0:3}"
          break;;
      esac
    done
  fi
  if [[ -n "${__unifi_version_installed:-}" ]]; then
    for step in "${!unifi_historical_versions[@]}"; do
      __eubnt_get_latest_unifi_version "${unifi_historical_versions[$step]}" "latest_unifi_version"
      if [[ (("${unifi_historical_versions[$step]:2:1}" -eq "${__unifi_version_installed:2:1}" && "${latest_unifi_version}" != "${__unifi_version_installed}") || "${unifi_historical_versions[$step]:2:1}" -gt "${__unifi_version_installed:2:1}") && "${unifi_historical_versions[$step]:2:1}" -le "${selected_unifi_version:2:1}" ]]; then
        unifi_versions_to_install+=("${unifi_historical_versions[$step]}")
     fi
    done
    if [[ "${#unifi_versions_to_install[@]}" -eq 0 ]]; then
      unifi_versions_to_install=("${__unifi_version_installed:0:3}")
    fi
  else
    unifi_versions_to_install=("${selected_unifi_version}")
  fi
  for version in "${!unifi_versions_to_install[@]}"; do
    __eubnt_install_unifi_version "${unifi_versions_to_install[$version]}"
  done
  __eubnt_run_command "service unifi start"
}

# Installs the latest minor version for the given major UniFi SDN version
# $1: The major version number to install
# TODO: Try to recover if install fails
function __eubnt_install_unifi_version()
{
  if [[ "${1:-}" ]]; then
    unifi_install_this_version="${1}"
  else
    __eubnt_show_error "No UniFi SDN version specified to install"
  fi
  if __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${unifi_install_this_version} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${unifi_install_this_version}"; then
    __eubnt_run_command "apt-get update" "quiet"
  fi
  unifi_updated_version=$(apt-cache policy unifi | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
  if [[ "${__unifi_version_installed}" = "${unifi_updated_version}" ]]; then
    __eubnt_show_notice "\\nUniFi SDN version ${__unifi_version_installed} is already installed\\n"
    if __eubnt_question_prompt "Do you want to reinstall?" "return" "n"; then
      echo "unifi unifi/has_backup boolean true" | debconf-set-selections
      DEBIAN_FRONTEND=noninteractive apt-get install --reinstall --yes unifi
    fi
    return 0
  fi
  __eubnt_show_header "Installing UniFi SDN version ${unifi_updated_version}...\\n"
  if [[ -n "${__unifi_version_installed:-}" ]]; then
    __eubnt_show_warning "Make sure you have a backup!\\n"
  fi
  local release_notes=
  if __eubnt_get_unifi_release_notes "${unifi_updated_version}" "release_notes"; then
    if __eubnt_question_prompt "Do you want to view the release notes?" "return" "n"; then
      more "${release_notes}"
    fi
  fi
  if __eubnt_question_prompt "" "return"; then
    __eubnt_run_command "service unifi restart"
    echo "unifi unifi/has_backup boolean true" | debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt-get install --yes unifi
    __unifi_version_installed="${unifi_updated_version}"
    tail --follow /var/log/unifi/server.log --lines=50 | while read -r log_line
    do
      if [[ "${log_line}" = *"${unifi_updated_version}"* ]]
      then
        __eubnt_show_success "\\n${log_line}\\n"
        pkill --full tail
      fi
    done
    sleep 1
  else
    if __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${__unifi_version_installed:0:3}"; then
      __eubnt_run_command "apt-get update" "quiet"
    fi
  fi
}

# Based on solution by @Frankedinven (https://community.ubnt.com/t5/UniFi-Wireless/Lets-Encrypt-on-Hosted-Controller/m-p/2463220/highlight/true#M318272)
function __eubnt_setup_certbot() {
  if [[ "${__os_version_name}" = "precise" || "${__os_version_name}" = "wheezy" ]]; then
    return 0
  fi
  local source_backports=
  local skip_certbot_questions=
  local domain_name=
  local email_address=
  local resolved_domain_name=
  local email_option=
  local days_to_renewal=
  __eubnt_show_header "Setting up Let's Encrypt...\\n"
  if __eubnt_question_prompt "Do you want to (re)setup Let's Encrypt?" "return" "n"; then
    if [[ "${__os_version_name}" = "jessie" ]]; then
      __eubnt_run_command "apt-get install --yes --target-release jessie-backports certbot"
    else
      __eubnt_install_package "certbot"
    fi
  else
    return 0
  fi
  domain_name=
  if __eubnt_run_command "hostname --fqdn" "return" "domain_name"; then
    echo
    if ! __eubnt_question_prompt "Do you want to use ${domain_name}?" "return" "y"; then
      __eubnt_get_user_input "\\nDomain name to use for the UniFi SDN Controller: " "domain_name"
    fi
  else
    __eubnt_get_user_input "\\nDomain name to use for the UniFi SDN Controller: " "domain_name"
  fi
  resolved_domain_name=$(dig +short "${domain_name}")
  if [[ "${__machine_ip_address}" != "${resolved_domain_name}" ]]; then
    echo; __eubnt_show_warning "The domain ${domain_name} does not resolve to ${__machine_ip_address}\\n"
    if ! __eubnt_question_prompt "" "return"; then
      return 0
    fi
  fi
  days_to_renewal=0
  if certbot certificates --domain "${domain_name:-}" | grep --quiet "Domains: "; then
    __eubnt_run_command "certbot certificates --domain ${domain_name}" "foreground"
    __eubnt_show_notice "\\nLet's Encrypt has been setup previously\\n"
    days_to_renewal=$(certbot certificates --domain "${domain_name}" | grep --only-matching --max-count=1 "VALID: .*" | awk '{print $2}')
    skip_certbot_questions=true
  fi
  if [[ -z "${skip_certbot_questions:-}" ]]; then
    __eubnt_get_user_input "\\nEmail address for renewal notifications (optional): " "email_address" "optional"
  fi
  echo
  __eubnt_show_warning "Let's Encrypt will verify your domain using HTTP (TCP port 80). This\\nscript will automatically allow HTTP through the firewall on this machine only.\\nPlease make sure firewalls external to this machine are set to allow HTTP.\\n"
  if __eubnt_question_prompt "Do you want to check if inbound HTTP is open to the Internet?" "return"; then
    local enable_ufw=
    if [[ $(dpkg --status "ufw" 2>/dev/null | grep "ok installed") && $(ufw status | grep " active") ]]; then
      __eubnt_run_command "ufw disable"
      enable_ufw=true
    fi
    __eubnt_show_text "Checking if port probing service is available"
    local port_probe_url=$(wget --quiet --output-document - "https://www.grc.com/x/portprobe=80" | grep --quiet "World Wide Web HTTP" && echo "https://www.grc.com/x/portprobe=")
    if [[ -n "${port_probe_url:-}" ]]; then
      local port_to_probe="80"
      __eubnt_show_text "Checking port ${port_to_probe}"
      if ! wget -q -O- "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
        echo
        __eubnt_show_warning "It doesn't look like port ${port_to_probe} is open! Check your upstream firewall.\\n"
        if __eubnt_question_prompt "Do you want to check port ${port_to_probe} again?" "return"; then
          if ! wget -q -O- "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
            echo
            __eubnt_show_warning "Port ${port_to_probe} is still not open!\\n"
            if ! __eubnt_question_prompt "Do you want to proceed anyway?" "return"; then
              return 1
            fi
          else
            __eubnt_show_success "\\nPort ${port_to_probe} is now open!\\n"
          fi
        fi
      else
        __eubnt_show_success "\\nPort ${port_to_probe} is open!\\n"
      fi
    else
      __eubnt_show_notice "\\nPort probing service is unavailable, try again later."
    fi
    if [[ -n "${enable_ufw:-}" ]]; then
      __eubnt_run_command "ufw --force enable"
    fi
  fi
  if [[ -n "${email_address:-}" ]]; then
    email_option="--email ${email_address}"
  else
    email_option="--register-unsafely-without-email"
  fi
  if [[ -n "${domain_name:-}" ]]; then
    local letsencrypt_scripts_dir=$(mkdir --parents "${__eubnt_dir}/letsencrypt" && echo "${__eubnt_dir}/letsencrypt")
    local pre_hook_script="${letsencrypt_scripts_dir}/pre-hook_${domain_name}.sh"
    local post_hook_script="${letsencrypt_scripts_dir}/post-hook_${domain_name}.sh"
    local letsencrypt_live_dir="${__letsencrypt_dir}/live/${domain_name}"
    local letsencrypt_renewal_dir="${__letsencrypt_dir}/renewal"
    local letsencrypt_renewal_conf="${letsencrypt_renewal_dir}/${domain_name}.conf"
    local letsencrypt_privkey="${letsencrypt_live_dir}/privkey.pem"
    local letsencrypt_fullchain="${letsencrypt_live_dir}/fullchain.pem"
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
    cp ${__unifi_data_dir}/keystore ${__unifi_data_dir}/keystore.backup.\$(date +%s) &>/dev/null
    openssl pkcs12 -export -inkey ${letsencrypt_privkey} -in ${letsencrypt_fullchain} -out ${letsencrypt_live_dir}/fullchain.p12 -name unifi -password pass:aircontrolenterprise &>/dev/null
    keytool -delete -alias unifi -keystore ${__unifi_data_dir}/keystore -deststorepass aircontrolenterprise &>/dev/null
    keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${__unifi_data_dir}/keystore -srckeystore ${letsencrypt_live_dir}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt &>/dev/null
    echo "unifi.https.ciphers=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_EMPTY_RENEGOTIATION_INFO_SCSVF" | tee -a "${__unifi_system_properties}"
    echo "unifi.https.sslEnabledProtocols=+TLSv1.1,+TLSv1.2,+SSLv2Hello" | tee -a "${__unifi_system_properties}"
    service unifi restart &>/dev/null
  fi
fi
EOF
# End of output to file
    chmod +x "${post_hook_script}"
    local force_renewal="--keep-until-expiring"
    local run_mode="--keep-until-expiring"
    if [[ "${days_to_renewal}" -ge 30 ]]; then
      if __eubnt_question_prompt "\\nDo you want to force certificate renewal?" "return" "n"; then
        force_renewal="--force-renewal"
      fi
    fi
    if [[ -n "${__script_debug:-}" ]]; then
      run_mode="--dry-run"
    else
      if __eubnt_question_prompt "\\nDo you want to do a dry run?" "return" "n"; then
        run_mode="--dry-run"
      fi
    fi
    # shellcheck disable=SC2086
    if certbot certonly --standalone --agree-tos --pre-hook ${pre_hook_script} --post-hook ${post_hook_script} --domain ${domain_name} ${email_option} ${force_renewal} ${run_mode}; then
      __eubnt_show_success "\\nCertbot succeeded for domain name: ${domain_name}"
      __unifi_domain_name="${domain_name}"
      sleep 5
    else
      echo
      __eubnt_show_warning "Certbot failed for domain name: ${domain_name}"
      sleep 10
    fi
    if [[ -f "${letsencrypt_renewal_conf}" ]]; then
      sed -i "s|^pre_hook.*$|pre_hook = ${pre_hook_script}|" "${letsencrypt_renewal_conf}"
      sed -i "s|^post_hook.*$|post_hook = ${post_hook_script}|" "${letsencrypt_renewal_conf}"
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
# De-duplicate SSH config file (https://stackoverflow.com/a/1444448)
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
      if [[ "${recommended_setting}" = "PermitRootLogin no" && -z "${__is_user_sudo:-}" ]]; then
        continue
      fi
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
    awk '!seen[$0]++' "${__sshd_config}" &>/dev/null
  fi
}

# Install and setup UFW
# Adds an app profile that includes all UniFi SDN ports to allow for easy rule management in UFW
# Checks if ports appear to be open/accessible from the Internet
function __eubnt_setup_ufw() {
  __eubnt_show_header "Setting up UFW (Uncomplicated Firewall)...\\n"
  unifi_local_udp_port_discoverable_controller="1900"
  unifi_local_udp_port_ap_discovery="10001"
  if [[ -f "${__unifi_system_properties}" ]]; then
    local unifi_tcp_port_inform=$(grep "^unifi.http.port" "${__unifi_system_properties}" | sed 's/.*=//g')
    if [[ -z "${unifi_tcp_port_inform:-}" ]]; then
      unifi_tcp_port_inform="8080"
    fi
    local unifi_tcp_port_admin=$(grep "^unifi.https.port" "${__unifi_system_properties}" | sed 's/.*=//g')
    if [[ -z "${unifi_tcp_port_admin:-}" ]]; then
      unifi_tcp_port_admin="8443"
    fi
    local unifi_tcp_port_http_portal=$(grep "^portal.http.port" "${__unifi_system_properties}" | sed 's/.*=//g')
    if [[ -z "${unifi_tcp_port_http_portal:-}" ]]; then
      unifi_tcp_port_http_portal="8880"
    fi
    local unifi_tcp_port_https_portal=$(grep "^portal.https.port" "${__unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_tcp_port_https_portal ]]; then
      unifi_tcp_port_https_portal="8843"
    fi
    unifi_tcp_port_throughput=$(grep "^unifi.throughput.port" "${__unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_tcp_port_throughput ]]; then
      unifi_tcp_port_throughput="6789"
    fi
    unifi_udp_port_stun=$(grep "^unifi.stun.port" "${__unifi_system_properties}" | sed 's/.*=//g')
    if [[ ! $unifi_udp_port_stun ]]; then
      unifi_udp_port_stun="3478"
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
  if [[ -n "${unifi_tcp_port_inform:-}" && -n "${unifi_tcp_port_admin:-}" && -n "${unifi_tcp_port_http_portal:-}" && -n "${unifi_tcp_port_https_portal:-}" && -n "${unifi_tcp_port_throughput:-}" && -n "${unifi_udp_port_stun:-}" ]]; then
    tee "/etc/ufw/applications.d/unifi" &>/dev/null <<EOF
[unifi]
title=UniFi SDN Ports
description=Default ports used by the UniFi SDN Controller
ports=${unifi_tcp_port_inform},${unifi_tcp_port_admin},${unifi_tcp_port_http_portal},${unifi_tcp_port_https_portal},${unifi_tcp_port_throughput}/tcp|${unifi_udp_port_stun}/udp

[unifi-local]
title=UniFi SDN Ports for Local Discovery
description=Ports used for discovery of devices on the local network by the UniFi SDN Controller
ports=${unifi_local_udp_port_discoverable_controller},${unifi_local_udp_port_ap_discovery}/udp
EOF
# End of output to file
  fi
  __eubnt_show_notice "\\nCurrent UFW status:\\n"
  __eubnt_run_command "ufw status" "foreground"
  echo
  if __eubnt_question_prompt "Do you want to reset your current UFW rules?" "return" "n"; then
    __eubnt_run_command "ufw --force reset"
    echo
  fi
  if __eubnt_question_prompt "Do you want to check if inbound UniFi SDN ports appear to be open?" "return"; then
    if ufw status | grep --quiet " active"; then
      __eubnt_run_command "ufw disable"
    fi
    __eubnt_show_text "Checking if port probing service is available"
    local port_probe_url=$(wget --quiet --output-document - "https://www.grc.com/x/portprobe=80" | grep --quiet "World Wide Web HTTP" && echo "https://www.grc.com/x/portprobe=")
    if [[ -n "${port_probe_url:-}" ]]; then
      if [[ -n "${ssh_port:-}" ]]; then
        local unifi_tcp_port_ssh="${ssh_port}"
      fi
      local port_to_probe=
      for var_name in ${!unifi_tcp_port_*}; do
        port_to_probe="${!var_name}"
        __eubnt_show_text "Checking port ${port_to_probe}"
        if ! wget -q -O- "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
          echo
          __eubnt_show_warning "It doesn't look like port ${port_to_probe} is open! Check your upstream firewall.\\n"
          if __eubnt_question_prompt "Do you want to check port ${port_to_probe} again?" "return"; then
            if ! wget -q -O- "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
              echo
              __eubnt_show_warning "Port ${port_to_probe} is still not open!\\n"
              if ! __eubnt_question_prompt "Do you want to proceed anyway?" "return"; then
                return 1
              fi
            else
              __eubnt_show_success "\\nPort ${port_to_probe} is open!\\n"
            fi
          fi
        else
          __eubnt_show_success "\\nPort ${port_to_probe} is open!\\n"
        fi
      done
    else
      __eubnt_show_notice "\\nPort probing service is unavailable, try again later."
    fi
  fi
  if [[ -n "${ssh_port:-}" ]]; then
    if __eubnt_question_prompt "Do you want to allow access to SSH from any host?" "return"; then
      __eubnt_run_command "ufw allow ${ssh_port}/tcp"
    else
      __eubnt_run_command "ufw --force delete allow ${ssh_port}/tcp" "quiet"
    fi
    echo
  fi
  if [[ "${unifi_tcp_port_inform:-}" && "${unifi_tcp_port_admin:-}" ]]; then
    __unifi_tcp_port_admin="${unifi_tcp_port_admin}"
    if __eubnt_question_prompt "Do you want to allow access to the UniFi SDN ports from any host?" "return"; then
      __eubnt_run_command "ufw allow from any to any app unifi"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app unifi" "quiet"
    fi
    echo
    if __eubnt_question_prompt "Will this controller discover devices on it's local network?" "return" "n"; then
      __eubnt_run_command "ufw allow from any to any app unifi-local"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app unifi-local" "quiet"
    fi
    echo
  else
    __eubnt_show_warning "Unable to determine UniFi SDN ports to allow. Is it installed?\\n"
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

# Perform various system checks, display system information and warnings about potential issues
# Check for currently installed versions of Java, MongoDB and UniFi SDN
function __eubnt_check_system() {
  local os_version_name_display=
  local os_version_supported=
  local os_version_recommended_display=
  local os_version_recommended=
  local os_bit=
  local have_space_for_swap=
  declare -a ubuntu_supported_versions=("precise" "trusty" "xenial" "bionic")
  declare -a debian_supported_versions=("wheezy" "jessie" "stretch")
  __eubnt_show_header "Checking system...\\n"
  if [[ "${__architecture}" = "i686" ]]; then
    __is_32=true
    os_bit="32-bit"
  elif [[ "${__architecture}" = "x86_64" ]]; then
    __is_64=true
    os_bit="64-bit"
  else
    __eubnt_show_warning "Architecture ${__architecture} is not officially supported\\n"
    __eubnt_question_prompt
    __is_experimental=true
    if [[ "${__architecture:0:3}" = "arm" ]]; then
      if [[ "${__architecture:4:1}" -ge 8 ]]; then
        __is_64=true
        os_bit="64-bit"
      else
        __is_32=true
        os_bit="32-bit"
      fi
    else
      os_bit="Unknown"
    fi
  fi
  if [[ "${__os_name:-}" = "Ubuntu" ]]; then
    __is_ubuntu=true
    os_version_recommended_display="16.04 Xenial"
    os_version_recommended="xenial"
    for version in "${!ubuntu_supported_versions[@]}"; do
      if [[ "${ubuntu_supported_versions[$version]}" = "${__os_version_name}" ]]; then
        __os_version_name_ubuntu_equivalent="${__os_version_name}"
        os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
        os_version_supported=true
        break
      fi
    done
  elif [[ "${__os_name:-}" = "Debian" || "${__os_name:-}" = "Raspbian" ]]; then
    __is_debian=true
    os_version_recommended_display="9.x Stretch"
    os_version_recommended="stretch"
    for version in "${!debian_supported_versions[@]}"; do
      if [[ "${debian_supported_versions[$version]}" = "${__os_version_name}" ]]; then
        __os_version_name_ubuntu_equivalent="${ubuntu_supported_versions[$version]}"
        os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
        os_version_supported=true
        break
      fi
    done
  else
    __eubnt_show_error "This script is for Ubuntu, Debian or Raspbian\\nYou appear to have: ${__os_all_info}\\n"
  fi
  if [[ -z "${os_version_supported:-}" ]]; then
    __eubnt_show_warning "${__os_name} ${__os_version} is not officially supported\\n"
    __eubnt_question_prompt
    __is_experimental=true
    os_version_name_display=$(echo "${__os_version_name}" | sed 's/./\u&/')
    if [[ -n "${__is_debian:-}" ]]; then
      __os_version_name="stretch"
      __os_version_name_ubuntu_equivalent="xenial"
    else
      __os_version_name="bionic"
      __os_version_name_ubuntu_equivalent="bionic"
    fi
  fi
  if [[ -z "${__os_version:-}" || ( -z "${__is_ubuntu:-}" && -z "${__is_debian:-}" ) ]]; then
    __eubnt_show_error "Unable to detect system information\\n"
  fi
  local show_disk_free_space=
  if [[ "${__disk_free_space%G*}" -le 2 ]]; then
    show_disk_free_space="${__disk_free_space_mb}"
  else
    show_disk_free_space="${__disk_free_space}"
  fi
  __eubnt_show_text "Disk free space is ${__colors_bold_text}${show_disk_free_space}${__colors_default}\\n"
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
  if [[ ( -n "${__is_ubuntu:-}" || -n "${__is_debian:-}" ) && ( "${__os_version_name:-}" != "${os_version_recommended:-}" || "${os_bit:-}" != "${__os_bit_recommended}" ) ]]; then
    __eubnt_show_warning "UBNT recommends ${__os_name} ${os_version_recommended_display} ${__os_bit_recommended}\\n"
  fi
  declare -a all_ip_addresses=()
  local apparent_public_ip_address=$(wget --quiet --output-document - http://dynamicdns.park-your-domain.com/getip)
  #shellcheck disable=SC2207
  all_ip_addresses=($(hostname --all-ip-addresses | xargs))
  all_ip_addresses+=("${apparent_public_ip_address}")
  #shellcheck disable=SC2207
  all_ip_addresses=($(printf "%s\\n" "${all_ip_addresses[@]}" | sort --unique))
  if [[ "${#all_ip_addresses[@]}" -gt 1 ]]; then
    __eubnt_show_notice "Which IP address will the controller be using?\\n"
    select ip_address in "${all_ip_addresses[@]}"; do
      case "${ip_address}" in
        *)
          __machine_ip_address="${ip_address}"
          echo
          break;;
      esac
    done
  else
    __machine_ip_address="${all_ip_addresses[0]}"
  fi
  __eubnt_show_text "Machine IP address to use is ${__colors_bold_text}${__machine_ip_address}${__colors_default}\\n"
  local configured_fqdn=
  if __eubnt_run_command "hostname --fqdn" "return" "configured_fqdn"; then
    __eubnt_show_text "\\nConfigured hostname is ${__colors_bold_text}${configured_fqdn}${__colors_default}\\n"
  else
    __eubnt_show_text "\\nNo configured hostname (FQDN) found\\n"
  fi
  if [[ -z "${__nameservers:-}" ]]; then
    __eubnt_show_warning "No nameservers found!\\n"
  else
    if [[ $(echo "${__nameservers}" | awk '{print $2}') ]]; then
      __eubnt_show_text "Current nameservers in use are ${__colors_bold_text}${__nameservers}${__colors_default}\\n"
    else
      __eubnt_show_text "Current nameserver in use is ${__colors_bold_text}${__nameservers}${__colors_default}\\n"
    fi
  fi
  if ! __eubnt_run_command "dig +short ${__ubnt_dns}" "return"; then
    echo
    if __eubnt_question_prompt "Unable to resolve ${__ubnt_dns}, do you want to use ${__recommended_nameserver} as your nameserver?" "return"; then
      if __eubnt_install_package "resolvconf" "return"; then
        echo "nameserver ${__recommended_nameserver}" | tee "/etc/resolvconf/resolv.conf.d/head"
        __eubnt_run_command "resolvconf -u"
        __nameservers=$(awk '/nameserver/{print $2}' /etc/resolv.conf | xargs)
        if ! __eubnt_run_command "dig +short ${__ubnt_dns}" "return"; then
          echo
          if ! __eubnt_question_prompt "${__colors_warning_text}Still unable to resolve ${__ubnt_dns}, do you want to continue anyway?" "return" "n"; then
            echo
            __eubnt_show_error "Unable to resolve ${__ubnt_dns} using ${__nameservers}, is DNS blocked?"
            return 1
          fi
        fi
      fi
    fi
  else
    __eubnt_show_success "\\nDNS appears to be working!\\n"
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
  __eubnt_run_command "apt-get update"
  echo
  if [[ $(command -v java) ]]; then
    local java_version_installed=""
    local java_package_installed=""
    local set_java_alternative=""
    if __eubnt_is_package_installed "oracle-java8-installer"; then
      java_package_installed="oracle-java8-installer"
    fi
    if __eubnt_is_package_installed "openjdk-8-jre-headless"; then
      java_package_installed="openjdk-8-jre-headless"
    fi
    if [[ -n "${java_package_installed:-}" ]]; then
      java_version_installed=$(dpkg --list "${java_package_installed}" | awk '/^i/{print $3}' | sed 's/-.*//')
    fi
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
      __eubnt_show_success "Java ${java_version_installed} is the latest\\n"
    fi
    if ! dpkg --list "${java_package_installed}" | grep --quiet "^ii"; then
      __eubnt_show_warning "The Java 8 installation appears to be damaged\\n"
    fi
  else
    __eubnt_show_text "Java 8 will be installed\\n"
    __setup_source_java=true
  fi
  if __eubnt_is_package_installed "mongodb-server" || __eubnt_is_package_installed "mongodb-org-server" ; then
    local mongo_version_installed=""
    local mongo_package_installed=""
    local mongo_update_available=""
    local mongo_version_check=""
    if __eubnt_is_package_installed "mongodb-org-server"; then
      mongo_package_installed="mongodb-org-server"
    fi
    if __eubnt_is_package_installed "mongodb-server"; then
      mongo_package_installed="mongodb-server"
    fi
    if [[ -n "${mongo_package_installed:-}" ]]; then
      mongo_version_installed=$(dpkg --list "${mongo_package_installed}" | awk '/^i/{print $3}' | sed 's/.*://' | sed 's/-.*//')
    fi
    if [[ "${mongo_package_installed:-}" = "mongodb-server" && -n "${__is_64:-}" && ! -f "/lib/systemd/system/unifi.service" ]]; then
      __eubnt_show_notice "Mongo officially maintains 'mongodb-org' packages but you have 'mongodb' packages installed\\n"
      if __eubnt_question_prompt "Do you want to remove the 'mongodb' packages and install 'mongodb-org' packages instead?" "return"; then
        __purge_mongo=true
        __setup_source_mongo=true
      fi
    fi
  fi
  if [[ -n "${mongo_version_installed:-}" && -n "${mongo_package_installed:-}" && ! $__purge_mongo ]]; then
    mongo_update_available=$(apt-cache policy "${mongo_package_installed}" | awk '/Candidate/{print $2}' | sed 's/.*://' | sed 's/-.*//')
    mongo_version_check=$(echo "${mongo_version_installed:0:3}" | sed 's/\.//')
    if [[ "${mongo_version_check:-}" -gt "34" && ! $(dpkg --list 2>/dev/null | grep "^i.*unifi.*") ]]; then
      __eubnt_show_warning "UBNT recommends MongoDB version ${__mongo_version_recommended}\\n"
      if __eubnt_question_prompt "Do you want to downgrade MongoDB to ${__mongo_version_recommended}?" "return"; then
        __purge_mongo=true
        __setup_source_mongo=true
      fi
    fi
    if [[ ! $__purge_mongo && -n "${mongo_update_available:-}" && "${mongo_update_available:-}" != "${mongo_version_installed}" ]]; then
      __eubnt_show_text "MongoDB version ${mongo_version_installed} is installed, ${__colors_warning_text}version ${mongo_update_available} is available\\n"
      if ! __eubnt_question_prompt "Do you want to update MongoDB to ${mongo_update_available}?" "return"; then
        __hold_mongo="${mongo_package_installed}"
      fi
      echo
    elif [[ ! $__purge_mongo && -n "${mongo_update_available:-}" && "${mongo_update_available:-}" = "${mongo_version_installed}" ]]; then
      __eubnt_show_success "MongoDB version ${mongo_version_installed} is the latest\\n"
    fi
    if ! dpkg --list "${mongo_package_installed}" | grep --quiet "^ii"; then
      __eubnt_show_warning "The MongoDB installation appears to be damaged\\n"
    fi
  else
    __eubnt_show_text "MongoDB will be installed\\n"
    __setup_source_mongo=true
  fi
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    __is_unifi_installed=true
    __unifi_version_installed=$(dpkg --list "unifi" | awk '/^i/{print $3}' | sed 's/-.*//')
    __unifi_update_available=$(apt-cache policy "unifi" | awk '/Candidate/{print $2}' | sed 's/-.*//')
    if [[ "${__unifi_update_available:0:3}" != "${__unifi_version_installed:0:3}" ]]; then
      __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${__unifi_version_installed:0:3}" && __eubnt_run_command "apt-get update" "quiet"
      __unifi_update_available=$(apt-cache policy "unifi" | awk '/Candidate/{print $2}' | sed 's/-.*//')
    fi
    if [[ -n "${__unifi_update_available}" && "${__unifi_update_available}" != "${__unifi_version_installed}" ]]; then
      __eubnt_show_text "UniFi SDN version ${__unifi_version_installed} is installed, ${__colors_warning_text}version ${__unifi_update_available} is available\\n"
      __hold_unifi="unifi"
    elif [[ -n "${__unifi_update_available}" && "${__unifi_update_available}" = "${__unifi_version_installed}" ]]; then
      __eubnt_show_success "UniFi SDN version ${__unifi_version_installed} is the latest\\n"
      __unifi_update_available=
    fi
    if ! dpkg --list "unifi" | grep --quiet "^ii"; then
      __eubnt_show_warning "The UniFi SDN Controller installation appears to be damaged\\n"
    fi
    __eubnt_show_warning "Be sure to have a backup before proceeding\\n"
  else
    __eubnt_show_text "UniFi SDN does not appear to be installed yet\\n"
  fi
}

### Tests
##############################################################################

### Execution of script
##############################################################################

ln --force --symbolic "${__script_log}" "${__script_log_dir}/${__script_name}-latest.log"
__eubnt_script_colors
__eubnt_show_header
__eubnt_show_license
if [[ -n "${__accept_license:-}" ]]; then
  sleep 3
else
  __eubnt_question_prompt "Do you agree to the license and want to proceed?" "exit" "n"
fi
__eubnt_check_system
__eubnt_question_prompt
__eubnt_purge_mongo
# shellcheck disable=SC2119
__eubnt_setup_sources
__eubnt_install_fixes
__eubnt_install_updates_utils
if [[ -f /var/run/reboot-required ]]; then
  echo
  __eubnt_show_warning "A reboot is recommended.\\nRun this script again after reboot.\\n"
  # TODO: Restart the script automatically after reboot
  if [[ -n "${__quick_mode:-}" ]]; then
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
