#!/bin/bash

# WiFi Fallback Script v0.7.2 - Fixed NetworkManager control
# Configuration
WIFI_INTERFACE="wlan0"
HOTSPOT_SSID="$(hostname)-hotspot"
HOTSPOT_PASSWORD="raspberry"
HOTSPOT_IP="192.168.66.66"
CHECK_INTERVAL=30
MAX_RETRIES=4
RECONNECT_INTERVAL=1800  # 30 minutes
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

# Check if clients connected
get_hotspot_clients() {
    if pgrep hostapd >/dev/null; then
        arp -an | grep -c "192.168.66" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Clean interface
cleanup_interface() {
    log_message "Cleaning interface $WIFI_INTERFACE"
    
    killall -9 wpa_supplicant 2>/dev/null || true
    killall -9 hostapd 2>/dev/null || true
    killall -9 dnsmasq 2>/dev/null || true
    killall -9 dhclient 2>/dev/null || true
    
    sleep 2
    
    ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
    ip link set "$WIFI_INTERFACE" down
    sleep 2
    ip link set "$WIFI_INTERFACE" up
    sleep 2
}

# Check WiFi connected
is_wifi_connected() {
    # First check with nmcli if available
    if command -v nmcli >/dev/null 2>&1; then
        if nmcli device status 2>/dev/null | grep -q "^$WIFI_INTERFACE.*connected"; then
            if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
                return 0
            fi
        fi
    fi
    
    # Fallback check
    if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
        gateway=$(ip route | grep default | awk '{print $3}' | head -1)
        if [ -n "$gateway" ] && ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Check hotspot active
is_hotspot_active() {
    if pgrep hostapd >/dev/null && ip addr show "$WIFI_INTERFACE" | grep -q "$HOTSPOT_IP"; then
        return 0
    fi
    return 1
}

# Connect to WiFi - try nmcli first, fall back to simpler method
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
    
    # Try Method 1: nmcli (if available and NetworkManager running)
    if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; then
        log_message "Using nmcli method"
        
        # Temporarily manage wlan0
        nmcli device set wlan0 managed yes 2>/dev/null || true
        sleep 2
        
        # Delete old connection
        nmcli connection delete "$ssid" 2>/dev/null || true
        
        # Connect
        if [ -n "$password" ]; then
            if nmcli device wifi connect "$ssid" password "$password" ifname "$WIFI_INTERFACE" 2>/dev/null; then
                log_message "Connected via nmcli"
                sleep 3
                if is_wifi_connected; then
                    return 0
                fi
            fi
        else
            if nmcli device wifi connect "$ssid" ifname "$WIFI_INTERFACE" 2>/dev/null; then
                log_message "Connected to open network via nmcli"
                return 0
            fi
        fi
        
        # Set back to unmanaged on failure
        nmcli device set wlan0 managed no 2>/dev/null || true
    fi
    
    # Method 2: Direct wpa_supplicant (fallback)
    log_message "Using direct wpa_supplicant method"
    
    # Create config
    cat > /tmp/wpa_temp.conf <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=GB

network={
    ssid="$ssid"
    psk="$password"
    key_mgmt=WPA-PSK
    scan_ssid=1
}
EOF
    
    # Start wpa_supplicant
    wpa_supplicant -B -i "$WIFI_INTERFACE" -c /tmp/wpa_temp.conf
    
    # Wait and get DHCP
    sleep 10
    dhclient "$WIFI_INTERFACE" 2>/dev/null
    
    # Check
    if is_wifi_connected; then
        log_message "Connected via wpa_supplicant"
        return 0
    else
        log_message "Failed to connect"
        killall wpa_supplicant 2>/dev/null || true
        return 1
    fi
}

# Setup NAT
setup_nat() {
    log_message "Setting up NAT"
    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
    iptables -A FORWARD -i "$WIFI_INTERFACE" -j ACCEPT
    iptables -A FORWARD -o "$WIFI_INTERFACE" -j ACCEPT
}

# Start hotspot
start_hotspot() {
    log_message "Starting hotspot mode"
    
    # Ensure wlan0 unmanaged
    if command -v nmcli >/dev/null 2>&1; then
        nmcli device set wlan0 managed no 2>/dev/null || true
    fi
    
    cleanup_interface
    
    ip addr add "$HOTSPOT_IP/24" dev "$WIFI_INTERFACE"
    
    sed -i "s/server.port.*=.*/server.port = 8080/" /etc/lighttpd/lighttpd.conf
    systemctl restart lighttpd
    
    log_message "Starting hostapd"
    systemctl start hostapd
    sleep 5
    
    if ! pgrep hostapd >/dev/null; then
        log_message "ERROR: hostapd failed"
        return 1
    fi
    
    log_message "Starting dnsmasq"
    systemctl start dnsmasq
    sleep 2
    
    if ! pgrep dnsmasq >/dev/null; then
        log_message "ERROR: dnsmasq failed"
        systemctl stop hostapd
        return 1
    fi
    
    setup_nat
    
    log_message "Hotspot started successfully"
    return 0
}

# Stop hotspot
stop_hotspot() {
    log_message "Stopping hotspot"
    
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    
    iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    
    sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    systemctl restart lighttpd
    
    ip addr flush dev "$WIFI_INTERFACE"
}

# Main loop
log_message "==== WiFi Fallback starting v0.7.2 ===="

hotspot_active=false
wifi_connected=false
last_force_state="$FORCE_HOTSPOT"
connection_attempts=0
last_reconnect_time=0

while true; do
    current_time=$(date +%s)
    
    # Reload config
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Check force hotspot change
    if [ "$last_force_state" != "$FORCE_HOTSPOT" ]; then
        log_message "Force hotspot changed to: $FORCE_HOTSPOT"
        last_force_state="$FORCE_HOTSPOT"
        
        if [ "$FORCE_HOTSPOT" = "true" ]; then
            if ! is_hotspot_active; then
                start_hotspot
                hotspot_active=true
                wifi_connected=false
            fi
        else
            if is_hotspot_active; then
                stop_hotspot
                hotspot_active=false
            fi
            connection_attempts=0
        fi
    fi
    
    # Handle force hotspot
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        if ! is_hotspot_active; then
            log_message "Force hotspot but not active - starting"
            start_hotspot
            hotspot_active=true
        fi
    else
        # Normal mode
        wifi_connected=false
        hotspot_active=false
        
        if is_wifi_connected; then
            wifi_connected=true
            connection_attempts=0
        elif is_hotspot_active; then
            hotspot_active=true
            
            # Check reconnect
            clients=$(get_hotspot_clients)
            time_since_last=$((current_time - last_reconnect_time))
            
            if [ "$clients" -eq 0 ] && [ $time_since_last -gt $RECONNECT_INTERVAL ]; then
                if [ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]; then
                    log_message "No clients, trying WiFi"
                    stop_hotspot
                    hotspot_active=false
                    connection_attempts=0
                    last_reconnect_time=$current_time
                fi
            fi
        fi
        
        # Not connected - try connect
        if [ "$wifi_connected" = false ] && [ "$hotspot_active" = false ]; then
            connection_attempts=$((connection_attempts + 1))
            
            if [ -n "$MAIN_SSID" ] && [ $connection_attempts -le $MAX_RETRIES ]; then
                log_message "Try $connection_attempts/$MAX_RETRIES main"
                if connect_to_wifi "$MAIN_SSID" "$MAIN_PASSWORD" "main"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            elif [ -n "$BACKUP_SSID" ] && [ $connection_attempts -le $((MAX_RETRIES * 2)) ]; then
                log_message "Try $((connection_attempts - MAX_RETRIES))/$MAX_RETRIES backup"
                if connect_to_wifi "$BACKUP_SSID" "$BACKUP_PASSWORD" "backup"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            else
                log_message "All failed, starting hotspot"
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
