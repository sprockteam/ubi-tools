### Display functions
##############################################################################

# Set script colors
function __eubnt_script_colors() {
  echo "${__colors_default}"
}

# Print an error to the screen
# $1: An optional error message to display
function __eubnt_show_error() {
  if [[ -n "${__script_debug:-}" ]]; then
    echo -e "Pausing before error message for 10 seconds..."
    sleep 10
  else
    clear || true
  fi
  echo -e "${__colors_error_text}### ${__script_full_title}"
  echo -e "##############################################################################\\n"
  echo -e "ERROR! Script halted!${__colors_default}\\n"
  if [[ -f "${__script_log:-}" ]]; then
    echo -e "To help troubleshoot, here are the last five entries from the script log:\\n"
    log_lines="$(tail --lines=5 "${__script_log}")"
    echo -e "${log_lines}\\n"
  fi
  __eubnt_echo_and_log "${__colors_error_text}Error at line $(caller)"
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "Error message: ${1}"
  fi
  echo -e "${__colors_default}"
  exit 1
}
trap '__eubnt_show_error' ERR

# Print a header that informs the user what task is running
# $1: Can be set with a string to display additional details about the current task
# $2: Can be set to "noclear" to not clear the screen before displaying header
###
# If the script is not in debug mode, then the screen will be cleared first
# The script header will then be displayed
# If $1 is set then it will be displayed under the header
function __eubnt_show_header() {
  if [[ -z "${__script_debug:-}" || "${2:-}" != "noclear" ]]; then
    clear || true
  fi
  echo -e "${__colors_notice_text}### ${__script_full_title}"
  echo -e "##############################################################################${__colors_default}"
  __eubnt_show_notice "${1:-}"
  echo
}

# Print text to the screen
# $1: The text to display
function __eubnt_show_text() {
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "${__colors_default}${1}${__colors_default}"
    echo
  fi
}

# Print a notice to the screen
# $1: The notice to display
function __eubnt_show_notice() {
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "${__colors_notice_text}${1}${__colors_default}"
    echo
  fi
}

# Print a success message to the screen
# $1: The message to display
function __eubnt_show_success() {
  if [[ -n "${1:-}" ]]; then
    echo
    __eubnt_echo_and_log "${__colors_success_text}${1}${__colors_default}"
    echo
  fi
}

# Print a warning to the screen
# $1: The warning to display
# $2: Can be set to "none" to not show the "WARNING:" prefix
function __eubnt_show_warning() {
  if [[ -n "${1:-}" ]]; then
    local warning_prefix=""
    if [[ "${2:-}" != "none" ]]; then
      warning_prefix="WARNING: "
    fi
    echo
    __eubnt_echo_and_log "${__colors_warning_text}${warning_prefix:-}${1}${__colors_default}"
    echo
  fi
}

# Print a timer on the screen
# $1: The number of seconds to display the timer
# $2: The optional message to show after the timer is done
function __eubnt_show_timer() {
  local countdown="5"
  local message="${2:-Proceeding in 0...}"
  if [[ "${1:-}" =~ ${__regex_number} && "${1:-}" -le 9 && "${1:-}" -ge 1 ]]; then
    countdown="${1}"
  fi
  while [[ "${countdown}" -ge 0 ]]; do
    if [[ "${countdown}" -ge 1 ]]; then
      echo -e -n "\\rProceeding in ${countdown}..."
    else
      echo -e -n "\\r${message}"
      sleep 0.5
    fi
    sleep 1
    countdown=$(( countdown-1 ))
  done
}

# Print a short message and progress spinner to the scree
# $1: The background process ID
# $2: An optional message to display
# $3: Optionally specify the max amount of time in seconds to show the spinner
function __eubnt_show_spinner() {
  local background_pid="${1}"
  local message="${2:-Please wait...}"
  local timeout="${3:-360}"
  local i=0
  while [[ -d /proc/$background_pid ]]; do
    echo -e -n "\\r${message} [${__spinner:i++%${#__spinner}:1}]"
    sleep 0.5
    if [[ $i -gt $timeout ]]; then
      break
    fi
  done
  # shellcheck disable=SC2086
  wait $background_pid
}

# Print the license and disclaimer for this script to the screen
function __eubnt_show_license() {
  __eubnt_show_text "MIT License\\nCopyright (c) 2018-2019 SprockTech, LLC and contributors\\n
Read the full MIT License for this script here:
https://github.com/sprockteam/easy-ubnt/raw/master/LICENSE\\n
Contributors (UBNT Community Username):"
  __eubnt_show_notice "${__script_contributors:-}"
  __eubnt_show_text "This script will guide you through installing, upgrading or removing
the UBNT products, as well as tweaking, securing and maintaining
this system according to best practices."
  __eubnt_show_warning "THIS SCRIPT IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND!"
}

### Screen display and user input functions
##############################################################################

# Use whiptail to display information and options on the screen
# $1: The type of whiptail object to display: "msgbox" (default), "yesno", "input", "menu"
# $2: The message text to display under the title
# $3: The variable to assign return values for "menu" and "input" responses
# $4: If $1 is "menu" then an array of menu items ("tag" "description" ...)
#     If $1 is "input" then this can be set to "optional" to allow for empty responses
# $5: Optionally set to "alert" for a red background
# $6: Optionally specify the height
# $7: Optionally specify the width
# $8: If a menu, optionally specify the number of lines for the menu
function __eubnt_show_whiptail() {
  if ! __eubnt_is_command "whiptail"; then
    if ! __eubnt_install_package "whiptail"; then
      return 1
    fi
  fi
  if [[ -n "${1:-}" ]]; then
    local message=""
    local height=""
    local width=""
    local error_response=
    local old_newt_colors="${NEWT_COLORS:-}"
    local newt_colors_normal="
    window=black,white
    title=black,white
    border=black,white
    textbox=black,white
    listbox=black,white
    actsellistbox=white,blue
    button=white,blue"
    local newt_colors_alert="
    root=,red
    window=red,white
    title=red,white
    border=red,white
    textbox=red,white
    listbox=red,white
    actsellistbox=white,red
    button=white,red"
    if [[ "${1}" = "menu" && -n "${4:-}" ]]; then
      export NEWT_COLORS="${newt_colors_normal}"
      local -n menu_items=${4}
      local menu_lines=$((${#menu_items[@]} + 3))
      menu_lines="${8:-${menu_lines}}"
      message=${2:-"Please make a selection:"}
      height="${6:-30}"
      width="${7:-80}"
      local selected_item="$(whiptail --title "${__script_full_title}" --menu "\\n${message}" "${height}" "${width}" "${menu_lines}" "${menu_items[@]}" 3>&1 1>&2 2>&3)" || true
      if [[ -n "${selected_item:-}" ]]; then
        eval "${3}=\"${selected_item}\""
      else
        error_response=true
      fi
    elif [[ "${1}" = "input" && -n "${2:-}" ]]; then
      export NEWT_COLORS="${newt_colors_normal}"
      message=${2}
      height="${6:-15}"
      width="${7:-80}"
      local answer="$(whiptail --title "${__script_full_title}" --inputbox "\\n${message}" "${height}" "${width}" 3>&1 1>&2 2>&3)" || true
      if [[ -n "${answer:-}" ]]; then
        eval "${3}=\"${answer}\""
      elif [[ -z "${answer:-}" && "${4:-}" = "optional" ]]; then
        true # Allow an empty response
      else
        error_response=true
      fi
    else
      error_response=true
    fi
    export NEWT_COLORS="${old_newt_colors}"
    if [[ -n "${error_response:-}" ]]; then
      return 1
    fi
  fi
}

# Display a yes or no question and proceed accordingly based on the answer
# If no answer is given, the default answer is used
# If the script it running in "quiet mode" then the default answer is used without prompting
# $1: The question to use instead of the default question
# $2: Can be set to "return" if an error should be returned instead of exiting
# $3: Can be set to "n" if the default answer should be no instead of yes
function __eubnt_question_prompt() {
  local yes_no=""
  local default_question="Do you want to proceed?"
  local default_answer="y"
  if [[ "${3:-}" = "n" ]]; then
    default_answer="n"
  fi
  if [[ -n "${__quick_mode:-}" ]]; then
    __eubnt_add_to_log "Quick mode, default answer selected"
    yes_no="${default_answer}"
  fi
  while [[ ! "${yes_no:-}" =~ (^[Yy]([Ee]?|[Ee][Ss])?$)|(^[Nn][Oo]?$) ]]; do
    echo -e -n "${__colors_notice_text}${1:-$default_question} (y/n, default ${default_answer})${__colors_default} "
    read -r yes_no
    echo -e -n "\\r"
    if [[ "${yes_no}" = "" ]]; then
      yes_no="${default_answer}"
    fi
  done
  __eubnt_add_to_log "${1:-$default_question} ${yes_no}"
  case "${yes_no}" in
    [Nn]*)
      echo
      if [[ "${2:-}" = "return" ]]; then
        return 1
      else
        exit
      fi;;
    [Yy]*)
      echo
      return 0;;
  esac
}

# Display a question and return full user input
# No validation is done on use the input within this function, must be done after the answer has been returned
# $1: The question to ask, there is no default question so one must be set
# $2: The variable to assign the answer to, this must also be set
# $3: Can be set to "optional" to allow for an empty response to bypass the question
function __eubnt_get_user_input() {
  local user_input=""
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    while [[ -z "${user_input}" ]]; do
      echo -e -n "${__colors_notice_text}${1}${__colors_default} "
      read -r user_input
      echo -e -n "\\r"
      if [[ "${3:-}" = "optional" ]]; then
        break
      fi
    done
    if [[ -n "${user_input:-}" ]]; then
      __eubnt_add_to_log "${1} ${user_input}"
      eval "${2}=\"${user_input}\""
    fi
  fi
}

### End ##
