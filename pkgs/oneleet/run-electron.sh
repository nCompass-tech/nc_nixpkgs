#!/bin/bash

# # Start dbus if not running
# if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
#   eval $(dbus-launch --sh-syntax)
# fi

# Make sure any existing gnome-keyring-daemon is properly terminated
killall gnome-keyring-daemon 2>/dev/null

# Start fresh daemon and capture its output - don't use --replace as it can cause issues
KEYRING_OUTPUT=$(gnome-keyring-daemon --replace --components=secrets,pkcs11,ssh)
echo "Raw keyring daemon output: $KEYRING_OUTPUT"

# Process each line of output to set variables
while IFS= read -r line; do
  if [[ "$line" =~ ^([A-Z_]+)=(.*) ]]; then
    var_name="${BASH_REMATCH[1]}"
    var_value="${BASH_REMATCH[2]}"
    export "$var_name"="$var_value"
    echo "Set $var_name=$var_value"
  fi
done <<< "$KEYRING_OUTPUT"

# IMPORTANT: Save these variables to a file for other processes to use
{
  echo "export GNOME_KEYRING_CONTROL=\"$GNOME_KEYRING_CONTROL\""
  echo "export SSH_AUTH_SOCK=\"$SSH_AUTH_SOCK\""
  echo "export GPG_AGENT_INFO=\"$GPG_AGENT_INFO\""
} > ~/.gnome-keyring-env

# Check if the variables are set
echo "GNOME_KEYRING_CONTROL: ${GNOME_KEYRING_CONTROL:-not set}"
echo "SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-not set}"
echo "GPG_AGENT_INFO: ${GPG_AGENT_INFO:-not set}"

# Test if we can access the keyring
if command -v secret-tool &> /dev/null; then
  echo "Testing keyring access with secret-tool..."
  if secret-tool store --label="Test" service test key test; then
    echo "Successfully stored test key"
    if VALUE=$(secret-tool lookup service test key test); then
      echo "Successfully retrieved test key: $VALUE"
    else
      echo "Failed to retrieve test key"
    fi
  else
    echo "Failed to store test key"
  fi
else
  echo "secret-tool not found, can't test keyring access"
fi

# # Create test key if it doesn't exist
# secret-tool store --label="Electron Test" service test key test || true

# Run electron with the correct password store
electron main.js --password-store=gnome-libsecret 
