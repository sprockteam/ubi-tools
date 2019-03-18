### Setup OpenSSH
##############################################################################

# Install OpenSSH server and harden the configuration
###
# Hardening the OpenSSH Server config according to best practices (https://gist.github.com/nvnmo/91a20f9e72dffb9922a01d499628040f | https://linux-audit.com/audit-and-harden-your-ssh-configuration/)
# De-duplicate SSH config file (https://stackoverflow.com/a/1444448)
function __eubnt_setup_ssh_server() {
  __eubnt_show_header "Setting up OpenSSH Server..."
  if ! __eubnt_is_package_installed "openssh-server"; then
    echo
    if __eubnt_question_prompt "Do you want to install the OpenSSH server?" "return"; then
      __eubnt_run_command "apt-get install --yes openssh-server"
    fi
  fi
  if [[ $(dpkg --list | grep "openssh-server") && -f "${__sshd_config}" ]]; then
    cp "${__sshd_config}" "${__sshd_config}.bak-${__script_time}"
    __eubnt_show_notice "Checking OpenSSH server settings for recommended changes..."
    echo
    if [[ $(grep ".*Port 22$" "${__sshd_config}") || ! $(grep ".*Port.*" "${__sshd_config}") ]]; then
      if __eubnt_question_prompt "Change SSH port from the default 22?" "return" "n"; then
        local ssh_port=""
        while [[ ! $ssh_port =~ ^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$ ]]; do
          read -r -p "Port number: " ssh_port
        done
        if grep --quiet ".*Port.*" "${__sshd_config}"; then
          sed -i "s/^.*Port.*$/Port ${ssh_port}/" "${__sshd_config}"
        else
          echo "Port ${ssh_port}" | tee -a "${__sshd_config}"
        fi
        __restart_ssh_server=true
      fi
    fi
    declare -A ssh_changes=(
      ['Protocol 2']='Use SSH protocol version 2 (recommended)?'
      ['UsePrivilegeSeparation yes']='Enable privilege separation (recommended)?'
      ['StrictModes yes']='Enforce strict security checks for SSH server (recommended)?'
      ['PermitEmptyPasswords no']='Disallow empty passwords (recommended)?'
      ['PermitRootLogin no']='Disallow root user to log into SSH (optional)?'
      ['IgnoreRhosts yes']='Disable legacy rhosts authentication (recommended)?'
      ['MaxAuthTries 5']='Limit authentication attempts to 5 (recommended)?'
      #['TCPKeepAlive yes']='Enable TCP keep alive (optional)?'
    )
    for recommended_setting in "${!ssh_changes[@]}"; do
      if [[ "${recommended_setting}" = "PermitRootLogin no" && -z "${__is_user_sudo:-}" ]]; then
        continue
      fi
      if ! grep --quiet "^${recommended_setting}" "${__sshd_config}"; then
        setting_name=$(echo "${recommended_setting}" | awk '{print $1}')
        echo
        if __eubnt_question_prompt "${ssh_changes[$recommended_setting]}" "return"; then
          if grep --quiet ".*${setting_name}.*" "${__sshd_config}"; then
            sed -i "s/^.*${setting_name}.*$/${recommended_setting}/" "${__sshd_config}"
          else
            echo "${recommended_setting}" | tee -a "${__sshd_config}"
          fi
          __restart_ssh_server=true
        fi
      fi
    done
    awk '!seen[$0]++' "${__sshd_config}" &>/dev/null
  fi
}

### End ###
