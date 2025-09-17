#!/bin/bash

# WiFi Fallback Script v3.0 - Using nmcli for reliable connections
# Configuration
WIFI_INTERFACE="wlan0"
HOTSPOT_SSID="$(hostname)-hotspot"
HOTSPOT_PASSWORD="raspberry"
HOTSPOT_IP="192.168.66.66"
CHECK_INTERVAL=30
MAX_RETRIES=4
RECONNECT_INTERVAL=900  # 15 minutes between reconnection attempts
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false

# Files
CONFIG_FILE="/etc/wifi-fallback.conf"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

log_message() {
    echo "$(date): $1" | sudo tee -a /var/log/wifi-fallback.log
}

# Check if clients are connected to hotspot
get_hotspot_clients() {
    local count=0
    if pgrep hostapd >/dev/null; then
        # Count ARP entries in hotspot subnet
        count=$(sudo arp -an | grep -c "192.168.66" 2>/dev/null || echo "0")
    fi
    echo $count
}

# Simple cleanup without killing everything
simple_cleanup_interface() {
    log_message "Cleaning up interface $WIFI_INTERFACE"
    
    # Just flush addresses and reset interface
    sudo ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
    sudo ip link set "$WIFI_INTERFACE" down
    sleep 2
    sudo ip link set "$WIFI_INTERFACE" up
    sleep 2
}

# Deep cleanup only when necessary
deep_cleanup_interface() {
    log_message "Performing deep cleanup of $WIFI_INTERFACE"
    
    # Stop NetworkManager's control of wlan0 temporarily
    sudo nmcli device set wlan0 managed no 2>/dev/null || true
    
    # Kill old processes
    sudo killall -9 wpa_supplicant 2>/dev/null || true
    sudo killall -9 hostapd 2>/dev/null || true
    sudo killall -9 dnsmasq 2>/dev/null || true
    sudo killall -9 dhclient 2>/dev/null || true
    
    sleep 2
    
    # Clean interface
    simple_cleanup_interface
    
    log_message "Deep cleanup completed"
}

is_wifi_connected() {
    # Use nmcli to check connection status
    if nmcli device status | grep -q "^$WIFI_INTERFACE.*connected"; then
        # Verify we have an IP
        if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
            return 0
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

connect_to_wifi_nmcli() {
    local ssid="$1"
    local password="$2"
    local network_name="$3"
    
    [ -z "$ssid" ] && return 1
    
    log_message "Attempting to connect to $network_name: $ssid using nmcli"
    
    # Ensure we're not in hotspot mode
    if is_hotspot_active; then
        log_message "Stopping hotspot first"
        stop_hotspot
        sleep 3
    fi
    
    # Enable NetworkManager control of wlan0
    sudo nmcli device set wlan0 managed yes 2>/dev/null || true
    sleep 2
    
    # Delete existing connection if exists
    sudo nmcli connection delete "$ssid" 2>/dev/null || true
    
    # Create new connection
    if [ -n "$password" ]; then
        # WPA/WPA2 network
        if sudo nmcli device wifi connect "$ssid" password "$password" ifname "$WIFI_INTERFACE"; then
            log_message "Successfully connected to $network_name via nmcli"
            sleep 3
            
            # Verify connection
            if is_wifi_connected; then
                local ip=$(ip -4 addr show "$WIFI_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
                log_message "Connected with IP: $ip"
                
                # After successful connection, set wlan0 as unmanaged again
                sudo nmcli device set wlan0 managed no 2>/dev/null || true
                
                return 0
            fi
        fi
    else
        # Open network
        if sudo nmcli device wifi connect "$ssid" ifname "$WIFI_INTERFACE"; then
            log_message "Successfully connected to open network $network_name"
            sudo nmcli device set wlan0 managed no 2>/dev/null || true
            return 0
        fi
    fi
    
    log_message "Failed to connect to $network_name via nmcli"
    # Set back to unmanaged on failure
    sudo nmcli device set wlan0 managed no 2>/dev/null || true
    return 1
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
        sudo nmcli device disconnect "$WIFI_INTERFACE" 2>/dev/null || true
        sleep 3
    fi
    
    # Clean up but less aggressively
    simple_cleanup_interface
    
    # Set wlan0 as unmanaged by NetworkManager
    sudo nmcli device set wlan0 managed no 2>/dev/null || true
    
    # Configure static IP for hotspot
    sudo ip addr add "$HOTSPOT_IP/24" dev "$WIFI_INTERFACE" 2>/dev/null || true
    
    # Configure lighttpd for port 8080
    sudo sed -i "s/server.port.*=.*/server.port = 8080/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    # Start hostapd
    log_message "Starting hostapd..."
    sudo systemctl start hostapd
    sleep 5
    
    if ! pgrep hostapd >/dev/null; then
        log_message "ERROR: hostapd failed to start"
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
    
    log_message "✅ Hotspot started successfully"
    log_message "Access points: Config UI at http://$HOTSPOT_IP:8080"
    
    return 0
}

stop_hotspot() {
    log_message "Stopping hotspot mode"
    
    # Stop services
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    
    # Clean up NAT rules
    sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -o "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    
    # Reset lighttpd to port 80
    sudo sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    # Clean interface
    simple_cleanup_interface
    
    log_message "Hotspot stopped"
}

# Main loop
log_message "==== WiFi Fallback service starting v3.0 (nmcli) ===="

# Ensure NetworkManager is running
if ! systemctl is-active --quiet NetworkManager; then
    log_message "Starting NetworkManager..."
    sudo systemctl start NetworkManager
    sleep 5
fi

hotspot_active=false
wifi_connected=false
last_force_state="$FORCE_HOTSPOT"
connection_attempts=0
last_reconnect_attempt=0
startup_attempt=true

while true; do
    current_time=$(date +%s)
    
    # Reload configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Check if force hotspot state changed
    if [ "$last_force_state" != "$FORCE_HOTSPOT" ]; then
        log_message "Force hotspot state changed to: $FORCE_HOTSPOT"
        last_force_state="$FORCE_HOTSPOT"
        
        if [ "$FORCE_HOTSPOT" = "true" ]; then
            # Force hotspot mode enabled
            if is_wifi_connected; then
                log_message "Disconnecting from WiFi for forced hotspot"
                sudo nmcli device disconnect "$WIFI_INTERFACE" 2>/dev/null || true
                sleep 3
            fi
            if start_hotspot; then
                hotspot_active=true
                wifi_connected=false
            fi
        else
            # Force hotspot disabled - try to connect to WiFi
            if is_hotspot_active; then
                stop_hotspot
                hotspot_active=false
            fi
            connection_attempts=0
            startup_attempt=true
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
            connection_attempts=0
            startup_attempt=false
        elif is_hotspot_active; then
            hotspot_active=true
            
            # Check if we should try to reconnect to WiFi
            clients=$(get_hotspot_clients)
            time_since_last_attempt=$((current_time - last_reconnect_attempt))
            
            # Only try reconnection if:
            # 1. No clients connected
            # 2. Enough time has passed (15 minutes)
            # 3. We have configured networks
            if [ "$clients" -eq 0 ] && \
               [ $time_since_last_attempt -gt $RECONNECT_INTERVAL ] && \
               ([ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]); then
                log_message "No clients connected, attempting WiFi reconnection"
                stop_hotspot
                hotspot_active=false
                connection_attempts=0
                last_reconnect_attempt=$current_time
            elif [ "$clients" -gt 0 ]; then
                log_message "Skipping reconnection: $clients client(s) connected to hotspot"
            fi
        fi
        
        # Not connected to anything - try to connect
        if [ "$wifi_connected" = false ] && [ "$hotspot_active" = false ]; then
            
            # On startup or first attempt after hotspot, try immediately
            if [ "$startup_attempt" = true ] || [ $connection_attempts -eq 0 ]; then
                connection_attempts=$((connection_attempts + 1))
                
                # Try main network
                if [ -n "$MAIN_SSID" ] && [ $connection_attempts -le $MAX_RETRIES ]; then
                    log_message "Attempt $connection_attempts/$MAX_RETRIES to connect to main network"
                    if connect_to_wifi_nmcli "$MAIN_SSID" "$MAIN_PASSWORD" "main"; then
                        wifi_connected=true
                        connection_attempts=0
                        startup_attempt=false
                    fi
                # Try backup network
                elif [ -n "$BACKUP_SSID" ] && [ $connection_attempts -le $((MAX_RETRIES * 2)) ]; then
                    log_message "Attempt $((connection_attempts - MAX_RETRIES))/$MAX_RETRIES to connect to backup network"
                    if connect_to_wifi_nmcli "$BACKUP_SSID" "$BACKUP_PASSWORD" "backup"; then
                        wifi_connected=true
                        connection_attempts=0
                        startup_attempt=false
                    fi
                # Start hotspot as fallback
                else
                    log_message "All WiFi attempts failed, starting hotspot"
                    if start_hotspot; then
                        hotspot_active=true
                        last_reconnect_attempt=$current_time
                    fi
                    connection_attempts=0
                    startup_attempt=false
                fi
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
