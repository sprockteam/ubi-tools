### CLI wrapper functions
##############################################################################

# Call the various CLI wrapper functions and exits
function __eubnt_invoke_cli() {
  if [[ -n "${__ubnt_product_command:-}" && -n "${__ubnt_selected_product:-}" ]]; then
    __ubnt_selected_product="$(echo "${__ubnt_selected_product}" | sed 's/-/_/g')"
    __ubnt_product_command="$(echo "${__ubnt_product_command}" | sed 's/-/_/g')"
    local command_type="$(type -t "__eubnt_cli_${__ubnt_selected_product}_${__ubnt_product_command}")"
    if [[ "${command_type:-}" = "function" ]]; then
      # shellcheck disable=SC2086,SC2086
      __eubnt_cli_${__ubnt_selected_product}_${__ubnt_product_command} "${__ubnt_product_version:-}" || true
      exit
    else
      __eubnt_show_warning "Unknown command ${__ubnt_product_command}"
      exit 1
    fi
  fi
}

# A wrapper function to get the available UniFi Network Controller version number
function __eubnt_cli_unifi_controller_get_available_version() {
  local version_to_check="$(__eubnt_ubnt_get_product "unifi-controller" "${1:-stable}" | tail --lines=1)"
  if [[ "${version_to_check:-}" =~ ${__regex_version_full} ]]; then
    echo -n "${version_to_check}"
  else
    return 1
  fi
}

# A wrapper function to get the available UniFi Network Controller download URL for given version
function __eubnt_cli_unifi_controller_get_available_download() {
  local download_to_check="$(__eubnt_ubnt_get_product "unifi-controller" "${1:-stable}" "url" | tail --lines=1)"
  if [[ "${download_to_check:-}" =~ ${__regex_url_ubnt_deb} ]]; then
    echo -n "${download_to_check}"
  else
    return 1
  fi
}

# A wrapper function to get the installed UniFi Network Controller version
function __eubnt_cli_unifi_controller_get_installed_version() {
  __eubnt_initialize_unifi_controller_variables
  if [[ "${__unifi_controller_package_version:-}" =~ ${__regex_version_full} ]]; then
    echo -n "${__unifi_controller_package_version}"
    return 0
  fi
  return 1
}

### End ###
