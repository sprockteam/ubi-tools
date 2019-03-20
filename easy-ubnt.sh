#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2034,SC2119,SC2120,SC2143,SC2154,SC2155

### Info and Contributors
##############################################################################
# A utility script to easily administer UBNT software
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018-2019 SprockTech, LLC and contributors
__script_title="Easy UBNT"
__script_version="v0.6.0"
__script_full_title="${__script_title} ${__script_version}"
__script_contributors="Klint Van Tassel (SprockTech)
Frank Gabriel (Frankedinven)
Adrian Miller (adrianmmiller)
Sam Sawyer (ssawyer)"

### Copyrights, Mentions and Credits
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
###
# https://unix.stackexchange.com/a/159369 - Basic sed usage
# https://stackoverflow.com/a/26568996 - Combine multiple sed patterns
# https://stackoverflow.com/a/4168417 - Use cut to split variable at delimiter
# https://stackoverflow.com/a/27254437 - Check if variable is an array
# https://stackoverflow.com/a/15394738 - Check if string is in simple array
# https://stackoverflow.com/a/1970254 - Redirect stderr to variable
# https://stackoverflow.com/a/48590164 - Return variable in function
# https://unix.stackexchange.com/a/104887 - Remove characters from variables
# https://unix.stackexchange.com/a/225183 - Show a spinner
# https://askubuntu.com/a/637514 - Pass options to debconf
# https://stackoverflow.com/a/1570356 - Wait for a background process to finish
# https://askubuntu.com/a/445496 - Debian/Ubuntu version equivalents
# https://en.wikipedia.org/wiki/Linux_Mint_version_history - LinuxMint/Ubuntu version equivalents
# https://askubuntu.com/a/674366 - Pass array to function
# https://superuser.com/a/246841 - Add text to beginning of file
# https://askubuntu.com/a/90219 - Purge un-unsed kernels in /boot on Ubuntu
# https://unix.stackexchange.com/a/77738 - Parse apt-cache with madison script
# https://unix.stackexchange.com/a/490994 - Sort array
# https://stackoverflow.com/a/13373256 - Extract substring
# https://stackoverflow.com/a/16310021 - Use awk to check if a number greater than exists
# https://stackoverflow.com/a/27355109 - Comment lines using sed
###


### Startup checks
##############################################################################

# Enable debug tracing if needed
#set -o xtrace
# Exit on error, append "|| true" if an error is expected
set -o errexit
trap 'echo "Uncaught error on line ${LINENO}"' ERR
# Exit on error inside any functions or subshells
set -o errtrace
# Do not allow use of undefined vars, use ${var:-} if a variable might be undefined
set -o nounset

# Only run this script with Bash
if [ ! "$BASH_VERSION" ]; then
  echo
  echo "Startup failed! Please run this script with Bash"
  echo
  exit 1
fi

# As of now, this script is designed to run on Debian-based distributions
if ! command -v apt-get &>/dev/null; then
  echo -e "\\nStartup failed! Please run this on a Debian-based distribution\\n"
  exit 1
fi

# Root or sudo privilege is needed to install things and make system changes
# TODO: Only run commands as root when needed?
if [[ $(id --user) -ne 0 ]]; then
  echo -e "\\nStartup failed! Please run this script as root or use sudo\\n"
  exit 1
fi

# This script is for i386, amd64, armhf and arm64
declare -a __supported_architectures=("i386" "amd64" "armhf" "arm64")
__architecture="$(dpkg --print-architecture)"
for arch in "${!__supported_architectures[@]}"; do
  if [[ "${__supported_architectures[$arch]}" = "${__architecture:-}" ]]; then
    if [[ "${__architecture:-}" = "amd64" || "${__architecture:-}" = "arm64" ]]; then
      __is_64=true
    else
      __is_32=true
    fi
    break
  fi
done
if [[ -z "${__is_32:-}" && -z "${__is_64:-}" ]]; then
  echo -e "\\nStartup failed! Unknown architecture ${__architecture:-}\\n"
  exit 1
fi

### Initialize variables
##############################################################################

# Script variables
__script_check_for_updates=
__script_setup_executable=
__script_is_piped="$(tty --silent && echo -n || echo -n true)"
__script_time="$(date +%s)"
__script_name="easy-ubnt"
__script_name_short="eubnt"
__script_git_url="https://github.com/sprockteam/easy-ubnt.git"
__script_git_branch="master"
__script_git_raw_content="https://github.com/sprockteam/easy-ubnt/raw/${__script_git_branch}"
__script_dir="$(mkdir --parents "/usr/lib/${__script_name}" && echo -n "/usr/lib/${__script_name}")"
__script_file="${__script_name}.sh"
__script_path="${__script_dir}/${__script_file}"
__script_sbin_command="/sbin/${__script_name}"
__script_sbin_command_short="/sbin/${__script_name_short}"
__script_log_dir="$(mkdir --parents "/var/log/${__script_name}" && echo -n "/var/log/${__script_name}" || echo -n)"
__script_log="$(touch "${__script_log_dir}/${__script_time}.log" && echo -n "${__script_log_dir}/${__script_time}.log" || echo -n)"
__script_data_dir="$(mkdir --parents "/var/lib/${__script_name}" && echo -n "/var/lib/${__script_name}" || echo -n)"
__script_temp_dir=$(mktemp --directory)

# System variables
__os_all_info="$(uname --all)"
__os_kernel_version="$(uname --release | sed 's/[-][a-z].*//g')"
__os_version="$(lsb_release --release --short)"
__os_version_name="$(lsb_release --codename --short)"
__os_version_major="$(echo -n "${__os_version:-}" | cut --fields 1 --delimiter '.')"
__os_name="$(lsb_release --id --short | sed 's/.*/\l&/g')"
__disk_total_space_mb="$(df . | awk '/\//{printf "%.0f", $2/1024}')"
__disk_total_space_gb="$(df . | awk '/\//{printf "%.0f", $2/1024/1024}')"
__disk_free_space_mb="$(df . | awk '/\//{printf "%.0f", $4/1024}')"
__disk_free_space_gb="$(df . | awk '/\//{printf "%.0f", $4/1024/1024}')"
__memory_total_mb="$(grep "MemTotal" /proc/meminfo | awk '{printf "%.0f", $2/1024}')"
__memory_total_gb="$(grep "MemTotal" /proc/meminfo | awk '{printf "%.0f", $2/1024/1024}')"
__swap_total_mb="$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.0f", $2/1024}')"
__swap_total_gb="$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.0f", $2/1024/1024}')"
__recommended_disk_free_space_gb="10"
__recommended_memory_total_gb="2"
__recommended_swap_total_gb="2"
__nameservers="$(awk '/nameserver/{print $2}' /etc/resolv.conf | xargs)"
__is_user_sudo="$([[ -n "${SUDO_USER:-}" ]] && echo -n true || echo -n)"
__hostname_local="$(hostname --short)"
__hostname_fqdn="$(hostname --fqdn)"

# Package decision variables
if [[ "${__os_name:-}" = "ubuntu" && -n "${__os_version:-}" ]]; then
  __is_ubuntu=true
  if [[ "${__os_version//.}" -ge 1804 ]]; then
    __ubuntu_version_name_to_use_for_repos="bionic"
  elif [[ "${__os_version//.}" -ge 1604 && "${__os_version//.}" -lt 1804 ]]; then
    __ubuntu_version_name_to_use_for_repos="xenial"
  elif [[ "${__os_version//.}" -ge 1404 && "${__os_version//.}" -lt 1604 ]]; then
    __ubuntu_version_name_to_use_for_repos="trusty"
  elif [[ "${__os_version//.}" -ge 1204 && "${__os_version//.}" -lt 1404 ]]; then
    __ubuntu_version_name_to_use_for_repos="precise"
  else
    # Try xenial ¯\_(ツ)_/¯
    __ubuntu_version_name_to_use_for_repos="xenial"
  fi
elif [[ "${__os_name:-}" = "linuxmint" && -n "${__os_version_major:-}" ]]; then
  __is_mint=true
  if [[ "${__os_version_major}" -ge 19 ]]; then
    __ubuntu_version_name_to_use_for_repos="bionic"
  elif [[ "${__os_version_major}" -eq 18 ]]; then
    __ubuntu_version_name_to_use_for_repos="xenial"
  elif [[ "${__os_version_major}" -eq 17 ]]; then
    __ubuntu_version_name_to_use_for_repos="trusty"
  elif [[ "${__os_version_major}" -ge 13 && "${__os_version_major}" -lt 17 ]]; then
    __ubuntu_version_name_to_use_for_repos="precise"
  else
    # Try xenial ¯\_(ツ)_/¯
    __ubuntu_version_name_to_use_for_repos="xenial"
  fi
else
  __is_debian=true
  if [[ -n "${__os_version_major:-}" ]]; then
    if [[ "${__os_version_major}" -ge 10 ]]; then
      __ubuntu_version_name_to_use_for_repos="bionic"
    elif [[ "${__os_version_major}" -eq 9 ]]; then
      __ubuntu_version_name_to_use_for_repos="xenial"
    elif [[ "${__os_version_major}" -eq 8 ]]; then
      __ubuntu_version_name_to_use_for_repos="trusty"
    elif [[ "${__os_version_major}" -eq 7 ]]; then
      __ubuntu_version_name_to_use_for_repos="precise"
    else
      # Try xenial ¯\_(ツ)_/¯
      __ubuntu_version_name_to_use_for_repos="xenial"
    fi
  fi
fi

# UBNT variables
__ubnt_dl="dl.ubnt.com"
__ubnt_update_api="https://fw-update.ubnt.com/api/firmware"
declare -A __ubnt_products=(
  ['aircontrol']='airControl Server|ubnt|i386,armhf,arm64,amd64'
  ['unifi-controller']='UniFi SDN Controller|ubnt|i386,armhf,arm64,amd64'
  ['unifi-protect']='UniFi Protect|ubnt|i386,armhf,arm64,amd64'
  ['unifi-video']='UniFi Video|ubnt|amd64'
  ['eot-controller']='UniFi EoT (LED) Controller|ubiquiti/eot-controller|amd64,arm64'
  ['ucrm']='Ubiquiti Customer Relationship Management|Ubiquiti-App/UCRM|amd64,arm64'
  ['unms']='Ubiquiti Network Management System|Ubiquiti-App/UNMS|amd64,arm64'
)

# Miscellaneous variables
__apt_sources_dir="/etc/apt/sources.list.d"
__sshd_config="/etc/ssh/sshd_config"
__letsencrypt_dir="/etc/letsencrypt"
__regex_ip_address='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|1[0-9]|2[0-9]|3[0-2]))?$'
__regex_port_number='^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'
__regex_url='^http(s)?:\/\/\S+$'
__regex_url_ubnt_deb='^http(s)?:\/\/.*(ui\.com|ubnt\.com)\S+\.deb$'
__regex_number='^[0-9]+$'
__regex_version_major_minor='^[0-9]+\.[0-9]+$'
__regex_version_full='^[0-9]+\.[0-9]+\.[0-9]+$'
__regex_version_java8='^8u[0-9]{1,3}$'
__regex_version_mongodb3_4='^(2\.(4\.[0-9]{2}|[5-9]\.[0-9]{1,2}|[0-9]{2}\.[0-9]{1,2}))|(^3\.[0-4]\.[0-9]{1,2})$'
__version_mongodb3_4="3.4.99"
__install_mongodb_package="mongodb"
__recommended_nameserver="9.9.9.9"
__github_api_releases_all="https://api.github.com/repos/__/releases"
__github_api_releases_stable="${__github_api_releases_all}/latest"

# Script colors and special text to use
__colors_bold_text="$(tput bold)"
__colors_warning_text="${__colors_bold_text}$(tput setaf 1)"
__colors_error_text="${__colors_bold_text}$(tput setaf 1)"
__colors_notice_text="${__colors_bold_text}$(tput setaf 6)"
__colors_success_text="${__colors_bold_text}$(tput setaf 2)"
__colors_default="$(tput sgr0)"
__spinner="-\\|/"
__failed_mark="${__colors_warning_text}x${__colors_default}"
__completed_mark="${__colors_success_text}\\xE2\\x9C\\x93${__colors_default}"

### Logging functions
##############################################################################

# Add to the script log file
# $1: The message to log
function __eubnt_add_to_log() {
  if [[ -n "${1:-}" && -f "${__script_log:-}" ]]; then
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
      if [[ ! -f "${2}" ]]; then
        if ! touch "${2}"; then
          __eubnt_show_warning "Unable to create ${2} at $(caller)"
          return
        fi
      fi
      if [[ "${3:-}" = "append" ]]; then
        echo "${1}" >>"${2}"
      else
        echo "${1}" >"${2}"
      fi
    else
      echo -e -n "${1}"
    fi
    __eubnt_add_to_log "${1}"
  fi
}

### Parse commandline options
##############################################################################

# Display basic usage information and exit
function __eubnt_show_help() {
  echo -e "
  -a          Accept and skip the license agreement
  -c          Command to issue to product, used with -p
              Currently supported commands:
              'archive_all_alerts'
  -d          Specify what domain name (FQDN) to use in the script
  -h          Show this help screen
  -i [arg]    Specify a version to install, used with -p
              Can be a version number or the keywords 'beta', 'candidate' or 'stable'
              Examples: '5.9.29', 'stable, 'beta'
  -p [arg]    Specify which UBNT product to administer
              Currently supported products:
              'unifi-controller'
  -q          Run the script in quick mode, accepting all default answers
  -v          Enable verbose screen output
  -x          Enable script execution tracing\\n"
  exit 1
}

# Basic way to get command line options
# TODO: Incorporate B3BP methods here for long options
while getopts ":c:d:i:p:afhqvx" options; do
  case "${options}" in
    a)
      __accept_license=true
      __eubnt_add_to_log "Command line option: accepted license";;
    c)
      if [[ -n "${OPTARG:-}" ]]; then
        __ubnt_product_command="${OPTARG}"
      else
        __eubnt_show_help
      fi;;
    d)
      if [[ -n "${OPTARG:-}" ]]; then
        __hostname_fqdn="${OPTARG}"
        __eubnt_add_to_log "Command line option: specified domain name ${__hostname_fqdn}"
      else
        __eubnt_show_help
      fi;;
    h|\?)
      __eubnt_show_help;;
    i)
      if [[ -n "${OPTARG:-}" && ( "${OPTARG:-}" =~ ${__regex_version_full} || "${OPTARG:-}" =~ ${__regex_version_major_minor} ) ]]; then
        __ubnt_product_version="${OPTARG}"
        __eubnt_add_to_log "Command line option: specified UBNT product version ${__ubnt_product_version}"
      else
        __eubnt_show_help
      fi;;
    p)
      if [[ -n "${OPTARG:-}" ]]; then
        if [[ "${OPTARG}" = "unifi-sdn" ]]; then
          __ubnt_selected_product="unifi-controller"
        else
          for product in "${!__ubnt_products[@]}"; do
            if [[ "${OPTARG}" = "${product}" ]]; then
              __ubnt_selected_product="${OPTARG}"
              break
            fi
          done
        fi
      fi
      if [[ -n "${__ubnt_selected_product:-}" ]]; then
        __eubnt_add_to_log "Command line option: selected UBNT product ${__ubnt_selected_product}"
      else
        __eubnt_show_help
      fi;;
    q)
      __quick_mode=true
      __eubnt_add_to_log "Command line option: enabled quick mode";;
    v)
      __verbose_output=true
      __eubnt_add_to_log "Command line option: enabled verbose mode";;
    x)
      set -o xtrace
      __script_debug=true
      __eubnt_add_to_log "Command line option: enabled xtrace debugging";;
    *)
      break;;
  esac
done
if [[ ( -n "${__ubnt_product_version:-}" || -n "${__ubnt_product_command:-}" ) && -z "${__ubnt_selected_product:-}" ]]; then
  __eubnt_show_help
fi
if [[ -z "${__ubnt_selected_product:-}" ]]; then
  __ubnt_selected_product="unifi-controller"
  __eubnt_add_to_log "Defaulting to selected UBNT product: ${__ubnt_selected_product}"
fi

### Error/cleanup handling
##############################################################################

# Run miscellaneous tasks before exiting
# Auto clean and remove un-needed apt-get info/packages
# Restart services if needed
# Cleanup script logs
# Reboot system if needed
# Unset global script variables
function __eubnt_cleanup_before_exit() {
  set +o xtrace
  echo -e "${__colors_default:-}"
  if [[ -z "${__ubnt_product_command:-}" ]]; then
    echo -e "\\nCleaning up script, please wait...\\n"
  fi
  if [[ -n "${__run_autoremove:-}" ]]; then
    __eubnt_run_command "apt-get autoremove --yes"
    __eubnt_run_command "apt-get autoclean --yes"
  fi
  if [[ -n "${__restart_ssh_server:-}" ]]; then
    __eubnt_run_command "service ssh restart"
  fi
  if [[ -d "${__script_log_dir:-}" ]]; then
    local log_files_to_delete="$(find "${__script_log_dir}" -maxdepth 1 -type f -print0 | xargs -0 --exit ls -t | awk 'NR>10')"
    if [[ -n "${log_files_to_delete:-}" ]]; then
      echo "${log_files_to_delete}" | xargs --max-lines=1 rm
    fi
  fi
  if [[ -d "${__script_temp_dir:-}" ]]; then
    rm --recursive --force "${__script_temp_dir}"
  fi
  if [[ -n "${__reboot_system:-}" ]]; then
    shutdown -r now
  fi
  for var_name in ${!__*}; do
    unset -v "${var_name}"
  done
  echo
}
trap '__eubnt_cleanup_before_exit' EXIT

### Display functions
##############################################################################

# Set script colors
function __eubnt_script_colors() {
  echo "${__colors_default}"
}

# Print an error to the screen
# $1: An optional error message to display
function __eubnt_show_error() {
  if [[ -n "${__script_debug:-}" ]]; then
    echo -e "Pausing before error message for 10 seconds..."
    sleep 10
  else
    clear
  fi
  echo -e "${__colors_error_text}### ${__script_full_title}"
  echo -e "##############################################################################\\n"
  echo -e "ERROR! Script halted!${__colors_default}\\n"
  if [[ -f "${__script_log:-}" ]]; then
    echo -e "To help troubleshoot, here are the last five entries from the script log:\\n"
    log_lines="$(tail --lines=5 "${__script_log}")"
    echo -e "${log_lines}\\n"
  fi
  __eubnt_echo_and_log "${__colors_error_text}Error at line $(caller)"
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "Error message: ${1}"
  fi
  echo -e "${__colors_default}"
  exit 1
}
trap '__eubnt_show_error' ERR

# Print a header that informs the user what task is running
# $1: Can be set with a string to display additional details about the current task
# $2: Can be set to "noclear" to not clear the screen before displaying header
###
# If the script is not in debug mode, then the screen will be cleared first
# The script header will then be displayed
# If $1 is set then it will be displayed under the header
function __eubnt_show_header() {
  if [[ -z "${__script_debug:-}" || "${2:-}" != "noclear" ]]; then
    clear
  fi
  echo -e "${__colors_notice_text}### ${__script_full_title}"
  echo -e "##############################################################################${__colors_default}"
  __eubnt_show_notice "${1:-}"
  echo
}

# Print text to the screen
# $1: The text to display
function __eubnt_show_text() {
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "${__colors_default}${1}${__colors_default}"
    echo
  fi
}

# Print a notice to the screen
# $1: The notice to display
function __eubnt_show_notice() {
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "${__colors_notice_text}${1}${__colors_default}"
    echo
  fi
}

# Print a success message to the screen
# $1: The message to display
function __eubnt_show_success() {
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "${__colors_success_text}${1}${__colors_default}"
    echo
  fi
}

# Print a warning to the screen
# $1: The warning to display
# $2: Can be set to "none" to not show the "WARNING:" prefix
function __eubnt_show_warning() {
  if [[ -n "${1:-}" ]]; then
    local warning_prefix=""
    if [[ "${2:-}" != "none" ]]; then
      warning_prefix="WARNING: "
    fi
    echo
    __eubnt_echo_and_log "${__colors_warning_text}${warning_prefix:-}${1}${__colors_default}"
    echo
  fi
}

# Print a timer on the screen
# $1: The number of seconds to display the timer
# $2: The optional message to show after the timer is done
function __eubnt_show_timer() {
  local countdown="5"
  local message="${2:-Proceeding in 0...}"
  if [[ "${1:-}" =~ ${__regex_number} && "${1:-}" -le 9 && "${1:-}" -ge 1 ]]; then
    countdown="${1}"
  fi
  while [[ "${countdown}" -ge 0 ]]; do
    if [[ "${countdown}" -ge 1 ]]; then
      echo -e -n "\\rProceeding in ${countdown}..."
    else
      echo -e -n "\\r${message}"
      sleep 0.5
    fi
    sleep 1
    countdown=$(( countdown-1 ))
  done
}

# Print a short message and progress spinner to the scree
# $1: The background process ID
# $2: An optional message to display
# $3: Optionally specify the max amount of time in seconds to show the spinner
function __eubnt_show_spinner() {
  local background_pid="${1}"
  local message="${2:-Please wait...}"
  local timeout="${3:-360}"
  local i=0
  while [[ -d /proc/$background_pid ]]; do
    echo -e -n "\\r${message} [${__spinner:i++%${#__spinner}:1}]"
    sleep 0.5
    if [[ $i -gt $timeout ]]; then
      break
    fi
  done
  # shellcheck disable=SC2086
  wait $background_pid
}

# Print the license and disclaimer for this script to the screen
function __eubnt_show_license() {
  __eubnt_show_text "MIT License\\nCopyright (c) 2018-2019 SprockTech, LLC and contributors\\n
Read the full MIT License for this script here:
https://github.com/sprockteam/easy-ubnt/raw/master/LICENSE\\n
Contributors (UBNT Community Username):"
  __eubnt_show_notice "${__script_contributors:-}"
  __eubnt_show_text "This script will guide you through installing, upgrading or removing
the UBNT products, as well as tweaking, securing and maintaining
this system according to best practices."
  __eubnt_show_warning "THIS SCRIPT IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND!"
}

### Screen display and user input functions
##############################################################################

# Use whiptail to display information and options on the screen
# $1: The type of whiptail object to display: "msgbox" (default), "yesno", "input", "menu"
# $2: The message text to display under the title
# $3: The variable to assign return values for "menu" and "input" responses
# $4: If $1 is "menu" then an array of menu items ("tag" "description" ...)
#     If $1 is "input" then this can be set to "optional" to allow for empty responses
# $5: Optionally set to "alert" for a red background
# $6: Optionally specify the height
# $7: Optionally specify the width
# $8: If a menu, optionally specify the number of lines for the menu
function __eubnt_show_whiptail() {
  if ! __eubnt_is_command "whiptail"; then
    if ! __eubnt_install_package "whiptail"; then
      return 1
    fi
  fi
  if [[ -n "${1:-}" ]]; then
    local message=""
    local height=""
    local width=""
    local error_response=
    local old_newt_colors="${NEWT_COLORS:-}"
    local newt_colors_normal="
    window=black,white
    title=black,white
    border=black,white
    textbox=black,white
    listbox=black,white
    actsellistbox=white,blue
    button=white,blue"
    local newt_colors_alert="
    root=,red
    window=red,white
    title=red,white
    border=red,white
    textbox=red,white
    listbox=red,white
    actsellistbox=white,red
    button=white,red"
    if [[ "${1}" = "menu" && -n "${4:-}" ]]; then
      export NEWT_COLORS="${newt_colors_normal}"
      local -n menu_items=${4}
      local menu_lines=$((${#menu_items[@]} + 3))
      menu_lines="${8:-${menu_lines}}"
      message=${2:-"Please make a selection:"}
      height="${6:-30}"
      width="${7:-80}"
      local selected_item="$(whiptail --title "${__script_full_title}" --menu "\\n${message}" "${height}" "${width}" "${menu_lines}" "${menu_items[@]}" 3>&1 1>&2 2>&3)" || true
      if [[ -n "${selected_item:-}" ]]; then
        eval "${3}=\"${selected_item}\""
      else
        error_response=true
      fi
    elif [[ "${1}" = "input" && -n "${2:-}" ]]; then
      export NEWT_COLORS="${newt_colors_normal}"
      message=${2}
      height="${6:-15}"
      width="${7:-80}"
      local answer="$(whiptail --title "${__script_full_title}" --inputbox "\\n${message}" "${height}" "${width}" 3>&1 1>&2 2>&3)" || true
      if [[ -n "${answer:-}" ]]; then
        eval "${3}=\"${answer}\""
      elif [[ -z "${answer:-}" && "${4:-}" = "optional" ]]; then
        true # Allow an empty response
      else
        error_response=true
      fi
    else
      error_response=true
    fi
    export NEWT_COLORS="${old_newt_colors}"
    if [[ -n "${error_response:-}" ]]; then
      return 1
    fi
  fi
}

# Display a yes or no question and proceed accordingly based on the answer
# If no answer is given, the default answer is used
# If the script it running in "quiet mode" then the default answer is used without prompting
# $1: The question to use instead of the default question
# $2: Can be set to "return" if an error should be returned instead of exiting
# $3: Can be set to "n" if the default answer should be no instead of yes
function __eubnt_question_prompt() {
  local yes_no=""
  local default_question="Do you want to proceed?"
  local default_answer="y"
  if [[ "${3:-}" = "n" ]]; then
    default_answer="n"
  fi
  if [[ -n "${__quick_mode:-}" ]]; then
    __eubnt_add_to_log "Quick mode, default answer selected"
    yes_no="${default_answer}"
  fi
  while [[ ! "${yes_no:-}" =~ (^[Yy]([Ee]?|[Ee][Ss])?$)|(^[Nn][Oo]?$) ]]; do
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
# No validation is done on use the input within this function, must be done after the answer has been returned
# $1: The question to ask, there is no default question so one must be set
# $2: The variable to assign the answer to, this must also be set
# $3: Can be set to "optional" to allow for an empty response to bypass the question
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
    if [[ -n "${user_input:-}" ]]; then
      __eubnt_add_to_log "${1} ${user_input}"
      eval "${2}=\"${user_input}\""
    fi
  fi
}

### End ##
### Task and command functions
##############################################################################

# Check if something is a valid command on the system
# $1: A string with a command to check
function __eubnt_is_command() {
  if command -v "${1:-}" &>/dev/null; then
    return 0
  fi
  return 1
}

# Check if something is a valid process running on the system
# $1: A string with a process name to check
function __eubnt_is_process() {
  if [[ -n "${1:-}" && $(pgrep --count ".*${1}") -gt 0 ]]; then
    return 0
  fi
  return 1
}

# Check if a given port is in use
# $1: The port number to check
# $2: The protocol to check, default is "tcp" but could be set to "udp"
# $3: Optionally specify a process to check
# $4: If set to "continuous" then run netstat in continuous mode until listening port is found
function __eubnt_is_port_in_use() {
  if [[ "${1:-}" =~ ${__regex_port_number} ]]; then
    local port_to_check="${1}"
    local protocol_to_check="tcp"
    local process_to_check=""
    if [[ -n "${2:-}" && "${2}" = "udp" ]]; then
      protocol_to_check="udp"
    fi
    if __eubnt_is_process "${3:-}"; then
      process_to_check=".*${3}"
    fi
    local grep_check="^${protocol_to_check}.*:${port_to_check} ${process_to_check}"
    if [[ "${4:-}" = "continuous" ]]; then
      if netstat --listening --numeric --programs --${protocol_to_check} --continous | grep --line-buffer --quiet "${grep_check}"; then
        return 0
      fi
    else
      if netstat --listening --numeric --programs --${protocol_to_check} | grep --quiet "${grep_check}"; then
        return 0
      fi
    fi
  fi
  return 1
}

# Try to check if a given TCP port is open and accessible from the Internet
# $1: The TCP port number to check, if set to "available" then just check if port probing service is available
function __eubnt_probe_port() {
  if [[ ! "${1:-}" =~ ${__regex_port_number} && "${1:-}" != "available" ]]; then
    return 1
  fi
  local port_probe_url="https://www.grc.com/x/portprobe="
  local port_to_probe="${1}"
  if [[ "${port_to_probe}" = "available" ]]; then
    if ! wget --quiet --output-document - "${port_probe_url}80" | grep --quiet "World Wide Web HTTP"; then
      return 2
    else
      return 0
    fi
  fi
  if ! __eubnt_is_port_in_use "${port_to_probe}"; then
    nc -l "${port_to_probe}" &
    local listener_pid=$!
  fi
  local return_code=1
  local break_loop=
  while [[ -z "${break_loop:-}" ]]; do
    __eubnt_show_text "Checking port ${port_to_probe}"
    if ! wget --quiet --output-document - "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
      __eubnt_show_warning "It doesn't look like port ${port_to_probe} is open! Check your upstream firewall."
      echo
      if ! __eubnt_question_prompt "Do you want to check port ${port_to_probe} again?" "return"; then
        break_loop=true
      fi
    else
      __eubnt_show_success "Port ${port_to_probe} is open!"
      break_loop=true
      return_code=0
    fi
  done
  if [[ -n "${listener_pid:-}" ]]; then
    __eubnt_run_command "kill -9 ${listener_pid}" "quiet"
  fi
  return ${return_code}
}

# Compare two version numbers like 5.6.40 and 5.9.29
# $1: The first version number to compare
# $2: The comparison operator, could be "gt" "eq" or "ge"
# $3: The second version number to compare
function __eubnt_version_compare() {
  if [[ -n "${1:-}" && -n "${3:-}" ]]; then
    if [[ ! "${1}" =~ ${__regex_version_full} || ! "${3}" =~ ${__regex_version_full} ]]; then
      __eubnt_show_warning "Invalid version number passed at $(caller)"
      return 1
    fi
    IFS='.' read -r -a first_version <<< "${1}"
    IFS='.' read -r -a second_version <<< "${3}"
    if [[ "${2:-}" = "eq" ]]; then
      if [[ "${1//.}" -eq "${3//.}" ]]; then
        return 0
      fi
    elif [[ "${2:-}" = "gt" ]]; then
      if [[ "${first_version[0]}" -ge "${second_version[0]}" \
         && ( ("${first_version[1]}" -gt "${second_version[1]}") \
         || ("${first_version[1]}" -eq "${second_version[1]}" && "${first_version[2]}" -gt "${second_version[2]}") ) ]]; then
        return 0
      fi
    elif [[ "${2:-}" = "ge" ]]; then
      if [[ "${first_version[0]}" -ge "${second_version[0]}" \
         && ( ("${first_version[1]}" -gt "${second_version[1]}") \
         || ("${first_version[1]}" -eq "${second_version[1]}" && "${first_version[2]}" -ge "${second_version[2]}") ) ]]; then
        return 0
      fi
    fi
  fi
  return 1
}

# A wrapper to run commands, display a nice message and handle errors gracefully
# Make sure the command seems valid
# Run the command in the background and show a spinner
# Run the command in the foreground when in verbose mode
# Wait for the command to finish and get the exit code
# $1: The full command to run as a string
# $2: If set to "foreground" then the command will run in the foreground
#     If set to "quiet" the output will be directed to the log file
#     If set to "return" then output will be assigned to variable named in $3
# $3: Name of variable to assign output value of the command if $2 is set to "return"
function __eubnt_run_command() {
  if [[ -z "${1:-}" ]]; then
    __eubnt_show_warning "No command given at $(caller)"
    return 1
  fi
  local background_pid=""
  local command_output=""
  local command_return=""
  declare -a full_command=()
  IFS=' ' read -r -a full_command <<< "${1}"
  if ! __eubnt_is_command "${full_command[0]}"; then
    local found_package=""
    local unknown_command="${full_command[0]}"
    __eubnt_install_package "apt-file"
    __eubnt_run_command "apt-file update"
    if [[ "${unknown_command}" != "apt-file" ]]; then
      __eubnt_run_command "apt-file --package-only --regexp search .*bin\\/${unknown_command}$" "return" "found_package"
      if [[ -n "${found_package:-}" ]]; then
        found_package="$(echo "${found_package}" | head --lines=1)"
        if __eubnt_question_prompt "Do you want to install ${found_package}?" "return"; then
          if ! __eubnt_install_package "${found_package}"; then
            __eubnt_show_error "Unable to install package ${found_package} to get command ${unknown_command} at $(caller)"
          fi
        fi
      else
        __eubnt_show_error "Unknown command ${unknown_command} at $(caller)"
      fi
    fi
  fi
  if [[ "${full_command[0]}" != "echo" ]]; then
    __eubnt_add_to_log "${1}"
  fi
  if [[ ( -n "${__verbose_output:-}" && "${2:-}" != "quiet" ) || "${2:-}" = "foreground" || "${full_command[0]}" = "echo" ]]; then
    "${full_command[@]}" | tee -a "${__script_log}"
    command_return=$?
  elif [[ "${2:-}" = "quiet" ]]; then
    "${full_command[@]}" &>>"${__script_log}" || __eubnt_add_to_log "Error returned running ${1} at $(caller)"
    command_return=$?
  elif [[ "${2:-}" = "return" ]]; then
    command_output="$(mktemp)"
    "${full_command[@]}" &>>"${command_output}" &
    background_pid=$!
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
    # shellcheck disable=SC2086
    wait $background_pid
    command_return=$?
    if [[ ${command_return} -gt 0 ]]; then
      __eubnt_echo_and_log "\\rRunning ${1} [${__failed_mark}]\\n"
    else
      __eubnt_echo_and_log "\\rRunning ${1} [${__completed_mark}]\\n"
    fi
  fi
  if [[ "${2:-}" = "return" && -n "${3:-}" && -e "${command_output:-}" && -s "${command_output:-}" && ${command_return} -eq 0 ]]; then
    # shellcheck disable=SC2086
    eval "${3}=\"$(cat ${command_output})\""
    rm "${command_output}"
  fi
  if [[ ${command_return} -gt 0 ]]; then
    return 1
  fi
}

# Install package if needed and handle errors gracefully
# $1: The name of the package to install
# $2: An optional target release to use
# $3: If set to "return" then return a status
function __eubnt_install_package() {
  if [[ "${1:-}" ]]; then
    if __eubnt_is_package_installed "${1}"; then
      if [[ "${3:-}" != "reinstall" ]]; then
        __eubnt_echo_and_log "Package ${1} already installed [${__completed_mark}]"
        echo
        return 0
      fi
    fi
    if ! __eubnt_is_package_installed "${1}"; then
      if [[ $? -gt 1 ]]; then
        __eubnt_run_command "dpkg --remove --force-all ${1}"
        __eubnt_common_fixes "noheader"
      fi
    fi
    if ! __eubnt_run_command "apt-get install --simulate ${1}" "quiet"; then
      __eubnt_setup_sources
      __eubnt_common_fixes "noheader"
    fi
    if __eubnt_run_command "apt-get install --simulate ${1}" "quiet"; then
      local i=0
      while lsof /var/lib/dpkg/lock &>/dev/null; do
        echo -e -n "\\rWaiting for package manager to become available... [${__spinner:i++%${#__spinner}:1}]"
        sleep 0.5
      done
      __eubnt_echo_and_log "\\rWaiting for package manager to become available... [${__completed_mark}]"
      echo
      if [[ -n "${2:-}" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install --quiet --no-install-recommends --yes --target-release "${2}" "${1}" &>>"${__script_log}" &
        background_pid=$!
      else
        DEBIAN_FRONTEND=noninteractive apt-get install --quiet --no-install-recommends --yes "${1}" &>>"${__script_log}" &
        background_pid=$!
      fi
      if [[ -n "${background_pid:-}" ]]; then
        local i=0
        while [[ -d /proc/$background_pid ]]; do
          echo -e -n "\\rInstalling package ${1} [${__spinner:i++%${#__spinner}:1}]"
          sleep 0.5
          if [[ $i -gt 360 ]]; then
            break
          fi
        done
        # shellcheck disable=SC2086
        wait $background_pid
        command_return=$?
        if [[ "${command_return:-}" -gt 0 ]]; then
          __eubnt_echo_and_log "\\rInstalling package ${1} [${__failed_mark}]"
          echo
          if [[ "${3:-}" = "return" ]]; then
            return 1
          fi
        else
          __eubnt_echo_and_log "\\rInstalling package ${1} [${__completed_mark}]"
          echo
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

# Check if is package is installed
# $1: The name of the package to check
function __eubnt_is_package_installed() {
  if [[ -n "${1:-}" ]]; then
    local package_name=$(echo "${1}" | sed 's/=.*//')
    if dpkg --list "${package_name}" 2>/dev/null | grep --quiet "^ii.* ${package_name} "; then
      return 0
    elif dpkg --list "${package_name}" 2>/dev/null | grep --quiet "^i[^i].* ${package_name}"; then
      return 2
    fi
  fi
  return 1
}

# Add a source list to the system if needed
# $1: The source information to use
# $2: The name of the source list file to make on the local machine
# $3: A search term to use when checking if the source list should be added
function __eubnt_add_source() {
  if [[ "${1:-}" && "${2:-}" && "${3:-}" ]]; then
    if [[ ! $(find /etc/apt -name "*.list" -exec grep "${3}" {} \;) ]]; then
      if [[ -d "${__apt_sources_dir:-}" ]]; then
        __eubnt_echo_and_log "deb ${1}" "${__apt_sources_dir}/${2}"
        return 0
      fi
    else
      __eubnt_add_to_log "Skipping add source for ${1}"
      return 0
    fi
  fi
  return 1
}

# Remove a source list that contains a string or matches a name
# $1: The string or file name to search for in the source lists
#     If set to a value ending in ".list" then search for a filename
#     If anything else, then search for a string in the list contents
function __eubnt_remove_source() {
  if [[ -n "${1:-}" && "${1:-}" = *".list" ]]; then
    find /etc/apt -name "*${1}" -exec mv --force {} {}.bak \;
    __eubnt_run_command "apt-get update"
    return 0
  elif [[ -n "${1:-}" ]]; then
    find /etc/apt -name "*.list" -exec sed -i "\|${1}|s|^|#|g" {} \;
    __eubnt_run_command "apt-get update"
    return 0
  fi
  return 1
}

# Add a package signing key to the system if needed
# $1: The 32-bit hex fingerprint of the key to add
function __eubnt_add_key() {
  if [[ -n "${1:-}" ]]; then
    if ! apt-key list 2>/dev/null | grep --quiet "${1:0:4}.*${1:4:4}"; then
      if ! __eubnt_run_command "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key ${1}"; then
        __eubnt_show_warning "Unable to add key ${1} at $(caller)"
        return 1
      fi
    else
      __eubnt_add_to_log "Skipping add key for ${1}"
      return 0
    fi
  else
    __eubnt_show_warning "No key fingerprint was given at $(caller)"
    return 1
  fi
}

### General UBNT functions
##############################################################################

# Get a UBNT product version number or download URL
# $1: The UBNT product to check
# $2: The version number to check, can be like "5", "5.9" or "5.9.29"
# $3: If set to "url" then return the full URL to the download file
# $4: The variable to assign the found version number or URL, if not set then result will be echoed
function __eubnt_ubnt_get_product() {
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    local ubnt_product=""
    for prod in "${!__ubnt_products[@]}"; do
      if [[ "${1}" = "${prod}" ]]; then
        ubnt_product="${1}"
        break
      fi
    done
    if [[ -z "${ubnt_product:-}" ]]; then
      __eubnt_show_warning "Invalid product: ${1}"
      return 1
    fi
    local can_install=
    local where_to_look="$(echo "${__ubnt_products[$ubnt_product]}" | cut --delimiter '|' --fields 2)"
    IFS=',' read -r -a architectures_supported <<< "$(echo "${__ubnt_products[$ubnt_product]}" | cut --delimiter '|' --fields 3)"
    for arch in "${!architectures_supported[@]}"; do
      if [[ "${architectures_supported[$arch]}" = "${__architecture}" ]]; then
        can_install=true
        break
      fi
    done
    if [[ -z "${can_install:-}" ]]; then
      __eubnt_show_warning "Incompatible hardware for product: ${ubnt_product}"
      return 1
    fi
    local update_url=
    local download_url=""
    local found_version=""
    local version_major=""
    local version_minor=""
    local version_patch=""
    IFS='.' read -r -a version_array <<< "${2}"
    if [[ "${where_to_look:-}" = "ubnt" ]]; then
      if [[ -n "${version_array[0]:-}" && "${version_array[0]}" =~ ${__regex_number} ]]; then
        version_major="&filter=eq~~version_major~~${version_array[0]}"
      fi
      if [[ -n "${version_array[1]:-}" && "${version_array[1]}" =~ ${__regex_number} ]]; then
        version_minor="&filter=eq~~version_minor~~${version_array[1]}"
      fi
      if [[ -n "${version_array[2]:-}" && "${version_array[2]}" =~ ${__regex_number} ]]; then
        version_patch="&filter=eq~~version_patch~~${version_array[2]}"
      fi
      local product="?filter=eq~~product~~${ubnt_product}"
      local product_channel="&filter=eq~~channel~~release"
      local product_platform="&filter=eq~~platform~~"
      if [[ "${ubnt_product}" = "aircontrol" ]]; then
        product_platform="${product_platform}cp"
      elif [[ "${ubnt_product}" = "unifi-controller" ]]; then
        product_platform="${product_platform}debian"
      elif [[ "${ubnt_product}" = "unifi-protect" && -n "${__architecture:-}" ]]; then
        product_platform="${product_platform}Debian9_${__architecture}"
      elif [[ "${ubnt_product}" = "unifi-video" && -n "${__architecture:-}" ]]; then
        if [[ -n "${__is_ubuntu:-}" ]]; then
          if [[ -n "${__os_version:-}" && "${__os_version//.}" -lt 1604 ]]; then
            product_platform="${product_platform}Ubuntu14.04_${__architecture}"
          else
            product_platform="${product_platform}Ubuntu16.04_${__architecture}"
          fi
        else
          product_platform="${product_platform}Debian7_${__architecture}"
        fi
      fi
      if [[ -n "${product:-}" && -n "${product_channel:-}" && -n "${product_platform:-}" ]]; then
        update_url="${__ubnt_update_api}${product}${product_channel}${product_platform}${version_major:-}${version_minor:-}${version_patch:-}&sort=-version&limit=1"
        declare -a wget_command=(wget --quiet --output-document - "${update_url}")
        if [[ "${3:-}" = "url" ]]; then
          # shellcheck disable=SC2068
          download_url="$(${wget_command[@]} | jq -r '._embedded.firmware | .[0] | ._links.data.href')"
        else
          # shellcheck disable=SC2068
          found_version="$(${wget_command[@]} | jq -r '._embedded.firmware | .[0] | .version' | sed 's/+.*//; s/[^0-9.]//g')"
        fi
      fi
    fi
    if [[ -n "${download_url:-}" ]]; then
      if [[ -n "${4:-}" ]]; then
        eval "${4}=\"${download_url}\""
      else
        echo "${download_url}"
      fi
      return 0
    elif [[ -n "${found_version:-}" ]]; then
      if [[ -n "${4:-}" ]]; then
        eval "${4}=\"${found_version}\""
      else
        echo "${found_version}"
      fi
      return 0
    fi
  fi
  return 1
}

# Try to get the release notes for the given product and version
# $1: The full version number to check, for instance: "5.9.29"
# $2: The variable to assign the filename with the release notes
# $3: The UBNT product to check, right now it's just "unifi-controller"
function __eubnt_ubnt_get_release_notes() {
  if [[ -z "${1:-}" && -z "${2:-}" ]]; then
    __eubnt_show_warning "Invalid check for release notes at $(caller)"
    return 1
  fi
  if [[ ! "${1}" =~ ${__regex_version_full} ]]; then
    __eubnt_show_warning "Invalid version number ${1} given at $(caller)"
    return 1
  fi
  local download_url=""
  local found_version=""
  IFS='.' read -r -a version_array <<< "${2}"
  local product="&filter=eq~~product~~${3:-unifi-controller}"
  local version_major="&filter=eq~~version_major~~$(echo "${1}" | cut --fields 1 --delimiter '.')"
  local version_minor="&filter=eq~~version_minor~~$(echo "${1}" | cut --fields 2 --delimiter '.')"
  local version_patch="&filter=eq~~version_patch~~$(echo "${1}" | cut --fields 3 --delimiter '.')"
  local update_url="${__ubnt_update_api}?filter=eq~~platform~~document${product}${version_major}${version_minor}${version_patch}&sort=-version&limit=1"
  local release_notes_url="$(wget --quiet --output-document - "${update_url:-}" | jq -r '._embedded.firmware | .[0] | ._links.changelog.href')"
  local release_notes_file="${__script_temp_dir}/${3:-unifi-controller}-${1}-release-notes.md"
  if [[ "${release_notes_url:-}" =~ ${__regex_url} ]]; then
    __eubnt_add_to_log "Trying to get release notes from: ${release_notes_url:-}"
    if wget --quiet --output-document - "${release_notes_url:-}" | sed '/#### Recommended Firmware:/,$d' 1>"${release_notes_file:-}"; then
      if [[ -f "${release_notes_file:-}" && -s "${release_notes_file:-}" ]]; then
        eval "${2}=\"${release_notes_file}\""
        return 0
      fi
    fi
  fi
  return 1
}

# Try to get a Debian install file from the UBNT
# $1: The URL to download
# $2: The variable to assign the filename
# $3: The UBNT product
function __eubnt_download_ubnt_deb() {
  if [[ "${1:-}" =~ ${__regex_url_ubnt_deb} && -n "${2:-}" ]]; then
    local deb_url="${1}"
    local deb_version="$(__eubnt_extract_version_from_url "${deb_url}")"
    local deb_file="${__script_temp_dir}/${3:-unifi-controller}_${deb_version:-custom}.deb"
    if __eubnt_run_command "wget --quiet --output-document ${deb_file} ${deb_url}"; then
      if [[ -f "${deb_file}" ]]; then
        eval "${2}=\"${deb_file}\""
        return 0
      fi
    fi
  fi
  return 1
}

# Tries to extract a version substring from a given UBNT URL
# $1: The URL string
function __eubnt_extract_version_from_url() {
  echo "${1:-}" | grep --only-matching --extended-regexp "[0-9]+\.[0-9]+\.[0-9]+" | head --lines=1
}

### UniFi SDN Controller functions
##############################################################################

# Return a service port from the UniFi SDN Controller properties
# $1: The port setting name to check
function __eubnt_unifi_controller_get_port() {
  if [[ -z "${1:-}" ]]; then
    return
  fi
  if [[ -z "${__unifi_controller_system_properties:-}" ]]; then
    __eubnt_initialize_unifi_controller_variables "skip_ports"
  fi
  if [[ -n "${__unifi_controller_system_properties:-}" && -f "${__unifi_controller_system_properties}" ]]; then
    declare -a port_settings=( \
      "unifi.http.port" \
      "unifi.https.port" \
      "portal.http.port" \
      "portal.https.port" \
      "unifi.throughput.port" \
      "unifi.stun.port" \
    )
    # shellcheck disable=SC2076
    if [[ " ${port_settings[@]} " =~ " ${1} " ]]; then
      grep "${1}" "${__unifi_controller_system_properties}" 2>/dev/null | tail --lines 1 | sed 's/.*=//g'
    fi
  fi
}

# This will initialize all variables related to UniFi SDN Controller functions
# TODO: Make more of these dynamic
# $1: If set to "skip_ports" then don't initialize port variables
function __eubnt_initialize_unifi_controller_variables() {
  __unifi_controller_is_installed=
  __unifi_controller_limited_to_lts=
  __unifi_controller_data_dir="/var/lib/unifi"
  __unifi_controller_system_properties=""
  __unifi_controller_mongodb_host=""
  __unifi_controller_mongodb_port=""
  __unifi_controller_data_version=""
  __unifi_controller_package_version=""
  if __eubnt_is_package_installed "unifi"; then
    __unifi_controller_is_installed=true
    __unifi_controller_package_version=$(dpkg --list "unifi" | awk '/^ii/{print $3}' | sed 's/-.*//')
    __unifi_controller_mongodb_host="localhost"
    __unifi_controller_mongodb_port="27117"
  fi
  if [[ -d "${__unifi_controller_data_dir:-}" ]]; then
    __unifi_controller_system_properties="${__unifi_controller_data_dir}/system.properties"
    if [[ -f "${__unifi_controller_data_dir}/db/version" ]]; then
      __unifi_controller_data_version="$(cat "${__unifi_controller_data_dir:-}/db/version" 2>/dev/null)"
    fi
    if [[ -f "${__unifi_controller_data_dir}/system.properties" ]]; then
      __unifi_controller_system_properties="${__unifi_controller_data_dir}/system.properties"
      if [[ "${1:-}" != "skip_ports" ]]; then
        __unifi_controller_local_udp_port_discoverable_controller="1900"
        __unifi_controller_local_udp_port_ap_discovery="10001"
        __unifi_controller_port_tcp_inform="$(__eubnt_unifi_controller_get_port "unifi.http.port")"
        __unifi_controller_port_tcp_admin="$(__eubnt_unifi_controller_get_port "unifi.https.port")"
        __unifi_controller_port_tcp_portal_http="$(__eubnt_unifi_controller_get_port "portal.http.port")"
        __unifi_controller_port_tcp_portal_https="$(__eubnt_unifi_controller_get_port "portal.https.port")"
        __unifi_controller_port_tcp_throughput=$(__eubnt_unifi_controller_get_port "unifi.throughput.port")
        __unifi_controller_port_udp_stun=$(__eubnt_unifi_controller_get_port "unifi.stun.port")
      fi
    fi
  fi
}

# Perform various checks to see if the UniFi SDN Controller is running
# $1: Optionally set this to "continous" to keep checking until it's running
function __eubnt_is_unifi_controller_running() {
  __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_is_installed:-}" ]]; then
    if __eubnt_is_port_in_use "${__unifi_controller_port_tcp_inform}" "tcp" "java" "${1:-}"; then
      if __eubnt_is_port_in_use "${__unifi_controller_port_tcp_admin}" "tcp" "java" "${1:-}"; then
        if __eubnt_is_port_in_use "${__unifi_controller_local_udp_port_ap_discovery}" "udp" "java" "${1:-}"; then
          if [[ -f "${__unifi_controller_data_dir}/db/mongod.lock" ]]; then
            if wget --quiet --no-check-certificate --output-document - "https://localhost:8443/manage" | grep --quiet "${__unifi_controller_package_version}"; then
              return 0
            fi
          fi
        fi
      fi
    fi
  fi
  return 1
}

# Various evaluations to use with MongoDB related to the UniFi SDN Controller
# $1: Specify which "eval" command to issue
#     "lts-devices" will check if devices are in the database that are only supported by LTS
function __eubnt_unifi_controller_mongodb_evals() {
  if [[ -n "${1:-}" && $(__eubnt_is_command "mongo") ]]; then
    __eubnt_initialize_unifi_controller_variables
    case "${1}" in
      "lts-devices")
        # shellcheck disable=SC2016
        if mongo --quiet --host ${__unifi_controller_mongodb_host} --port ${__unifi_controller_mongodb_port} --eval 'db.getSiblingDB("ace").device.find({model: { $regex: /^U7E$|^U7O$|^U7Ev2$/ }})' | grep --quiet "mac"; then
          return 0
        fi;;
      "reset-password")
        # shellcheck disable=SC2016
        if mongo --quiet --host ${__unifi_controller_mongodb_host} --port ${__unifi_controller_mongodb_port} --eval 'db.getSiblingDB("ace").device.find({model: { $regex: /^U7E$|^U7O$|^U7Ev2$/ }})' | grep --quiet "adopted\" : true"; then
          return 0
        fi;;
    esac
  fi
  return 1
}

# Show install/reinstall/update options for UniFi SDN Controller
function __eubnt_install_unifi_controller()
{
  __eubnt_show_header "Installing UniFi SDN Controller..."
  local selected_version=""
  local available_version_lts="$(__eubnt_ubnt_get_product "unifi-controller" "5.6")"
  local available_version_stable="$(__eubnt_ubnt_get_product "unifi-controller" "stable")"
  if [[ -n "${__ubnt_product_version:-}" ]]; then
    local available_version_selected="$(__eubnt_ubnt_get_product "unifi-controller" "${__ubnt_product_version}")"
  fi
  declare -a versions_to_install=()
  declare -a versions_to_select=()
  __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    if ! __eubnt_version_compare "${__unifi_controller_package_version}" "gt" "${available_version_stable}"; then
      versions_to_select+=("${__unifi_controller_package_version}" "   Version currently installed")
    fi
  fi
  if [[ -n "${__ubnt_product_version:-}" && -n "${available_version_selected:-}" ]]; then
    selected_version="${available_version_selected}"
  elif [[ -n "${__quick_mode:-}" && -z "${__unifi_controller_package_version:-}" && -n "${available_version_stable:-}" ]]; then
    selected_version="${available_version_stable}"
  elif [[ -n "${__quick_mode:-}" && -n "${__unifi_controller_package_version:-}" ]]; then
    return 1
  else
    local add_lts_version=true
    local add_stable_version=true
    if [[ -n "${available_version_lts:-}" ]]; then
      if [[ -n "${__unifi_controller_package_version:-}" ]]; then
        if ! __eubnt_version_compare "${available_version_lts}" "gt" "${__unifi_controller_package_version}"; then
          add_lts_version=
        fi
      fi
    fi
    if [[ -n "${available_version_stable:-}" ]]; then
      if [[ -n "${__unifi_controller_package_version:-}" ]]; then
        if ! __eubnt_version_compare "${available_version_stable}" "gt" "${__unifi_controller_package_version}"; then
          add_stable_version=
        fi
      fi
    fi
    if [[ -n "${add_stable_version:-}" ]]; then
      versions_to_select+=("${available_version_stable}" "   Latest public stable release")
    fi
    if [[ -n "${add_lts_version:-}" ]]; then
      versions_to_select+=("${available_version_lts}" "   LTS release, to support Gen1 AC and PicoM2")
    fi
    versions_to_select+=("Other" "   Manually enter a version number" "Early Access" "   Use this to paste Early Access release URLs")
    __eubnt_show_whiptail "menu" "Which UniFi SDN Controller version do you want to (re)install or upgrade to?" "selected_version" "versions_to_select"
    if [[ "${selected_version}" = "Cancel" ]]; then
      return 1
    fi
    if [[ "${selected_version}" = "Other" ]]; then
      local what_other_version=""
      while [[ ! "${selected_version:-}" =~ ${__regex_version_full} ]]; do
        __eubnt_get_user_input "What other version (i.e. 5.7 or 5.8.30) do you want to install?" "what_other_version" "optional"
        if [[ -z "${what_other_version:-}" ]]; then
          if ! __eubnt_question_prompt "Do you want to cancel and return to the script?" "return"; then
            return 1
          fi
        else
          selected_version="$(__eubnt_ubnt_get_product "unifi-controller" "${what_other_version}" || echo "")"
          if [[ ! "${selected_version:-}" =~ ${__regex_version_full} ]]; then
            if ! __eubnt_question_prompt "Version ${what_other_version} isn't available, do you want to try another?" "return"; then
              return 1
            fi
            what_other_version=""
          fi
        fi
      done
    fi
    if [[ "${selected_version}" = "Early Access" ]]; then
      local what_custom_url=""
      local what_custom_file=""
      while [[ ! "${selected_version:-}" =~ ${__regex_url_ubnt_deb} ]]; do
        __eubnt_get_user_input "Please enter the early access URL to download and install?" "what_custom_url" "optional"
        if [[ -z "${what_custom_url:-}" ]]; then
          if ! __eubnt_question_prompt "Do you want to cancel and return to the script?" "return"; then
            return 1
          fi
        else
          if [[ "${what_custom_url:-}" =~ ${__regex_url_ubnt_deb} ]] && wget --quiet --spider "${what_custom_url}"; then
              selected_version="${what_custom_url}"
          else
            if ! __eubnt_question_prompt "The URL is inaccessible or invalid, do you want to try another?" "return"; then
              return 1
            fi
            what_custom_url=""
          fi
        fi
      done
    fi
  fi
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    if [[ "${selected_version:-}" =~ ${__regex_version_full} ]] && __eubnt_version_compare "${selected_version}" "gt" "${__unifi_controller_package_version}"; then
      local version_upgrade="$(__eubnt_ubnt_get_product "unifi-controller" "$(echo "${__unifi_controller_package_version}" | cut --fields 1-2 --delimiter '.')")"
      if __eubnt_version_compare "${version_upgrade}" "gt" "${__unifi_controller_package_version}"; then
        versions_to_install+=("${version_upgrade}|$(__eubnt_ubnt_get_product "unifi-controller" "${version_upgrade}" "url")")
      fi
    fi
  fi
  if [[ "${selected_version:-}" =~ ${__regex_url_ubnt_deb} ]]; then
    versions_to_install+=("$(__eubnt_extract_version_from_url "${selected_version}")|${selected_version}")
  elif [[ "${selected_version:-}" =~ ${__regex_version_full} ]]; then
    versions_to_install+=("${selected_version}|$(__eubnt_ubnt_get_product "unifi-controller" "${selected_version}" "url")")
  fi
  if [[ ${#versions_to_install[@]} -gt 0 ]]; then
    versions_to_install=($(printf "%s\\n" "${versions_to_install[@]}" | sort --unique --version-sort))
    for version in "${!versions_to_install[@]}"; do
      if ! __eubnt_install_unifi_controller_version "${versions_to_install[$version]}"; then
        return 1
      fi
    done
  fi
}

# Installs the UniFi SDN Controller based on a version number and download URL
# $1: The full version number to install and URL, example: "5.6.40|https://dl.ubnt.com/unifi/5.6.40/unifi_sysvinit_all.deb"
# TODO: Try to recover if install fails
function __eubnt_install_unifi_controller_version()
{
  if [[ -z "${1:-}" ]]; then
    return 1
  fi
  local install_this_version="$(echo "${1}" | cut --fields 1 --delimiter '|')"
  local install_this_url="$(echo "${1}" | cut --fields 2 --delimiter '|')"
  if [[ ! "${install_this_version:-}" =~ ${__regex_version_full} ]]; then
    return 1
  fi
  if [[ ! "${install_this_url:-}" =~ ${__regex_url_ubnt_deb} ]]; then
    return 1
  fi
  __eubnt_show_header "Installing UniFi SDN Controller ${install_this_version:-}..."
  __eubnt_initialize_unifi_controller_variables
  if [[ "${__unifi_controller_data_version:-}" =~ ${__regex_version_full} ]]; then
    __eubnt_show_warning "Make sure you have a backup!"
    echo
    if ! __eubnt_question_prompt "" "return"; then
      return 1
    fi
  fi
  if __eubnt_version_compare "${__unifi_controller_package_version:-}" "eq" "${install_this_version:-}"; then
    __eubnt_show_notice "UniFi SDN Controller ${install_this_version} is already installed..."
    echo
    if ! __eubnt_question_prompt "Do you want to reinstall it?" "return" "n"; then
      return 1
    fi
  elif __eubnt_version_compare "${__unifi_controller_package_version:-}" "gt" "${install_this_version:-}"; then
    __eubnt_show_warning "UniFi SDN Controller ${install_this_version} is a previous version..."
    echo
    if ! __eubnt_question_prompt "Do you want to purge all data and downgrade?" "return" "n"; then
      return 1
    fi
  fi
  local release_notes=
  if __eubnt_ubnt_get_release_notes "${install_this_version}" "release_notes"; then
    if __eubnt_question_prompt "Do you want to view the release notes?" "return" "n"; then
      more "${release_notes}"
      __eubnt_question_prompt
    fi
  fi
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    __eubnt_run_command "service unifi restart"
    __eubnt_show_text "Waiting for UniFi SDN Controller to finish loading..."
    echo
    while ! __eubnt_is_unifi_controller_running; do
      sleep 3
    done
  fi
  local unifi_deb_file=""
  if __eubnt_download_ubnt_deb "${install_this_url}" "unifi_deb_file"; then
    if [[ -f "${unifi_deb_file}" ]]; then
      echo
      __eubnt_install_package "binutils"
      if __eubnt_install_java8 "noheader"; then
        if __eubnt_install_mongodb3_4 "noheader"; then
          echo "unifi unifi/has_backup boolean true" | debconf-set-selections
          __eubnt_show_text "Installing $(basename "${unifi_deb_file}")"
          if DEBIAN_FRONTEND=noninteractive dpkg --install --force-all "${unifi_deb_file}"; then
            __eubnt_show_success "Installation complete! Waiting for UniFi SDN Controller to finish loading..."
            while ! __eubnt_is_unifi_controller_running; do
              sleep 3
            done
          fi
        fi
      fi
    fi
  fi
}

### Setup sources and install common packages
##############################################################################

# Setup source lists for later use in the script
# Ubuntu: Setup alternative source lists to get certain packages
# Debian: Make sure the dirmngr package is installed so keys can be validated
# Certbot: Debian distribution sources include it, add sources for Ubuntu except Precise
# Java: Use WebUpd8 repository for Precise and Trusty era OSes
# Java: Use the core distribution sources to get Java for all others
# MongoDB: Official repository only distributes 64-bit packages, not compatible with Wheezy
# MongoDB: UniFi will install it from distribution sources if needed
# $1: Optionally setup sources for "mongodb3_4", "java8", "nodejs", "certbot"
function __eubnt_setup_sources() {
  local do_apt_update=
  if [[ -z "${__os_version_name:-}" ]]; then
    __os_version_name="$(lsb_release --codename --short)"
  fi
  __eubnt_install_package "software-properties-common" || true
  if [[ -n "${__is_ubuntu:-}" || -n "${__is_mint:-}" ]]; then
    local kernel_mirror_repo="ubuntu"
    if [[ -n "${__is_mint:-}" ]]; then
      kernel_mirror_repo="linuxmint-packages"
    fi
    __eubnt_add_source "http://archive.ubuntu.com/ubuntu ${__os_version_name} main universe" "${__os_version_name}-archive.list" "archive\\.ubuntu\\.com.*${__os_version_name}.*main" && do_apt_update=true
    __eubnt_add_source "http://security.ubuntu.com/ubuntu ${__os_version_name}-security main universe" "${__os_version_name}-security.list" "security\\.ubuntu\\.com.*${__os_version_name}-security main" && do_apt_update=true
    __eubnt_add_source "http://mirrors.kernel.org/${kernel_mirror_repo} ${__os_version_name} main universe" "${__os_version_name}-mirror.list" "mirrors\\.kernel\\.org.*${__os_version_name}.*main" && do_apt_update=true
  elif [[ -n "${__is_debian:-}" ]]; then
    __eubnt_install_package "dirmngr" || true
    __eubnt_add_source "http://ftp.debian.org/debian ${__os_version_name}-backports main" "${__os_version_name}-backports.list" "ftp\\.debian\\.org.*${__os_version_name}-backports.*main" && do_apt_update=true
    __eubnt_add_source "http://mirrors.kernel.org/debian ${__os_version_name} main" "${__os_version_name}-mirror.list" "mirrors\\.kernel\\.org.*${__os_version_name}.*main" && do_apt_update=true
  fi
  if [[ -n "${do_apt_update:-}" ]]; then
    __eubnt_run_command "apt-get update"
    do_apt_update=
  fi
  if [[ "${1:-}" = "mongodb3_4" ]]; then
    local distro_mongodb_installable_version="$(apt-cache madison mongodb | sort --version-sort | tail --lines=1 | awk '{print $3}' | sed 's/.*://; s/[-+].*//;')"
    if __eubnt_version_compare "${distro_mongodb_installable_version}" "gt" "${__version_mongodb3_4}"; then
      local official_mongodb_repo_url=""
      if [[ -n "${__is_64:-}" && ( -n "${__is_ubuntu:-}" || "${__is_mint:-}" ) ]]; then
        local os_version_name_for_official_mongodb_repo="${__ubuntu_version_name_to_use_for_repos}"
        if [[ "${__ubuntu_version_name_to_use_for_repos}" = "precise" ]]; then
          os_version_name_for_official_mongodb_repo="trusty"
        elif [[ "${__ubuntu_version_name_to_use_for_repos}" = "bionic" ]]; then
          os_version_name_for_official_mongodb_repo="xenial"
        fi
        official_mongodb_repo_url="http://repo.mongodb.org/apt/ubuntu ${os_version_name_for_official_mongodb_repo}/mongodb-org/3.4 multiverse"
      elif [[ -n "${__is_64:-}" && -n "${__is_debian:-}" ]]; then
        if [[ "${__os_version_name:-}" != "wheezy" ]]; then
          official_mongodb_repo_url="http://repo.mongodb.org/apt/debian jessie/mongodb-org/3.4 main"
          __eubnt_add_source "http://ftp.debian.org/debian jessie-backports main" "jessie-backports.list" "ftp\\.debian\\.org.*jessie-backports.*main" && do_apt_update=true
        fi
      fi
      if [[ -n "${official_mongodb_repo_url:-}" ]]; then
        if __eubnt_add_source "${official_mongodb_repo_url}" "mongodb-org-3.4.list" "repo\\.mongodb\\.org.*3\\.4"; then
          __eubnt_add_key "A15703C6" # MongoDB official package signing key
          __install_mongodb_package="mongodb-org"
          do_apt_update=true
        fi
      fi
    fi
  elif [[ "${1:-}" = "java8" ]]; then
    local openjdk8_installable_version="$(apt-cache madison openjdk-8-jre-headless | awk '{print $3}' | sed 's/.*://; s/[-+].*//;' | sort --version-sort | tail --lines=1)"
    if [[ ! "${openjdk8_installable_version}" =~ ${__regex_version_java8} ]]; then
      if __eubnt_add_source "http://ppa.launchpad.net/webupd8team/java/ubuntu ${__ubuntu_version_name_to_use_for_repos} main" "webupd8team-java.list" "ppa\\.launchpad\\.net.*${__ubuntu_version_name_to_use_for_repos}.*main"; then
        __eubnt_add_key "EEA14886" # WebUpd8 package signing key
        do_apt_update=true
        __install_webupd8_java=true
      fi
    fi
  elif [[ "${1:-}" = "nodejs" ]]; then
    local nodejs_sources_script=$(mktemp)
    if __eubnt_run_command "wget --quiet https://deb.nodesource.com/setup_8.x --output-document ${nodejs_sources_script}"; then
      if __eubnt_run_command "bash ${nodejs_sources_script}"; then
        do_apt_update=true
      else
        __eubnt_show_warning "Unable to setup list for NodeJS"
        return 1
      fi
    fi
  elif [[ "${1:-}" = "certbot" ]]; then
    if [[ -n "${__is_ubuntu:-}" && "${__os_version_name:-}" != "precise" ]]; then
      if __eubnt_add_source "http://ppa.launchpad.net/certbot/certbot/ubuntu ${__os_version_name} main" "certbot-ubuntu-certbot-${__os_version_name}.list" "ppa\\.laundpad\\.net.*${__os_version_name}.*main"; then
        if __eubnt_add_key "75BCA694"; then
          do_apt_update=true
        else
          __eubnt_show_warning "Unable to setup list for Certbot"
          return 1
        fi
      fi
    fi
  fi
  if [[ -n "${do_apt_update:-}" ]]; then
    __eubnt_run_command "apt-get update"
  fi
}

# Install package upgrades through apt-get dist-upgrade
# Ask if packages critical to UniFi SDN Controller function should be updated or not
function __eubnt_install_updates() {
  __eubnt_show_header "Installing updates..."
  local java_update_available=
  local mongodb_update_available=
  local java_held=
  local mongodb_held=
  __eubnt_run_command "apt-get dist-upgrade --simulate" "quiet"
  if [[ -z $(tail --lines=1 "${__script_log}" | awk '$1>0') ]]; then
    return
  fi
  if __eubnt_question_prompt "Check for and install available package upgrades?" "return"; then
    __eubnt_install_package "unattended-upgrades" || true
    if __eubnt_is_package_installed "${__java_package_installed:-}"; then
      java_update_available=$(apt-cache policy "${__java_package_installed}" | awk '/Candidate/{print $2}' | sed 's/-.*//')
    fi
    if __eubnt_is_package_installed "${__mongodb_package_installed:-}"; then
      mongodb_update_available=$(apt-cache policy "${__mongodb_package_installed}" | awk '/Candidate/{print $2}' | sed 's/.*://; s/-.*//')
    fi
    if [[ -n "${mongodb_update_available:-}" && "${mongodb_update_available:-}" != "${__mongodb_version_installed}" ]]; then
      __eubnt_show_text "MongoDB ${__mongodb_version_installed} is installed, ${__colors_warning_text}version ${mongodb_update_available} is available"
      echo
      if ! __eubnt_question_prompt "Do you want to update MongoDB to ${mongodb_update_available}?" "return"; then
        __eubnt_run_command "apt-mark hold ${__mongodb_package_installed}"
        mongodb_held=true
      fi
      echo
    fi
    if [[ -n "${java_update_available:-}" && "${java_update_available:-}" != "${__java_version_installed}" ]]; then
      __eubnt_show_text "Java ${__java_version_installed} is installed, ${__colors_warning_text}version ${java_update_available} is available"
      echo
      if ! __eubnt_question_prompt "Do you want to update Java to ${java_update_available}?" "return"; then
        __eubnt_run_command "apt-mark hold ${__java_package_installed}"
        java_held=true
      fi
      echo
    fi
    __eubnt_run_command "apt-get dist-upgrade --yes" || true
    __run_autoremove=true
  fi
  if [[ -n "${java_held:-}" ]]; then
    __eubnt_run_command "apt-mark unhold ${__java_package_installed}"
  fi
  if [[ -n "${mongodb_held:-}" ]]; then
    __eubnt_run_command "apt-mark unhold ${__mongodb_package_installed}"
  fi
}

# Install OpenJDK Java 8 for most OS versions
# Install WebUpd8 Team's Oracle Java 8 PPA if needed
# Use haveged for better entropy generation from @ssawyer (https://community.ubnt.com/t5/UniFi-Wireless/UniFi-Controller-Linux-Install-Issues/m-p/1324455/highlight/true#M116452)
function __eubnt_install_java8() {
  if [[ -z "${__java_package_installed:-}" ]]; then
    if [[ "${1:-}" != "noheader" ]]; then
      __eubnt_show_header "Installing Java..."
    fi
    __eubnt_setup_sources "java8"
    if [[ -n "${__install_webupd8_java:-}" ]]; then
      echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
      if ! __eubnt_install_package "oracle-java8-installer"; then
        __eubnt_show_error "Unable to install WebUpd8 PPA Java 8 at $(caller)"
      fi
    else
      local target_release=""
      if [[ "${__os_version_name}" = "jessie" ]]; then
        target_release="${__os_version_name}-backports"
      fi
      if __eubnt_install_package "ca-certificates-java" "${target_release:-}"; then
        if ! __eubnt_install_package "openjdk-8-jre-headless" "${target_release:-}"; then
          __eubnt_show_error "Unable to install OpenJDK Java 8 at $(caller)"
        fi
      fi
    fi
  fi
  if [[ "${1:-}" != "noheader" ]]; then
    __eubnt_show_header "Checking extra Java-related packages..."
  fi
  if __eubnt_run_command "update-alternatives --list java" "quiet"; then
    __eubnt_install_package "jsvc"
    __eubnt_install_package "libcommons-daemon-java"
    __eubnt_install_package "haveged"
  fi
}

# Install MongoDB
function __eubnt_install_mongodb3_4()
{
  if [[ -z "${__mongodb_package_installed:-}" ]]; then
    if [[ "${1:-}" != "noheader" ]]; then
      __eubnt_show_header "Installing MongoDB..."
    fi
    __eubnt_setup_sources "mongodb3_4"
    __eubnt_install_package "${__install_mongodb_package:-}"
  fi
}

# Install script dependencies
function __eubnt_install_dependencies()
{
  __eubnt_install_package "apt-transport-https" || true
  __eubnt_install_package "sudo" || true
  __eubnt_install_package "curl" || true
  __eubnt_install_package "net-tools" || true
  __eubnt_install_package "dnsutils" || true
  __eubnt_install_package "psmisc" || true
  __eubnt_install_package "jq" || true
}

### Setup OpenSSH
##############################################################################

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
    __eubnt_show_notice "Checking OpenSSH server settings for recommended changes..."
    echo
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

### Setup certbot and hook scripts
##############################################################################

# Based on solution by @Frankedinven (https://community.ubnt.com/t5/UniFi-Wireless/Lets-Encrypt-on-Hosted-Controller/m-p/2463220/highlight/true#M318272)
function __eubnt_setup_certbot() {
  if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
    __eubnt_initialize_unifi_controller_variables
    if [[ ! -d "${__unifi_controller_data_dir:-}" || ! -f "${__unifi_controller_system_properties:-}" ]]; then
      return 1
    fi
  else
    return 1
  fi
  if [[ "${__os_version_name}" = "precise" || "${__os_version_name}" = "wheezy" ]]; then
    return 1
  fi
  local source_backports=
  local skip_certbot_questions=
  local domain_name=
  local email_address=
  local resolved_domain_name=
  local email_option=
  local days_to_renewal=
  __eubnt_show_header "Setting up Let's Encrypt...\\n"
  if [[ -n "${__quick_mode:-}" && -n "${__hostname_fqdn:-}" ]] || __eubnt_question_prompt "Do you want to (re)setup Let's Encrypt?" "return" "n"; then
    if ! __eubnt_is_command "certbot"; then
      if [[ -n "${__is_ubuntu:-}" ]]; then
        if ! __eubnt_setup_sources "certbot"; then
          return 1
        fi
      fi
      if [[ "${__os_version_name}" = "jessie" ]]; then
        __eubnt_run_command "apt-get install --yes --target-release jessie-backports python-cffi python-cryptography certbot"
      else
        __eubnt_install_package "certbot"
      fi
    fi
  else
    return 1
  fi
  if ! __eubnt_is_command "certbot"; then
    echo
    __eubnt_show_warning "Unable to setup certbot!"
    echo
    sleep 3
    return 1
  fi
  domain_name="${__hostname_fqdn:-}"
  if [[ -z "${domain_name:-}" ]]; then
    __eubnt_run_command "hostname --fqdn" "return" "domain_name"
  fi
  if [[ -z "${__quick_mode:-}" ]]; then
    __eubnt_get_user_input "Domain name to use (${domain_name:-}): " "domain_name" "optional"
    resolved_domain_name=$(dig +short "${domain_name}" | tail --lines=1)
    if [[ "${__apparent_public_ip_address:-}" =~ ${__regex_ip_address} && ( ! "${resolved_domain_name:-}" =~ ${__regex_ip_address} || ( "${resolved_domain_name:-}" =~ ${__regex_ip_address} && "${__apparent_public_ip_address}" != "${resolved_domain_name}" ) ) ]]; then
      echo
      __eubnt_show_warning "The domain ${domain_name} does not resolve to ${__apparent_public_ip_address}"
      echo
      if ! __eubnt_question_prompt "" "return"; then
        return 1
      fi
    fi
  fi
  days_to_renewal=0
  if certbot certificates --domain "${domain_name:-}" | grep --quiet "Domains: "; then
    __eubnt_run_command "certbot certificates --domain ${domain_name}" "foreground"
    __eubnt_show_notice "\\nLet's Encrypt has been setup previously\\n"
    days_to_renewal=$(certbot certificates --domain "${domain_name}" | grep --only-matching --max-count=1 "VALID: .*" | awk '{print $2}')
    skip_certbot_questions=true
  fi
  if [[ -z "${skip_certbot_questions:-}" && -z "${__quick_mode:-}" ]]; then
    __eubnt_get_user_input "\\nEmail address for renewal notifications (optional): " "email_address" "optional"
  fi
  echo
  __eubnt_show_warning "Let's Encrypt will verify your domain using HTTP (TCP port 80). This\\nscript will automatically allow HTTP through the firewall on this machine only.\\nPlease make sure firewalls external to this machine are set to allow HTTP.\\n"
  if [[ -n "${email_address:-}" ]]; then
    email_option="--email ${email_address}"
  else
    email_option="--register-unsafely-without-email"
  fi
  if [[ -n "${domain_name:-}" ]]; then
    __eubnt_initialize_unifi_controller_variables
    local letsencrypt_scripts_dir=$(mkdir --parents "${__script_dir}/letsencrypt" && echo "${__script_dir}/letsencrypt")
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
  http_process=\$(netstat -tulpn | awk '/:80 /{print \$7}' | sed 's/[0-9]*\///')
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
if [[ -f "\${http_process_file:-}" ]]; then
  http_process=\$(cat "\${http_process_file}")
  if [[ -n "\${http_process:-}" ]]; then
    service "\${http_process}" start &>/dev/null
  fi
fi
rm "\${http_process_file}" &>/dev/null
if [[ \$(dpkg --status "ufw" 2>/dev/null | grep "ok installed") && \$(ufw status | grep " active") && ! \$(netstat -tulpn | grep ":80 ") ]]; then
  ufw delete allow http &>/dev/null
fi
if [[ -f ${letsencrypt_privkey} && -f ${letsencrypt_fullchain} ]]; then
  if ! md5sum -c ${letsencrypt_fullchain}.md5 &>/dev/null; then
    md5sum ${letsencrypt_fullchain} >${letsencrypt_fullchain}.md5
    cp ${__unifi_controller_data_dir}/keystore ${__unifi_controller_data_dir}/keystore.backup.\$(date +%s) &>/dev/null
    openssl pkcs12 -export -inkey ${letsencrypt_privkey} -in ${letsencrypt_fullchain} -out ${letsencrypt_live_dir}/fullchain.p12 -name unifi -password pass:aircontrolenterprise &>/dev/null
    keytool -delete -alias unifi -keystore ${__unifi_controller_data_dir}/keystore -deststorepass aircontrolenterprise &>/dev/null
    keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${__unifi_controller_data_dir}/keystore -srckeystore ${letsencrypt_live_dir}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt &>/dev/null
    echo "unifi.https.ciphers=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_EMPTY_RENEGOTIATION_INFO_SCSVF" | tee -a "${__unifi_controller_system_properties}"
    echo "unifi.https.sslEnabledProtocols=+TLSv1.1,+TLSv1.2,+SSLv2Hello" | tee -a "${__unifi_controller_system_properties}"
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
    if certbot certonly --agree-tos --standalone --preferred-challenges http-01 --http-01-port 80 --pre-hook ${pre_hook_script} --post-hook ${post_hook_script} --domain ${domain_name} ${email_option} ${force_renewal} ${run_mode}; then
      echo
      __eubnt_show_success "Certbot succeeded for domain name: ${domain_name}"
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

### Setup UFW
##############################################################################

# Loops through comma separated list of IP address to allow as hosts to UFW app rules
# $1: A string matching to the name of a UFW app
# $2: A string containing a comma separated list of IP address or networks
function __eubnt_allow_hosts_ufw_app() {
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    local allowed_host=""
    local allowed_app="${1}"
    IFS=',' read -r -a host_addresses <<< "${2}"
    for host_address in "${!host_addresses[@]}"; do
      allowed_host="${host_addresses[$host_address]}"
      if [[ "${allowed_host}" =~ ${__regex_ip_address} ]]; then
        __eubnt_run_command "ufw allow from ${allowed_host} to any app ${allowed_app}"
      fi
    done
    return 0
  fi
  return 1
}

# Install and setup UFW
# Adds an app profile that includes all UniFi SDN ports to allow for easy rule management in UFW
# Checks if ports appear to be open/accessible from the Internet
function __eubnt_setup_ufw() {
  __eubnt_show_header "Setting up UFW (Uncomplicated Firewall)..."
  if ! __eubnt_is_package_installed "ufw"; then
    if ! __eubnt_question_prompt "Do you want to install UFW?" "return"; then
      return 1
    else
      if ! __eubnt_install_package "ufw"; then
        return 1
      fi
    fi
  fi
  declare -a apps_to_allow=()
  if __eubnt_is_process "sshd" && [[ -f "${__sshd_config:-}" ]]; then
    local ssh_port=$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')
    sed -i "s|^ports=.*|ports=${ssh_port}/tcp|" "/etc/ufw/applications.d/openssh-server"
    apps_to_allow+=("OpenSSH")
  fi
  if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
    __eubnt_initialize_unifi_controller_variables
    if [[ -n "${__unifi_controller_port_tcp_inform:-}" \
       && -n "${__unifi_controller_port_tcp_admin:-}" \
       && -n "${__unifi_controller_port_tcp_portal_http:-}" \
       && -n "${__unifi_controller_port_tcp_portal_https:-}" \
       && -n "${__unifi_controller_port_tcp_throughput:-}" \
       && -n "${__unifi_controller_port_udp_stun:-}" ]]; then
      apps_to_allow+=("UniFi-Controller")
      tee "/etc/ufw/applications.d/unifi-controller" &>/dev/null <<EOF
[UniFi-Controller-Inform]
title=UniFi SDN Controller Inform and STUN
description=TCP and UDP ports used to add devices to the controller and allow for remote terminal access
ports=${__unifi_controller_port_tcp_inform}/tcp|${__unifi_controller_port_udp_stun}/udp

[UniFi-Controller-Admin]
title=UniFi SDN Controller Admin
description=TCP port used to login and administer the controller
ports=${__unifi_controller_port_tcp_admin}/tcp

[UniFi-Controller-Speed]
title=UniFi SDN Controller Speed
description=TCP port used to test throughput from the mobile app to the controller
ports=${__unifi_controller_port_tcp_throughput}/tcp

[UniFi-Controller-Portal]
title=UniFi SDN Controller Portal Access
description=TCP ports used to allow for guest portal access
ports=${__unifi_controller_port_tcp_portal_http},${__unifi_controller_port_tcp_portal_https}/tcp

[UniFi-Controller-Local]
title=UniFi SDN Controller Local Discovery
description=UDP ports used for discovery of devices on the local (layer 2) network, not recommended for cloud controllers
ports=${__unifi_controller_local_udp_port_discoverable_controller},${__unifi_controller_local_udp_port_ap_discovery}/udp
EOF
# End of output to file
    fi
  fi
  __eubnt_show_notice "Current UFW status:"
  echo
  __eubnt_run_command "ufw app update all" "quiet"
  __eubnt_run_command "ufw status verbose" "foreground"
  echo
  if [[ ${#apps_to_allow[@]} -gt 0 ]]; then
    if __eubnt_question_prompt "Do you want to setup or make changes to UFW now?" "return" "y"; then
      if ufw status | grep --quiet " active"; then
        if __eubnt_question_prompt "Do you want to reset your current UFW rules?" "return" "y"; then
          __eubnt_run_command "ufw --force reset"
        fi
      fi
      local hosts_to_allow=""
      local allow_access="n"
      local apps_to_check="$(IFS=$'|'; echo "${apps_to_allow[*]}")"
      declare -a app_list=($(ufw app list | grep --extended-regexp "${apps_to_check}" | awk '{print $1}'))
      for app_name in "${!app_list[@]}"; do
        allowed_app="${app_list[$app_name]}"
        if [[ "${allowed_app}" = "UniFi-Controller-Local" ]]; then
          allow_access="n"
        else
          allow_access="y"
        fi
        echo
        __eubnt_run_command "ufw app info ${allowed_app}" "foreground"
        echo
        if __eubnt_question_prompt "Do you want to allow access to these ports?" "return" "${allow_access:-n}"; then
          hosts_to_allow=""
          if [[ -z "${__quick_mode:-}" ]]; then
            echo
            __eubnt_get_user_input "IP(s) to allow, separated by commas, default is 'any': " "hosts_to_allow" "optional"
            echo
          fi
          if [[ -z "${hosts_to_allow:-}" ]]; then
            __eubnt_run_command "ufw allow from any to any app ${allowed_app}"
          else
            if __eubnt_allow_hosts_ufw_app "${allowed_app}" "${hosts_to_allow}"; then
              hosts_to_allow=""
            fi
          fi
        else
          __eubnt_run_command "ufw --force delete allow ${allowed_app}" "quiet"
        fi
      done
      echo "y" | ufw enable >>"${__script_log}"
      __eubnt_run_command "ufw reload"
      echo
      __eubnt_show_notice "Updated UFW status:"
      echo
      __eubnt_run_command "ufw status verbose" "foreground"
    fi
  fi
  if __eubnt_probe_port "available"; then
    if __eubnt_question_prompt "Do you want to check if TCP ports appear to be accessible?" "return" "n"; then
      local port_list=($(ufw status verbose | grep ".*\/tcp.*ALLOW IN" | sed 's|/.*||'))
      local post_to_probe=""
      __eubnt_run_command "ufw --force disable" "quiet"
      for port_number in "${!port_list[@]}"; do
        port_to_probe="${port_list[$port_number]}"
        __eubnt_probe_port "${port_to_probe}"
      done
      echo "y" | ufw enable >>"${__script_log}"
    fi
  fi
}

### CLI wrapper functions
##############################################################################

# Call the various CLI wrapper functions and exits
function __eubnt_invoke_cli() {
  if [[ -n "${__ubnt_product_command:-}" && -n "${__ubnt_selected_product:-}" ]]; then
    __ubnt_selected_product="$(echo "${__ubnt_selected_product}" | sed 's/-/_/g')"
    __ubnt_product_command="$(echo "${__ubnt_product_command}" | sed 's/-/_/g')"
    # shellcheck disable=SC2086,SC2086
    __eubnt_cli_${__ubnt_selected_product}_${__ubnt_product_command} "${__ubnt_product_version:-}" || true
    exit
  fi
}

# A wrapper function to get the available UniFi SDN Controller version number
function __eubnt_cli_unifi_controller_get_available_version() {
  if ! __eubnt_ubnt_get_product "unifi-controller" "${1:-stable}"; then
    return 1
  fi
}

# A wrapper function to get the available UniFi SDN Controller download URL for given version
function __eubnt_cli_unifi_controller_get_available_download() {
  if ! __eubnt_ubnt_get_product "unifi-controller" "${1:-stable}" "url"; then
    return 1
  fi
}

# A wrapper function to get the installed UniFi SDN Controller version
function __eubnt_cli_unifi_controller_get_installed_version() {
  __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_is_installed:-}" ]]; then
    if echo "${__unifi_controller_package_version:-}"; then
      return 0
    fi
  fi
  return 1
}

### Miscellaneous fixes and things
##############################################################################

# Collection of different fixes to do pre/post
# Try to fix broken installs
# Remove un-needed packages
# Remove cached source list information
# Fix for kernel files filling /boot in Ubuntu
# Fix localhost issue on Ubuntu for sudo use
# Update apt-get and apt-file
function __eubnt_common_fixes {
  if [[ "${1:-}" != "noheader" ]]; then
    __eubnt_show_header "Running common fixes..."
  fi
  __eubnt_run_command "apt-get install --fix-broken --yes"
  __eubnt_run_command "apt-get autoremove --yes"
  __eubnt_run_command "apt-get clean --yes"
  __eubnt_run_command "rm -rf /var/lib/apt/lists/*"
  if [[ ( -n "${__is_ubuntu:-}" || -n "${__is_mint:-}" ) && -d /boot ]]; then
    if ! grep --quiet "127\.0\.1\.1.*{__hostname_local}" /etc/hosts; then
      sed -i "1s/^/127.0.1.1\t${__hostname_local}\n/" /etc/hosts
    fi
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

# Recommended by CrossTalk Solutions (https://crosstalksolutions.com/15-minute-hosted-unifi-controller-setup/)
# Virtual memory tweaks from @adrianmmiller
function __eubnt_setup_swap_file() {
  if __eubnt_run_command "fallocate -l 2G /swapfile"; then
    if __eubnt_run_command "chmod 600 /swapfile"; then
      if __eubnt_run_command "mkswap /swapfile"; then
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
      fi
    fi
  fi
  if [[ $(cat /proc/sys/vm/swappiness) -ne 10 ]]; then
    __eubnt_run_command "sysctl vm.swappiness=10"
  fi
  if [[ $(cat /proc/sys/vm/vfs_cache_pressure) -ne 50 ]]; then
    __eubnt_run_command "sysctl vm.vfs_cache_pressure=50"
  fi
  echo
}

### Tests
##############################################################################

### Execution of script
##############################################################################

ln --force --symbolic "${__script_log}" "${__script_log_dir}/latest.log"
__eubnt_invoke_cli
__eubnt_script_colors
if [[ -z "${__accept_license:-}" ]]; then
  __eubnt_show_header
  __eubnt_show_license
  __eubnt_show_notice "By using this script you agree to the license\\n"
  __eubnt_show_timer "5" "${__colors_notice_text}Thanks for playing! Here we go!${__colors_default}"
  echo
fi
__eubnt_show_header "Checking system..."
__eubnt_install_dependencies
__eubnt_run_command "dig +short ${__ubnt_dl:-}" "quiet"
if ! tail --lines=2 "${__script_log}" | grep --quiet --extended-regexp "${__regex_ip_address}"; then
  __eubnt_show_error "Unable to resolve ${__ubnt_dl} using the following nameservers: ${__nameservers}"
else
  __eubnt_show_success "DNS appears to be working!"
fi
__apparent_public_ip_address="$(wget --quiet --output-document - "sprocket.link/ip" 2>/dev/null)"
if [[ -n "${__apparent_public_ip_address:-}" ]]; then
  __eubnt_show_text "Apparent public IP address is ${__colors_bold_text}${__apparent_public_ip_address}${__colors_default}"
fi
show_disk_free_space="$([[ "${__disk_free_space_gb}" -lt 2 ]] && echo "${__disk_free_space_mb}MB" || echo "${__disk_free_space_gb}GB" )"
__eubnt_show_text "Disk free space is ${__colors_bold_text}${show_disk_free_space}${__colors_default}"
if [[ "${__disk_free_space_gb}" -lt ${__recommended_disk_free_space_gb} ]]; then
  __eubnt_show_warning "Disk free space is below ${__colors_bold_text}${__recommended_disk_free_space_gb}GB${__colors_default}"
else
  if [[ "${__disk_free_space_gb}" -ge $((__recommended_disk_free_space_gb + __recommended_swap_total_gb)) ]]; then
    have_space_for_swap=true
  fi
fi
show_memory_total="$([[ "${__memory_total_gb}" -le 1 ]] && echo "${__memory_total_mb}MB" || echo "${__memory_total_gb}GB" )"
__eubnt_show_text "Memory total size is ${__colors_bold_text}${show_memory_total}${__colors_default}"
if [[ "${__memory_total_gb}" -lt ${__recommended_memory_total_gb} ]]; then
  __eubnt_show_warning "Memory total size is below ${__colors_bold_text}${__recommended_memory_total_gb}GB${__colors_default}"
fi
show_swap_total="$([[ "${__swap_total_gb}" -le 1 ]] && echo "${__swap_total_mb}MB" || echo "${__swap_total_gb}GB" )"
__eubnt_show_text "Swap total size is ${__colors_bold_text}${show_swap_total}${__colors_default}"
if [[ "${__swap_total_mb}" -eq 0 && -n "${have_space_for_swap:-}" ]]; then
  if __eubnt_question_prompt "Do you want to setup a ${__recommended_swap_total_gb}GB swap file?" "return"; then
    __eubnt_setup_swap_file
  fi
fi
if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
  __eubnt_initialize_unifi_controller_variables
  if [[ "${__unifi_controller_package_version:-}" =~ ${__regex_version_full} ]]; then
    __eubnt_show_notice "UniFi SDN Controller ${__unifi_controller_package_version} is installed"
  fi
fi
echo
if [[ -z "${__quick_mode:-}" ]]; then
  __eubnt_show_timer
fi
__eubnt_common_fixes
__eubnt_setup_sources
__eubnt_install_updates
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
if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
  __eubnt_install_unifi_controller || true
fi
__eubnt_setup_ssh_server || true
__eubnt_setup_certbot || true
__eubnt_setup_ufw || true
__eubnt_show_success "\\nDone!\\n"
sleep 3
