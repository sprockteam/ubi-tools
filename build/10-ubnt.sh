### General UBNT functions
##############################################################################

# Get a UBNT product version number or download URL
# $1: The UBNT product to check
# $2: The version number to check, can be like "5", "5.9" or "5.9.29"
#     Can also be one of the following keywords: "beta", "candidate", "stable" or "latest"
# $3: The variable to assign the found version number or URL
# $4: If set to "url" then return the full URL to the download file
function __eubnt_ubnt_get_product() {
  if [[ -n "${1:-}" && -n "${2:-}" ]]; then
    local ubnt_product=""
    for prod in "${!__ubnt_products[@]}"; do
      if [[ "${1}" = "${prod}" ]]; then
        ubnt_product="${1}"
        break
      fi
    done
    if [[ -z "${ubnt_product:-}" ]]; then
      __eubnt_show_warning "Invalid product: ${1}"
      return 1
    fi
    local can_install=
    local where_to_look="$(echo ${__ubnt_products[$ubnt_product]} | cut --delimiter '|' --fields 2)"
    IFS=',' read -r -a architectures_supported <<< "$(echo ${__ubnt_products[$ubnt_product]} | cut --delimiter '|' --fields 3)"
    for arch in "${!architectures_supported[@]}"; do
      if [[ "${architectures_supported[$arch]}" = "${__architecture}" ]]; then
        can_install=true
        break
      fi
    done
    if [[ -z "${can_install:-}" ]]; then
      __eubnt_show_warning "Incompatible hardware for product: ${ubnt_product}"
      return 1
    fi
    local update_url=
    declare -a download_url=()
    declare -a found_version=()
    local version_major=""
    local version_minor=""
    local version_patch=""
    IFS='.' read -r -a version_array <<< "${2}"
    if [[ "${where_to_look:-}" = "ubnt" ]]; then
      if [[ -n "${version_array[0]:-}" && "${version_array[0]}" =~ ${__regex_number} ]]; then
        version_major="&filter=eq~~version_major~~${version_array[0]}"
      fi
      if [[ -n "${version_array[1]:-}" && "${version_array[1]}" =~ ${__regex_number} ]]; then
        version_minor="&filter=eq~~version_minor~~${version_array[1]}"
      fi
      if [[ -n "${version_array[2]:-}" && "${version_array[2]}" =~ ${__regex_number} ]]; then
        version_minor="&filter=eq~~version_patch~~${version_array[2]}"
      fi
      local product="?filter=eq~~product~~${ubnt_product}"
      local product_channel="&filter=eq~~channel~~release"
      local product_platform="&filter=eq~~platform~~"
      if [[ "${ubnt_product}" = "aircontrol" ]]; then
        product_platform="${product_platform}cp"
      elif [[ "${ubnt_product}" = "unifi-controller" ]]; then
        product_platform="${product_platform}debian"
      elif [[ "${ubnt_product}" = "unifi-protect" && -n "${__architecture:-}" ]]; then
        product_platform="${product_platform}Debian9_${__architecture}"
      elif [[ "${ubnt_product}" = "unifi-video" && -n "${__architecture:-}" ]]; then
        if [[ -n "${__is_ubuntu:-}" ]]; then
          if [[ -n "${__os_version:-}" && "${__os_version//.}" -lt 1604 ]]; then
            product_platform="${product_platform}Ubuntu14.04_${__architecture}"
          else
            product_platform="${product_platform}Ubuntu16.04_${__architecture}"
          fi
        else
          product_platform="${product_platform}Debian7_${__architecture}"
        fi
      fi
      if [[ -n "${product:-}" && -n "${product_channel:-}" && -n "${product_platform:-}" ]]; then
        update_url="${__ubnt_update_api}${product}${product_channel}${product_platform}${version_major:-}${version_minor:-}${version_patch:-}&sort=-version&limit=1"
        declare -a wget_command=(wget --quiet --output-document - "${update_url}")
        if [[ "${4:-}" = "url" ]]; then
          download_url="$(${wget_command[@]} | jq -r '._embedded.firmware | .[0] | ._links.data.href')"
        else
          found_version="$(${wget_command[@]} | jq -r '._embedded.firmware | .[0] | .version' | sed 's/+.*//; s/[^0-9.]//g')"
        fi
      fi
    fi
    if [[ -n "${download_url:-}" ]]; then
      if [[ -n "${3:-}" ]]; then
        eval "${3}=\"${download_url}\""
      else
        echo "${download_url}"
      fi
      return 0
    elif [[ -n "${found_version:-}" ]]; then
      if [[ -n "${3:-}" ]]; then
        eval "${3}=\"${found_version}\""
      else
        echo "${found_version}"
      fi
      return 0
    fi
  fi
  return 1
}

# Try to get the release notes for the given product and version
# $1: The full version number to check, for instance: "5.9.29"
# $2: The variable to assign the filename with the release notes
# $3: The UBNT product to check, right now it's just "unifi-controller"
function __eubnt_ubnt_get_release_notes() {
  if [[ -z "${1:-}" && -z "${2:-}" ]]; then
    __eubnt_show_warning "Invalid check for release notes at $(caller)"
    return 1
  fi
  if [[ ! "${1}" =~ ${__regex_version_full} ]]; then
    __eubnt_show_warning "Invalid version number ${1} given at $(caller)"
    return 1
  fi
  local download_url=""
  local found_version=""
  IFS='.' read -r -a version_array <<< "${2}"
  local product="&filter=eq~~product~~${3:-unifi-controller}"
  local version_major="&filter=eq~~version_major~~$(echo "${1}" | cut --fields 1 --delimiter '.')"
  local version_minor="&filter=eq~~version_minor~~$(echo "${1}" | cut --fields 2 --delimiter '.')"
  local version_patch="&filter=eq~~version_patch~~$(echo "${1}" | cut --fields 3 --delimiter '.')"
  local update_url="${__ubnt_update_api}?filter=eq~~platform~~document${product}${version_major}${version_minor}${version_patch}&sort=-version&limit=1"
  local release_notes_url="$(wget --quiet --output-document - "${update_url:-}" | jq -r '._embedded.firmware | .[0] | ._links.changelog.href')"
  local release_notes_file="${__script_temp_dir}/${3:-unifi-controller}-${1}-release-notes.md"
  __eubnt_add_to_log "Trying to get release notes from: ${release_notes_url:-}"
  if wget --quiet --output-document - "${release_notes_url:-}" | sed '/#### Recommended Firmware:/,$d' 1>"${release_notes_file:-}"; then
    if [[ -f "${release_notes_file:-}" && -s "${release_notes_file:-}" ]]; then
      eval "${2}=\"${release_notes_file}\""
      return 0
    fi
  fi
  return 1
}

### End ###
