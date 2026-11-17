#!/bin/bash
# Antigravity Watchdog FSM
# Implements the fallback logic for Debian Trixie

FALLBACK_CON="Antigravity_AP"
TARGET_HOST="8.8.8.8"
GATEWAY_CHECK=true
LOG_TAG="Antigravity-FSM"

log() {
    logger -t "$LOG_TAG" "$1"
    echo "$(date) [$LOG_TAG] $1"
}

# 0. Load Configuration & Sync Profiles
CONF_FILE="/etc/wifi-fallback.conf"
FORCE_HOTSPOT=false

if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
fi

if [ "$FORCE_HOTSPOT" == "true" ]; then
    log "Force Hotspot Mode is ENABLED. Preventing client connections."
fi

# Sync Function: Ensure NM defines the configured networks
sync_profile() {
    local ssid="$1"
    local psk="$2"
    if [ -n "$ssid" ]; then
        if ! nmcli -t -f 802-11-wireless.ssid con show | grep -q "^$ssid$"; then
            log "Creating new profile for $ssid"
            nmcli con add type wifi ifname wlan0 con-name "$ssid" ssid "$ssid" \
                wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" 2>/dev/null
        else
            # Update PSK if needed? Hard to check without revealing secrets.
            # Assume if it exists it's correct throughout the session, or user deleted and we recreate.
            :
        fi
    fi
}

sync_profile "$MAIN_SSID" "$MAIN_PASSWORD"
sync_profile "$BACKUP_SSID" "$BACKUP_PASSWORD"


# 1. Get Current State
# We look for the active connection on wlan0
ACTIVE_CON=$(nmcli -t -f NAME,DEVICE con show --active | grep ":wlan0" | cut -d':' -f1)

log "Heartbeat. Active Connection on wlan0: '${ACTIVE_CON}'"

if [ "$ACTIVE_CON" == "$FALLBACK_CON" ]; then
    # STATE: AP_ACTIVE
    
    if [ "$FORCE_HOTSPOT" == "true" ]; then
        log "Force Hotspot Active. Skipping scan."
        exit 0
    fi

    # Logic: Scan for known networks (Hysteresis)
    # We don't want to scan every 2 minutes as it disrupts the AP.
    # Let's check a timestamp file.
    SCAN_MARKER="/tmp/antigravity_last_scan"
    NOW=$(date +%s)
    
    if [ -f "$SCAN_MARKER" ]; then
        LAST_SCAN=$(cat "$SCAN_MARKER")
    else
        LAST_SCAN=0
    fi
    
    DIFF=$((NOW - LAST_SCAN))
    SCAN_INTERVAL=900 # 15 minutes
    
    if [ $DIFF -ge $SCAN_INTERVAL ]; then
        log "Scanning window open. Checking for known networks..."
        
        # Get list of configured SSIDs (excluding Fallback)
        KNOWN_SSIDS=$(nmcli -t -f 802-11-wireless.ssid con show | grep -v "$FALLBACK_CON" | sort -u)
        
        if [ -z "$KNOWN_SSIDS" ]; then
            log "No known client networks configured. Stay in AP."
        else
            # Perform Scan
            # Note: Scanning might temporarily drop AP clients or be slow.
            VISIBLE_SSIDS=$(nmcli -t -f SSID dev wifi list --rescan yes)
            
            FOUND_MATCH=""
            for ssid in $KNOWN_SSIDS; do
                if echo "$VISIBLE_SSIDS" | grep -q "^$ssid$"; then
                    FOUND_MATCH="$ssid"
                    break
                fi
            done
            
            if [ -n "$FOUND_MATCH" ]; then
                log "Found known network: $FOUND_MATCH. Attempting transition..."
                # Attempt connection
                if nmcli con up id "$FOUND_MATCH"; then
                    log "Transition Successful. Connected to $FOUND_MATCH."
                    exit 0
                else
                    log "Transition Failed. Reverting to AP."
                    nmcli con up "$FALLBACK_CON"
                fi
            else
                log "No known networks found in range."
            fi
        fi
        
        echo "$NOW" > "$SCAN_MARKER"
    else
        log "In AP Mode. Scan window closed (Wait $((SCAN_INTERVAL - DIFF))s)."
    fi

elif [ -z "$ACTIVE_CON" ]; then
    # STATE: DISCONNECTED
    log "Interface wlan0 is disconnected. Triggering Fallback."
    nmcli con up "$FALLBACK_CON"

else
    # STATE: CLIENT_CONNECTED
    # Logic: Verify L3 Connectivity
    
    FAIL=0
    
    # 1. Gateway Ping (if available)
    GATEWAY=$(ip route | grep default | awk '{print $3}')
    if [ -n "$GATEWAY" ]; then
        if ! ping -c 3 -W 2 "$GATEWAY" >/dev/null; then
            log "Gateway ($GATEWAY) unreachable."
            FAIL=$((FAIL + 1))
        fi
    else
        log "No default gateway found."
        FAIL=$((FAIL + 1))
    fi
    
    # 2. Internet Ping (if gateway passed or strict mode)
    if ! ping -c 3 -W 3 "$TARGET_HOST" >/dev/null; then
        log "Internet ($TARGET_HOST) unreachable."
        FAIL=$((FAIL + 1))
    fi
    
    # Threshold
    if [ $FAIL -ge 2 ]; then
        log "Connectivity lost ($FAIL failures). Triggering Fallback."
        nmcli con up "$FALLBACK_CON"
    else
        log "Connectivity OK."
    fi
fi
