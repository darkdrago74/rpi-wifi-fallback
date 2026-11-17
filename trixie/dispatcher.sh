#!/bin/bash
# Antigravity Dispatcher
# Triggered by NetworkManager on interface state changes
# Path: /etc/NetworkManager/dispatcher.d/99-antigravity

INTERFACE="$1"
ACTION="$2"

# Define PATH to avoid 'command not found' in restricted env
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Only care about wlan0
if [ "$INTERFACE" != "wlan0" ]; then
    exit 0
fi

LOG_TAG="Antigravity-Dispatcher"
log() { logger -t "$LOG_TAG" "$1"; }

log "Event: $INTERFACE $ACTION"

case "$ACTION" in
    down)
        log "Interface down. Triggering Watchdog/Fallback..."
        # We start the service to handle the logic asynchronously
        systemctl start antigravity-watchdog.service
        ;;
    up)
        # Check if we have an IP/Gateway.
        # If CONNECTED but NO IP, the watchdog will catch it.
        # But we can speed it up.
        # Wait a moment for DHCP
        # We don't want to block the dispatcher.
        # Let the periodic watchdog handle 'Connected No Internet' for now to avoid complexity/race.
        ;;
esac

exit 0
