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
  __unifi_controller_mongodb_post=""
  __unifi_controller_data_version=""
  __unifi_controller_package_version=""
  if __eubnt_is_package_installed "unifi"; then
    __unifi_controller_is_installed=true
    __unifi_controller_package_version=$(dpkg --list "unifi" | awk '/^ii/{print $3}' | sed 's/-.*//')
    __unifi_controller_mongodb_host="localhost"
    __unifi_controller_mongodb_post="27117"
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
            return 0
          fi
        fi
      fi
    fi
  fi
  return 1
}

# Show install/reinstall/update options for UniFi SDN Controller
function __eubnt_install_unifi()
{
  __eubnt_show_header "Installing UniFi SDN Controller...\\n"
  local selected_version=""
  local available_version_lts="$(__eubnt_ubnt_get_product "unifi-controller" "lts")"
  local available_version_stable="$(__eubnt_ubnt_get_product "unifi-controller" "stable")"
  local available_version_beta="$(__eubnt_ubnt_get_product "unifi-controller" "beta")"
  local available_version_candidate="$(__eubnt_ubnt_get_product "unifi-controller" "candidate")"
  local available_version_selected="$(__eubnt_ubnt_get_product "unifi-controller" "${__ubnt_product_version:-}")"
  declare -a unifi_versions_to_install=()
  declare -a unifi_versions_to_select=()
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    __eubnt_show_notice "Version ${__unifi_controller_package_version} is currently installed"
  fi
  if [[ -n "${__ubnt_product_version:-}" ]]; then
    selected_version="$(__eubnt_ubnt_get_product "unifi-controller" "${__ubnt_product_version}")"
    elif [[ -n "${__unifi_controller_version_installed:-}" ]]; then
      selected_version="${__unifi_controller_version_installed:0:3}"
    else
      selected_version="${__unifi_version_stable}"
    fi
  elif [[ -n "${__unifi_controller_version_to_install}" ]]; then
    selected_version="${__unifi_controller_version_to_install}"
  else
    for version in "${!__unifi_supported_versions[@]}"; do
      if [[ -n "${__unifi_controller_version_installed:-}" ]]; then
        if [[ "${__unifi_supported_versions[$version]:0:3}" = "${__unifi_controller_version_installed:0:3}" ]]; then
          if [[ $__unifi_controller_update_available ]]; then
            unifi_versions_to_select+=("${__unifi_controller_update_available}")
          else
            unifi_versions_to_select+=("${__unifi_controller_version_installed}")
          fi
        elif [[ "${__unifi_supported_versions[$version]:2:1}" -gt "${__unifi_controller_version_installed:2:1}" ]]; then
          __eubnt_ubnt_get_product "unifi-controller" "${__unifi_supported_versions[$version]}" "latest_unifi_version"
          unifi_versions_to_select+=("${latest_unifi_version}")
        fi
      else
        __eubnt_get_latest_unifi_version "${__unifi_supported_versions[$version]}" "latest_unifi_version"
        unifi_versions_to_select+=("${latest_unifi_version}")
      fi
    done
    unifi_versions_to_select+=("Cancel")
    __eubnt_show_notice "Which UniFi SDN Controller version do you want to (re)install or upgrade to?\\n"
    select version in "${unifi_versions_to_select[@]}"; do
      if [[ -z "${version:-}" ]]; then
        selected_version="${__unifi_version_stable}"
        break
      elif [[ "${version:-}" = "Cancel" ]]; then
        return 1
      else
        selected_version="${version:0:3}"
        break
      fi
    done
  fi
  if [[ -n "${__unifi_controller_version_installed:-}" ]]; then
    for step in "${!__unifi_historical_versions[@]}"; do
      __eubnt_get_latest_unifi_version "${__unifi_historical_versions[$step]}" "latest_unifi_version"
      if [[ (("${__unifi_historical_versions[$step]:2:1}" -eq "${__unifi_controller_version_installed:2:1}" && "${latest_unifi_version}" != "${__unifi_controller_version_installed}") || "${__unifi_historical_versions[$step]:2:1}" -gt "${__unifi_controller_version_installed:2:1}") && "${__unifi_historical_versions[$step]:2:1}" -le "${selected_version:2:1}" ]]; then
        unifi_versions_to_install+=("${__unifi_historical_versions[$step]}")
     fi
    done
    if [[ "${#unifi_versions_to_install[@]}" -eq 0 ]]; then
      unifi_versions_to_install=("${__unifi_controller_version_installed:0:3}")
    fi
  else
    unifi_versions_to_install=("${selected_version}")
  fi
  for version in "${!unifi_versions_to_install[@]}"; do
    if ! __eubnt_install_unifi_version "${unifi_versions_to_install[$version]}"; then
      return 1
    fi
  done
  if ! __eubnt_question_prompt "Do you want to return to the main menu?" "return" "n"; then
    exit
  fi
}

# Show install/reinstall/update options for UniFi SDN
function __eubnt_install_unifi()
{
  __eubnt_show_header "Installing UniFi SDN Controller...\\n"
  local selected_version=
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
      selected_version="${__unifi_version_installed:0:3}"
    else
      selected_version="${__unifi_version_stable}"
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
          selected_version="${__unifi_version_stable}"
          break;;
        *)
          if [[ "${version}" = "Skip" ]]; then
            return 0
          fi
          selected_version="${version:0:3}"
          break;;
      esac
    done
  fi
  if [[ -n "${__unifi_version_installed:-}" ]]; then
    for step in "${!unifi_historical_versions[@]}"; do
      __eubnt_get_latest_unifi_version "${unifi_historical_versions[$step]}" "latest_unifi_version"
      if [[ (("${unifi_historical_versions[$step]:2:1}" -eq "${__unifi_version_installed:2:1}" && "${latest_unifi_version}" != "${__unifi_version_installed}") || "${unifi_historical_versions[$step]:2:1}" -gt "${__unifi_version_installed:2:1}") && "${unifi_historical_versions[$step]:2:1}" -le "${selected_version:2:1}" ]]; then
        unifi_versions_to_install+=("${unifi_historical_versions[$step]}")
     fi
    done
    if [[ "${#unifi_versions_to_install[@]}" -eq 0 ]]; then
      unifi_versions_to_install=("${__unifi_version_installed:0:3}")
    fi
  else
    unifi_versions_to_install=("${selected_version}")
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
    __eubnt_question_prompt
  fi
  local release_notes=
  if __eubnt_ubnt_get_release_notes "${unifi_updated_version}" "release_notes"; then
    if __eubnt_question_prompt "Do you want to view the release notes?" "return" "n"; then
      more "${release_notes}"
      __eubnt_question_prompt
    fi
  fi
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    __eubnt_run_command "service unifi restart"
  fi
  echo "unifi unifi/has_backup boolean true" | debconf-set-selections
  if DEBIAN_FRONTEND=noninteractive apt-get install --yes unifi; then
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
    if [[ -n "${__unifi_version_installed:-}" ]]; then
      if __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${__unifi_version_installed:0:3}"; then
        __eubnt_run_command "apt-get update" "quiet"
      fi
    fi
  fi
}

# Show install/reinstall/update options for UniFi SDN
function __eubnt_unifi_controller_install()
{
  __eubnt_show_header "Installing UniFi SDN Controller...\\n"
  local selected_version=
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
      selected_version="${__unifi_version_installed:0:3}"
    else
      selected_version="${__unifi_version_stable}"
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
          selected_version="${__unifi_version_stable}"
          break;;
        *)
          if [[ "${version}" = "Skip" ]]; then
            return 0
          fi
          selected_version="${version:0:3}"
          break;;
      esac
    done
  fi
  if [[ -n "${__unifi_version_installed:-}" ]]; then
    for step in "${!unifi_historical_versions[@]}"; do
      __eubnt_get_latest_unifi_version "${unifi_historical_versions[$step]}" "latest_unifi_version"
      if [[ (("${unifi_historical_versions[$step]:2:1}" -eq "${__unifi_version_installed:2:1}" && "${latest_unifi_version}" != "${__unifi_version_installed}") || "${unifi_historical_versions[$step]:2:1}" -gt "${__unifi_version_installed:2:1}") && "${unifi_historical_versions[$step]:2:1}" -le "${selected_version:2:1}" ]]; then
        unifi_versions_to_install+=("${unifi_historical_versions[$step]}")
     fi
    done
    if [[ "${#unifi_versions_to_install[@]}" -eq 0 ]]; then
      unifi_versions_to_install=("${__unifi_version_installed:0:3}")
    fi
  else
    unifi_versions_to_install=("${selected_version}")
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
    __eubnt_question_prompt
  fi
  local release_notes=
  if __eubnt_get_unifi_release_notes "${unifi_updated_version}" "release_notes"; then
    if __eubnt_question_prompt "Do you want to view the release notes?" "return" "n"; then
      more "${release_notes}"
      __eubnt_question_prompt
    fi
  fi
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    __eubnt_run_command "service unifi restart"
  fi
  echo "unifi unifi/has_backup boolean true" | debconf-set-selections
  if DEBIAN_FRONTEND=noninteractive apt-get install --yes unifi; then
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
    if [[ -n "${__unifi_version_installed:-}" ]]; then
      if __eubnt_add_source "http://www.ubnt.com/downloads/unifi/debian unifi-${__unifi_version_installed:0:3} ubiquiti" "100-ubnt-unifi.list" "www\\.ubnt\\.com.*unifi-${__unifi_version_installed:0:3}"; then
        __eubnt_run_command "apt-get update" "quiet"
      fi
    fi
  fi
}

### End ###
