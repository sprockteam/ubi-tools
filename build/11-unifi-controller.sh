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
  if [[ -n "${1:-}" ]]; then
    __eubnt_initialize_unifi_controller_variables
    case "${1}" in
      "lts-devices")
        if mongo --quiet --host ${__unifi_controller_mongodb_host} --port ${__unifi_controller_mongodb_port} --eval 'db.getSiblingDB("ace").device.find({model: { $regex: /^U7E$|^U7O$|^U7Ev2$/ }})' | grep --quiet "mac"; then
          return 0
        fi;;
      "reset-password")
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
  __eubnt_show_header "Installing UniFi SDN Controller...\\n"
  local selected_version=""
  local available_version_lts="$(__eubnt_ubnt_get_product "unifi-controller" "lts")"
  local available_version_stable="$(__eubnt_ubnt_get_product "unifi-controller" "stable")"
  local available_version_selected="$(__eubnt_ubnt_get_product "unifi-controller" "${__ubnt_product_version:-}")"
  declare -a versions_to_install=()
  declare -a versions_to_select=()
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    __eubnt_show_notice "Version ${__unifi_controller_package_version} is currently installed"
  fi
  if [[ -n "${__ubnt_product_version:-}" && -n "${available_version_selected:-}" ]]; then
    selected_version="${available_version_selected}"
  elif [[ -n "${__quick_mode:-}" && "${available_version_stable:-}" ]]; then
    selected_version="${available_version_stable}"
  else
    if [[ -n "${available_version_lts:-}" ]]; then
      if __eubnt_version_compare "${__unifi_controller_package_version:-}" "ge" "${available_version_lts}"; then
        versions_to_select+=("${available_version_lts}" "LTS Release (Support for Gen1 AC and PicoM2)")
      fi
    fi
    if [[ -n "${available_version_stable:-}" ]]; then
      if __eubnt_version_compare "${__unifi_controller_package_version:-}" "ge" "${available_version_stable}"; then
        versions_to_select+=("${available_version_stable}" "Current Stable Release")
      fi
    fi
    versions_to_select+=("Custom" "" "Other" "" "Cancel" "")
    __eubnt_show_whiptail "menu" "Which UniFi SDN Controller version do you want to (re)install or upgrade to?" "selected_version" "versions_to_select"
    if [[ "${selected_version}" = "Cancel" ]]; then
      return 1
    fi
    if [[ "${selected_version}" = "Other" ]]; then
      local what_version=""
      while [[ ! $(__eubnt_ubnt_get_product "unifi-controller" "${what_version}") ]]; do
        __eubnt_get_user_input "What other version (i.e. 5.7 or 5.8.30, 5.4 or later) do you want to install?"
      done
      selected_version="$(__eubnt_ubnt_get_product "unifi-controller" "${what_version}")"
    fi
  fi
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    if __eubnt_version_compare "${selected_version}" "eq" "${__unifi_controller_package_version}"; then
      versions_to_install=("${selected_version}")
    elif __eubnt_version_compare "${selected_version}" "eq" "${__unifi_controller_package_version}"; then
      local next_version="${__unifi_controller_package_version}"
      while [[ $(__eubnt_version_compare "${selected_version}" "ge" "${next_version}") ]]; do
        if [[ "${next_version}" ]]; then
          next_version="$(__eubnt_ubnt_get_product "unifi-controller" "latest")"
        fi
      done
    fi
  else
    versions_to_install=("${selected_version}")
  fi
  versions_to_install=($(printf "%s\\n" "${versions_to_install[@]}" | sort --unique --version-sort))
  for version in "${!versions_to_install[@]}"; do
    if ! __eubnt_install_unifi_controller_version "${versions_to_install[$version]}"; then
      return 1
    fi
  done
}

# Installs the latest minor version for the given major UniFi SDN version
# $1: The major version number to install
# TODO: Try to recover if install fails
function __eubnt_install_unifi_controller_version()
{
  if [[ -n "${1:-}" ]]; then
    install_this_version="${1}"
  else
    return 1
  fi
  __eubnt_show_header "Installing UniFi SDN version ${unifi_updated_version}..."
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    __eubnt_show_warning "Make sure you have a backup!"
    __eubnt_question_prompt
  fi
  if [[ "${__unifi_controller_package_version:-}" = "${install_this_version}" ]]; then
    __eubnt_show_notice "UniFi SDN version ${__unifi_controller_package_version} is already installed"
    if ! __eubnt_question_prompt "Do you want to reinstall?" "return" "n"; then
      return 1
    fi
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

### End ###
