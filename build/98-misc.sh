### Miscellaneous fixes and things
##############################################################################

# Collection of different fixes to do pre/post
# Try to fix broken installs
# Remove un-needed packages
# Remove cached source list information
# Fix for kernel files filling /boot in Ubuntu
# Fix localhost issue on Ubuntu for sudo use
# Update apt-get and apt-file
function __eubnt_common_fixes {
  if [[ "${1:-}" != "noheader" ]]; then
    __eubnt_show_header "Running common fixes..."
  fi
  __eubnt_run_command "apt-get install --fix-broken --yes"
  __eubnt_run_command "apt-get autoremove --yes"
  __eubnt_run_command "apt-get clean --yes"
  __eubnt_run_command "rm -rf /var/lib/apt/lists/*"
  if [[ ( -n "${__is_ubuntu:-}" || -n "${__is_mint:-}" ) && -d /boot ]]; then
    if ! grep --quiet "127\.0\.1\.1.*{__hostname_local}" /etc/hosts; then
      sed -i "1s/^/127.0.1.1\t${__hostname_local}\n/" /etc/hosts
    fi
    if [[ $(df /boot | awk '/\/boot/{gsub("%", ""); print $5}') -gt 50 ]]; then
      declare -a files_in_boot=()
      declare -a kernel_packages=()
      __eubnt_show_text "Removing old kernel files from /boot"
      while IFS=$'\n' read -r found_file; do files_in_boot+=("$found_file"); done < <(find /boot -maxdepth 1 -type f)
      for boot_file in "${!files_in_boot[@]}"; do
        kernel_version=$(echo "${files_in_boot[$boot_file]}" | grep --extended-regexp --only-matching "[0-9]+\\.[0-9]+(\\.[0-9]+)?(\\-{1}[0-9]+)?")
        if [[ "${kernel_version}" = *"-"* && "${__os_kernel_version}" = *"-"* && "${kernel_version//-*/}" = "${__os_kernel_version//-*/}" && "${kernel_version//*-/}" -lt "${__os_kernel_version//*-/}" ]]; then
          # shellcheck disable=SC2227
          find /boot -maxdepth 1 -type f -name "*${kernel_version}*" -exec rm {} \; -exec echo Removing {} >>"${__script_log}" \;
        fi
      done
      __eubnt_run_command "apt-get install --fix-broken --yes"
      __eubnt_run_command "apt-get autoremove --yes"
      while IFS=$'\n' read -r found_package; do kernel_packages+=("$found_package"); done < <(dpkg --list linux-{image,headers}-"[0-9]*" | awk '/linux/{print $2}')
      for kernel in "${!kernel_packages[@]}"; do
        kernel_version=$(echo "${kernel_packages[$kernel]}" | sed --regexp-extended 's/linux-(image|headers)-//g' | sed 's/[-][a-z].*//g')
        if [[ "${kernel_version}" = *"-"* && "${__os_kernel_version}" = *"-"* && "${kernel_version//-*/}" = "${__os_kernel_version//-*/}" && "${kernel_version//*-/}" -lt "${__os_kernel_version//*-/}" ]]; then
          __eubnt_run_command "apt-get purge --yes ${kernel_packages[$kernel]}"
        fi
      done
    fi
  fi
  __eubnt_run_command "apt-get update"
  __eubnt_run_command "apt-file update"
}

# Recommended by CrossTalk Solutions (https://crosstalksolutions.com/15-minute-hosted-unifi-controller-setup/)
# Virtual memory tweaks from @adrianmmiller
function __eubnt_setup_swap_file() {
  if __eubnt_run_command "fallocate -l 2G /swapfile"; then
    if __eubnt_run_command "chmod 600 /swapfile"; then
      if __eubnt_run_command "mkswap /swapfile"; then
        if swapon /swapfile; then
          if grep --quiet "^/swapfile " "/etc/fstab"; then
            sed -i "s|^/swapfile.*$|/swapfile none swap sw 0 0|" "/etc/fstab"
          else
            echo "/swapfile none swap sw 0 0" >>/etc/fstab
          fi
          __eubnt_show_success "\\nCreated swap file!\\n"
        else
          rm -rf /swapfile
          __eubnt_show_warning "Unable to create swap file!\\n"
        fi
      fi
    fi
  fi
  if [[ $(cat /proc/sys/vm/swappiness) -ne 10 ]]; then
    __eubnt_run_command "sysctl vm.swappiness=10"
  fi
  if [[ $(cat /proc/sys/vm/vfs_cache_pressure) -ne 50 ]]; then
    __eubnt_run_command "sysctl vm.vfs_cache_pressure=50"
  fi
  echo
}

### End ###
