#!/bin/bash

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

is_wifi_connected() {
    # Check if interface has valid IP and can ping gateway
    if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
        # Try to ping default gateway
        local gateway=$(ip route | grep default | grep "$WIFI_INTERFACE" | awk '{print $3}' | head -1)
        if [ -n "$gateway" ]; then
            if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    return 1
}

cleanup_interface() {
    log_message "Cleaning up interface $WIFI_INTERFACE"
    
    # Kill all conflicting processes
    sudo killall -9 wpa_supplicant dhclient dhcpcd 2>/dev/null || true
    sleep 2
    
    # Remove any existing IP addresses
    sudo ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
    
    # Bring interface down and up
    sudo ip link set "$WIFI_INTERFACE" down
    sleep 2
    sudo ip link set "$WIFI_INTERFACE" up
    sleep 2
}

connect_to_wifi() {
    local ssid="$1"
    local password="$2"
    local network_name="$3"
    
    [ -z "$ssid" ] && return 1
    
    log_message "Attempting to connect to $network_name: $ssid"
    
    # Stop hotspot if running
    if pgrep hostapd >/dev/null; then
        stop_hotspot
    fi
    
    cleanup_interface
    
    # Create wpa_supplicant config
    sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=GB

network={
    ssid="$ssid"
    psk="$password"
    key_mgmt=WPA-PSK
}
EOF
    
    # Start wpa_supplicant
    sudo wpa_supplicant -B -i "$WIFI_INTERFACE" -c /etc/wpa_supplicant/wpa_supplicant.conf
    
    # Wait for association
    local attempts=0
    while [ $attempts -lt 20 ]; do
        if wpa_cli -i "$WIFI_INTERFACE" status | grep -q "wpa_state=COMPLETED"; then
            break
        fi
        sleep 1
        attempts=$((attempts + 1))
    done
    
    # Request DHCP
    sudo dhclient -r "$WIFI_INTERFACE" 2>/dev/null || true
    sudo dhclient "$WIFI_INTERFACE" 2>/dev/null
    
    sleep 5
    
    # Check if connected
    if is_wifi_connected; then
        log_message "Successfully connected to $network_name"
        return 0
    else
        log_message "Failed to connect to $network_name"
        return 1
    fi
}

setup_nat() {
    log_message "Setting up NAT and IP forwarding"
    
    # Enable IP forwarding
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    # Clear existing NAT rules for our interface
    sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -o "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    
    # Add NAT rules for both eth0 and any other active interface
    sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
    sudo iptables -A FORWARD -i "$WIFI_INTERFACE" -j ACCEPT
    sudo iptables -A FORWARD -o "$WIFI_INTERFACE" -j ACCEPT
    
    # Save iptables rules
    sudo netfilter-persistent save 2>/dev/null || true
    
    log_message "NAT setup complete"
}

start_hotspot() {
    log_message "Starting hotspot mode"
    
    # Stop any WiFi client services
    sudo systemctl stop wpa_supplicant 2>/dev/null || true
    sudo killall -9 wpa_supplicant dhclient dhcpcd 2>/dev/null || true
    sleep 2
    
    cleanup_interface
    
    # Configure static IP for hotspot
    sudo ip addr add 192.168.66.66/24 dev "$WIFI_INTERFACE" 2>/dev/null || true
    
    # Configure lighttpd for port 8080
    sudo sed -i "s/server.port.*=.*/server.port = 8080/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    # Start hostapd
    log_message "Starting hostapd"
    sudo systemctl start hostapd
    
    # Wait for hostapd to initialize
    sleep 5
    
    # Verify hostapd is running
    if ! pgrep hostapd >/dev/null; then
        log_message "ERROR: hostapd failed to start"
        return 1
    fi
    
    # Start dnsmasq
    log_message "Starting dnsmasq"
    sudo systemctl start dnsmasq
    
    # Setup NAT for internet sharing
    setup_nat
    
    log_message "Hotspot started successfully"
    log_message "Access points: Config UI at http://192.168.66.66:8080"
    
    return 0
}

stop_hotspot() {
    log_message "Stopping hotspot mode"
    
    # Stop services
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    
    # Kill any remaining processes
    sudo killall -9 hostapd dnsmasq 2>/dev/null || true
    
    # Clean up NAT rules
    sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -o "$WIFI_INTERFACE" -j ACCEPT 2>/dev/null || true
    
    # Reset lighttpd to port 80
    sudo sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    cleanup_interface
    
    log_message "Hotspot stopped"
}

# Main loop
log_message "WiFi Fallback service starting..."
hotspot_active=false
last_force_state="$FORCE_HOTSPOT"
connection_attempts=0

while true; do
    # Reload configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Check if force hotspot state changed
    if [ "$last_force_state" != "$FORCE_HOTSPOT" ]; then
        log_message "Force hotspot state changed to: $FORCE_HOTSPOT"
        last_force_state="$FORCE_HOTSPOT"
        
        if [ "$FORCE_HOTSPOT" = "false" ] && [ "$hotspot_active" = true ]; then
            # Force hotspot was just disabled, stop hotspot and try to connect
            stop_hotspot
            hotspot_active=false
            connection_attempts=0
        fi
    fi
    
    # Handle force hotspot mode
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        if [ "$hotspot_active" = false ]; then
            log_message "Force hotspot enabled - starting hotspot"
            if start_hotspot; then
                hotspot_active=true
            else
                log_message "Failed to start hotspot, will retry"
            fi
        else
            # Hotspot is active, verify NAT is still working
            if ! iptables -t nat -L POSTROUTING -n | grep -q "192.168.66.0/24"; then
                log_message "NAT rules missing, reapplying..."
                setup_nat
            fi
        fi
    else
        # Normal mode - try to connect to WiFi
        if [ "$hotspot_active" = true ]; then
            # We're in hotspot mode but force is off, check if we should try WiFi
            if [ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]; then
                log_message "Attempting to switch from hotspot to WiFi"
                stop_hotspot
                hotspot_active=false
                connection_attempts=0
            fi
        fi
        
        # Check current connection
        if is_wifi_connected; then
            connection_attempts=0
            # Reset if we successfully connected
        else
            connection_attempts=$((connection_attempts + 1))
            
            # Try main network
            if [ -n "$MAIN_SSID" ] && [ $connection_attempts -le $MAX_RETRIES ]; then
                if connect_to_wifi "$MAIN_SSID" "$MAIN_PASSWORD" "main"; then
                    connection_attempts=0
                fi
            # Try backup network
            elif [ -n "$BACKUP_SSID" ] && [ $connection_attempts -le $((MAX_RETRIES * 2)) ]; then
                if connect_to_wifi "$BACKUP_SSID" "$BACKUP_PASSWORD" "backup"; then
                    connection_attempts=0
                fi
            # Start hotspot as fallback
            elif [ "$hotspot_active" = false ]; then
                log_message "All WiFi attempts failed, starting hotspot"
                if start_hotspot; then
                    hotspot_active=true
                fi
                connection_attempts=0  # Reset for next cycle
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
