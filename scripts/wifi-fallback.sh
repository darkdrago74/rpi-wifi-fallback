#!/bin/bash

# WiFi Fallback Script v0.7.1 - Using nmcli for reliability
# Based on what worked in your web interface

# Configuration
WIFI_INTERFACE="wlan0"
HOTSPOT_SSID="$(hostname)-hotspot"
HOTSPOT_PASSWORD="raspberry"
HOTSPOT_IP="192.168.66.66"
CHECK_INTERVAL=30
MAX_RETRIES=4
RECONNECT_INTERVAL=1800  # 30 minutes between reconnection attempts
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false

# Files
CONFIG_FILE="/etc/wifi-fallback.conf"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

log_message() {
    echo "$(date): $1" | tee -a /var/log/wifi-fallback.log
}

# Check if clients are connected to hotspot
get_hotspot_clients() {
    if pgrep hostapd >/dev/null; then
        # Count clients in our subnet
        arp -an | grep -c "192.168.66" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Simple interface cleanup
cleanup_interface() {
    log_message "Cleaning up interface $WIFI_INTERFACE"
    
    # Kill processes
    killall -9 wpa_supplicant 2>/dev/null || true
    killall -9 hostapd 2>/dev/null || true
    killall -9 dnsmasq 2>/dev/null || true
    killall -9 dhclient 2>/dev/null || true
    
    sleep 2
    
    # Reset interface
    ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
    ip link set "$WIFI_INTERFACE" down
    sleep 2
    ip link set "$WIFI_INTERFACE" up
    sleep 2
    
    log_message "Interface cleanup completed"
}

# Check if WiFi is connected
is_wifi_connected() {
    # Use nmcli to check if wlan0 is connected
    if nmcli device status 2>/dev/null | grep -q "^$WIFI_INTERFACE.*connected"; then
        # Also verify we have an IP
        if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
            return 0
        fi
    fi
    return 1
}

# Check if hotspot is active
is_hotspot_active() {
    if pgrep hostapd >/dev/null && ip addr show "$WIFI_INTERFACE" | grep -q "$HOTSPOT_IP"; then
        return 0
    fi
    return 1
}

# Connect to WiFi using nmcli (this is what worked from web interface)
connect_to_wifi() {
    local ssid="$1"
    local password="$2"
    local network_name="$3"
    
    [ -z "$ssid" ] && return 1
    
    log_message "Attempting to connect to $network_name: $ssid"
    
    # Stop hotspot if running
    if is_hotspot_active; then
        stop_hotspot
        sleep 3
    fi
    
    # Clean interface
    cleanup_interface
    
    # Make sure NetworkManager can manage wlan0 temporarily
    nmcli device set wlan0 managed yes 2>/dev/null || true
    sleep 2
    
    # Delete existing connection if exists
    nmcli connection delete "$ssid" 2>/dev/null || true
    
    # Try to connect using nmcli (same as web interface does)
    if [ -n "$password" ]; then
        # WPA/WPA2 network
        if nmcli device wifi connect "$ssid" password "$password" ifname "$WIFI_INTERFACE" 2>/dev/null; then
            log_message "Successfully connected to $network_name via nmcli"
            sleep 3
            
            # Verify connection
            if is_wifi_connected; then
                # After successful connection, set wlan0 as unmanaged again
                nmcli device set wlan0 managed no 2>/dev/null || true
                return 0
            fi
        fi
    else
        # Open network
        if nmcli device wifi connect "$ssid" ifname "$WIFI_INTERFACE" 2>/dev/null; then
            log_message "Successfully connected to open network $network_name"
            nmcli device set wlan0 managed no 2>/dev/null || true
            return 0
        fi
    fi
    
    log_message "Failed to connect to $network_name"
    # Set back to unmanaged on failure
    nmcli device set wlan0 managed no 2>/dev/null || true
    return 1
}

# Setup NAT for internet sharing
setup_nat() {
    log_message "Setting up NAT"
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Clear old rules
    iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    
    # Add NAT rule
    iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
    iptables -A FORWARD -i "$WIFI_INTERFACE" -j ACCEPT
    iptables -A FORWARD -o "$WIFI_INTERFACE" -j ACCEPT
    
    log_message "NAT setup complete"
}

# Start hotspot
start_hotspot() {
    log_message "Starting hotspot mode"
    
    # Make sure wlan0 is unmanaged by NetworkManager
    nmcli device set wlan0 managed no 2>/dev/null || true
    
    # Clean interface
    cleanup_interface
    
    # Configure static IP
    ip addr add "$HOTSPOT_IP/24" dev "$WIFI_INTERFACE"
    
    # Configure lighttpd port
    sed -i "s/server.port.*=.*/server.port = 8080/" /etc/lighttpd/lighttpd.conf
    systemctl restart lighttpd
    
    # Start hostapd
    log_message "Starting hostapd"
    systemctl start hostapd
    sleep 5
    
    if ! pgrep hostapd >/dev/null; then
        log_message "ERROR: hostapd failed to start"
        return 1
    fi
    
    # Start dnsmasq
    log_message "Starting dnsmasq"
    systemctl start dnsmasq
    sleep 2
    
    if ! pgrep dnsmasq >/dev/null; then
        log_message "ERROR: dnsmasq failed to start"
        systemctl stop hostapd
        return 1
    fi
    
    # Setup NAT
    setup_nat
    
    log_message "Hotspot started successfully"
    log_message "Access: http://$HOTSPOT_IP:8080"
    
    return 0
}

# Stop hotspot
stop_hotspot() {
    log_message "Stopping hotspot mode"
    
    # Stop services
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    
    # Clear NAT
    iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    
    # Reset lighttpd port
    sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    systemctl restart lighttpd
    
    # Clean interface
    ip addr flush dev "$WIFI_INTERFACE"
    
    log_message "Hotspot stopped"
}

# Main loop
log_message "==== WiFi Fallback service starting v0.7.1 ===="

# Make sure NetworkManager is running
if ! systemctl is-active --quiet NetworkManager; then
    log_message "Starting NetworkManager..."
    systemctl start NetworkManager
    sleep 5
fi

hotspot_active=false
wifi_connected=false
last_force_state="$FORCE_HOTSPOT"
connection_attempts=0
last_reconnect_time=0

while true; do
    current_time=$(date +%s)
    
    # Reload configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Check if force hotspot state changed
    if [ "$last_force_state" != "$FORCE_HOTSPOT" ]; then
        log_message "Force hotspot changed to: $FORCE_HOTSPOT"
        last_force_state="$FORCE_HOTSPOT"
        
        if [ "$FORCE_HOTSPOT" = "true" ]; then
            # Enable hotspot
            if ! is_hotspot_active; then
                start_hotspot
                hotspot_active=true
                wifi_connected=false
            fi
        else
            # Disable force hotspot - try WiFi
            if is_hotspot_active; then
                stop_hotspot
                hotspot_active=false
            fi
            connection_attempts=0
        fi
    fi
    
    # Handle force hotspot mode
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        # Ensure hotspot stays active
        if ! is_hotspot_active; then
            log_message "Force hotspot enabled but not active - starting"
            start_hotspot
            hotspot_active=true
        else
            # Check NAT is still working
            if ! iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "192.168.66.0/24"; then
                log_message "NAT rules missing, reapplying..."
                setup_nat
            fi
        fi
    else
        # Normal mode - check status
        wifi_connected=false
        hotspot_active=false
        
        if is_wifi_connected; then
            wifi_connected=true
            connection_attempts=0
        elif is_hotspot_active; then
            hotspot_active=true
            
            # Check if we should try WiFi
            clients=$(get_hotspot_clients)
            time_since_last=$((current_time - last_reconnect_time))
            
            # Only try if: no clients AND enough time passed AND we have networks configured
            if [ "$clients" -eq 0 ] && [ $time_since_last -gt $RECONNECT_INTERVAL ]; then
                if [ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]; then
                    log_message "No clients connected, attempting WiFi reconnection"
                    stop_hotspot
                    hotspot_active=false
                    connection_attempts=0
                    last_reconnect_time=$current_time
                fi
            fi
        fi
        
        # Not connected to anything - try to connect
        if [ "$wifi_connected" = false ] && [ "$hotspot_active" = false ]; then
            connection_attempts=$((connection_attempts + 1))
            
            # Try main network
            if [ -n "$MAIN_SSID" ] && [ $connection_attempts -le $MAX_RETRIES ]; then
                log_message "Attempt $connection_attempts/$MAX_RETRIES for main network"
                if connect_to_wifi "$MAIN_SSID" "$MAIN_PASSWORD" "main"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            # Try backup network
            elif [ -n "$BACKUP_SSID" ] && [ $connection_attempts -le $((MAX_RETRIES * 2)) ]; then
                attempt_num=$((connection_attempts - MAX_RETRIES))
                log_message "Attempt $attempt_num/$MAX_RETRIES for backup network"
                if connect_to_wifi "$BACKUP_SSID" "$BACKUP_PASSWORD" "backup"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            # Start hotspot as fallback
            else
                log_message "All attempts failed, starting hotspot"
                if start_hotspot; then
                    hotspot_active=true
                    last_reconnect_time=$current_time
                fi
                connection_attempts=0
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
