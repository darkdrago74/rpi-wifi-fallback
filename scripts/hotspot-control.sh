#!/bin/bash

CONFIG_FILE="/etc/wifi-fallback.conf"
LOG_FILE="/var/log/wifi-fallback.log"

log_message() {
    echo "$(date): [HOTSPOT-CONTROL] $1" | sudo tee -a "$LOG_FILE"
}

get_connected_clients() {
    # Function to get connected clients count
    local count=$(sudo arp -an | grep -c "192.168.66" || echo "0")
    echo "$count"
}

get_wifi_ip() {
    # Function to get WiFi IP address
    local ip=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    echo "$ip"
}

case "$1" in
    on|enable|start)
        echo "Enabling manual hotspot mode..."
        log_message "User requested hotspot ON"
        
        # Update config file
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i 's/FORCE_HOTSPOT=.*/FORCE_HOTSPOT=true/' "$CONFIG_FILE"
        else
            echo "FORCE_HOTSPOT=true" | sudo tee "$CONFIG_FILE" > /dev/null
        fi
        
        echo "✅ Manual hotspot mode ENABLED"
        echo "⏳ Switching to hotspot mode..."
        echo ""
        
        # Force immediate switch by restarting service
        sudo systemctl restart wifi-fallback
        
        echo "⏳ Please wait 15-30 seconds for hotspot to activate..."
        echo ""
        echo "📡 Hotspot Name: $(hostname)-hotspot"
        echo "🔑 Password: raspberry"
        echo "🌐 WiFi Config: http://192.168.66.66:8080"
        echo "🖨️ Klipper/Mainsail: http://192.168.66.66"
        
        log_message "Force hotspot enabled in config, service restarted"
        ;;
        
    off|disable|stop)
        echo "Disabling manual hotspot mode..."
        log_message "User requested hotspot OFF"
        
        # Update config file
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i 's/FORCE_HOTSPOT=.*/FORCE_HOTSPOT=false/' "$CONFIG_FILE"
        else
            echo "FORCE_HOTSPOT=false" | sudo tee "$CONFIG_FILE" > /dev/null
        fi
        
        echo "✅ Manual hotspot mode DISABLED"
        echo "📶 Switching back to WiFi mode..."
        
        # Show current configured networks
        if [ -f "$CONFIG_FILE" ]; then
            source "$CONFIG_FILE"
            if [ -n "$MAIN_SSID" ]; then
                echo "   Will try primary network: $MAIN_SSID"
            fi
            if [ -n "$BACKUP_SSID" ]; then
                echo "   Will try backup network: $BACKUP_SSID"
            fi
            if [ -z "$MAIN_SSID" ] && [ -z "$BACKUP_SSID" ]; then
                echo "⚠️  WARNING: No WiFi networks configured!"
                echo "   The device will return to hotspot mode."
                echo "   Configure networks at http://192.168.66.66:8080"
            fi
        fi
        
        # Force immediate switch by restarting service
        sudo systemctl restart wifi-fallback
        
        echo "⏳ Please wait 15-30 seconds for WiFi connection..."
        
        log_message "Force hotspot disabled in config, service restarted"
        ;;
        
    status)
        echo "🔍 Hotspot Control Status"
        echo "========================="
        echo ""
        
        # Check force hotspot setting
        if [ -f "$CONFIG_FILE" ]; then
            source "$CONFIG_FILE"
            if [ "$FORCE_HOTSPOT" = "true" ]; then
                echo "🔴 Manual hotspot mode: ENABLED (forced on)"
            else
                echo "🟢 Manual hotspot mode: DISABLED (auto-fallback mode)"
            fi
            
            echo ""
            echo "📋 Configured Networks:"
            if [ -n "$MAIN_SSID" ]; then
                echo "   Primary: $MAIN_SSID"
            else
                echo "   Primary: (not configured)"
            fi
            if [ -n "$BACKUP_SSID" ]; then
                echo "   Backup: $BACKUP_SSID"
            else
                echo "   Backup: (not configured)"
            fi
        else
            echo "⚠️  No configuration file found"
        fi
        
        echo ""
        echo "📡 Current Network Status:"
        
        # Check if hostapd is running
        if pgrep hostapd >/dev/null; then
            echo "   Mode: HOTSPOT ACTIVE"
            echo "   SSID: $(hostname)-hotspot"
            echo "   IP: 192.168.66.66"
            
            # Check NAT status
            if sudo iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "192.168.66.0/24"; then
                echo "   NAT: ✅ Configured"
            else
                echo "   NAT: ❌ Not configured (no internet sharing)"
            fi
            
            # Check connected clients using function
            clients=$(get_connected_clients)
            echo "   Connected clients: $clients"
        else
            # Check WiFi connection
            if iwgetid wlan0 >/dev/null 2>&1; then
                echo "   Mode: WIFI CLIENT"
                connected_ssid=$(iwgetid wlan0 -r)
                if [ -n "$connected_ssid" ]; then
                    echo "   Connected to: $connected_ssid"
                    wifi_ip=$(get_wifi_ip)
                    if [ -n "$wifi_ip" ]; then
                        echo "   IP address: $wifi_ip"
                    fi
                fi
            else
                echo "   Mode: DISCONNECTED/TRANSITIONING"
            fi
        fi
        
        # Check Ethernet status
        echo ""
        echo "🔌 Ethernet Status:"
        if ip link show eth0 | grep -q "state UP"; then
            eth_ip=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            if [ -n "$eth_ip" ]; then
                echo "   Connected with IP: $eth_ip"
            else
                echo "   Connected but no IP assigned"
            fi
        else
            echo "   Not connected"
        fi
        
        echo ""
        echo "🔧 Service Status:"
        if systemctl is-active --quiet wifi-fallback; then
            echo "   wifi-fallback: ✅ Running"
        else
            echo "   wifi-fallback: ❌ Stopped"
        fi
        
        # Show last few log entries
        echo ""
        echo "📋 Recent Activity:"
        if [ -f "$LOG_FILE" ]; then
            sudo tail -5 "$LOG_FILE" | sed 's/^/   /'
        else
            echo "   No log file found"
        fi
        ;;
        
    restart)
        echo "🔄 Restarting WiFi Fallback service..."
        log_message "User requested service restart"
        sudo systemctl restart wifi-fallback
        echo "✅ Service restarted"
        echo "⏳ Please wait 30 seconds for changes to take effect"
        ;;
        
    *)
        echo "Hotspot Control - Manage WiFi Fallback Hotspot"
        echo "=============================================="
        echo ""
        echo "Usage: hotspot {on|off|status|restart}"
        echo ""
        echo "Commands:"
        echo "  on      - Force hotspot mode (disable WiFi connections)"
        echo "  off     - Disable forced hotspot (return to auto-fallback)"
        echo "  status  - Show current hotspot and network status"
        echo "  restart - Restart the WiFi fallback service"
        echo ""
        echo "Examples:"
        echo "  hotspot on      # Keep hotspot active for coworker access"
        echo "  hotspot off     # Return to normal WiFi with fallback"
        echo "  hotspot status  # Check current state and connections"
        echo ""
        echo "Access points when in hotspot mode:"
        echo "  • WiFi Config: http://192.168.66.66:8080"
        echo "  • Klipper/Mainsail: http://192.168.66.66"
        ;;
esac
