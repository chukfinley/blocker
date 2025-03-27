#!/bin/bash
#
# Blocker Service:
# - Monitors a JSON configuration file for blocked apps/websites.
# - Kills blocked desktop apps during configured blocked time.
# - Updates the NextDNS denylist via API.
# - Logs events to a specified log file.
# - Sends desktop notifications when a blocked app launch is detected.
#
# Requirements: jq, curl, notify-send
#
# Usage:
#   sudo ./blocker_service.sh
#

# -------------------------------
# Configuration file path (edit if required)
CONFIG_FILE="/root/blocker_config.json"

# Validate that the configuration file exists and is a valid JSON.
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Configuration file $CONFIG_FILE does not exist. Exiting."
  exit 1
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "Configuration file $CONFIG_FILE contains invalid JSON. Exiting."
  exit 1
fi

# Poll interval (in seconds)
POLL_INTERVAL=10

# -------------------------------
# Functions

# Log messages to the log file.
log_message() {
  local message="$1"
  LOG_FILE=$(jq -r '.log_file // "/var/log/blocker.log"' "$CONFIG_FILE")
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" >> "$LOG_FILE"
}

# Determine if the current time is within the blocked period.
is_blocked_time() {
  BLOCKED_START=$(jq -r '.blocked_time.start' "$CONFIG_FILE")
  BLOCKED_END=$(jq -r '.blocked_time.end' "$CONFIG_FILE")
  current=$(date +%H:%M)
  if [[ "$current" > "$BLOCKED_START" && "$current" < "$BLOCKED_END" ]]; then
    return 0
  else
    return 1
  fi
}

# Send a desktop notification to the target user.
send_notification() {
  local title="$1"
  local message="$2"
  TARGET_USER=$(jq -r '.target_user' "$CONFIG_FILE")
  if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "null" ]; then
    log_message "Target user not configured."
    return 1
  fi
  export DISPLAY=:0
  su - "$TARGET_USER" -c "notify-send '$title' '$message'"
}

# Update the NextDNS Denylist from the configuration.
update_nextdns_websites() {
  websites=$(jq -r '.blocked_websites[]' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$websites" ]; then
    log_message "No blocked websites defined in configuration."
    return 0
  fi

  # Build the JSON payload.
  domains_json="[]"
  for site in $websites; do
    if is_blocked_time; then
      obj=$(printf '{"id": "%s", "active": true}' "$site")
    else
      obj=$(printf '{"id": "%s", "active": false}' "$site")
    fi
    domains_json=$(echo "$domains_json" | jq --argjson o "$obj" '. + [$o]')
  done
  payload=$(jq -n --argjson denylist "$domains_json" '{denylist: $denylist}')

  # Extract NextDNS credentials from the configuration.
  NEXTDNS_PROFILE_ID=$(jq -r '.nextdns.profile_id' "$CONFIG_FILE")
  API_KEY=$(jq -r '.nextdns.api_key' "$CONFIG_FILE")
  if [ -z "$NEXTDNS_PROFILE_ID" ] || [ "$NEXTDNS_PROFILE_ID" = "null" ]; then
    log_message "NextDNS profile ID not configured."
    return 1
  fi
  if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    log_message "NextDNS API key not configured."
    return 1
  fi

  NEXTDNS_DENYLIST_URL="https://api.nextdns.io/profiles/${NEXTDNS_PROFILE_ID}/denylist"
  AUTH_HEADER="X-Api-Key: ${API_KEY}"
  CONTENT_TYPE="Content-Type: application/json"

  if is_blocked_time; then
    log_message "Blocked time active: updating NextDNS denylist (adding websites)..."
    response=$(curl -s -X POST "$NEXTDNS_DENYLIST_URL" \
      -H "$AUTH_HEADER" -H "$CONTENT_TYPE" -d "$payload")
    log_message "NextDNS POST response: $response"
  else
    log_message "Off blocked time: deactivating NextDNS denylist entries..."
    response=$(curl -s -X PATCH "$NEXTDNS_DENYLIST_URL" \
      -H "$AUTH_HEADER" -H "$CONTENT_TYPE" -d "$payload")
    log_message "NextDNS PATCH response: $response"
  fi
}

# Kill blocked desktop applications.
kill_blocked_apps() {
  apps=$(jq -r '.blocked_apps[]' "$CONFIG_FILE" 2>/dev/null)
  if is_blocked_time; then
    for app in $apps; do
      if pgrep "$app" &>/dev/null; then
        log_message "User attempted to open '$app' during blocked time."
        send_notification "Blocked Application" "You attempted to open '$app'. It has been closed."
        killall "$app" 2>/dev/null && log_message "Killed '$app'." || log_message "Failed to kill '$app'."
      fi
    done
  fi
}

# -------------------------------
# Main Loop: Poll config file and enforce policies.
main_loop() {
  last_checksum=""
  while true; do
    checksum=$(sha256sum "$CONFIG_FILE" | awk '{print $1}')
    if [ "$checksum" != "$last_checksum" ]; then
      log_message "Configuration change detected. New checksum: $checksum"
      last_checksum="$checksum"
    fi
    kill_blocked_apps
    update_nextdns_websites
    sleep "$POLL_INTERVAL"
  done
}

log_message "Starting NextDNS Blocker Service as root..."
main_loop
