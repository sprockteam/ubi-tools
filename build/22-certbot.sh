### Setup certbot and hook scripts
##############################################################################

# Based on solution by @Frankedinven (https://community.ubnt.com/t5/UniFi-Wireless/Lets-Encrypt-on-Hosted-Controller/m-p/2463220/highlight/true#M318272)
function __eubnt_setup_certbot() {
  if [[ -n "${__quick_mode:-}" && -z "${__hostname_fqdn:-}" ]]; then
    return 1
  fi
  if [[ "${__ubnt_selected_product:-}" = "unifi-controller" ]]; then
    __eubnt_initialize_unifi_controller_variables
    if [[ ! -d "${__unifi_controller_data_dir:-}" || ! -f "${__unifi_controller_system_properties:-}" ]]; then
      return 1
    fi
  else
    return 1
  fi
  if [[ "${__os_version_name}" = "precise" || "${__os_version_name}" = "wheezy" ]]; then
    return 1
  fi
  local source_backports=""
  local skip_certbot_questions=""
  local domain_name=""
  local valid_domain_name=
  local email_address=""
  local resolved_domain_name=""
  local apparent_public_ip=""
  local email_option=""
  local days_to_renewal=""
  __eubnt_show_header "Setting up Let's Encrypt...\\n"
  if __eubnt_question_prompt "Do you want to (re)setup Let's Encrypt?" "return" "n"; then
    if ! __eubnt_is_command "certbot"; then
      if [[ -n "${__is_ubuntu:-}" ]]; then
        if ! __eubnt_setup_sources "certbot"; then
          return 1
        fi
      fi
      if [[ "${__os_version_name}" = "jessie" ]]; then
        if ! __eubnt_install_package "python-cffi python-cryptography certbot" "jessie-backports"; then
          __eubnt_show_warning "Unable to install certbot"
          return 1
        fi
      else
        if ! __eubnt_install_package "certbot"; then
          __eubnt_show_warning "Unable to install certbot"
          return 1
        fi
      fi
    fi
  else
    return 1
  fi
  if ! __eubnt_is_command "certbot"; then
    echo
    __eubnt_show_warning "Unable to setup certbot!"
    echo
    sleep 3
    return 1
  fi
  domain_name="${__hostname_fqdn:-}"
  if [[ -z "${domain_name:-}" ]]; then
    __eubnt_run_command "hostname --fqdn" "" "domain_name"
  fi
  if [[ -z "${__quick_mode:-}" ]]; then
    while [[ -z "${valid_domain_name}" ]]; do
      echo
      __eubnt_get_user_input "Domain name to use (${domain_name:-}): " "domain_name" "optional"
      # shellcheck disable=SC2086
      resolved_domain_name="$(dig +short ${domain_name} @${__recommended_nameserver} | tail --lines=1)"
      apparent_public_ip="$(wget --quiet --output-document - "${__ip_lookup_url}")"
      if [[ "${apparent_public_ip:-}" =~ ${__regex_ip_address} && ( ! "${resolved_domain_name:-}" =~ ${__regex_ip_address} || ( "${resolved_domain_name:-}" =~ ${__regex_ip_address} && "${apparent_public_ip}" != "${resolved_domain_name}" ) ) ]]; then
        __eubnt_show_warning "The domain ${domain_name} does not appear to resolve to ${apparent_public_ip}"
        echo
        if ! __eubnt_question_prompt "Do you want to re-enter the domain name?" "return" "n"; then
          echo
          valid_domain_name=true
        fi
      else
        echo
        valid_domain_name=true
      fi
    done
  fi
  days_to_renewal=0
  if certbot certificates --domain "${domain_name:-}" | grep --quiet "Domains: "; then
    __eubnt_run_command "certbot certificates --domain ${domain_name}" "foreground" || true
    echo
    __eubnt_show_notice "Let's Encrypt has been setup previously"
    echo
    days_to_renewal=$(certbot certificates --domain "${domain_name}" | grep --only-matching --max-count=1 "VALID: .*" | awk '{print $2}')
    skip_certbot_questions=true
  fi
  if [[ -z "${skip_certbot_questions:-}" && -z "${__quick_mode:-}" ]]; then
    echo
    __eubnt_get_user_input "Email address for renewal notifications (optional): " "email_address" "optional"
  fi
  __eubnt_show_warning "Let's Encrypt will verify your domain using HTTP (TCP port 80). This\\nscript will automatically allow HTTP through the firewall on this machine only.\\nPlease make sure firewalls external to this machine are set to allow HTTP.\\n"
  if [[ -n "${email_address:-}" ]]; then
    email_option="--email ${email_address}"
  else
    email_option="--register-unsafely-without-email"
  fi
  if [[ -n "${domain_name:-}" ]]; then
    __eubnt_initialize_unifi_controller_variables
    local letsencrypt_scripts_dir=$(mkdir --parents "${__script_dir}/letsencrypt" && echo "${__script_dir}/letsencrypt")
    local pre_hook_script="${letsencrypt_scripts_dir}/pre-hook_${domain_name}.sh"
    local post_hook_script="${letsencrypt_scripts_dir}/post-hook_${domain_name}.sh"
    local letsencrypt_live_dir="${__letsencrypt_dir}/live/${domain_name}"
    local letsencrypt_renewal_dir="${__letsencrypt_dir}/renewal"
    local letsencrypt_renewal_conf="${letsencrypt_renewal_dir}/${domain_name}.conf"
    local letsencrypt_privkey="${letsencrypt_live_dir}/privkey.pem"
    local letsencrypt_fullchain="${letsencrypt_live_dir}/fullchain.pem"
    tee "${pre_hook_script}" &>/dev/null <<EOF
#!/usr/bin/env bash
http_process_file="${letsencrypt_scripts_dir}/http_process"
rm "\${http_process_file}" &>/dev/null
if netstat -tulpn | grep ":80 " --quiet; then
  http_process=\$(netstat -tulpn | awk '/:80 /{print \$7}' | sed 's/[0-9]*\///')
  service "\${http_process}" stop &>/dev/null
  echo "\${http_process}" >"\${http_process_file}"
fi
if [[ \$(dpkg --status "ufw" 2>/dev/null | grep "ok installed") && \$(ufw status | grep " active") ]]; then
  ufw allow http &>/dev/null
fi
EOF
# End of output to file
    chmod +x "${pre_hook_script}"
    tee "${post_hook_script}" &>/dev/null <<EOF
#!/usr/bin/env bash
http_process_file="${letsencrypt_scripts_dir}/http_process"
if [[ -f "\${http_process_file:-}" ]]; then
  http_process=\$(cat "\${http_process_file}")
  if [[ -n "\${http_process:-}" ]]; then
    service "\${http_process}" start &>/dev/null
  fi
fi
rm "\${http_process_file}" &>/dev/null
if [[ \$(dpkg --status "ufw" 2>/dev/null | grep "ok installed") && \$(ufw status | grep " active") && ! \$(netstat -tulpn | grep ":80 ") ]]; then
  ufw delete allow http &>/dev/null
fi
if [[ -f ${letsencrypt_privkey} && -f ${letsencrypt_fullchain} ]]; then
  if ! md5sum -c ${letsencrypt_fullchain}.md5 &>/dev/null; then
    md5sum ${letsencrypt_fullchain} >${letsencrypt_fullchain}.md5
    cp ${__unifi_controller_data_dir}/keystore ${__unifi_controller_data_dir}/keystore.backup.\$(date +%s) &>/dev/null
    openssl pkcs12 -export -inkey ${letsencrypt_privkey} -in ${letsencrypt_fullchain} -out ${letsencrypt_live_dir}/fullchain.p12 -name unifi -password pass:aircontrolenterprise &>/dev/null
    keytool -delete -alias unifi -keystore ${__unifi_controller_data_dir}/keystore -deststorepass aircontrolenterprise &>/dev/null
    keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${__unifi_controller_data_dir}/keystore -srckeystore ${letsencrypt_live_dir}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt &>/dev/null
    echo "unifi.https.ciphers=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_EMPTY_RENEGOTIATION_INFO_SCSVF" | tee -a "${__unifi_controller_system_properties}"
    echo "unifi.https.sslEnabledProtocols=+TLSv1.1,+TLSv1.2,+SSLv2Hello" | tee -a "${__unifi_controller_system_properties}"
    service unifi restart &>/dev/null
  fi
fi
EOF
# End of output to file
    chmod +x "${post_hook_script}"
    local force_renewal="--keep-until-expiring"
    local run_mode="--keep-until-expiring"
    if [[ "${days_to_renewal}" -ge 30 ]]; then
      if __eubnt_question_prompt "Do you want to force certificate renewal?" "return" "n"; then
        force_renewal="--force-renewal"
      fi
      echo
    fi
    if [[ -n "${__script_debug:-}" ]]; then
      run_mode="--dry-run"
    else
      if __eubnt_question_prompt "Do you want to do a dry run?" "return" "n"; then
        run_mode="--dry-run"
      fi
      echo
    fi
    # shellcheck disable=SC2086
    if certbot certonly --agree-tos --standalone --preferred-challenges http-01 --http-01-port 80 --pre-hook ${pre_hook_script} --post-hook ${post_hook_script} --domain ${domain_name} ${email_option} ${force_renewal} ${run_mode}; then
      echo
      __eubnt_show_success "Certbot succeeded for domain name: ${domain_name}"
      sleep 5
    else
      echo
      __eubnt_show_warning "Certbot failed for domain name: ${domain_name}"
      sleep 10
    fi
    if [[ -f "${letsencrypt_renewal_conf}" ]]; then
      sed -i "s|^pre_hook.*$|pre_hook = ${pre_hook_script}|" "${letsencrypt_renewal_conf}"
      sed -i "s|^post_hook.*$|post_hook = ${post_hook_script}|" "${letsencrypt_renewal_conf}"
      if crontab -l | grep --quiet "^[^#]"; then
        local found_file crontab_file
        declare -a files_in_crontab
        while IFS=$'\n' read -r found_file; do files_in_crontab+=("$found_file"); done < <(crontab -l | awk '/^[^#]/{print $6}')
        for crontab_file in "${!files_in_crontab[@]}"; do
          if grep --quiet "keystore" "${crontab_file}"; then
            __eubnt_show_warning "Please check your crontab to make sure there aren't any conflicting Let's Encrypt renewal scripts"
            sleep 3
          fi
        done
      fi
    fi
  fi
}

### End ###
