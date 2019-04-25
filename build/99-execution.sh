### Tests
##############################################################################
if [[ -n "${__script_test_mode:-}" ]]; then
  if [[ -f "${__script_tests:-}" ]]; then
    source "${__script_tests}"
  fi
  exit
fi

### Execution of script
##############################################################################

__eubnt_invoke_cli
__eubnt_script_colors
if [[ -z "${__accept_license:-}" ]]; then
  __eubnt_show_header "License Agreement"
  __eubnt_show_license
  __eubnt_show_notice "By using this script you agree to the license"
  echo
  __eubnt_show_timer "5" "${__colors_notice_text}Thanks for playing! Here we go!${__colors_default}"
  echo
fi
__eubnt_show_header "Checking system...\\n"
__eubnt_install_dependencies
ubnt_dl_ip=""
__eubnt_run_command "dig +short ${__ubnt_dl:-}" "quiet" "ubnt_dl_ip"
ubnt_dl_ip="$(echo "${ubnt_dl_ip:-}" | tail --lines=1)"
if [[ ! "${ubnt_dl_ip:-}" =~ ${__regex_ip_address} ]]; then
  __eubnt_show_error "Unable to resolve ${__ubnt_dl} using the following nameservers: ${__nameservers}"
else
  __eubnt_show_success "DNS appears to be working!"
fi
show_disk_free_space="$([[ "${__disk_free_space_gb}" -lt 2 ]] && echo "${__disk_free_space_mb}MB" || echo "${__disk_free_space_gb}GB" )"
__eubnt_show_text "Disk free space is ${__colors_bold_text}${show_disk_free_space}${__colors_default}"
if [[ "${__disk_free_space_gb}" -lt ${__recommended_disk_free_space_gb} ]]; then
  __eubnt_show_warning "Disk free space is below ${__colors_bold_text}${__recommended_disk_free_space_gb}GB${__colors_default}"
else
  if [[ "${__disk_free_space_gb}" -ge $((__recommended_disk_free_space_gb + __recommended_swap_total_gb)) ]]; then
    have_space_for_swap=true
  fi
fi
show_memory_total="$([[ "${__memory_total_gb}" -le 1 ]] && echo "${__memory_total_mb}MB" || echo "${__memory_total_gb}GB" )"
__eubnt_show_text "Memory total size is ${__colors_bold_text}${show_memory_total}${__colors_default}"
if [[ "${__memory_total_gb}" -lt ${__recommended_memory_total_gb} ]]; then
  __eubnt_show_warning "Memory total size is below ${__colors_bold_text}${__recommended_memory_total_gb}GB${__colors_default}"
fi
show_swap_total="$([[ "${__swap_total_gb}" -le 1 ]] && echo "${__swap_total_mb}MB" || echo "${__swap_total_gb}GB" )"
__eubnt_show_text "Swap total size is ${__colors_bold_text}${show_swap_total}${__colors_default}"
if [[ "${__swap_total_mb}" -eq 0 && -n "${have_space_for_swap:-}" ]]; then
  if __eubnt_question_prompt "Do you want to setup a ${__recommended_swap_total_gb}GB swap file?"; then
    __eubnt_setup_swap_file
  fi
fi
if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
  __eubnt_initialize_unifi_controller_variables
  if [[ "${__unifi_controller_package_version:-}" =~ ${__regex_version_full} ]]; then
    __eubnt_show_notice "UniFi Network Controller ${__unifi_controller_package_version} is installed"
  fi
fi
echo
if [[ -n "${__is_cloud_key:-}" ]]; then
  __eubnt_show_warning "This script isn't fully tested with Cloud Key!\\n"
  __eubnt_question_prompt "" "exit"
else
  __eubnt_show_timer
fi
if [[ -z "${__is_cloud_key:-}" ]]; then
  __eubnt_common_fixes
  __eubnt_setup_sources
  __eubnt_install_updates
  if [[ -f /var/run/reboot-required ]]; then
    echo
    __eubnt_show_warning "A reboot is recommended. Run this script again after reboot."
    # TODO: Restart the script automatically after reboot
    if [[ -n "${__quick_mode:-}" ]]; then
      __eubnt_show_warning "The system will automatically reboot in 10 seconds."
      sleep 10
    fi
    if __eubnt_question_prompt "Do you want to reboot now?"; then
      __eubnt_show_warning "Exiting script and rebooting system now!"
      __reboot_system=true
      exit 0
    fi
  fi
fi
if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
  __eubnt_install_unifi_controller || true
fi
__eubnt_setup_certbot || true
if [[ -z "${__is_cloud_key:-}" ]]; then
  __eubnt_setup_ssh_server || true
  __eubnt_setup_ufw || true
fi