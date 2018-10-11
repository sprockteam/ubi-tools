#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2143
script_version="v0.2.5"
##############################################################################
# Easy UBNT: UniFi Installer                                                 #
##############################################################################
# A guided script to install and upgrade the UniFi Controller
# https://github.com/sprockteam/easy-ubnt
# MIT License
# Copyright (c) 2018 SprockTech, LLC and contributors
##############################################################################
# Copyrights and Mentions                                                    #
##############################################################################
# BASH3 Boilerplate
# https://github.com/kvz/bash3boilerplate
# MIT License
# Copyright (c) 2013 Kevin van Zonneveld and contributors
###
# UniFi Installation Scripts by Glenn Rietveld
###

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
  sleep 2
  exit
fi

# Check if sudo is present and if user is sudoer (root also works)
# All commands are executed with sudo so it can be run by root or any sudoer
clear
if [[ ! "$(command -v sudo)" ]]
then
  echo -e "\\nPlease install sudo and try again\\n"
  sleep 2
  exit
elif [[ "$(command -v sudo)" && "$EUID" -ne 0 ]]
then
  echo -e "\\nYou must have sudo privileges to proceed\\n"
  sudo echo
  clear
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
      break;;
    *)
      break;;
  esac
done

# Setup text colors to use
colors_script_background=$(tput setab 7)
colors_warning_text=$(tput setaf 1)
colors_notice_text=$(tput setaf 4)
colors_script_text=$(tput setaf 0)
colors_default=$(tput sgr0)

function script_colors()
{
  echo "${colors_script_background}${colors_script_text}"
}

function cleanup()
{
  [[ "${restart_ssh_server:-}" ]] && sudo service ssh restart
  [[ "${run_autoremove:-}" ]] && sudo apt-get clean --yes; sudo apt-get autoremove --yes
  sleep 1
  echo "${colors_default}"
  clear
  if [[ -f "/lib/systemd/system/unifi.service" ]]
  then
    echo "Dumping current UniFi Controller status..."
    service unifi status | cat
  else
    echo "The UniFi Controller does not appear to be installed"
  fi
}
trap cleanup EXIT

# Show an error message and exit
function abort()
{
  echo -e "${colors_warning_text}##############################################################################\\n"
  error_message="ERROR!"
  [[ "${1:-}" ]] && error_message+=" ${1}"
  echo -e "${error_message}\\n"
  exit 1
}

# Used to pause and ask if the user wants to continue the script
function question_prompt()
{
  [[ "${1:-}" ]] && question="${1}" || question="Do you want to proceed?"
  read -r -p "${colors_notice_text}${question} (y/n) ${colors_script_text}" yes_no
  case "${yes_no}" in
    [Nn]*)
      echo
      if [[ "${2:-}" == "return" ]]
      then
        return 1
      else
        exit
      fi;;
    *)
      echo
      return 0;;
  esac
}

# Clears the screen and informs the user what task is running
function print_header()
{
  clear
  echo -e "${colors_notice_text}##############################################################################"
  echo -e "# Easy UBNT: UniFi Installer ${script_version}                                          #"
  echo -e "##############################################################################${colors_script_text}\\n"
  [[ "${1:-}" ]] && show_notice "${1}"
}

# Print a notice to the screen
function show_notice()
{
  [[ "${1:-}" ]] && echo -e "${colors_notice_text}${1}${colors_script_text}"
}

# Print a warning to the screen
function show_warning()
{
  [[ "${1:-}" ]] && echo -e "${colors_warning_text}WARNING: ${1}${colors_script_text}"
}

# What UBNT currently recommends
os_bit_recommended="64-bit"
java_version_recommended="8"
java_version_recommended_regx='^8'
mongo_version_recommended="3.4"
mongo_version_recommended_regx='^3\.4'

# UniFi specific variables
unifi_supported_versions=(5.6 5.8 5.9)
unifi_historical_versions=(5.2 5.3 5.4 5.5 5.6 5.8 5.7 5.9)
unifi_repo_source_file="/etc/apt/sources.list.d/100-ubnt-unifi.list"

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

# Change some default OpenSSH server configurations for better security
# https://gist.github.com/nvnmo/91a20f9e72dffb9922a01d499628040f
function setup_ssh_server()
{
  if [[ ! $(dpkg --list | grep "openssh-server") ]]
  then
    echo
    if question_prompt "Do you want to install the OpenSSH server?" "return"
    then
      sudo apt-get install --yes openssh-server
    fi
  fi
  sshd_config="/etc/ssh/sshd_config"
  if [[ $(dpkg --list | grep "openssh-server") && -f "${sshd_config}" ]]
  then
    # Hardening the OpenSSH Server config according to best practices
    # https://linux-audit.com/audit-and-harden-your-ssh-configuration/
    # Using solution for sed to fail if search string not found
    # https://stackoverflow.com/questions/15965073/return-code-of-sed-for-no-match#15966279
    show_notice "\\nChecking OpenSSH server settings for recommended changes...\\n\\nAnswer yes on each unless you know what you are doing..."
    sudo cp "${sshd_config}" "${sshd_config}.bak"
    sleep 1
    if [[ ! $(grep "^Protocol 2" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Use SSH protocol version 2?" "return"
      then
        sudo sed -i 's/^.*Protocol.*$/,${s//Protocol 2/;b};$q1' "${sshd_config}" || echo "Protocol 2" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^PermitRootLogin no" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Disable root login?" "return"
      then
        sudo sed -i 's/^.*PermitRootLogin.*$/,${s//PermitRootLogin no/;b};$q1' "${sshd_config}" || echo "PermitRootLogin no" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^UsePrivilegeSeparation yes" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Use privilege separation?" "return"
      then
        sudo sed -i 's/^.*UsePrivilegeSeparation.*$/,${s//UsePrivilegeSeparation yes/;b};$q1' "${sshd_config}" || echo "UsePrivilegeSeparation yes" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^PermitEmptyPasswords no" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Disallow empty passwords?" "return"
      then
        sudo sed -i 's/^.*PermitEmptyPasswords.*$/,${s//PermitEmptyPasswords no/;b};$q1' "${sshd_config}" || echo "PermitEmptyPasswords no" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^PermitEmptyPasswords no" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Disallow empty passwords?" "return"
      then
        sudo sed -i 's/^.*TCPKeepAlive.*$/,${s//TCPKeepAlive yes/;b};$q1' "${sshd_config}" || echo "PermitEmptyPasswords no" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^X11Forwarding no" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Block X11 forwarding?" "return"
      then
        sudo sed -i 's/^.*X11Forwarding.*$/,${s//X11Forwarding no/;b};$q1' "${sshd_config}" || echo "X11Forwarding no" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^IgnoreRhosts yes" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Ignore rhosts authentication?" "return"
      then
        sudo sed -i 's/^.*IgnoreRhosts.*$/,${s//IgnoreRhosts yes/;b};$q1' "${sshd_config}" || echo "IgnoreRhosts yes" | sudo tee -a "${sshd_config}"
      fi
    fi
    if [[ ! $(grep "^MaxAuthTries 3" "${sshd_config}") ]]
    then
      echo
      if question_prompt "Do you want to limit authentication attempts?" "return"
      then
        sudo sed -i 's/^.*MaxAuthTries.*$/,${s//MaxAuthTries 3/;b};$q1' "${sshd_config}" || echo "MaxAuthTries 3" | sudo tee -a "${sshd_config}"
      fi
    fi
    restart_ssh_server=true
  fi
}

function setup_sources()
{
  # Backup existing source lists
  sudo find /etc/apt/sources.list.d -type f -not -name '*.bak' -exec mv '{}' '{}'.bak \;
  # Fix for stale sources in some cases
  sudo rm -rf /var/lib/apt/lists/*
  sudo apt-get clean --yes
  # Add sources for Java-related packages
  if [[ $is_ubuntu ]]
  then 
    if [[ ! $(sudo apt-cache policy | grep --extended-regexp "archive.ubuntu.com.*${os_version_name_ubuntu}/main") ]]
    then
      echo "deb http://archive.ubuntu.com/ubuntu ${os_version_name_ubuntu} main universe" | sudo tee "/etc/apt/sources.list.d/${os_version_name_ubuntu}-archive.list"
    fi
    if [[ ! $(sudo apt-cache policy | grep --extended-regexp "security.ubuntu.com.*${os_version_name_ubuntu}-security/main") ]]
    then
      echo "deb http://security.ubuntu.com/ubuntu ${os_version_name_ubuntu}-security main universe" | sudo tee "/etc/apt/sources.list.d/${os_version_name_ubuntu}-security.list"
    fi
  fi
  # Use WebUpd8 PPA to get Java 8 on older OS versions
  # https://gist.github.com/pyk/19a619b0763d6de06786
  if [[ "${os_version_name_ubuntu}" != "xenial" && "${os_version_name_ubuntu}" != "bionic" ]]
  then
    echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu ${os_version_name_ubuntu} main" | sudo tee /etc/apt/sources.list.d/webupd8team-java.list
    echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu ${os_version_name_ubuntu} main" | sudo tee -a /etc/apt/sources.list.d/webupd8team-java.list
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
    # Silently accept the license for Java
    # https://askubuntu.com/questions/190582/installing-java-automatically-with-silent-option
    echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections
  fi
  # Setup Mongo package repository
  # Mongo only distributes 64-bit packages
  if [[ $is_64 && $is_ubuntu ]]
  then
    if [[ "${os_version_name}" == "Precise" ]]
    then
      mongo_repo_distro="trusty"
    elif [[ "${os_version_name}" == "Bionic" ]]
    then
      mongo_repo_distro="xenial"
    else
      mongo_repo_distro="${os_version_name_ubuntu}"
    fi
    mongo_repo_url="deb [ arch=amd64 ] http://repo.mongodb.org/apt/ubuntu ${mongo_repo_distro}/mongodb-org/3.4 multiverse"
  fi
  if [[ $is_64 && $is_debian ]]
  then
    # Mongo 3.4 isn't compatible with Wheezy
    if [[ "${os_version_name}" != "Wheezy" ]]
    then
      mongo_repo_url="deb http://repo.mongodb.org/apt/debian jessie/mongodb-org/3.4 main"
    fi
  fi
  if [[ "${mongo_repo_url:-}" ]]
  then
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
    echo "${mongo_repo_url}" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.4.list
  fi
  sudo apt-get update
}

# Installs updates and basic system software
function install_updates_dependencies()
{
  print_header "Checking updates, installing dependencies...\\n"
  sudo apt-get dist-upgrade --yes
  sudo apt-get install --yes software-properties-common
  sudo apt-get install --yes unattended-upgrades
  run_autoremove=true
}

function install_java()
{
  print_header "Installing Java...\\n"
  if [[ "${os_version_name_ubuntu}" == "xenial" || "${os_version_name_ubuntu}" == "bionic" ]]
  then
    sudo apt-get install --yes openjdk-8-jre-headless
  else
    sudo apt-get install --yes oracle-java8-installer
    sudo apt-get install --yes oracle-java8-set-default
  fi
  sudo apt-get install --yes jsvc
  sudo apt-get install --yes libcommons-daemon-java
}

function install_mongo()
{
  # Currently this will only install Mongo 3.4 for 64-bit
  # Skip if 32-bit and go with Mongo 2.6 bundled in the UniFi controller package
  if [[ $is_64 && $mongo_repo_url ]]
  then
    print_header "Installing MongoDB...\\n"
    sudo apt-get install --yes mongodb-org
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
      show_notice "Version ${unifi_version_recommended}.x is recommended\\n"
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
  echo "deb http://www.ubnt.com/downloads/unifi/debian unifi-${unifi_install_this_version} ubiquiti" | sudo tee /etc/apt/sources.list.d/ubnt-unifi.list
  sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 06E85760C0A52C50
  sudo apt-get update
  unifi_updated_version=$(sudo apt-cache policy unifi | grep "Candidate" | awk '{print $2}' | sed 's/-.*//g')
  if [[ "${unifi_version_installed}" == "${unifi_updated_version}" ]]
  then
    show_notice "\\nUniFi ${unifi_version_installed} is already installed\\n"
    sleep 2
    return
  fi
  print_header "Installing UniFi version ${unifi_updated_version}...\\n"
  if [[ $unifi_version_installed ]]
  then
    # TODO: Add API call to make a backup
    show_warning "Make sure you have a backup!\\n"
  fi
  question_prompt
  sudo apt-get install --yes unifi
  script_colors
  # TODO: Add error handling in case install fails
  sleep 1
  sudo tail --follow /var/log/unifi/server.log --lines=50 | while read -r log_line
  do
    if [[ "${log_line}" == *"${unifi_updated_version}"* ]]
    then
      show_notice "\\n${log_line}\\n"
      sudo killall tail
      # sudo pkill --parent $$ tail # This doesn't work as expected
    fi
  done
  sleep 2
}

function setup_ufw()
{
  print_header "Setting up UFW (Uncomplicated Firewall)\\n"
  # Use UFW for basic firewall protection
  # TODO: Get ports from system.properties
  sudo apt-get install --yes ufw
  sudo tee "/etc/ufw/applications.d/unifi" > /dev/null <<EOF
[unifi]
title=UniFi Ports
description=Default ports used by the UniFi Controller
ports=8080,8443,8880,8843,6789/tcp|3478/udp

[unifi-local]
title=UniFi Ports for Local Discovery
description=Ports used for discovery of devices on the local network by the UniFi Controller
ports=1900,10001/udp
EOF
# End of output to file
  echo
  if question_prompt "Do you want to reset your current UFW rules?" "return"
  then
    sudo ufw --force reset
  fi
  sudo ufw allow from any to any app unifi
  if [[ $(dpkg --list | grep "openssh-server") ]]
  then
    sudo ufw allow from any to any app OpenSSH
  fi
  echo
  if question_prompt "Is your controller on your local network?" "return"
  then
    sudo ufw allow from any to any app unifi-local
  else
    sudo ufw delete allow from any to any app unifi-local
  fi
  sudo ufw enable
  sudo ufw reload
}

script_colors

print_header "Checking system...\\n"

# Get architecture and OS information
architecture=$(uname --machine)
os_all_info=$(uname --all)
os_version=$(lsb_release --release --short)

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
  elif [[ $os_version =~ ^10 ]]
  then
    os_version_name="Buster"
    os_version_name_debian="buster"
    os_version_name_ubuntu="bionic"
  else
    abort "${os_name} ${os_version} is not supported"
  fi
  # What UBNT recommends
  os_version_recommended="9 Stretch"
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

if [[ ! $os_version =~ $os_version_recommended_regx ]]
then
  show_warning "UBNT recommends ${os_name} ${os_version_recommended} ${os_bit_recommended}\\n"
fi

if [[ $is_32 ]]
then
  show_warning "Mongo only distributes 64-bit packages\\n"
fi

# Detect if Java is installed and what version
if [[ "$(command -v java)" ]]
then
  # shellcheck disable=SC1117
  java_version_installed=$(sudo dpkg --list | grep --extended-regexp "(jdk|JDK)(.*)?(8)\W" --max-count=1 | awk '{print $3}' | sed 's/-.*//g')
  show_notice "Java ${java_version_installed} is currently installed\\n"
  if [[ ! $java_version_installed =~ $java_version_recommended_regx ]]
  then
    show_warning "UBNT recommends Java ${java_version_recommended}\\n"
  fi
else
  show_notice "Java is not installed\\n"
fi

# Detect if Mongo is installed and what version
if [[ "$(command -v mongo)" ]]
then
  mongo_version_installed=$(dpkg --list | grep --extended-regexp "mongo.*server" | awk '{print $3}' | sed 's/.*://' | sed 's/-.*//g')
fi

if [[ $mongo_version_installed ]]
then
  show_notice "Mongo ${mongo_version_installed} is installed\\n"
  if [[ ! $mongo_version_installed =~ $mongo_version_recommended_regx ]]
  then
    show_warning "UBNT recommends Mongo ${mongo_version_recommended}\\n"
  fi
else
  show_notice "Mongo is not installed\\n"
fi

# Detect if UniFi is installed and what version
if [[ -f "/lib/systemd/system/unifi.service" ]]
then
  unifi_version_installed=$(dpkg --list | grep "unifi" | awk '{print $3}' | sed 's/-.*//g')
  show_notice "UniFi ${unifi_version_installed} is installed\\n"
else
  show_notice "UniFi is not installed\\n"
  if [[ -f "${unifi_repo_source_file}" ]]
  then
    sudo rm ${unifi_repo_source_file}
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

setup_sources
install_updates_dependencies
setup_ssh_server
install_java
install_mongo
install_unifi
setup_ufw
