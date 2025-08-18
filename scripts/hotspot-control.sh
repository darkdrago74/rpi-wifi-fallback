# Create manual hotspot control script
sudo tee /usr/local/bin/hotspot-control > /dev/null <<EOF
#!/bin/bash

CONFIG_FILE="/etc/wifi-fallback.conf"

case "$1" in
    on|enable|start)
        echo "Enabling manual hotspot mode..."
        # Set force hotspot in config
        if [ -f "$CONFIG_FILE" ]; then
            sed -i 's/FORCE_HOTSPOT=.*/FORCE_HOTSPOT=true/' "$CONFIG_FILE"
        else
            echo "FORCE_HOTSPOT=true" > "$CONFIG_FILE"
        fi
        echo "✅ Manual hotspot mode ENABLED"
        echo "🔄 Restarting WiFi service to apply changes..."
        sudo systemctl restart wifi-fallback.service
        sleep 5
        echo "📡 Hotspot should be active in ~30 seconds"
        echo "🌐 WiFi Config: http://192.168.66.66:8080"
        echo "🖨️ Klipper/Mainsail: http://192.168.66.66"
        ;;
    off|disable|stop)
        echo "Disabling manual hotspot mode..."
        if [ -f "$CONFIG_FILE" ]; then
            sed -i 's/FORCE_HOTSPOT=.*/FORCE_HOTSPOT=false/' "$CONFIG_FILE"
        fi
        echo "✅ Manual hotspot mode DISABLED"
        echo "🔄 Restarting WiFi service to reconnect to configured networks..."
        sudo systemctl restart wifi-fallback.service
        echo "📶 Will attempt to reconnect to WiFi in ~30 seconds"
        ;;
    status)
        if [ -f "$CONFIG_FILE" ] && grep -q "FORCE_HOTSPOT=true" "$CONFIG_FILE"; then
            echo "🔴 Manual hotspot mode: ENABLED"
        else
            echo "🟢 Manual hotspot mode: DISABLED"
        fi
        echo ""
        echo "Service status:"
        sudo systemctl status wifi-fallback.service --no-pager -l
        echo ""
        echo "Current network:"
        if iwgetid wlan0 >/dev/null 2>&1; then
            echo "📶 Connected to: $(iwgetid wlan0 -r)"
            echo "🌐 IP address: $(ip route get 1 | awk '{print $7}' | head -1)"
        else
            echo "📡 In hotspot mode or disconnected"
        fi
        ;;
    *)
        echo "Hotspot Control Commands:"
        echo ""
        echo "  hotspot-control on     - Enable manual hotspot mode"
        echo "  hotspot-control off    - Disable manual hotspot mode"  
        echo "  hotspot-control status - Show current status"
        echo ""
        echo "Manual hotspot mode keeps the hotspot active even when"
        echo "WiFi networks are available. Perfect for:"
        echo "• Allowing coworkers to connect"
        echo "• Maintenance and configuration" 
        echo "• Multiple user access"
        echo ""
        echo "Access points when in hotspot mode:"
        echo "• WiFi Config: http://192.168.66.66:8080"
        echo "• Klipper/Mainsail: http://192.168.66.66"
        ;;
esac
EOF

# Make it executable
sudo chmod +x /usr/local/bin/hotspot-control

# Create a convenient alias
echo 'alias hotspot="sudo hotspot-control"' | sudo tee -a /etc/bash.bashrc
