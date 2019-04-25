#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2001,SC2034,SC2119,SC2120,SC2143,SC2154,SC2155,SC2207

### Info and Contributors
##############################################################################
# A utility script to easily administer UBNT software
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018-2019 SprockTech, LLC and contributors
__script_title="Easy UBNT"
__script_name="easy-ubnt"
__script_name_short="eubnt"
__script_version="v0.6.2"
__script_full_title="${__script_title} ${__script_version}"
__script_contributors="Klint Van Tassel (SprockTech)
Frank Gabriel (Frankedinven)
Adrian Miller (adrianmmiller)"
__script_mentions="florisvdk, jonbloom, Mattgphoto, samsawyer, SatisfyIT"

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
# Bash Cheatsheet
# https://devhints.io/bash
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
# https://stackoverflow.com/a/13982225 - Do "non-greedy" matching in sed
# https://stackoverflow.com/a/13014199 - Replace or add text in sed
# https://stackoverflow.com/a/22221307 - Extract text between lines using sed
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

# Display basic usage information and exit
function __eubnt_show_help() {
  echo -e "
  Note:
  This script currently requires root access.

  Usage:
  sudo bash ${__script_name}.sh [options]

  Options:
  -a          Accept and skip the license agreement
  -c          Command to issue to product, used with -p
              Currently supported commands:
              'archive_all_alerts'
  -d [arg]    Specify what domain name (FQDN) to use in the script
  -h          Show this help screen
  -i [arg]    Specify a version to install, used with -p
              Examples: '5.9.29', 'stable, '5.7'
  -p [arg]    Specify which UBNT product to administer
              Currently supported products:
              'unifi-controller'
  -u          Skip UFW setup
  -q          Run the script in quick mode, accepting all default answers
  -v          Enable verbose screen output
  -x          Enable script execution tracing\\n"
  exit 1
}

# Root or sudo privilege is needed to install things and make system changes
# TODO: Only run commands as root when needed?
if [[ $(id --user) -ne 0 ]]; then
  __eubnt_show_help
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
__script_test_mode=
__script_error=
__script_is_piped="$(tty --silent && echo -n || echo -n true)"
__script_time="$(date +%s)"
__script_git_url="https://github.com/sprockteam/easy-ubnt.git"
__script_git_branch="master"
__script_git_raw_content="https://github.com/sprockteam/easy-ubnt/raw/${__script_git_branch}"
__script_dir="$(mkdir --parents "/usr/lib/${__script_name}" && echo -n "/usr/lib/${__script_name}" || exit 1)"
__script_file="${__script_name}.sh"
__script_path="${__script_dir}/${__script_file}"
__script_sbin_command="/sbin/${__script_name}"
__script_sbin_command_short="/sbin/${__script_name_short}"
__script_log_dir="$(mkdir --parents "/var/log/${__script_name}" && echo -n "/var/log/${__script_name}" || exit 1)"
__script_log="$(touch "${__script_log_dir}/${__script_time}.log" && echo -n "${__script_log_dir}/${__script_time}.log" || exit 1)"
__script_data_dir="$(mkdir --parents "/var/lib/${__script_name}" && echo -n "/var/lib/${__script_name}" || exit 1)"
__script_temp_dir="$(mktemp --directory)"
__script_real_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__script_tests="${__script_real_path:-}/tests.sh"
ln --force --symbolic "${__script_log}" "${__script_log_dir}/latest.log"

# System variables
__is_cloud_key="$(uname --release | grep --quiet "\-ubnt\-" && echo -n true || echo -n)"
__os_kernel_version="$(uname --release | sed 's/[-][a-z].*//g')"
__os_version="$(lsb_release --release --short)"
__os_version_name="$(lsb_release --codename --short)"
__os_version_major="$(echo -n "${__os_version:-}" | cut --fields 1 --delimiter '.')"
__os_name="$(lsb_release --id --short | sed 's/.*/\l&/g')"
__os_description="$(lsb_release --description --short)"
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
# Default to xenial ¯\_(ツ)_/¯
__ubuntu_version_name_to_use_for_repos="xenial"
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
    fi
  fi
fi

# UBNT variables
__ubnt_dl="dl.ubnt.com"
__ubnt_update_api="https://fw-update.ubnt.com/api/firmware"
declare -A __ubnt_products=(
  ['aircontrol']='airControl Server|ubnt|i386,armhf,arm64,amd64'
  ['unifi-controller']='UniFi Network Controller|ubnt|i386,armhf,arm64,amd64'
  ['unifi-protect']='UniFi Protect|ubnt|i386,armhf,arm64,amd64'
  ['unifi-video']='UniFi Video|ubnt|amd64'
  ['eot-controller']='UniFi EoT (LED) Controller|ubiquiti/eot-controller|amd64,arm64'
  ['ucrm']='Ubiquiti Customer Relationship Management|Ubiquiti-App/UCRM|amd64,arm64'
  ['unms']='Ubiquiti Network Management System|Ubiquiti-App/UNMS|amd64,arm64'
)

# Miscellaneous variables
__apt_sources_dir="/etc/apt/sources.list.d"
__sshd_dir="/etc/ssh"
__sshd_config="${__sshd_dir}/sshd_config"
__sshd_port="$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')"
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
__recommended_nameserver="8.8.8.8"
__ip_lookup_url="sprocket.link/ip"
__github_api_releases_all="https://api.github.com/repos/__/releases"
__github_api_releases_stable="${__github_api_releases_all}/latest"

# Script colors and special text to use
__colors_bold_text="\e[1m"
__colors_warning_text="\e[1;31m"
__colors_error_text="\e[1;31m"
__colors_notice_text="\e[1;36m"
__colors_success_text="\e[1;32m"
__colors_default="\e[0m"
__spinner="-\\|/"
__failed_mark="${__colors_warning_text}x${__colors_default}"
__completed_mark="${__colors_success_text}ok${__colors_default}"

### End ###
