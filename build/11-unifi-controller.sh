### UniFi Network Controller functions
##############################################################################

# Return a service port from the UniFi Network Controller properties
# $1: The port setting name to check
function __eubnt_unifi_controller_get_port() {
  if [[ -z "${1:-}" ]]; then
    return 0
  fi
  if [[ -z "${__unifi_controller_has_data:-}" ]]; then
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
    # shellcheck disable=SC2076,SC2199
    if [[ " ${port_settings[@]} " =~ " ${1} " ]]; then
      grep "${1}" "${__unifi_controller_system_properties}" 2>/dev/null | tail --lines 1 | sed 's/.*=//g' || true
    fi
  fi
}

# This will initialize all variables related to UniFi Network Controller functions
# TODO: Make more of these dynamic
# $1: If set to "skip_ports" then don't initialize port variables
function __eubnt_initialize_unifi_controller_variables() {
  __unifi_controller_is_installed=
  __unifi_controller_is_running=
  __unifi_controller_has_data=
  __unifi_controller_limited_to_lts=
  __unifi_controller_data_dir=""
  __unifi_controller_log_dir=""
  __unifi_controller_system_properties=""
  __unifi_controller_mongodb_host=""
  __unifi_controller_mongodb_port=""
  __unifi_controller_mongodb_ace=""
  __unifi_controller_mongodb_ace_stat=""
  __unifi_controller_data_version=""
  __unifi_controller_package_version=""
  if __eubnt_is_package_installed "unifi"; then
    __unifi_controller_package_version=$(dpkg --list "unifi" | awk '/^ii/{print $3}' | sed 's/-.*//')
    __unifi_controller_service="/lib/systemd/system/unifi.service"
    if [[ "${__unifi_controller_package_version:-}" =~ ${__regex_version_full} ]]; then
      __unifi_controller_is_installed=true
      __eubnt_add_to_log "UniFi Network Controller ${__unifi_controller_package_version} is installed"
      if [[ -f "${__unifi_controller_service}" ]] && __eubnt_run_command "service unifi start" "quiet"; then
        __unifi_controller_is_running=true
        __eubnt_add_to_log "UniFi Network Controller ${__unifi_controller_package_version} is running"
        local unifi_service=""
        __eubnt_run_command "pgrep java --list-full" "quiet" "unifi_service" || true
        __unifi_controller_data_dir="$(echo "${unifi_service:-}" | tail --lines=1 | sed -e 's|.* -Dunifi.datadir=||; s| .*||')"
        __unifi_controller_log_dir="$(echo "${unifi_service:-}"| tail --lines=1 | sed -e 's|.* -Dunifi.logdir=||; s| .*||')"
        if [[ ! -d "${__unifi_controller_data_dir:-}" ]]; then
          __unifi_controller_data_dir="/var/lib/unifi"
        fi
        if [[ ! -d "${__unifi_controller_log_dir:-}" ]]; then
          __unifi_controller_log_dir="/var/log/unifi"
        fi
        if [[ -d "${__unifi_controller_log_dir:-}" ]]; then
          if [[ -d "${__unifi_controller_data_dir:-}" ]]; then
            __unifi_controller_data_version="$(cat "${__unifi_controller_data_dir}/db/version" 2>/dev/null)"
            if [[ "${__unifi_controller_data_version:-}" =~ ${__regex_version_full} ]]; then
              __unifi_controller_system_properties="${__unifi_controller_data_dir}/system.properties"
              if [[ -f "${__unifi_controller_system_properties:-}" ]]; then
                if [[ -f "${__unifi_controller_data_dir}/db/mongod.lock" ]]; then
                  local unifi_mongod=""
                  __eubnt_run_command "pgrep mongod --list-full" "quiet" "unifi_mongod" || true
                  __unifi_controller_mongodb_port="$(echo "${unifi_mongod:-}" | tail --lines=1 | sed -e 's|.*--port ||; s| --.*||')"
                  if ! __eubnt_is_port_in_use "${__unifi_controller_mongodb_port:-}"; then
                    __unifi_controller_mongodb_port="27117"
                  fi
                  if __eubnt_is_port_in_use "${__unifi_controller_mongodb_port:-}" && [[ -f "${__unifi_controller_data_dir}/db/mongod.lock" ]]; then
                    __eubnt_add_to_log "UniFi Network Controller ${__unifi_controller_package_version} has data loaded"
                    __unifi_controller_mongodb_host="localhost"
                    __unifi_controller_mongodb_ace="ace"
                    __unifi_controller_mongodb_ace_stat="ace_stat"
                    __unifi_controller_has_data=true
                    # shellcheck disable=SC2016,SC2086
                    if mongo --quiet --host ${__unifi_controller_mongodb_host} --port ${__unifi_controller_mongodb_port} ${__unifi_controller_mongodb_ace} --eval 'db.device.find({model: { $regex: /^U7E$|^U7O$|^U7Ev2$/ }})' | grep --quiet "adopted\" : true"; then
                      __unifi_controller_limited_to_lts=true
                    fi
                  else
                    __eubnt_add_to_log "UniFi Network Controller does not appear to have any data loaded"
                  fi
                fi
              fi
            fi
          fi
        fi
      else
        __eubnt_add_to_log "UniFi Network Controller ${__unifi_controller_package_version} is not running"
      fi
    fi
  else
    __eubnt_add_to_log "UniFi Network Controller does not appear to be installed"
  fi
  if [[ -n "${__unifi_controller_has_data:-}" && "${1:-}" != "skip_ports" ]]; then
    __unifi_controller_local_udp_port_discoverable_controller="1900"
    __unifi_controller_local_udp_port_ap_discovery="10001"
    __unifi_controller_port_tcp_inform="$(__eubnt_unifi_controller_get_port "unifi.http.port")"
    __unifi_controller_port_tcp_admin="$(__eubnt_unifi_controller_get_port "unifi.https.port")"
    __unifi_controller_port_tcp_portal_http="$(__eubnt_unifi_controller_get_port "portal.http.port")"
    __unifi_controller_port_tcp_portal_https="$(__eubnt_unifi_controller_get_port "portal.https.port")"
    __unifi_controller_port_tcp_throughput=$(__eubnt_unifi_controller_get_port "unifi.throughput.port")
    __unifi_controller_port_udp_stun=$(__eubnt_unifi_controller_get_port "unifi.stun.port")
  fi
  return 0
}

# Perform various checks to see if the UniFi Network Controller is running
# $1: Optionally set this to "continuous" to keep checking until it's running
function __eubnt_is_unifi_controller_running() {
  local counter=0
  while true; do
    __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_is_installed:-}" && -n "${__unifi_controller_is_running:-}" && -n "${__unifi_controller_has_data:-}" ]]; then
    if __eubnt_is_port_in_use "${__unifi_controller_port_tcp_inform:-8080}" "tcp" "java" "${1:-}"; then
      if __eubnt_is_port_in_use "${__unifi_controller_port_tcp_admin:-8443}" "tcp" "java" "${1:-}"; then
        return 0
      else
        if [[ "${1:-}" != "continuous" || "${counter:-}" -gt 600 ]]; then
          return 1
        fi
        sleep 1
        (( counter++ ))
      fi
    fi
  fi
  done
}

# Various evaluations to use with MongoDB related to the UniFi Network Controller
# $1: Specify which "eval" command to issue
#     "lts-devices" will check if devices are in the database that are only supported by LTS
function __eubnt_unifi_controller_mongodb_eval() {
  if [[ -n "${1:-}" ]] && __eubnt_is_command "mongo"; then
    __eubnt_initialize_unifi_controller_variables
    case "${1}" in
      "lts-devices")
        if [[ -n "${__unifi_controller_limited_to_lts:-}" ]]; then
          return 0
        fi;;
      "reset-password")
        # shellcheck disable=SC2016,SC2086
        if mongo --quiet --host ${__unifi_controller_mongodb_host:-} --port ${__unifi_controller_mongodb_port:-} --eval 'db.admin.update( { "name" : "alkadgalkga" }, { $set : { "x_shadow" : "$6$9Ter1EZ9$lSt6/tkoPguHqsDK0mXmUsZ1WE2qCM4m9AQ.x9/eVNJxws.hAxt2Pe8oA9TFB7LPBgzaHBcAfKFoLpRQlpBiX1" } } )' | grep --quiet "nModified\" : 1"; then
          return 0
        fi;;
    esac
  fi
  return 1
}

# Show install/reinstall/update options for UniFi Network Controller
function __eubnt_install_unifi_controller()
{
  __eubnt_show_header "Installing UniFi Network Controller...\\n"
  local selected_version=""
  local available_version_lts="$(__eubnt_ubnt_get_product "unifi-controller" "5.6" | tail --lines=1)"
  local available_version_stable="$(__eubnt_ubnt_get_product "unifi-controller" "stable" | tail --lines=1)"
  if [[ -n "${__ubnt_product_version:-}" ]]; then
    local available_version_selected="$(__eubnt_ubnt_get_product "unifi-controller" "${__ubnt_product_version}" | tail --lines=1)"
  fi
  declare -a versions_to_install=()
  declare -a versions_to_select=()
  local get_ubnt_url=
  __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    versions_to_select+=("${__unifi_controller_package_version}" "   Reinstall this version")
    if __eubnt_version_compare "${__unifi_controller_package_version}" "gt" "${available_version_stable}"; then
      get_ubnt_url=true
    fi
  fi
  if [[ -n "${__ubnt_product_version:-}" && -n "${available_version_selected:-}" ]]; then
    selected_version="${available_version_selected}"
  elif [[ -n "${__quick_mode:-}" && -z "${__unifi_controller_package_version:-}" && -n "${available_version_stable:-}" ]]; then
    selected_version="${available_version_stable}"
  elif [[ -n "${__quick_mode:-}" && -n "${__unifi_controller_package_version:-}" ]]; then
    return 1
  else
    local add_lts_version=
    local add_stable_version=
    if [[ "${available_version_lts:-}" =~ ${__regex_version_full} ]]; then
      if [[ -z "${__unifi_controller_package_version:-}" ]] || __eubnt_version_compare "${available_version_lts}" "gt" "${__unifi_controller_package_version:-}"; then
        add_lts_version=true
      fi
    fi
    if [[ "${available_version_stable:-}" =~ ${__regex_version_full} ]]; then
      if [[ -z "${__unifi_controller_package_version:-}" ]] || __eubnt_version_compare "${available_version_stable}" "gt" "${__unifi_controller_package_version:-}"; then
        if [[ -z "${__unifi_controller_limited_to_lts:-}" ]]; then
          add_stable_version=true
        fi
      fi
    fi
    if [[ -n "${add_stable_version:-}" ]]; then
      versions_to_select+=("${available_version_stable}" "   Latest public stable release")
    fi
    if [[ -n "${add_lts_version:-}" ]]; then
      versions_to_select+=("${available_version_lts}" "   LTS release for Gen1 AC and PicoM2")
    fi
    versions_to_select+=("Other" "   Enter a version number" "Beta" "   Enter a beta or unstable URL")
    selected_version="$(__eubnt_show_whiptail "menu" "UniFi Network Controller" "versions_to_select")"
    if [[ -z "${selected_version:-}" || "${selected_version:-}" = "Cancel" ]]; then
      return 1
    fi
    if [[ "${selected_version}" = "Other" ]]; then
      get_ubnt_url=
      local what_other_version=""
      while [[ ! "${selected_version:-}" =~ ${__regex_version_full} ]]; do
        __eubnt_show_header "Installing UniFi Network Controller...\\n"
        what_other_version=""
        __eubnt_get_user_input "What version (i.e. 5.7 or 5.8.30) do you want to install?" "what_other_version" "optional"
        if [[ -z "${what_other_version:-}" ]]; then
          echo
          if ! __eubnt_question_prompt "Do you want to continue installation?" "return" "n"; then
            return 1
          else
            continue
          fi
        else
          if [[ "${what_other_version:-}" =~ ${__regex_version_full} || "${what_other_version:-}" =~ ${__regex_version_major_minor} ]]; then
            selected_version="$(__eubnt_ubnt_get_product "unifi-controller" "${what_other_version}" | tail --lines=1 || true)"
            if [[ ! "${selected_version:-}" =~ ${__regex_version_full} ]]; then
              echo
              if ! __eubnt_question_prompt "Version ${what_other_version} isn't available, do you want to try another?"; then
                return 1
              else
                continue
              fi
            else
              break
            fi
          else
            echo
            if ! __eubnt_question_prompt "Version ${what_other_version} is invalid, do you want to try another?"; then
              return 1
            else
              continue
            fi
          fi
        fi
      done
    fi
    if [[ "${selected_version}" = "Beta" || -n "${get_ubnt_url:-}" ]]; then
      local what_ubnt_url=""
      while [[ ! "${selected_version:-}" =~ ${__regex_url_ubnt_deb} ]]; do
        __eubnt_show_header "Installing UniFi Network Controller...\\n"
        what_ubnt_url=""
        __eubnt_get_user_input "Please enter a package URL to download and install?" "what_ubnt_url" "optional"
        if [[ -z "${what_ubnt_url:-}" ]]; then
          echo
          if ! __eubnt_question_prompt "Do you want to continue installation?" "return" "n"; then
            return 1
          else
            continue
          fi
        else
          if [[ "${what_ubnt_url:-}" =~ ${__regex_url_ubnt_deb} ]] && wget --quiet --spider "${what_ubnt_url}"; then
              selected_version="${what_ubnt_url}"
          else
            echo
            if ! __eubnt_question_prompt "The URL is inaccessible or invalid, do you want to try another?"; then
              return 1
            else
              continue
            fi
          fi
        fi
      done
    fi
  fi
  if [[ -n "${__unifi_controller_package_version:-}" ]]; then
    if [[ "${selected_version:-}" =~ ${__regex_version_full} ]] && __eubnt_version_compare "${selected_version}" "gt" "${__unifi_controller_package_version}"; then
      local version_upgrade="$(__eubnt_ubnt_get_product "unifi-controller" "$(echo "${__unifi_controller_package_version}" | tail --lines=1 | cut --fields 1-2 --delimiter '.')")"
      if __eubnt_version_compare "${version_upgrade}" "gt" "${__unifi_controller_package_version}"; then
        versions_to_install+=("${version_upgrade}|$(__eubnt_ubnt_get_product "unifi-controller" "${version_upgrade}" "url" | tail --lines=1)")
      fi
    fi
  fi
  if [[ "${selected_version:-}" =~ ${__regex_url_ubnt_deb} ]]; then
    versions_to_install+=("$(__eubnt_extract_version_from_url "${selected_version}")|${selected_version}")
  elif [[ "${selected_version:-}" =~ ${__regex_version_full} ]]; then
    versions_to_install+=("${selected_version}|$(__eubnt_ubnt_get_product "unifi-controller" "${selected_version}" "url" | tail --lines=1)")
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

# Installs the UniFi Network Controller based on a version number and download URL
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
  __eubnt_show_header "Installing UniFi Network Controller ${install_this_version:-}..."
  __eubnt_initialize_unifi_controller_variables
  if [[ "${__unifi_controller_data_version:-}" =~ ${__regex_version_full} ]]; then
    __eubnt_show_warning "Make sure you have a backup!\\n"
    __eubnt_question_prompt || return 1
  fi
  if __eubnt_version_compare "${__unifi_controller_package_version:-}" "eq" "${install_this_version:-}"; then
    __eubnt_show_notice "UniFi Network Controller ${install_this_version} is already installed...\\n"
    __eubnt_question_prompt "Are you sure you want to reinstall?" "return" "n" || return 1
  elif __eubnt_version_compare "${__unifi_controller_package_version:-}" "gt" "${install_this_version:-}"; then
    __eubnt_show_warning "UniFi Network Controller ${install_this_version} is a previous version...\\n"
    if __eubnt_question_prompt "Do you want to purge all data and downgrade?" "return" "n"; then
      echo
      if ! DEBIAN_FRONTEND=noninteractive dpkg --purge --force-all unifi; then
        return 1
      fi
    else
      return 1
    fi
  fi
  __eubnt_show_header "Installing UniFi Network Controller ${install_this_version:-}...\\n"
  local release_notes=
  if __eubnt_ubnt_get_release_notes "${install_this_version}" "release_notes"; then
    if __eubnt_question_prompt "Do you want to view the release notes?" "return" "n"; then
      echo
      more "${release_notes}"
      __eubnt_question_prompt || return 1
    fi
  fi
  __eubnt_show_header "Installing UniFi Network Controller ${install_this_version:-}...\\n"
  if [[ -f "/lib/systemd/system/unifi.service" ]]; then
    if __eubnt_run_command "service unifi restart"; then
      __eubnt_show_text "Waiting for UniFi Network Controller to finish restarting...\\n"
      __eubnt_is_unifi_controller_running "continuous"
    fi
  fi
  __eubnt_show_header "Installing UniFi Network Controller ${install_this_version:-}...\\n"
  local unifi_deb_file=""
  if __eubnt_download_ubnt_deb "${install_this_url}" "unifi_deb_file"; then
    if [[ -f "${unifi_deb_file}" ]]; then
      echo
      if __eubnt_install_package "binutils"; then
        if __eubnt_install_java "noheader"; then
          if __eubnt_install_mongodb "noheader"; then
            echo "unifi unifi/has_backup boolean true" | debconf-set-selections
            __eubnt_show_text "Installing $(basename "${unifi_deb_file}")"
            if DEBIAN_FRONTEND=noninteractive dpkg --install --force-all "${unifi_deb_file}"; then
              __eubnt_show_success "Installation complete! Waiting for UniFi Network Controller to finish loading..."
              if ! __eubnt_is_unifi_controller_running "continuous"; then
                return 1
              fi
            fi
          fi
        fi
      fi
    fi
  fi
}

### End ###
