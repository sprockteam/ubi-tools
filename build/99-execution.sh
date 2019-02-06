### Tests
##############################################################################

if [[ -n "${__ubnt_product_command:-}" && -n "${__ubnt_selected_product:-}" ]]; then
  __ubnt_selected_product="$(echo ${__ubnt_selected_product} | sed 's/-/_/g')"
  __ubnt_product_command="$(echo ${__ubnt_product_command} | sed 's/-/_/g')"
  __eubnt_${__ubnt_selected_product}_${__ubnt_product_command} "${__ubnt_product_version:-}"
fi
exit

### Execution of script
##############################################################################

ln --force --symbolic "${__script_log}" "${__script_log_dir}/latest.log"
__eubnt_script_colors
if [[ -z "${__accept_license:-}" ]]; then
  __eubnt_show_header
  __eubnt_show_license
  __eubnt_show_notice "By using this script you agree to the license\\n"
  __eubnt_show_timer "5" "${__colors_notice_text}Thanks for playing! Here we go!${__colors_default}"
  echo
fi
__eubnt_show_header "Checking system..."
__eubnt_run_command "dig +short ${__ubnt_dl:-}" "quiet"
if ! tail --lines=1 "${__script_log}" | grep --quiet --extended-regexp "${__regex_ip_address}"; then
  __eubnt_show_error "Unable to resolve ${__ubnt_dl} using the following nameservers: ${__nameservers}"
else
  __eubnt_show_success "DNS appears to be working!"
fi
__apparent_public_ip_address="$(wget --quiet --output-document - "sprocket.link/ip" 2>/dev/null)"
__eubnt_show_text "Apparent public IP address is "
show_disk_free_space=""
if [[ "${__disk_free_space%G*}" -le 2 ]]; then
  show_disk_free_space="${__disk_free_space_mb}"
else
  show_disk_free_space="${__disk_free_space}"
fi
__eubnt_show_text "Disk free space is ${__colors_bold_text}${show_disk_free_space}${__colors_default}"
if [[ "${__disk_free_space%G*}" -lt "${__recommended_disk_free_space%G*}" ]]; then
  __eubnt_show_warning "UBNT recommends at least ${__recommended_disk_free_space} of free space"
else
  if [[ "${__disk_free_space%G*}" -gt $(( ${__recommended_disk_free_space%G*} + ${__recommended_swap_total_gb%G*} )) ]]; then
    have_space_for_swap=true
  fi
fi
__eubnt_show_text "Memory total size is ${__colors_bold_text}${__memory_total}${__colors_default}\\n"
__eubnt_show_text "Swap total size is ${__colors_bold_text}${__swap_total}"
if [[ "${__swap_total%M*}" -eq 0 && "${have_space_for_swap:-}" ]]; then
  if __eubnt_question_prompt "Do you want to setup a ${__recommended_swap_total_gb} swap file?" "return"; then
    __eubnt_setup_swap_file
  fi
fi
__eubnt_show_timer
__eubnt_common_fixes
__eubnt_setup_sources
__eubnt_install_updates
if [[ -f /var/run/reboot-required ]]; then
  echo
  __eubnt_show_warning "A reboot is recommended.\\nRun this script again after reboot.\\n"
  # TODO: Restart the script automatically after reboot
  if [[ -n "${__quick_mode:-}" ]]; then
    __eubnt_show_warning "The system will automatically reboot in 10 seconds.\\n"
    sleep 10
  fi
  if __eubnt_question_prompt "Do you want to reboot now?" "return"; then
    __eubnt_show_warning "Exiting script and rebooting system now!"
    __reboot_system=true
    exit 0
  fi
fi
__eubnt_install_java8
__eubnt_install_mongodb
__eubnt_install_unifi
__eubnt_setup_ssh_server
if [[ -n "${__unifi_domain_name:-}" ]]; then
  __eubnt_setup_certbot
fi
__eubnt_setup_ufw
__eubnt_show_success "\\nDone!\\n"
sleep 3
