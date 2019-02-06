### Task and command functions
##############################################################################

# Check if something is a valid command on the system
# $1: A string with a command to check
function __eubnt_is_command() {
  if command -v "${1:-}" &>/dev/null; then
    return 0
  fi
  return 1
}

# Check if a given port is in use
# $1: The port number to check
# $2: The protocol to check, default is "tcp" but could be set to "udp"
# $3: Optionally specify a process to check
# $4: If set to "continuous" then run netstat in continuous mode until listening port is found
function __eubnt_is_port_in_use() {
  if [[ -n "${1:-}" ]]; then
    port_to_check="${1}"
    protocol_to_check="tcp"
    process_to_check=""
    if [[ -n "${2:-}" && "${2}" = "udp" ]]; then
      protocol_to_check="udp"
    fi
    if [[ -n "${3:-}" ]]; then
      if __eubnt_is_command "${3}"; then
        process_to_check=".*${3}"
      fi
    fi
    grep_check="^${protocol_to_check}.*:${port_to_check} ${process_to_check}"
    if [[ "${4:-}" = "continuous" ]]; then
      if netstat --listening --numeric --programs --${protocol_to_check} --continous | grep --line-buffer --quiet "${grep_check}"; then
        return 0
      fi
    else
      if netstat --listening --numeric --programs --${protocol_to_check} | grep --quiet "${grep_check}"; then
        return 0
      fi
    fi
  fi
  return 1
}

# Try to check if a given TCP port is open and accessible from the Internet
# $1: The TCP port number to check
# $2: If set to "return" then return a status code
function __eubnt_probe_port() {
  if [[ -n "${1:-}" ]]; then
    local port_to_probe="${1}"
  else
    __eubnt_show_warning "No port given at $(caller)"
    return 1
  fi
  local return_code=0
  __eubnt_show_text "Checking if port probing service is available"
  local port_probe_url=$(wget --quiet --output-document - "https://www.grc.com/x/portprobe=80" | grep --quiet "World Wide Web HTTP" && echo "https://www.grc.com/x/portprobe=")
  if [[ -z "${port_probe_url:-}" ]]; then
    __eubnt_show_notice "Port probing service is unavailable, try again later."
    return_code=2
  else
    if ! __eubnt_is_port_in_use "${port_to_probe}"; then
      "${full_command[@]}" &>>"${command_output}" &
      listener_pid=$!
      local break_probe_loop=
      while [[ -z "${break_probe_loop:-}" ]]; do
        __eubnt_show_text "Checking port ${port_to_probe}"
        if ! wget --quiet -output-document - "${port_probe_url}${port_to_probe}" | grep --quiet "OPEN!"; then
          __eubnt_show_warning "It doesn't look like port ${port_to_probe} is open! Check your upstream firewall.\\n"
          if ! __eubnt_question_prompt "Do you want to check port ${port_to_probe} again?" "return"; then
            break_probe_loop=true
          fi
        else
          __eubnt_show_success "Port ${port_to_probe} is open!"
          break_probe_loop=true
        fi
      done
    fi
  fi
  if [[ "${2:-}" = "return" ]]; then
    return ${return_code}
  fi
}

# A wrapper to run commands, display a nice message and handle errors gracefully
# Make sure the command seems valid
# Run the command in the background and show a spinner
# Run the command in the foreground when in verbose mode
# Wait for the command to finish and get the exit code
# $1: The full command to run as a string
# $2: If set to "foreground" then the command will run in the foreground
#     If set to "quiet" the output will be directed to the log file
#     If set to "return" then output will be assigned to variable named in $3
# $3: Name of variable to assign output value of the command if $2 is set to "return"
function __eubnt_run_command() {
  if [[ -z "${1:-}" ]]; then
    __eubnt_show_warning "No command given at $(caller)"
    return 1
  fi
  local background_pid=""
  local command_output=""
  local command_return=""
  declare -a full_command=()
  IFS=' ' read -r -a full_command <<< "${1}"
  if ! __eubnt_is_command "${full_command[0]}"; then
    local found_package=
    local unknown_command="${full_command[0]}"
    __eubnt_install_package "apt-file"
    __eubnt_run_command "apt-file update"
    __eubnt_run_command "apt-file --package-only --regexp search .*bin\\/${unknown_command}$" "return" "found_package"
    if [[ -n "${found_package:-}" ]]; then
      if ! __eubnt_install_package "${found_package}"; then
        __eubnt_show_error "Unable to install package ${found_package} to get command ${unknown_command} at $(caller)"
      fi
    else
      __eubnt_show_error "Unknown command ${unknown_command} at $(caller)"
    fi
  fi
  if [[ "${full_command[0]}" != "echo" ]]; then
    __eubnt_add_to_log "${1}"
  fi
  if [[ ( -n "${__verbose_output:-}" && "${2:-}" != "quiet" ) || "${2:-}" = "foreground" || "${full_command[0]}" = "echo" ]]; then
    "${full_command[@]}" | tee -a "${__script_log}"
    command_return=$?
  elif [[ "${2:-}" = "quiet" ]]; then
    "${full_command[@]}" &>>"${__script_log}" || __eubnt_add_to_log "Error returned running ${1} at $(caller)"
    command_return=$?
  elif [[ "${2:-}" = "return" ]]; then
    command_output="$(mktemp)"
    "${full_command[@]}" &>>"${command_output}" &
    background_pid=$!
  else
    "${full_command[@]}" &>>"${__script_log}" &
    background_pid=$!
  fi
  if [[ -n "${background_pid:-}" ]]; then
    local i=0
    while [[ -d /proc/$background_pid ]]; do
      echo -e -n "\\rRunning ${1} [${__spinner:i++%${#__spinner}:1}]"
      sleep 0.5
      if [[ $i -gt 360 ]]; then
        break
      fi
    done
    wait $background_pid
    command_return=$?
    if [[ ${command_return} -gt 0 ]]; then
      __eubnt_echo_and_log "\\rRunning ${1} [${__failed_mark}]\\n"
    else
      __eubnt_echo_and_log "\\rRunning ${1} [${__completed_mark}]\\n"
    fi
  fi
  if [[ "${2:-}" = "return" && -n "${3:-}" && -e "${command_output:-}" && -s "${command_output:-}" && ${command_return} -eq 0 ]]; then
    # shellcheck disable=SC2086
    eval "${3}=\"$(cat ${command_output})\""
    rm "${command_output}"
  fi
  if [[ ${command_return} -gt 0 ]]; then
    return 1
  fi
}

# Install package if needed and handle errors gracefully
# $1: The name of the package to install
# $2: An optional target release to use
# $3: If set to "return" then return a status
function __eubnt_install_package() {
  if [[ "${1:-}" ]]; then
    if __eubnt_is_package_installed "${1}"; then
      if [[ "${3:-}" != "reinstall" ]]; then
        __eubnt_echo_and_log "Package ${1} already installed [\\xE2\\x9C\\x93]"
        echo
        return 0
      fi
    fi
    if ! __eubnt_is_package_installed "${1}"; then
      if [[ $? -gt 1 ]]; then
        __eubnt_run_command "dpkg --remove --force-all ${1}"
        __eubnt_common_fixes
      fi
    fi
    if ! __eubnt_run_command "apt-get install --simulate ${1}" "quiet"; then
      __eubnt_setup_sources
      __eubnt_common_fixes
    fi
    if __eubnt_run_command "apt-get install --simulate ${1}" "quiet"; then
      local i=0
      while lsof /var/lib/dpkg/lock &>/dev/null; do
        echo -e -n "\\rWaiting for package manager to become available... [${__spinner:i++%${#__spinner}:1}]"
        sleep 0.5
      done
      __eubnt_echo_and_log "\\rWaiting for package manager to become available... [\\xE2\\x9C\\x93]"
      echo
      if [[ -n "${2:-}" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install --quiet --no-install-recommends --yes --target-release "${2}" "${1}" &>>"${__script_log}" &
        background_pid=$!
      else
        DEBIAN_FRONTEND=noninteractive apt-get install --quiet --no-install-recommends --yes "${1}" &>>"${__script_log}" &
        background_pid=$!
      fi
      if [[ -n "${background_pid:-}" ]]; then
        local i=0
        while [[ -d /proc/$background_pid ]]; do
          echo -e -n "\\rInstalling package ${1} [${__spinner:i++%${#__spinner}:1}]"
          sleep 0.5
          if [[ $i -gt 360 ]]; then
            break
          fi
        done
        wait $background_pid
        command_return=$?
        if [[ "${command_return:-}" -gt 0 ]]; then
          __eubnt_echo_and_log "\\rInstalling package ${1} [x]"
          echo
          if [[ "${3:-}" = "return" ]]; then
            return 1
          fi
        else
          __eubnt_echo_and_log "\\rInstalling package ${1} [\\xE2\\x9C\\x93]"
          echo
        fi
      fi
    else
      __eubnt_show_error "Unable to install package ${1} at $(caller)"
      if [[ "${3:-}" = "return" ]]; then
        return 1
      fi
    fi
  fi
}

# Check if is package is installed
# $1: The name of the package to check
function __eubnt_is_package_installed() {
  if [[ -n "${1:-}" ]]; then
    local package_name=$(echo "${1}" | sed 's/=.*//')
    if dpkg --list "${package_name}" 2>/dev/null | grep --quiet "^ii.* ${package_name} "; then
      return 0
    elif dpkg --list "${package_name}" 2>/dev/null | grep --quiet "^i[^i].* ${package_name}"; then
      return 2
    fi
  fi
  return 1
}

# Add a source list to the system if needed
# $1: The source information to use
# $2: The name of the source list file to make on the local machine
# $3: A search term to use when checking if the source list should be added
function __eubnt_add_source() {
  if [[ "${1:-}" && "${2:-}" && "${3:-}" ]]; then
    if [[ ! $(find /etc/apt -name "*.list" -exec grep "${3}" {} \;) ]]; then
      if [[ -d "${__apt_sources_dir:-}" ]]; then
        __eubnt_echo_and_log "deb ${1}" "${__apt_sources_dir}/${2}"
        return 0
      fi
    else
      __eubnt_add_to_log "Skipping add source for ${1}"
      return 0
    fi
  fi
  return 1
}

# Add a package signing key to the system if needed
# $1: The 32-bit hex fingerprint of the key to add
function __eubnt_add_key() {
  if [[ -n "${1:-}" ]]; then
    if ! apt-key list 2>/dev/null | grep --quiet "${1:0:4}.*${1:4:4}"; then
      if ! __eubnt_run_command "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key ${1}"; then
        __eubnt_show_warning "Unable to add key ${1} at $(caller)"
        return 1
      fi
    else
      __eubnt_add_to_log "Skipping add key for ${1}"
      return 0
    fi
  else
    __eubnt_show_warning "No key fingerprint was given at $(caller)"
    return 1
  fi
}

### End ###
