#!/usr/bin/env bash
# Author: Klint Van Tassel (SprockTech)
# Credits: Frank Gabriel (Frankedinven) and others
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
__unifi_data_dir="/usr/lib/unifi/data"
__unifi_system_properties="${__unifi_data_dir}/system.properties"
__unifi_hostname=""
__cert_live_dir="/etc/letsencrypt/live"
__keypass="aircontrolenterprise"
__mongodb_host="localhost"
__mongodb_port="27117"
__mongodb_ace="ace"
__regex_fingerprint='^[0-9A-Za-z:]+$'

if command -v easy-ubnt &>/dev/null; then
  __unifi_hostname="$(easy-ubnt -p unifi-controller -c get-hostname)"
fi

function do_fingerprints_match() {
  local domain="${1:-}"

  # Find the SHA1 fingerprint of the domain cert from certbot
  certbot_fingerprint="$(openssl x509 -in ${__cert_live_dir:-}/${domain:-}/fullchain.pem -noout -sha1 -fingerprint 2>/dev/null | sed 's/.*=//')"
  # Find the SHA1 fingerprint of the domain cert in the UniFi keystore
  keystore_fingerprint="$(keytool -list -keystore ${__unifi_data_dir:-}/keystore -storepass ${__keypass:-} 2>/dev/null | grep "fingerprint" | sed 's/.*(SHA1): //')"

  # If the fingerprints match then return success
  if [[ "${certbot_fingerprint:-}" =~ ${__regex_fingerprint} && "${keystore_fingerprint:-}" =~ ${__regex_fingerprint} && "${certbot_fingerprint}" = "${keystore_fingerprint}" ]]; then
    return 0
  fi

  # Default is to return error
  return 1
}

function deploy_cert_to_unifi() {

  # Make sure a domain has been passed to this function
  if [[ -z "${1:-}" ]]; then
    echo "No domain has been specified"
    return 1
  fi
  local domain="${1}"

  # Make sure we have a valid cert folder
  if [[ ! -d "${__cert_live_dir}/${domain}" ]]; then
    echo "Unable to find cert folder: ${__cert_live_dir}/${domain}"
    return 1
  fi

  # If the keystore can't be found then we can't proceed
  if [[ ! -f "${__unifi_data_dir:-}/keystore" ]]; then
    echo "Unable to find UniFi keystore"
    return 1
  fi

  # We really only want to import a new cert
  if do_fingerprints_match ${domain}; then
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
          if do_fingerprints_match ${domain}; then

            # Make sure permissions are right
            chown unifi:unifi ${__unifi_data_dir}/keystore &>/dev/null

            # Restart UniFi with the updated cert
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

      # Cleanup the PKC12 file
      rm --force ${__cert_live_dir}/${domain}/fullchain.p12 &>/dev/null
    fi

    # Make sure permissions are right
    chown unifi:unifi ${__unifi_data_dir}/keystore &>/dev/null
  fi
  echo "Unknown error trying to import certificate for domain: ${domain}"
  return 1
}

# RENEWED_DOMAINS should be passed to this script when called by certbot
for domain in "${RENEWED_DOMAINS:-}"; do

  # If UniFi has been configure with a hostname, then only proceed if the renewed cert domain matches
  if [[ -n "${__unifi_hostname:-}" && "${__unifi_hostname}" != "${domain}" ]]; then
    continue
  fi

  # Try once to deploy the cert to UniFi
  if deploy_cert_to_unifi "${domain}"; then
    echo "New certificate imported to UniFi keystore for domain: ${domain}"
    exit 0
  else
    echo "Unable to import certificate to UniFi keystore for domain: ${domain}"
    exit 1
  fi
done
