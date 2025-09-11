#!/bin/bash

# Configuration
WIFI_INTERFACE="wlan0"
HOTSPOT_SSID="$(hostname)-hotspot"
HOTSPOT_PASSWORD="raspberry"
HOTSPOT_IP="192.168.66.66"
WEB_PORT="8080"  # Web configurator port to avoid conflicts
CHECK_INTERVAL=300
MAX_RETRIES=2
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false

# Files
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
CONFIG_FILE="/etc/wifi-fallback.conf"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

log_message() {
    echo "$(date): $1" | sudo tee -a /var/log/wifi-fallback.log
}

is_wifi_connected() {
    # Check wpa_supplicant state first
    if wpa_cli -i "$WIFI_INTERFACE" status | grep -q "wpa_state=COMPLETED"; then
        # Verify we have IP address
        if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
            return 0
        fi
    fi
    return 1
}

connect_to_wifi() {
    local ssid="$1"
    local password="$2"
    local network_name="$3"
    
    log_message "Attempting to connect to $network_name: $ssid"
    
    # Create temporary wpa_supplicant config
    sudo tee /tmp/wpa_temp.conf > /dev/null <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=GB

network={
    ssid="$ssid"
    psk="$password"
    key_mgmt=WPA-PSK
}
EOF
    
    # Stop current wpa_supplicant
    sudo systemctl stop wpa_supplicant
    sudo killall wpa_supplicant 2>/dev/null || true
    
    # Start wpa_supplicant with temp config
    sudo wpa_supplicant -B -i "$WIFI_INTERFACE" -c /tmp/wpa_temp.conf
    
    # Wait for connection
    sleep 10
    
    # Request DHCP
    sudo dhclient "$WIFI_INTERFACE" 2>/dev/null
    
    # Check if connected
    if is_wifi_connected; then
        log_message "Successfully connected to $network_name"
        # Save successful configuration
        sudo cp /tmp/wpa_temp.conf "$WPA_CONF"
        return 0
    else
        log_message "Failed to connect to $network_name"
        return 1
    fi
}

start_hotspot() {
    log_message "Starting hotspot mode - forcing interface control"
    
    # ENHANCED interface cleanup with better process management
    log_message "Cleaning up WiFi client mode before hotspot"
    
    # Disable auto-restart of conflicting services temporarily
    sudo systemctl mask wpa_supplicant@wlan0 2>/dev/null || true
    sudo systemctl mask wpa_supplicant 2>/dev/null || true
    sudo systemctl mask dhcpcd 2>/dev/null || true
    
    # Stop ALL WiFi client services more thoroughly
    sudo systemctl stop wpa_supplicant@wlan0 2>/dev/null || true
    sudo systemctl stop wpa_supplicant 2>/dev/null || true  
    sudo systemctl stop dhcpcd 2>/dev/null || true
    sudo systemctl stop NetworkManager 2>/dev/null || true
    
    # Kill processes multiple times to ensure they're really dead
    for i in {1..3}; do
        sudo killall -9 wpa_supplicant dhclient dhcpcd wpa_cli NetworkManager 2>/dev/null || true
        sleep 1
    done
    
    # Remove any wpa_supplicant control sockets
    sudo rm -rf /var/run/wpa_supplicant/wlan0 2>/dev/null || true
    sudo rm -rf /tmp/wpa_ctrl_* 2>/dev/null || true
    
    # Reset WiFi completely
    log_message "Resetting WiFi interface completely"
    sudo rfkill block wifi
    sleep 2
    sudo rfkill unblock wifi
    sleep 2
    
    # Reset interface thoroughly
    sudo ip link set $WIFI_INTERFACE down
    sudo ip addr flush dev $WIFI_INTERFACE
    
    # Remove interface from any bridge or master
    sudo ip link set $WIFI_INTERFACE nomaster 2>/dev/null || true
    
    # Wait longer for interface to be truly free
    sleep 5
    
    # Bring interface back up
    sudo ip link set $WIFI_INTERFACE up
    sleep 3
    
    # Set static IP for hotspot
    sudo ip addr add 192.168.66.66/24 dev $WIFI_INTERFACE
    
    log_message "Interface cleaned and ready for hotspot"
    
    # Start hostapd with better error checking
    log_message "Starting hostapd with enhanced monitoring"
    
    # Try starting hostapd
    sudo systemctl start hostapd
    
    # Wait and verify it started
    sleep 8
    if ! sudo systemctl is-active --quiet hostapd; then
        log_message "ERROR: hostapd failed to start, checking logs"
        sudo journalctl -u hostapd --no-pager -l | tail -10 | while read line; do
            log_message "hostapd: $line"
        done
        
        # Try manual start for debugging
        log_message "Attempting manual hostapd start"
        sudo hostapd /etc/hostapd/hostapd.conf -B 2>&1 | while read line; do
            log_message "hostapd manual: $line"
        done
        
        # Unmask services before returning
        sudo systemctl unmask wpa_supplicant@wlan0 wpa_supplicant dhcpcd 2>/dev/null || true
        return 1
    fi
    
    # Additional verification - check if interface is in AP mode
    sleep 5
    if iwgetid $WIFI_INTERFACE 2>/dev/null; then
        log_message "ERROR: Interface still in client mode after hostapd start"
        log_message "This indicates hostapd isn't properly controlling the interface"
        
        # Show interface details for debugging
        log_message "Interface details: $(ip link show $WIFI_INTERFACE)"
        log_message "Interface addresses: $(ip addr show $WIFI_INTERFACE | grep inet)"
        
        sudo systemctl stop hostapd
        sudo systemctl unmask wpa_supplicant@wlan0 wpa_supplicant dhcpcd 2>/dev/null || true
        return 1
    fi
    
    # Start dnsmasq
    log_message "Starting dnsmasq"
    sudo systemctl start dnsmasq
    if ! sudo systemctl is-active --quiet dnsmasq; then
        log_message "ERROR: dnsmasq failed to start"
        sudo systemctl stop hostapd
        sudo systemctl unmask wpa_supplicant@wlan0 wpa_supplicant dhcpcd 2>/dev/null || true
        return 1
    fi
    
    # Configure iptables for NAT forwarding (if available)
    if command -v iptables >/dev/null 2>&1; then
        log_message "Configuring NAT forwarding with iptables"
        sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
        sudo iptables -A FORWARD -i $WIFI_INTERFACE -o eth0 -j ACCEPT 2>/dev/null || true
        sudo iptables -A FORWARD -i eth0 -o $WIFI_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    else
        log_message "WARNING: iptables not available, NAT forwarding not configured"
    fi
    
    # Final verification with more time
    log_message "Verifying hotspot functionality"
    sleep 10
    
    # Check if interface is properly configured
    if ! ip addr show $WIFI_INTERFACE | grep -q "192.168.66.66"; then
        log_message "ERROR: Hotspot IP not properly configured"
        return 1
    fi
    
    # Check if hostapd is actually running and interface is in AP mode
    if ! pgrep hostapd > /dev/null; then
        log_message "ERROR: hostapd process not running"
        return 1
    fi
    
    # Try to detect if hotspot is broadcasting (with timeout)
    log_message "Checking if hotspot is broadcasting..."
    if timeout 15s sudo iwlist $WIFI_INTERFACE scan 2>/dev/null | grep -q "TestBenchLinuxRoro-hotspot"; then
        log_message "✅ SUCCESS: Hotspot 'TestBenchLinuxRoro-hotspot' is broadcasting and discoverable!"
    else
        log_message "⚠️  WARNING: Cannot detect hotspot broadcasting yet (may still be initializing)"
    fi
    
    log_message "✅ Hotspot services started successfully - ready for connections"
    
    # Re-enable services for future use (but don't start them)
    sudo systemctl unmask wpa_supplicant@wlan0 wpa_supplicant dhcpcd 2>/dev/null || true
    
    return 0
}

stop_hotspot() {
    log_message "Stopping hotspot mode"
    
    # Stop services
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    
    # Clean up iptables rules (if available)
    if command -v iptables >/dev/null 2>&1; then
        sudo iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
        sudo iptables -D FORWARD -i $WIFI_INTERFACE -o eth0 -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -i eth0 -o $WIFI_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    fi
    
    # Remove static IP
    sudo ip addr flush dev "$WIFI_INTERFACE"
    
    # Restart wpa_supplicant
    sudo systemctl start wpa_supplicant
    
    # Reset lighttpd to default port
    sudo sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    log_message "Hotspot stopped, attempting WiFi connection"
}

# Main loop
hotspot_active=false
main_retry_count=0
backup_retry_count=0
current_network="none"

while true; do
    # Check if hotspot is forced
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        if [ "$hotspot_active" = false ]; then
            log_message "Hotspot mode is FORCED - starting hotspot"
            if start_hotspot; then
                hotspot_active=true
            fi
        fi
        sleep $CHECK_INTERVAL
        # Reload config to check if force mode was disabled
        if [ -f "$CONFIG_FILE" ]; then
            source "$CONFIG_FILE"
        fi
        continue
    fi
    
    if is_wifi_connected; then
        if [ "$hotspot_active" = true ]; then
            stop_hotspot
            hotspot_active=false
        fi
        main_retry_count=0
        backup_retry_count=0
        log_message "WiFi connected successfully to $(iwgetid "$WIFI_INTERFACE" -r)"
    else
        log_message "No WiFi connection detected"
        
        # Try main network first
        if [ -n "$MAIN_SSID" ] && [ $main_retry_count -lt $MAX_RETRIES ]; then
            main_retry_count=$((main_retry_count + 1))
            if connect_to_wifi "$MAIN_SSID" "$MAIN_PASSWORD" "MAIN"; then
                current_network="main"
                main_retry_count=0
                backup_retry_count=0
                continue
            fi
        # If main failed, try backup
        elif [ -n "$BACKUP_SSID" ] && [ $backup_retry_count -lt $MAX_RETRIES ]; then
            backup_retry_count=$((backup_retry_count + 1))
            if connect_to_wifi "$BACKUP_SSID" "$BACKUP_PASSWORD" "BACKUP"; then
                current_network="backup"
                main_retry_count=0
                backup_retry_count=0
                continue
            fi
        # Both failed, start hotspot
        elif [ "$hotspot_active" = false ]; then
            log_message "Both networks failed after $MAX_RETRIES attempts each. Starting hotspot."
            if start_hotspot; then
                hotspot_active=true
            fi
            main_retry_count=0
            backup_retry_count=0
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
