#!/bin/bash

# WiFi Fallback Script v2.1 - Stable state transitions
# Configuration
WIFI_INTERFACE="wlan0"
HOTSPOT_SSID="$(hostname)-hotspot"
HOTSPOT_PASSWORD="raspberry"
HOTSPOT_IP="192.168.66.66"
CHECK_INTERVAL=30
MAX_RETRIES=4
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

# Complete cleanup function - kills ALL conflicting processes
deep_cleanup_interface() {
    log_message "Performing deep cleanup of $WIFI_INTERFACE"
    
    # Stop all services that might interfere
    sudo systemctl stop wpa_supplicant 2>/dev/null || true
    sudo systemctl stop wpa_supplicant@wlan0 2>/dev/null || true
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    sudo systemctl stop dhcpcd 2>/dev/null || true
    
    # Kill processes multiple times to ensure they're dead
    for i in {1..3}; do
        sudo killall -9 wpa_supplicant 2>/dev/null || true
        sudo killall -9 hostapd 2>/dev/null || true
        sudo killall -9 dnsmasq 2>/dev/null || true
        sudo killall -9 dhclient 2>/dev/null || true
        sudo killall -9 dhcpcd 2>/dev/null || true
        sudo killall -9 wpa_cli 2>/dev/null || true
        sleep 1
    done
    
    # Remove any control sockets
    sudo rm -rf /var/run/wpa_supplicant/* 2>/dev/null || true
    sudo rm -rf /tmp/wpa_ctrl_* 2>/dev/null || true
    
    # Clear IP addresses
    sudo ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
    
    # Bring interface completely down
    sudo ip link set "$WIFI_INTERFACE" down
    sleep 2
    
    # Bring back up
    sudo ip link set "$WIFI_INTERFACE" up
    sleep 2
    
    log_message "Deep cleanup completed"
}

is_wifi_connected() {
    # More thorough connection check
    if ! command -v wpa_cli >/dev/null 2>&1; then
        return 1
    fi
    
    # Check if wpa_supplicant is running and connected
    if wpa_cli -i "$WIFI_INTERFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
        # Also verify we have an IP
        if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
            # Try to ping gateway to verify connection
            local gateway=$(ip route | grep default | grep "$WIFI_INTERFACE" | awk '{print $3}' | head -1)
            if [ -n "$gateway" ]; then
                if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
                    return 0
                fi
            fi
        fi
    fi
    return 1
}

is_hotspot_active() {
    # Check if hostapd is running AND interface has hotspot IP
    if pgrep hostapd >/dev/null && ip addr show "$WIFI_INTERFACE" | grep -q "$HOTSPOT_IP"; then
        return 0
    fi
    return 1
}

connect_to_wifi() {
    local ssid="$1"
    local password="$2"
    local network_name="$3"
    
    [ -z "$ssid" ] && return 1
    
    log_message "Attempting to connect to $network_name: $ssid"
    
    # Ensure we're not in hotspot mode
    if is_hotspot_active; then
        log_message "Hotspot is active, stopping it first"
        stop_hotspot
        sleep 5
    fi
    
    # Deep cleanup before attempting connection
    deep_cleanup_interface
    
    # Create wpa_supplicant config
    sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=GB

network={
    ssid="$ssid"
    psk="$password"
    key_mgmt=WPA-PSK
    scan_ssid=1
    priority=1
}
EOF
    
    # Start wpa_supplicant with better error checking
    log_message "Starting wpa_supplicant..."
    if ! sudo wpa_supplicant -B -i "$WIFI_INTERFACE" -c /etc/wpa_supplicant/wpa_supplicant.conf -f /var/log/wpa_supplicant.log; then
        log_message "Failed to start wpa_supplicant"
        return 1
    fi
    
    # Wait for association with timeout
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if wpa_cli -i "$WIFI_INTERFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
            log_message "WiFi associated successfully"
            break
        fi
        sleep 1
        attempts=$((attempts + 1))
    done
    
    if [ $attempts -ge 30 ]; then
        log_message "WiFi association timeout"
        sudo killall wpa_supplicant 2>/dev/null || true
        return 1
    fi
    
    # Request DHCP
    log_message "Requesting DHCP..."
    sudo dhclient -r "$WIFI_INTERFACE" 2>/dev/null || true
    if ! sudo timeout 15 dhclient "$WIFI_INTERFACE" 2>/dev/null; then
        log_message "DHCP request failed"
        sudo killall wpa_supplicant 2>/dev/null || true
        return 1
    fi
    
    sleep 3
    
    # Verify connection
    if is_wifi_connected; then
        log_message "Successfully connected to $network_name"
        local ip=$(ip -4 addr show "$WIFI_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        log_message "Got IP address: $ip"
        return 0
    else
        log_message "Failed to verify connection to $network_name"
        sudo killall wpa_supplicant 2>/dev/null || true
        return 1
    fi
}

setup_nat() {
    log_message "Setting up NAT and IP forwarding"
    
    # Enable IP forwarding
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    # Clear existing NAT rules for our subnet
    sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -o "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    
    # Add NAT rules
    sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
    sudo iptables -A FORWARD -i "$WIFI_INTERFACE" -j ACCEPT
    sudo iptables -A FORWARD -o "$WIFI_INTERFACE" -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Save rules
    sudo netfilter-persistent save 2>/dev/null || true
    
    log_message "NAT setup complete"
}

start_hotspot() {
    log_message "Starting hotspot mode"
    
    # Ensure WiFi is disconnected first
    if is_wifi_connected; then
        log_message "WiFi is connected, disconnecting first"
        sudo killall wpa_supplicant 2>/dev/null || true
        sleep 3
    fi
    
    # Deep cleanup
    deep_cleanup_interface
    
    # Configure static IP for hotspot
    sudo ip addr add "$HOTSPOT_IP/24" dev "$WIFI_INTERFACE" 2>/dev/null || true
    
    # Configure lighttpd for port 8080
    sudo sed -i "s/server.port.*=.*/server.port = 8080/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    # Start hostapd with retry logic
    log_message "Starting hostapd..."
    local hostapd_attempts=0
    while [ $hostapd_attempts -lt 3 ]; do
        sudo systemctl start hostapd
        sleep 5
        
        if pgrep hostapd >/dev/null; then
            log_message "Hostapd started successfully"
            break
        else
            log_message "Hostapd failed to start, attempt $((hostapd_attempts + 1))/3"
            sudo systemctl stop hostapd 2>/dev/null || true
            sudo killall -9 hostapd 2>/dev/null || true
            sleep 2
        fi
        hostapd_attempts=$((hostapd_attempts + 1))
    done
    
    if ! pgrep hostapd >/dev/null; then
        log_message "ERROR: Failed to start hostapd after 3 attempts"
        return 1
    fi
    
    # Start dnsmasq
    log_message "Starting dnsmasq..."
    sudo systemctl start dnsmasq
    sleep 2
    
    if ! pgrep dnsmasq >/dev/null; then
        log_message "ERROR: dnsmasq failed to start"
        sudo systemctl stop hostapd
        return 1
    fi
    
    # Setup NAT
    setup_nat
    
    # Verify hotspot is working
    sleep 3
    if is_hotspot_active; then
        log_message "✅ Hotspot started successfully"
        log_message "Access points: Config UI at http://$HOTSPOT_IP:8080"
        return 0
    else
        log_message "ERROR: Hotspot verification failed"
        return 1
    fi
}

stop_hotspot() {
    log_message "Stopping hotspot mode"
    
    # Stop services
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    
    # Kill any remaining processes
    sudo killall -9 hostapd 2>/dev/null || true
    sudo killall -9 dnsmasq 2>/dev/null || true
    
    # Clean up NAT rules
    sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -o "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    
    # Reset lighttpd to port 80
    sudo sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    # Clean interface
    deep_cleanup_interface
    
    log_message "Hotspot stopped"
}

# Main loop
log_message "==== WiFi Fallback service starting v2.1 ===="
hotspot_active=false
wifi_connected=false
last_force_state="$FORCE_HOTSPOT"
connection_attempts=0
last_check_time=0

while true; do
    current_time=$(date +%s)
    
    # Reload configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Check if force hotspot state changed
    if [ "$last_force_state" != "$FORCE_HOTSPOT" ]; then
        log_message "Force hotspot state changed from $last_force_state to $FORCE_HOTSPOT"
        last_force_state="$FORCE_HOTSPOT"
        
        if [ "$FORCE_HOTSPOT" = "true" ]; then
            # Force hotspot mode enabled
            log_message "Force hotspot enabled - switching to hotspot mode"
            if is_wifi_connected; then
                log_message "Disconnecting from WiFi first"
                sudo killall wpa_supplicant 2>/dev/null || true
                sleep 3
            fi
            if start_hotspot; then
                hotspot_active=true
                wifi_connected=false
            fi
        else
            # Force hotspot disabled - try to connect to WiFi
            log_message "Force hotspot disabled - attempting WiFi connection"
            if is_hotspot_active; then
                stop_hotspot
                hotspot_active=false
            fi
            connection_attempts=0
        fi
    fi
    
    # Handle force hotspot mode
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        if ! is_hotspot_active; then
            log_message "Force hotspot mode but hotspot not active - starting it"
            if start_hotspot; then
                hotspot_active=true
                wifi_connected=false
            fi
        else
            # Verify NAT is still working
            if ! sudo iptables -t nat -L POSTROUTING -n | grep -q "192.168.66.0/24"; then
                log_message "NAT rules missing, reapplying..."
                setup_nat
            fi
        fi
    else
        # Normal mode - try WiFi with fallback to hotspot
        
        # Check current state
        wifi_connected=false
        hotspot_active=false
        
        if is_wifi_connected; then
            wifi_connected=true
        elif is_hotspot_active; then
            hotspot_active=true
        fi
        
        # Handle state transitions
        if [ "$wifi_connected" = false ] && [ "$hotspot_active" = false ]; then
            # Not connected to anything
            connection_attempts=$((connection_attempts + 1))
            
            # Try main network
            if [ -n "$MAIN_SSID" ] && [ $connection_attempts -le $MAX_RETRIES ]; then
                log_message "Attempt $connection_attempts/$MAX_RETRIES to connect to main network"
                if connect_to_wifi "$MAIN_SSID" "$MAIN_PASSWORD" "main"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            # Try backup network
            elif [ -n "$BACKUP_SSID" ] && [ $connection_attempts -le $((MAX_RETRIES * 2)) ]; then
                log_message "Attempt $((connection_attempts - MAX_RETRIES))/$MAX_RETRIES to connect to backup network"
                if connect_to_wifi "$BACKUP_SSID" "$BACKUP_PASSWORD" "backup"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            # Start hotspot as fallback
            else
                log_message "All WiFi attempts failed, starting hotspot"
                if start_hotspot; then
                    hotspot_active=true
                fi
                connection_attempts=0
            fi
        elif [ "$wifi_connected" = true ]; then
            # Connected to WiFi - verify it's still working
            if ! is_wifi_connected; then
                log_message "WiFi connection lost"
                wifi_connected=false
                connection_attempts=0
            else
                connection_attempts=0
            fi
        elif [ "$hotspot_active" = true ]; then
            # In hotspot mode - periodically check if we should try WiFi again
            if [ $((current_time - last_check_time)) -gt 300 ]; then  # Check every 5 minutes
                if [ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]; then
                    log_message "Periodic check: attempting to reconnect to WiFi"
                    stop_hotspot
                    hotspot_active=false
                    connection_attempts=0
                fi
                last_check_time=$current_time
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
