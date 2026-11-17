#!/bin/bash

# Hotspot Control Script v1.0
# Manual control for WiFi fallback hotspot

CONFIG_FILE="/etc/wifi-fallback.conf"
LOG_FILE="/var/log/wifi-fallback.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HOTSPOT-CONTROL] $1" | sudo tee -a "$LOG_FILE"
}

get_status() {
    # Check current mode
    if pgrep hostapd >/dev/null; then
        echo "HOTSPOT"
    elif iwgetid wlan0 >/dev/null 2>&1; then
        echo "WIFI"
    else
        echo "DISCONNECTED"
    fi
}

case "$1" in
    on)
        echo "Enabling manual hotspot mode..."
        log_message "User requested hotspot ON"
        
        # Update config
        sudo sed -i 's/FORCE_HOTSPOT=.*/FORCE_HOTSPOT=true/' "$CONFIG_FILE"
        
        echo "✅ Hotspot mode enabled"
        echo "⏳ Restarting service..."
        
        sudo systemctl restart wifi-fallback
        
        echo ""
        echo "📡 Hotspot: $(hostname)-hotspot"
        echo "🔑 Password: raspberry"
        echo "🌐 Config: http://192.168.66.66:8088"
        ;;
        
    off)
        echo "Disabling manual hotspot mode..."
        log_message "User requested hotspot OFF"
        
        # Update config
        sudo sed -i 's/FORCE_HOTSPOT=.*/FORCE_HOTSPOT=false/' "$CONFIG_FILE"
        
        echo "✅ Hotspot mode disabled"
        echo "📶 Switching to WiFi mode..."
        
        # Show configured networks
        source "$CONFIG_FILE"
        [ -n "$MAIN_SSID" ] && echo "   Primary: $MAIN_SSID"
        [ -n "$BACKUP_SSID" ] && echo "   Backup: $BACKUP_SSID"
        
        if [ -z "$MAIN_SSID" ] && [ -z "$BACKUP_SSID" ]; then
            echo "⚠️  No WiFi networks configured!"
            echo "   Configure at: http://192.168.66.66:8088"
        fi
        
        sudo systemctl restart wifi-fallback
        ;;
        
    status)
        echo "🔍 WiFi Fallback Status"
        echo "======================="
        
        # Load config
        source "$CONFIG_FILE"
        
        # Current mode
        MODE=$(get_status)
        echo ""
        echo "Current Mode: $MODE"
        
        if [ "$MODE" = "HOTSPOT" ]; then
            echo "  SSID: $(hostname)-hotspot"
            echo "  IP: 192.168.66.66"
            CLIENTS=$(arp -an | grep -c "192.168.66" 2>/dev/null || echo "0")
            echo "  Clients: $CLIENTS"
        elif [ "$MODE" = "WIFI" ]; then
            SSID=$(iwgetid wlan0 -r)
            IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            echo "  Connected to: $SSID"
            echo "  IP: $IP"
        fi
        
        echo ""
        echo "Configuration:"
        echo "  Force Hotspot: $FORCE_HOTSPOT"
        echo "  Primary SSID: ${MAIN_SSID:-<none>}"
        echo "  Backup SSID: ${BACKUP_SSID:-<none>}"
        
        echo ""
        echo "Services:"
        systemctl is-active wifi-fallback >/dev/null && echo "  wifi-fallback: ✅ Running" || echo "  wifi-fallback: ❌ Stopped"
        pgrep hostapd >/dev/null && echo "  hostapd: ✅ Running" || echo "  hostapd: ❌ Stopped"
        pgrep dnsmasq >/dev/null && echo "  dnsmasq: ✅ Running" || echo "  dnsmasq: ❌ Stopped"
        
        echo ""
        echo "Recent Logs:"
        sudo tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
        ;;
        
    restart)
        echo "Restarting WiFi Fallback service..."
        log_message "User requested service restart"
        sudo systemctl restart wifi-fallback
        echo "✅ Service restarted"
        ;;
        
    *)
        echo "Usage: hotspot {on|off|status|restart}"
        echo ""
        echo "  on      - Force hotspot mode"
        echo "  off     - Disable forced hotspot"
        echo "  status  - Show current status"
        echo "  restart - Restart service"
        ;;
esac
