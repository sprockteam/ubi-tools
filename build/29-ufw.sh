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
# Adds an app profile that includes all UniFi Network ports to allow for easy rule management in UFW
# Checks if ports appear to be open/accessible from the Internet
function __eubnt_setup_ufw() {
  if [[ -n "${__ufw_disable:-}" ]]; then
    if __eubnt_is_command "ufw"; then
      __eubnt_run_command "ufw --force disable" || true
    fi
    return 1
  fi
  __eubnt_show_header "Setting up UFW (Uncomplicated Firewall)..."
  if ! __eubnt_is_package_installed "ufw"; then
    if __eubnt_question_prompt "Do you want to install UFW?"; then
      __eubnt_install_package "ufw"
    else
      return 1
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
      apps_to_allow+=("UniFi-Network")
      tee "/etc/ufw/applications.d/unifi-controller" &>/dev/null <<EOF
[UniFi-Network-Inform]
title=UniFi Network Controller Inform
description=TCP port required to allow devices to communicate with the controller
ports=${__unifi_controller_port_tcp_inform}/tcp

[UniFi-Network-STUN]
title=UniFi Network Controller STUN
description=UDP port required to allow the controller to communicate back to devices
ports=${__unifi_controller_port_udp_stun}/udp

[UniFi-Network-Admin]
title=UniFi Network Controller Admin
description=TCP port required for controller administration
ports=${__unifi_controller_port_tcp_admin}/tcp

[UniFi-Network-Speed]
title=UniFi Network Controller Speed
description=TCP port used to test throughput from the mobile app to the controller
ports=${__unifi_controller_port_tcp_throughput}/tcp

[UniFi-Network-Portal]
title=UniFi Network Controller Portal Access
description=TCP ports used to allow for guest portal access
ports=${__unifi_controller_port_tcp_portal_http},${__unifi_controller_port_tcp_portal_https}/tcp

[UniFi-Network-Local]
title=UniFi Network Controller Local Discovery
description=UDP ports used for discovery of devices on the local (layer 2) network, not recommended for cloud controllers
ports=${__unifi_controller_local_udp_port_discoverable_controller},${__unifi_controller_local_udp_port_ap_discovery}/udp
EOF
# End of output to file
    fi
  fi
  __eubnt_show_notice "Current UFW status:"
  echo
  __eubnt_run_command "ufw app update all" "quiet" || true
  __eubnt_run_command "ufw status verbose" "foreground" || true
  if ! ufw status | grep --quiet " active"; then
    echo
  fi
  if [[ ${#apps_to_allow[@]} -gt 0 ]]; then
    if __eubnt_question_prompt "Do you want to setup or make changes to UFW now?"; then
      if ufw status | grep --quiet " active"; then
        echo
        if __eubnt_question_prompt "Do you want to reset your current UFW rules?"; then
          echo
          __eubnt_run_command "ufw --force reset" || true
        fi
      fi
      local activate_ufw=
      local hosts_to_allow=""
      local allow_access="n"
      local apps_to_check="$(IFS=$'|'; echo "${apps_to_allow[*]}")"
      declare -a app_list=($(ufw app list | grep --extended-regexp "${apps_to_check}" | awk '{print $1}'))
      for app_name in "${!app_list[@]}"; do
        allowed_app="${app_list[$app_name]}"
        if [[ "${allowed_app}" = "UniFi-Network-Local" ]]; then
          allow_access="n"
        else
          allow_access="y"
        fi
        echo
        __eubnt_run_command "ufw app info ${allowed_app}" "foreground" || true
        echo
        if __eubnt_question_prompt "Do you want to allow access to these ports?" "return" "${allow_access:-n}"; then
          hosts_to_allow=""
          activate_ufw=true
          if [[ -z "${__quick_mode:-}" ]]; then
            echo
            __eubnt_get_user_input "IP(s) to allow, separated by commas, default is 'any': " "hosts_to_allow" "optional"
            echo
          fi
          if [[ -z "${hosts_to_allow:-}" ]]; then
            if ! __eubnt_run_command "ufw allow from any to any app ${allowed_app}"; then
              __eubnt_show_warning "Unable to allow app ${allowed_app:-}"
            fi
          else
            if __eubnt_allow_hosts_ufw_app "${allowed_app}" "${hosts_to_allow}"; then
              hosts_to_allow=""
            fi
          fi
        else
          __eubnt_run_command "ufw --force delete allow ${allowed_app}" "quiet" || true
        fi
      done
      if [[ -n "${activate_ufw:-}" ]]; then
        echo
        echo "y" | ufw enable >>"${__script_log}"
        __eubnt_run_command "ufw reload" || true
      fi
      __eubnt_show_notice "Updated UFW status:"
      echo
      __eubnt_run_command "ufw status verbose" "foreground" || true
    else
      echo
    fi
  fi
  if ufw status | grep --quiet " active"; then
    if __eubnt_question_prompt "Do you want to check if TCP ports appear to be accessible?" "return" "n"; then
      if __eubnt_probe_port "available"; then
        local port_list=($(ufw status verbose | grep --invert-match "(v6)" | grep ".*\/tcp.*ALLOW IN" | sed 's|/.*||' | tr ',' '\n' | sort --unique))
        local post_to_probe=""
        __eubnt_run_command "ufw --force disable" "quiet" || true
        for port_number in "${!port_list[@]}"; do
          port_to_probe="${port_list[$port_number]}"
          __eubnt_probe_port "${port_to_probe}"
        done
        echo "y" | ufw enable >>"${__script_log}"
      else
        __eubnt_show_warning "Port probing service is unavailable!"
      fi
    fi
  fi
}

### End ###
