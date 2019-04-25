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
# $1: Optionally setup sources for "mongodb", "java", "nodejs", "certbot"
function __eubnt_setup_sources() {
  local do_apt_update=
  __eubnt_install_package "software-properties-common"
  if [[ -n "${__is_ubuntu:-}" || -n "${__is_mint:-}" ]]; then
    local kernel_mirror_repo="ubuntu"
    if [[ -n "${__is_mint:-}" ]]; then
      kernel_mirror_repo="linuxmint-packages"
    fi
    __eubnt_add_source "http://archive.ubuntu.com/ubuntu ${__os_version_name} main universe" "${__os_version_name}-archive.list" "archive\\.ubuntu\\.com.*${__os_version_name}.*main" && do_apt_update=true
    __eubnt_add_source "http://security.ubuntu.com/ubuntu ${__os_version_name}-security main universe" "${__os_version_name}-security.list" "security\\.ubuntu\\.com.*${__os_version_name}-security main" && do_apt_update=true
    __eubnt_add_source "http://security.ubuntu.com/ubuntu ${__ubuntu_version_name_to_use_for_repos}-security main universe" "${__ubuntu_version_name_to_use_for_repos}-security.list" "security\\.ubuntu\\.com.*${__ubuntu_version_name_to_use_for_repos}-security main" && do_apt_update=true
    __eubnt_add_source "http://mirrors.kernel.org/${kernel_mirror_repo} ${__os_version_name} main universe" "${__os_version_name}-mirror.list" "mirrors\\.kernel\\.org.*${__os_version_name}.*main" && do_apt_update=true
  elif [[ -n "${__is_debian:-}" ]]; then
    __eubnt_install_package "dirmngr" || true
    __eubnt_add_source "http://ftp.debian.org/debian ${__os_version_name}-backports main" "${__os_version_name}-backports.list" "ftp\\.debian\\.org.*${__os_version_name}-backports.*main" && do_apt_update=true
    __eubnt_add_source "http://mirrors.kernel.org/debian ${__os_version_name} main" "${__os_version_name}-mirror.list" "mirrors\\.kernel\\.org.*${__os_version_name}.*main" && do_apt_update=true
  fi
  if [[ -n "${do_apt_update:-}" ]]; then
    if __eubnt_run_command "apt-get update"; then
      do_apt_update=
    fi
  fi
  if [[ "${1:-}" = "mongodb" ]]; then
    local distro_mongodb_installable_version="$(apt-cache madison mongodb | sort --version-sort | tail --lines=1 | awk '{print $3}' | sed 's/.*://; s/[-+].*//;')"
    if __eubnt_version_compare "${distro_mongodb_installable_version}" "gt" "${__version_mongodb3_4}"; then
      local official_mongodb_repo_url=""
      if [[ -n "${__is_64:-}" && ( -n "${__is_ubuntu:-}" || -n "${__is_mint:-}" ) ]]; then
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
  elif [[ "${1:-}" = "java" ]]; then
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
    __eubnt_run_command "apt-get update" || true
  fi
}

# Install package upgrades through apt-get dist-upgrade
# Ask if packages critical to UniFi Network Controller function should be updated or not
function __eubnt_install_updates() {
  __eubnt_show_header "Installing updates...\\n"
  local updates_available=""
  __eubnt_run_command "apt-get update" || true
  __eubnt_run_command "apt-get dist-upgrade --simulate" "quiet" "updates_available"
  updates_available="$(echo "${updates_available}" | grep --count "^Inst " || updates_available=0)"
  if [[ "${updates_available:-}" -gt 0 ]]; then
    echo
    if __eubnt_question_prompt "Install available package upgrades?"; then
      echo
      __eubnt_install_package "unattended-upgrades" || true
      if __eubnt_run_command "apt-get dist-upgrade --yes"; then
        __run_autoremove=true
      fi
    fi
  fi
}

# Try to install OpenJDK Java 8
# Use haveged for better entropy generation from @ssawyer
# https://community.ubnt.com/t5/UniFi-Wireless/unifi-controller-Linux-Install-Issues/m-p/1324455/highlight/true#M116452
function __eubnt_install_java() {
  if [[ "${1:-}" != "noheader" ]]; then
    __eubnt_show_header "Installing Java...\\n"
  fi
  __eubnt_setup_sources "java"
  local target_release=""
  if [[ "${__os_version_name}" = "jessie" ]]; then
    target_release="${__os_version_name}-backports"
  fi
  if __eubnt_install_package "ca-certificates-java" "${target_release:-}"; then
    if ! __eubnt_install_package "openjdk-8-jre-headless" "${target_release:-}"; then
      __eubnt_show_warning "Unable to install OpenJDK Java 8 at $(caller)"
      return 1
    fi
  fi
  if [[ "${1:-}" != "noheader" ]]; then
    __eubnt_show_header "Checking extra Java-related packages...\\n"
  fi
  if __eubnt_run_command "update-alternatives --list java" "quiet"; then
    __eubnt_install_package "jsvc" || true
    __eubnt_install_package "libcommons-daemon-java" || true
    __eubnt_install_package "haveged" || true
  fi
}

# Set default Java alternative
# $1: The Java package to set as the default
function __eubnt_set_java_alternative() {
  true
}

# Install MongoDB
function __eubnt_install_mongodb()
{
  if [[ "${1:-}" != "noheader" ]]; then
    __eubnt_show_header "Installing MongoDB...\\n"
  fi
  __eubnt_setup_sources "mongodb"
  if ! __eubnt_install_package "${__install_mongodb_package:-mongodb}"; then
    __eubnt_show_warning "Unable to install MongoDB at $(caller)"
    return 1
  fi
}

# Install script dependencies
function __eubnt_install_dependencies()
{
  __eubnt_install_package "apt-transport-https"
  __eubnt_install_package "sudo" || true
  __eubnt_install_package "curl" || true
  __eubnt_install_package "net-tools" || true
  __eubnt_install_package "dnsutils" || true
  __eubnt_install_package "psmisc" || true
  __eubnt_install_package "jq"
}

### End ###
