#!/usr/bin/env bash
# Author: Frank Gabriel (Frankedinven) and Klint Van Tassel (SprockTech)
# Credits: Kalle Lilja and others
# Script location: /etc/letsencrypt/renewal-hooks/deploy/unifi-controller.sh (important for auto renewal)
# Note: The certbot deploy hook only runs if a new cert is generated

# Exit on error, append "|| true" if an error is expected
set -o errexit
trap 'echo "Uncaught error on line ${LINENO}"' ERR
# Exit on error inside any functions or subshells
set -o errtrace
# Do not allow use of undefined vars, use ${var:-} if a variable might be undefined
set -o nounset

# Change these if needed
__unifi_data_dir="${2:-/var/lib/unifi}"
__unifi_system_properties="${__unifi_data_dir}/system.properties"
__cert_live_dir="/etc/letsencrypt/live"
__keypass="aircontrolenterprise"
__mongodb_host="${3:-localhost}"
__mongodb_port="${4:-27117}"

# Optioanlly set this manually
# __unifi_controller_domain="unifi.my.tld"
# Optionally run the deploy cert function in any case
# __deploy_anyway=true

# If not set manually, then check if a domain was passed to the script
if [[ -z "${__unifi_controller_domain:-}" && -n "${1:-}" ]]; then
  __unifi_controller_domain="${1}"
fi

# If domain is not set manually or passed to the script, then try to get the domain in the UniFi settings
# Note that this currently won't work if a username/password is needed to connect to MongoDB
if [[ -z "${__unifi_controller_domain:-}" ]]; then
  if netstat --tcp --udp --listening --numeric --programs | grep --quiet "^tcp.*:${__mongodb_port} .*mongod"; then
    __unifi_controller_domain=$(mongo --quiet --host ${__mongodb_host} --port ${__mongodb_port} --eval 'db.getSiblingDB("ace").setting.find({"key": "super_identity"}).forEach(function(setting){ print(setting.hostname) })')
  fi
fi

function do_fingerprints_match() {

  # Find the SHA1 fingerprint of the domain cert from certbot
  certbot_fingerprint=$(openssl x509 -in ${__cert_live_dir}/${domain}/fullchain.pem -noout -sha1 -fingerprint 2>/dev/null | sed 's/.*=//')
  # Find the SHA1 fingerprint of the domain cert in the UniFi keystore
  keystore_fingerprint=$(keytool -list -keystore ${__unifi_data_dir}/keystore -storepass ${__keypass} 2>/dev/null | grep "fingerprint" | sed 's/.*(SHA1): //')

  # If the fingerprints match then return success
  if [[ -n "${certbot_fingerprint}" && -n "${keystore_fingerprint}" && "${certbot_fingerprint}" = "${keystore_fingerprint}" ]]; then
    return 0
  fi

  # Default is to return error
  return 1
}

function deploy_cert_to_unifi() {

  # Optionally, a domain can be passed to the function
  domain="${1:-${__unifi_controller_domain}}"

  # If the domain doesn't have a valid cert folder in certbot then we can't continue
  if [[ ! -d "${__cert_live_dir}/${domain}" ]]; then
    echo "Unable to find cert folder: ${__cert_live_dir}/${domain}"
    return 1
  fi

  # If the keystore and system.properties files can't be found, then we have a problem
  if [[ ! -f "${__unifi_data_dir}/keystore" || ! -f "${__unifi_system_properties}" ]]; then
    echo "Unable to find UniFi data structure"
    return 1
  fi

  # We really only want to import a new cert
  if do_fingerprints_match; then
    echo "The certificate is already in the UniFi keystore"
    return 1
  fi

  # Backup existing keystore to fallback if needed
  if cp --force ${__unifi_data_dir}/keystore ${__unifi_data_dir}/keystore.backup &>/dev/null; then

    # Convert cert to PKCS12 format
    if openssl pkcs12 -export -inkey ${__cert_live_dir}/${domain}/privkey.pem -in ${__cert_live_dir}/${domain}/fullchain.pem -out ${__cert_live_dir}/${domain}/fullchain.p12 -name unifi -password pass:${__keypass} &>/dev/null; then

      # Delete the existing 'unifi' cert in the keystore
      if keytool -delete -alias unifi -keystore ${__unifi_data_dir}/keystore -storepass aircontrolenterprise &>/dev/null

        # Finally import the new key
        if keytool -importkeystore -deststorepass ${__keypass} -destkeypass ${__keypass} -destkeystore ${__unifi_data_dir}/keystore -srckeystore ${__cert_live_dir}/${domain}/fullchain.p12 -srcstoretype PKCS12 -srcstorepass ${__keypass} -alias unifi -noprompt &>/dev/null; then

          # Import seemed successful, let's check
          if do_fingerprints_match; then

            # Make sure permissions are right
            chown --recursive unifi:unifi ${__unifi_data_dir} &>/dev/null

            # Set more secure TLS options in UniFi
            # Comment out these lines if you don't want them
            echo "unifi.https.ciphers=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_EMPTY_RENEGOTIATION_INFO_SCSVF" >>${__unifi_system_properties}
            echo "unifi.https.sslEnabledProtocols=+TLSv1.1,+TLSv1.2,+SSLv2Hello" >>${__unifi_system_properties}

            # Restart UniFi with the updated cert and settings
            if service unifi restart &>/dev/null; then
              # Cleanup the PKC12 file and backup file then return success
              rm --force ${__cert_live_dir}/${domain}/fullchain.p12 &>/dev/null
              rm --force ${__unifi_data_dir}/keystore.backup &>/dev/null
              return 0
            fi
          fi
        fi
      fi

      # Something didn't go right, revert to the backup if needed
      if ! cmp --silent ${__unifi_data_dir}/keystore ${__unifi_data_dir}/keystore.backup &>/dev/null; then
        if cp --force ${__unifi_data_dir}/keystore.backup ${__unifi_data_dir}/keystore &>/dev/null; then
          rm --force ${__unifi_data_dir}/keystore.backup &>/dev/null
        fi
      else
        rm --force ${__unifi_data_dir}/keystore.backup &>/dev/null
      fi

      # Cleanup the PKC12
      rm --force ${__cert_live_dir}/${domain}/fullchain.p12 &>/dev/null
    fi

    # Make sure permissions are right
    chown --recursive unifi:unifi ${__unifi_data_dir} &>/dev/null
  fi

  echo "Unknown error trying to import certificate for domain: ${domain}"
  return 1
}

# RENEWED_DOMAINS should be passed to this script when called by certbot
if [[ -n "${RENEWED_DOMAINS:-}" && -n "${__unifi_controller_domain:-}" ]]; then

  # Look for one of the domains getting a cert to match the UniFi domain
  for domain in "${RENEWED_DOMAINS}"; do
    if [[ "${__unifi_controller_domain}" = "${domain}" ]]; then

      # A match was found, try to deploy the cert to UniFi
      if deploy_cert_to_unifi "${domain}"; then
        echo "New certificate imported to UniFi keystore for domain: ${domain}"
      fi
      exit
    fi
  done
fi
