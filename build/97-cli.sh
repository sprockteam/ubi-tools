### CLI wrapper functions
##############################################################################

# Call the various CLI wrapper functions and exits
function __eubnt_invoke_cli() {
  if [[ -n "${__ubnt_product_command:-}" && -n "${__ubnt_selected_product:-}" ]]; then
    __ubnt_selected_product="$(echo "${__ubnt_selected_product}" | sed 's/-/_/g')"
    __ubnt_product_command="$(echo "${__ubnt_product_command}" | sed 's/-/_/g')"
    # shellcheck disable=SC2086,SC2086
    __eubnt_cli_${__ubnt_selected_product}_${__ubnt_product_command} "${__ubnt_product_version:-}" || true
    exit
  fi
}

# A wrapper function to get the available UniFi SDN Controller version number
function __eubnt_cli_unifi_controller_get_available_version() {
  if ! __eubnt_ubnt_get_product "unifi-controller" "${1:-stable}"; then
    return 1
  fi
}

# A wrapper function to get the available UniFi SDN Controller download URL for given version
function __eubnt_cli_unifi_controller_get_available_download() {
  if ! __eubnt_ubnt_get_product "unifi-controller" "${1:-stable}" "url"; then
    return 1
  fi
}

# A wrapper function to get the installed UniFi SDN Controller version
function __eubnt_cli_unifi_controller_get_installed_version() {
  __eubnt_initialize_unifi_controller_variables
  if [[ -n "${__unifi_controller_is_installed:-}" ]]; then
    if echo "${__unifi_controller_package_version:-}"; then
      return 0
    fi
  fi
  return 1
}

### End ###
