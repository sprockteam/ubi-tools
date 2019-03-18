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

### End ###
