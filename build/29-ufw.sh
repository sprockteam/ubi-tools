### Setup UFW
##############################################################################

# Install and setup UFW
# Adds an app profile that includes all UniFi SDN ports to allow for easy rule management in UFW
# Checks if ports appear to be open/accessible from the Internet
function __eubnt_setup_ufw() {
  __eubnt_show_header "Setting up UFW (Uncomplicated Firewall)...\\n"
  if [[ ! $(dpkg --list "ufw" | grep "^i") || ( $(command -v ufw) && $(ufw status | grep "inactive") ) ]]; then
    if ! __eubnt_question_prompt "Do you want to use UFW?" "return"; then
      return 1
    fi
  fi
  __eubnt_install_package "ufw"
  local ssh_port="22"
  local have_unifi_ports=
  if [[ -f "${__sshd_config}" ]]; then
    ssh_port=$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')
    __eubnt_run_command "sed -i 's|^ports=.*$|ports=${ssh_port}/tcp|' /etc/ufw/applications.d/openssh-server" "quiet"
  fi
  __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_port_tcp_inform:-}" \
     && -n "${__unifi_controller_port_tcp_admin:-}" \
     && -n "${__unifi_controller_port_tcp_portal_http:-}" \
     && -n "${__unifi_controller_port_tcp_portal_https:-}" \
     && -n "${__unifi_controller_port_tcp_throughput:-}" \
     && -n "${__unifi_controller_port_udp_stun:-}" ]]; then
    have_unifi_ports=true
    tee "/etc/ufw/applications.d/unifi-controller" &>/dev/null <<EOF
[UniFi_Controller]
title=UniFi SDN Controller Ports
description=Default ports used by the UniFi SDN Controller
ports=${__unifi_controller_port_tcp_inform},${__unifi_controller_port_tcp_admin},${__unifi_controller_port_tcp_portal_http},${__unifi_controller_port_tcp_portal_https},${__unifi_controller_port_tcp_throughput}/tcp|${__unifi_controller_port_udp_stun}/udp

[UniFi_Controller_Local_Discovery]
title=UniFi SDN Controller Ports for Local Discovery
description=Ports used for discovery of devices on the local network by the UniFi SDN Controller
ports=${__unifi_controller_local_udp_port_discoverable_controller},${__unifi_controller_local_udp_port_ap_discovery}/udp
EOF
# End of output to file
  fi
  __eubnt_show_notice "\\nCurrent UFW status:\\n"
  __eubnt_run_command "ufw status" "foreground"
  echo
  if ufw status | grep --quiet " active"; then
    if ! __eubnt_question_prompt "Do you want to make changes to your UFW rules?" "return" "n"; then
      return 0
    fi
  fi
  if __eubnt_question_prompt "Do you want to reset your current UFW rules?" "return" "n"; then
    __eubnt_run_command "ufw --force reset"
    echo
  fi
  if [[ -n "${ssh_port:-}" ]]; then
    if __eubnt_question_prompt "Do you want to allow access to SSH from any host?" "return"; then
      __eubnt_run_command "ufw allow OpenSSH"
    else
      __eubnt_run_command "ufw --force delete allow OpenSSH" "quiet"
    fi
    echo
  fi
  if [[ -n "${have_unifi_ports:-}" ]]; then
    if __eubnt_question_prompt "Do you want to allow access to the UniFi SDN ports from any host?" "return"; then
      __eubnt_run_command "ufw allow from any to any app UniFi_Controller"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app UniFi_Controller" "quiet"
    fi
    echo
    if __eubnt_question_prompt "Will this controller discover devices on it's local network?" "return" "n"; then
      __eubnt_run_command "ufw allow from any to any app UniFi_Controller_Local_Discovery"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app UniFi_Controller_Local_Discovery" "quiet"
    fi
    echo
  else
    __eubnt_show_warning "Unable to find configured UniFi SDN Controller ports. Is it installed?\\n"
  fi
  echo "y" | ufw enable >>"${__script_log}"
  __eubnt_run_command "ufw reload"
  __eubnt_show_notice "\\nUpdated UFW status:\\n"
  __eubnt_run_command "ufw status" "foreground"
  if __eubnt_question_prompt "Do you want to check if ingress TCP ports appear to be accessible?" "return"; then
    if __eubnt_probe_port "check"; then
      local port_to_probe=""
      for var_name in ${!__unifi_controller_port_tcp_*}; do
        port_to_probe="${!var_name}"
        __eubnt_probe_port "${port_to_probe}" "skip"
      done
    fi
  fi
  sleep 1
}

### End ###
