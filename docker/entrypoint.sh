#!/bin/bash

set -e

VERSION_FILE="VERSION"

if [[ -f "$VERSION_FILE" ]]; then
  VERSION=$(<"$VERSION_FILE")
else
  VERSION="unknown"
fi

echo "SEAFD VERSION: $VERSION"

BASE_DIR=${BASE_DIR:-"/seafd"}
mkdir -p "$BASE_DIR"

declare -a ACCOUNT_IDENTIFIERS=()
declare -A ACCOUNT_CONFIG=()
declare -A ACCOUNT_LIBRARIES

account_get_identifiers() {
  ACCOUNT_IDENTIFIERS=()
  while IFS='=' read -r key _; do
    if [[ "$key" =~ ^SEAFD_ACCOUNT_([A-Z0-9]+)$ ]]; then
      ACCOUNT_IDENTIFIERS+=("${BASH_REMATCH[1]}")
    fi
  done < <(env)
}

account_get_config() {
  local identifier="$1"
  local base="SEAFD_ACCOUNT_${identifier}"

  ACCOUNT_CONFIG[IDENTIFIER]="$identifier"
  ACCOUNT_CONFIG[USERNAME]="${!base}"

  local var
  for field in URL PASSWORD 2FA_SECRET DOWNLOAD_SPEED UPLOAD_SPEED SKIP_CERT; do
    var="${base}_${field}"
    ACCOUNT_CONFIG["$field"]="${!var}"
  done

  ACCOUNT_CONFIG[BASE_DIR]="${BASE_DIR}/${identifier,,}"
  ACCOUNT_CONFIG[CONFIG_DIR]="${BASE_DIR}/${identifier,,}/config"
  ACCOUNT_CONFIG[LIBRARY_DIR]="${BASE_DIR}/${identifier,,}/libraries"
}

account_get_libraries() {
  local identifier="$1"
  account_get_config "$identifier"

  ACCOUNT_LIBRARIES=()

  while IFS='=' read -r key value; do
    if [[ "$key" =~ ^SEAFD_ACCOUNT_${identifier}_LIBS_([A-Z0-9_]+)_PASSWORD$ ]]; then
      continue
    elif [[ "$key" =~ ^SEAFD_ACCOUNT_${identifier}_LIBS_([A-Z0-9_]+)$ ]]; then
      local lib_identifier="${BASH_REMATCH[1]}"
      local lib_guid="$value"
      local lib_passkey="SEAFD_ACCOUNT_${identifier}_LIBS_${lib_identifier}_PASSWORD"
      local lib_password="${!lib_passkey:-}"

      ACCOUNT_LIBRARIES["$lib_identifier.IDENTIFIER"]="$lib_identifier"
      ACCOUNT_LIBRARIES["$lib_identifier.GUID"]="$lib_guid"
      ACCOUNT_LIBRARIES["$lib_identifier.PASSWORD"]="$lib_password"
      ACCOUNT_LIBRARIES["$lib_identifier.LIBRARY_DIR"]="${ACCOUNT_CONFIG[LIBRARY_DIR]}/${lib_identifier,,}"
    fi
  done < <(env)
}

account_init() {
  local identifier="$1"
  account_get_config "$identifier"

  local base_dir="${ACCOUNT_CONFIG[BASE_DIR]}"
  local config_dir="${ACCOUNT_CONFIG[CONFIG_DIR]}"
  local lib_dir="${ACCOUNT_CONFIG[LIBRARY_DIR]}"
  local url="${ACCOUNT_CONFIG[URL]}"
  local skip_cert="${ACCOUNT_CONFIG[SKIP_CERT]}"
  local dl_limit="${ACCOUNT_CONFIG[DOWNLOAD_SPEED]}"
  local ul_limit="${ACCOUNT_CONFIG[UPLOAD_SPEED]}"

  echo "[INFO] [account=${identifier,,}]: Initializing Seafile CLI client."
  echo "   → Base directory      : $base_dir"
  echo "   → Config directory    : $config_dir"
  echo "   → Libraries directory : $lib_dir"
  echo "   → Server URL          : $url"
  echo "   → SSL verification    : $([[ "$skip_cert" == "true" ]] && echo "disabled" || echo "enabled")"
  echo "   → Download limit      : $dl_limit bytes"
  echo "   → Upload limit        : $ul_limit bytes"

  mkdir -p "$base_dir"
  account_get_libraries "$identifier"

  for lib in "${!ACCOUNT_LIBRARIES[@]}"; do
    if [[ "$lib" =~ \.LIBRARY_DIR$ ]]; then
      mkdir -p "${ACCOUNT_LIBRARIES[$lib]}"
    fi
  done

  if [ -f "$config_dir/seafile.ini" ]; then
    echo "[INFO] [account=${identifier,,}]: Seafile client already initialized at $config_dir, skipping init."
  else
    if ! seaf-cli init -c "$config_dir" -d "$base_dir"; then
      echo "Failed to initialize Seafile client. Check permissions or existing state."
      exit 1
    fi
  fi

  if [ "$skip_cert" = "true" ]; then
    if ! seaf-cli config -k disable_verify_certificate -v true -c "$config_dir"; then
      echo "Failed to configure SSL verification option."
      exit 1
    fi
  fi

  echo "[INFO] [account=${identifier,,}]: Starting Seafile daemon..."
  if ! seaf-cli start -c "$config_dir"; then
    echo "[ERROR] [account=${identifier,,}]: Failed to start Seafile daemon."
    exit 1
  fi

  echo "[INFO] [account=${identifier,,}]: Waiting 5 seconds for the daemon to fully initialize."
  sleep 5

  if [ "$dl_limit" -gt 0 ]; then
    if ! seaf-cli config -k download_limit -v "$dl_limit" -c "$config_dir"; then
      echo "[ERROR] [account=${identifier,,}]: Failed to configure download speed limit."
      exit 1
    fi
  fi

  if [ "$ul_limit" -gt 0 ]; then
    if ! seaf-cli config -k upload_limit -v "$ul_limit" -c "$config_dir"; then
      echo "[ERROR] [account=${identifier,,}]: Failed to configure upload speed limit."
      exit 1
    fi
  fi
}

account_sync() {
  local identifier="$1"
  account_get_config "$identifier"

  echo "[INFO] [account=${identifier,,}]: Attempting to sync Seafile libraries."

  local config_dir="${ACCOUNT_CONFIG[CONFIG_DIR]}"
  local config_url="${ACCOUNT_CONFIG[URL]}"
  local config_username="${ACCOUNT_CONFIG[USERNAME]}"
  local config_password="${ACCOUNT_CONFIG[PASSWORD]}"
  local config_2fa="${ACCOUNT_CONFIG[2FA_SECRET]}"

  local synced_libs
  synced_libs=$(seaf-cli list -c "${config_dir}" 2>/dev/null | awk 'NR > 1 { print $2 }')

  account_get_libraries "$identifier"

  if [ ${#ACCOUNT_LIBRARIES[@]} -eq 0 ]; then
    echo "[WARNING] [account=${identifier,,}]: No libraries found for this account, nothing to sync."
    return
  fi

  for key in "${!ACCOUNT_LIBRARIES[@]}"; do
    if [[ ! "$key" =~ \.IDENTIFIER$ ]]; then
      continue
    fi

    local lib_identifier="${ACCOUNT_LIBRARIES[$key]}"
    local lib_guid="${ACCOUNT_LIBRARIES[$lib_identifier.GUID]}"
    local lib_password="${ACCOUNT_LIBRARIES[$lib_identifier.PASSWORD]}"
    local lib_dir="${ACCOUNT_LIBRARIES[$lib_identifier.LIBRARY_DIR]}"

    if echo "$synced_libs" | grep -q -F "$lib_guid"; then
      echo "[INFO] [account=${identifier,,}, library=${lib_identifier,,}]: Library is already synced, skipping."
      continue
    fi

    echo "[INFO] [account=${identifier,,}, library=${lib_identifier,,}]: Processing library."
    mkdir -p "$lib_dir"

    local sync_args=(
      seaf-cli sync
      -l "$lib_guid"
      -d "$lib_dir"
      -s "$config_url"
      -u "$config_username"
      -p "$config_password"
      -c "$config_dir"
    )

    if [[ -n "$lib_password" ]]; then
      sync_args+=(-e "$lib_password")
    fi

    if [ -n "$config_2fa" ]; then
      echo "[INFO] [account=${identifier,,}, library=${lib_identifier,,}]: Generating TOTP token via oathtool."

      local totp
      totp=$(oathtool --base32 --totp "$config_2fa" 2>/dev/null)

      if [ -z "$totp" ]; then
        echo "[ERROR] [account=${identifier,,}, library=${lib_identifier,,}]: Failed to generate TOTP token."
        exit 1
      fi

      local prev_totp
      local attempts=0

      while true; do
        sleep 1
        totp=$(oathtool --base32 --totp "$config_2fa" 2>/dev/null)

        if [ -z "$totp" ]; then
          echo "[ERROR] [account=${identifier,,}, library=${lib_identifier,,}]: Failed to generate TOTP token."
          exit 1
        fi

        if [ "$totp" != "$prev_totp" ]; then
          prev_totp="$totp"
          break
        fi

        if ((attempts % 5 == 0)); then
          local remaining=$((30 - ($(date +%s) % 30)))
          echo "[INFO] [account=${identifier,,}, library=${lib_identifier,,}]: Waiting ~${remaining}s for new token."
        fi

        attempts=$((attempts + 1))

        if [ "$attempts" -ge 30 ]; then
          echo "[WARNING] [account=${identifier,,}, library=${lib_identifier,,}]: TOTP token has not rotated after $attempts tries."
          break
        fi
      done

      sync_args+=(-a "$totp")
    fi

    echo "[INFO] [account=${identifier,,}, library=${lib_identifier,,}]: Running sync command."
    if ! "${sync_args[@]}"; then
      echo "[ERROR] [account=${identifier,,}, library=${lib_identifier,,}]: Failed to sync library."
      exit 1
    fi

  done
}

account_get_identifiers

for identifier in "${ACCOUNT_IDENTIFIERS[@]}"; do
  account_init "$identifier"
  account_sync "$identifier"
done

log_paths=()

for identifier in "${ACCOUNT_IDENTIFIERS[@]}"; do
  account_get_config "$identifier"
  log_file="${ACCOUNT_CONFIG[CONFIG_DIR]}/logs/seafile.log"
  if [ -f "$log_file" ]; then
    log_paths+=("$log_file")
  else
    echo "[WARNING]: Log not found for ${identifier,,} at $log_file. Skipping."
  fi
done

if [ ${#log_paths[@]} -gt 0 ]; then
  exec tail -n +1 -F "${log_paths[@]}"
else
  echo "[WARNING]: No logs found. Sleeping indefinitely to keep container alive."
  exec tail -f /dev/null
fi
