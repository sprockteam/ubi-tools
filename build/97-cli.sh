### Commandline wrapper functions
##############################################################################

# A wrapper function to get the available UniFi SDN Controller version number
function __eubnt_cli_unifi_controller_get_available_version() {
  if ! __eubnt_ubnt_get_product "unifi-controller" "${1:-stable}"; then
    return 1
  fi
}

# A wrapper function to get the available UniFi SDN Controller download URL for given version
function __eubnt_cli_unifi_controller_get_available_download() {
  if ! __eubnt_ubnt_get_product "unifi-controller" "${1:-stable}" "" "url"; then
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
