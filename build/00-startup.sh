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
# Glenn Rietveld (AmazedMender16)
# https://glennr.nl
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

# Root or sudo privilege is needed to install things and make system changes
# TODO: Only run commands as root when needed?
if [[ $(id --user) -ne 0 ]]; then
  echo -e "\\nStartup failed! Please run this script as root or use sudo\\n"
  exit 1
fi

# As of now, this script is designed to run on Debian-based distributions
if ! command -v apt-get &>/dev/null; then
  echo -e "\\nStartup failed! Please run this on a Debian-based distribution\\n"
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
__regex_number='^[0-9]+$'
__regex_version_major_minor='^[0-9]+\.[0-9]+$'
__regex_version_full='^[0-9]+\.[0-9]+\.[0-9]+$'
__regex_version_java8='^8u[0-9]{1,3}$'
__regex_version_mongodb3_4='^(2\.(4\.[0-9]{2}|[5-9]\.[0-9]{1,2}|[0-9]{2}\.[0-9]{1,2}))|(^3\.[0-4]\.[0-9]{1,2})$'
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

### End ###
