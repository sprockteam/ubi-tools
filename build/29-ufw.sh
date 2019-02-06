### Setup UFW
##############################################################################

# Install and setup UFW
# Adds an app profile that includes all UniFi SDN ports to allow for easy rule management in UFW
# Checks if ports appear to be open/accessible from the Internet
function __eubnt_setup_ufw() {
  __eubnt_show_header "Setting up UFW (Uncomplicated Firewall)...\\n"
  if [[ ! $(dpkg --list "ufw" | grep "^i") || ( $(command -v ufw) && $(ufw status | grep "inactive") ) ]]; then
    if ! __eubnt_question_prompt "Do you want to use UFW?" "return"; then
      return 0
    fi
  fi
  __eubnt_install_package "ufw"
  if [[ -f "${__sshd_config}" ]]; then
    ssh_port=$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')
  fi
  if [[ -n "${unifi_tcp_port_inform:-}" && -n "${unifi_tcp_port_admin:-}" && -n "${unifi_tcp_port_http_portal:-}" && -n "${unifi_tcp_port_https_portal:-}" && -n "${unifi_tcp_port_throughput:-}" && -n "${unifi_udp_port_stun:-}" ]]; then
    tee "/etc/ufw/applications.d/unifi" &>/dev/null <<EOF
[unifi]
title=UniFi SDN Ports
description=Default ports used by the UniFi SDN Controller
ports=${unifi_tcp_port_inform},${unifi_tcp_port_admin},${unifi_tcp_port_http_portal},${unifi_tcp_port_https_portal},${unifi_tcp_port_throughput}/tcp|${unifi_udp_port_stun}/udp

[unifi-local]
title=UniFi SDN Ports for Local Discovery
description=Ports used for discovery of devices on the local network by the UniFi SDN Controller
ports=${unifi_local_udp_port_discoverable_controller},${unifi_local_udp_port_ap_discovery}/udp
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
  if __eubnt_question_prompt "Do you want to check if inbound UniFi SDN ports appear to be open?" "return"; then
    if ufw status | grep --quiet " active"; then
      __eubnt_run_command "ufw disable"
    fi
    __eubnt_show_text "Checking if port probing service is available"
    local port_probe_url=$(wget --quiet --output-document - "https://www.grc.com/x/portprobe=80" | grep --quiet "World Wide Web HTTP" && echo "https://www.grc.com/x/portprobe=")
    if [[ -n "${port_probe_url:-}" ]]; then
      if [[ -n "${ssh_port:-}" ]]; then
        local unifi_tcp_port_ssh="${ssh_port}"
      fi
      local port_to_probe=
      for var_name in ${!unifi_tcp_port_*}; do
        port_to_probe="${!var_name}"
        __eubnt_show_text "Checking port ${port_to_probe}"
        if ! wget -q -O- "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
          echo
          __eubnt_show_warning "It doesn't look like port ${port_to_probe} is open! Check your upstream firewall.\\n"
          if __eubnt_question_prompt "Do you want to check port ${port_to_probe} again?" "return"; then
            if ! wget -q -O- "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
              echo
              __eubnt_show_warning "Port ${port_to_probe} is still not open!\\n"
              if ! __eubnt_question_prompt "Do you want to proceed anyway?" "return"; then
                return 0
              fi
            else
              __eubnt_show_success "\\nPort ${port_to_probe} is open!\\n"
            fi
          fi
        else
          __eubnt_show_success "\\nPort ${port_to_probe} is open!\\n"
        fi
      done
    else
      __eubnt_show_notice "\\nPort probing service is unavailable, try again later."
    fi
  fi
  if [[ -n "${ssh_port:-}" ]]; then
    if __eubnt_question_prompt "Do you want to allow access to SSH from any host?" "return"; then
      __eubnt_run_command "ufw allow ${ssh_port}/tcp"
    else
      __eubnt_run_command "ufw --force delete allow ${ssh_port}/tcp" "quiet"
    fi
    echo
  fi
  if [[ "${unifi_tcp_port_inform:-}" && "${unifi_tcp_port_admin:-}" ]]; then
    __unifi_tcp_port_admin="${unifi_tcp_port_admin}"
    if __eubnt_question_prompt "Do you want to allow access to the UniFi SDN ports from any host?" "return"; then
      __eubnt_run_command "ufw allow from any to any app unifi"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app unifi" "quiet"
    fi
    echo
    if __eubnt_question_prompt "Will this controller discover devices on it's local network?" "return" "n"; then
      __eubnt_run_command "ufw allow from any to any app unifi-local"
    else
      __eubnt_run_command "ufw --force delete allow from any to any app unifi-local" "quiet"
    fi
    echo
  else
    __eubnt_show_warning "Unable to determine UniFi SDN ports to allow. Is it installed?\\n"
  fi
  echo "y" | ufw enable >>"${__script_log}"
  __eubnt_run_command "ufw reload"
  __eubnt_show_notice "\\nUpdated UFW status:\\n"
  __eubnt_run_command "ufw status" "foreground"
  sleep 1
}

### End ###
