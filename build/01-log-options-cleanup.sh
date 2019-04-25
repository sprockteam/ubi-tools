### Logging functions
##############################################################################

# Add to the script log file
# $1: The message to log
function __eubnt_add_to_log() {
  if [[ -n "${1:-}" && -f "${__script_log:-}" ]]; then
    echo "${1}" | sed -r 's/\\e\[[^m]*m//g; s/\\n/ /g; s/\\r/ /g' &>>"${__script_log}"
  fi
}

# Echo to the screen and log file
# $1: The message to echo
# $2: Optional file to pipe echo output to
# $3: If set to "append" then the message is appended to file specified in $2
function __eubnt_echo_and_log() {
  if [[ -n "${1:-}" ]]; then
    if [[ -n "${2:-}" ]]; then
      if [[ ! -f "${2}" ]]; then
        if ! touch "${2}"; then
          __eubnt_show_warning "Unable to create ${2} at $(caller)"
          return
        fi
      fi
      if [[ "${3:-}" = "append" ]]; then
        echo "${1}" >>"${2}"
      else
        echo "${1}" >"${2}"
      fi
    else
      echo -e -n "${1}"
    fi
    __eubnt_add_to_log "${1}"
  fi
}

### Parse commandline options
##############################################################################

# Basic way to get command line options
# TODO: Incorporate B3BP methods here for long options
while getopts ":c:d:f:i:p:ahqtvx" options; do
  case "${options}" in
    a)
      __accept_license=true
      __eubnt_add_to_log "Command line option: accepted license";;
    c)
      if [[ -n "${OPTARG:-}" ]]; then
        __ubnt_product_command="${OPTARG}"
      else
        __eubnt_show_help
      fi;;
    d)
      if [[ -n "${OPTARG:-}" ]]; then
        __hostname_fqdn="${OPTARG}"
        __eubnt_add_to_log "Command line option: specified domain name ${__hostname_fqdn}"
      else
        __eubnt_show_help
      fi;;
    f)
      if [[ -n "${OPTARG:-}" && "${OPTARG:-}" = "off" ]]; then
        __ufw_disable=true
        __eubnt_add_to_log "Command line option: disable firewall"
      fi;;
    h|\?)
      __eubnt_show_help;;
    i)
      if [[ -n "${OPTARG:-}" && ( "${OPTARG:-}" = "stable" || \
         ( "${OPTARG:-}" =~ ${__regex_version_full} || "${OPTARG:-}" =~ ${__regex_version_major_minor} ) ) ]]; then
        __ubnt_product_version="${OPTARG}"
        __eubnt_add_to_log "Command line option: specified UBNT product version ${__ubnt_product_version}"
      else
        __eubnt_show_help
      fi;;
    p)
      if [[ -n "${OPTARG:-}" ]]; then
        if [[ "${OPTARG}" = "unifi-sdn" || "${OPTARG}" = "unifi-network" ]]; then
          __ubnt_selected_product="unifi-controller"
        else
          for product in "${!__ubnt_products[@]}"; do
            if [[ "${OPTARG}" = "${product}" ]]; then
              __ubnt_selected_product="${OPTARG}"
              break
            fi
          done
        fi
      fi
      if [[ -n "${__ubnt_selected_product:-}" ]]; then
        __eubnt_add_to_log "Command line option: selected UBNT product ${__ubnt_selected_product}"
      else
        __eubnt_show_help
      fi;;
    q)
      __quick_mode=true
      __eubnt_add_to_log "Command line option: enabled quick mode";;
    t)
      __script_test_mode=true
      __eubnt_add_to_log "Command line option: running in test mode";;
    v)
      __verbose_output=true
      __eubnt_add_to_log "Command line option: enabled verbose mode";;
    x)
      set -o xtrace
      set +o errexit
      __script_debug=true
      __eubnt_add_to_log "Command line option: enabled xtrace debugging";;
    *)
      break;;
  esac
done
if [[ ( -n "${__ubnt_product_version:-}" || -n "${__ubnt_product_command:-}" ) && -z "${__ubnt_selected_product:-}" ]]; then
  __eubnt_show_help
fi
if [[ -z "${__ubnt_selected_product:-}" ]]; then
  __ubnt_selected_product="unifi-controller"
  __eubnt_add_to_log "Default option: selected UBNT product ${__ubnt_selected_product}"
fi

### Error/cleanup handling
##############################################################################

# Run miscellaneous tasks before exiting
# Auto clean and remove un-needed apt-get info/packages
# Restart services if needed
# Cleanup script logs
# Reboot system if needed
# Unset global script variables
function __eubnt_cleanup_before_exit() {
  if [[ -z "${__script_test_mode:-}" && -z "${__script_error:-}" ]]; then
    set +o xtrace
  fi
  if [[ -z "${__ubnt_product_command:-}" ]]; then
    local clearscreen=""
    if [[ -n "${__script_error:-}" || -n "${__script_test_mode:-}" ]]; then
      clearscreen="noclear"
    fi
    __eubnt_show_header "Cleaning up script, please wait...\\n" "${clearscreen:-}"
  fi
  echo -e "${__colors_default:-}"
  if [[ -n "${__run_autoremove:-}" ]]; then
    __eubnt_run_command "apt-get autoremove --yes" || true
    __eubnt_run_command "apt-get autoclean --yes" || true
  fi
  if [[ -n "${__restart_ssh_server:-}" ]]; then
    if __eubnt_run_command "service ssh restart"; then
      __eubnt_show_warning "The SSH service has been reloaded with a new configuration!\\n"
      if __eubnt_question_prompt "Do you want to verify the SSH config?" "return" "n"; then
        __sshd_port="$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')"
        __eubnt_show_notice "Try to connect a new SSH session on port ${__sshd_port:-22}...\\n"
        if ! __eubnt_question_prompt "Were you able to connect successfully?"; then
          __eubnt_show_notice "Undoing SSH config changes...\\n"
          cp "${__sshd_config}.bak-${__script_time}" "${__sshd_config}"
          __sshd_port="$(grep "Port" "${__sshd_config}" --max-count=1 | awk '{print $NF}')"
          if [[ -f "/etc/ufw/applications.d/openssh-server" ]]; then
            sed -i "s|^ports=.*|ports=${__sshd_port}/tcp|" "/etc/ufw/applications.d/openssh-server"
          fi
          __eubnt_run_command "service ssh restart" "quiet" || true
        fi
      fi
    fi
    echo
  fi
  if [[ -d "${__sshd_dir:-}" ]]; then
    local ssh_backups_to_delete="$(find "${__sshd_config}.bak"* -maxdepth 1 -type f -print0 | xargs -0 --exit ls -t | awk 'NR>2')"
    if [[ -n "${ssh_backups_to_delete:-}" ]]; then
      echo "${ssh_backups_to_delete}" | xargs --max-lines=1 rm
    fi
  fi
  if [[ -d "${__script_log_dir:-}" ]]; then
    local log_files_to_delete="$(find "${__script_log_dir}" -maxdepth 1 -type f -print0 | xargs -0 --exit ls -t | awk 'NR>10')"
    if [[ -n "${log_files_to_delete:-}" ]]; then
      echo "${log_files_to_delete}" | xargs --max-lines=1 rm
    fi
  fi
  if [[ -d "${__script_temp_dir:-}" ]]; then
    rm --recursive --force "${__script_temp_dir}"
  fi
  if [[ -n "${__reboot_system:-}" ]]; then
    shutdown -r now
  fi
  __eubnt_add_to_log "Dumping variables to log..."
  for var_name in ${!__*}; do
    if [[ -n "${!var_name:-}" && "${var_name}" != "__script_contributors" ]]; then
      __eubnt_add_to_log "${var_name}=${!var_name}"
    fi
    if [[ "${var_name}" != "__script_log" ]]; then
      unset -v "${var_name}"
    fi
  done
  unset -v IFS
  unset -v __script_log
  echo -e "Done!\\n"
}
trap '__eubnt_cleanup_before_exit' EXIT

### End ###
