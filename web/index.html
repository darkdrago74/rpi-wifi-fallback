#!/bin/bash

# WiFi Fallback Script v1.1 - With Force Disconnect
# Handles configuration changes and forces disconnect when needed

# Configuration
WIFI_INTERFACE="wlan0"
HOTSPOT_SSID="$(hostname)-hotspot"
HOTSPOT_PASSWORD="raspberry"
HOTSPOT_IP="192.168.66.66"
CHECK_INTERVAL=30
MAX_RETRIES=4
CONFIG_FILE="/etc/wifi-fallback.conf"
LOG_FILE="/var/log/wifi-fallback.log"

# State variables
hotspot_active=false
wifi_connected=false
last_force_state=""
connection_attempts=0
last_check_time=0
nm_available=false
last_main_ssid=""
last_backup_ssid=""

# Check if NetworkManager is available and running
if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; then
    nm_available=true
fi

# Enhanced logging
log_message() {
    local level="$1"
    shift
    local message="$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
    logger -t wifi-fallback "[$level] $message"
}

log_info() { log_message "INFO" "$@"; }
log_warn() { log_message "WARN" "$@"; }
log_error() { log_message "ERROR" "$@"; }
log_debug() { log_message "DEBUG" "$@"; }

# Get hotspot client count
get_hotspot_clients() {
    if pgrep hostapd >/dev/null; then
        local count=$(arp -an | grep -c "192.168.66" 2>/dev/null || echo "0")
        echo "$count"
    else
        echo "0"
    fi
}

# Check if WiFi is connected
is_wifi_connected() {
    log_debug "Checking WiFi connection status..."
    
    # Method 1: Check with NetworkManager
    if [ "$nm_available" = true ]; then
        if nmcli device status 2>/dev/null | grep -q "^$WIFI_INTERFACE.*connected"; then
            if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
                log_debug "WiFi connected via NetworkManager"
                return 0
            fi
        fi
    fi
    
    # Method 2: Direct interface check
    if iwgetid "$WIFI_INTERFACE" >/dev/null 2>&1; then
        local ssid=$(iwgetid "$WIFI_INTERFACE" -r)
        if [ -n "$ssid" ]; then
            if ip addr show "$WIFI_INTERFACE" | grep -q "inet .*scope global"; then
                local gateway=$(ip route | grep default | grep "$WIFI_INTERFACE" | awk '{print $3}' | head -1)
                if [ -n "$gateway" ] && ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
                    log_debug "WiFi connected to $ssid with working gateway"
                    return 0
                fi
            fi
        fi
    fi
    
    log_debug "WiFi not connected"
    return 1
}

# Check if hotspot is running
is_hotspot_active() {
    if pgrep hostapd >/dev/null && ip addr show "$WIFI_INTERFACE" | grep -q "$HOTSPOT_IP"; then
        return 0
    fi
    return 1
}

# Clean interface
cleanup_interface() {
    log_info "Cleaning up interface $WIFI_INTERFACE..."
    
    local processes=("wpa_supplicant" "hostapd" "dnsmasq" "dhclient" "dhcpcd")
    for proc in "${processes[@]}"; do
        if pgrep "$proc" >/dev/null; then
            log_debug "Stopping $proc"
            sudo killall -9 "$proc" 2>/dev/null || true
        fi
    done
    
    sleep 2
    
    sudo ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
    sudo ip link set "$WIFI_INTERFACE" down
    sleep 2
    sudo ip link set "$WIFI_INTERFACE" up
    sleep 2
    
    log_debug "Interface cleanup complete"
}

# Connect using NetworkManager
connect_wifi_nm() {
    local ssid="$1"
    local password="$2"
    
    log_info "Connecting to $ssid using NetworkManager..."
    
    nmcli device set "$WIFI_INTERFACE" managed yes 2>/dev/null || true
    sleep 2
    
    nmcli connection delete "$ssid" 2>/dev/null || true
    
    if [ -n "$password" ]; then
        if nmcli device wifi connect "$ssid" password "$password" ifname "$WIFI_INTERFACE" 2>/dev/null; then
            sleep 5
            if is_wifi_connected; then
                log_info "Successfully connected to $ssid via NetworkManager"
                return 0
            fi
        fi
    else
        if nmcli device wifi connect "$ssid" ifname "$WIFI_INTERFACE" 2>/dev/null; then
            sleep 5
            if is_wifi_connected; then
                log_info "Successfully connected to open network $ssid"
                return 0
            fi
        fi
    fi
    
    nmcli device set "$WIFI_INTERFACE" managed no 2>/dev/null || true
    return 1
}

# Connect using wpa_supplicant
connect_wifi_wpa() {
    local ssid="$1"
    local password="$2"
    
    log_info "Connecting to $ssid using wpa_supplicant..."
    
    cat > /tmp/wpa_temp.conf <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=GB

network={
    ssid="$ssid"
    $([ -n "$password" ] && echo "psk=\"$password\"" || echo "key_mgmt=NONE")
    scan_ssid=1
}
EOF
    
    sudo wpa_supplicant -B -i "$WIFI_INTERFACE" -c /tmp/wpa_temp.conf -f /var/log/wpa_supplicant.log
    
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if wpa_cli -i "$WIFI_INTERFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
            log_debug "WPA authentication completed"
            break
        fi
        sleep 1
        attempts=$((attempts + 1))
    done
    
    if [ $attempts -ge 30 ]; then
        log_warn "WPA authentication timeout"
        sudo killall wpa_supplicant 2>/dev/null || true
        return 1
    fi
    
    log_debug "Requesting DHCP..."
    sudo dhclient -r "$WIFI_INTERFACE" 2>/dev/null || true
    if sudo timeout 15 dhclient "$WIFI_INTERFACE" 2>/dev/null; then
        sleep 3
        if is_wifi_connected; then
            log_info "Successfully connected to $ssid via wpa_supplicant"
            return 0
        fi
    fi
    
    sudo killall wpa_supplicant 2>/dev/null || true
    return 1
}

# Main connection function
connect_to_wifi() {
    local ssid="$1"
    local password="$2"
    local network_name="$3"
    
    [ -z "$ssid" ] && return 1
    
    log_info "=== Starting connection attempt to $network_name network: $ssid ==="
    
    if is_hotspot_active; then
        stop_hotspot
        sleep 3
    fi
    
    cleanup_interface
    
    if [ "$nm_available" = true ]; then
        if connect_wifi_nm "$ssid" "$password"; then
            return 0
        fi
        log_warn "NetworkManager connection failed, trying wpa_supplicant..."
    fi
    
    if connect_wifi_wpa "$ssid" "$password"; then
        return 0
    fi
    
    log_error "Failed to connect to $ssid"
    return 1
}

# Setup NAT
setup_nat() {
    log_info "Setting up NAT for internet sharing..."
    
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    local ext_iface=""
    if ip link show eth0 2>/dev/null | grep -q "state UP"; then
        ext_iface="eth0"
        log_debug "Using eth0 for internet sharing"
    elif ip link show wlan1 2>/dev/null | grep -q "state UP"; then
        ext_iface="wlan1"
        log_debug "Using wlan1 for internet sharing"
    fi
    
    if [ -n "$ext_iface" ]; then
        sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 -o "$ext_iface" -j MASQUERADE 2>/dev/null || true
        sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 -o "$ext_iface" -j MASQUERADE
        
        sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -o "$ext_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -i "$ext_iface" -o "$WIFI_INTERFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        sudo iptables -A FORWARD -i "$WIFI_INTERFACE" -o "$ext_iface" -j ACCEPT
        sudo iptables -A FORWARD -i "$ext_iface" -o "$WIFI_INTERFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT
        
        log_info "NAT configured for internet sharing via $ext_iface"
    else
        log_warn "No external interface available for internet sharing"
    fi
}

# Start hotspot
start_hotspot() {
    log_info "=== Starting hotspot mode ==="
    
    if [ "$nm_available" = true ]; then
        nmcli device set "$WIFI_INTERFACE" managed no 2>/dev/null || true
    fi
    
    cleanup_interface
    
    sudo ip addr add "$HOTSPOT_IP/24" dev "$WIFI_INTERFACE" 2>/dev/null || true
    
    sudo sed -i "s/server.port.*=.*/server.port = 8080/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    log_info "Starting hostapd..."
    sudo systemctl start hostapd
    sleep 5
    
    if ! pgrep hostapd >/dev/null; then
        log_error "Failed to start hostapd"
        return 1
    fi
    
    log_info "Starting dnsmasq..."
    sudo systemctl start dnsmasq
    sleep 2
    
    if ! pgrep dnsmasq >/dev/null; then
        log_error "Failed to start dnsmasq"
        sudo systemctl stop hostapd
        return 1
    fi
    
    setup_nat
    
    log_info "✅ Hotspot started successfully"
    log_info "SSID: $HOTSPOT_SSID | Password: $HOTSPOT_PASSWORD"
    log_info "Config URL: http://$HOTSPOT_IP:8080"
    return 0
}

# Stop hotspot
stop_hotspot() {
    log_info "Stopping hotspot mode..."
    
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    
    sudo sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
    sudo systemctl restart lighttpd
    
    sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
    
    cleanup_interface
    
    log_info "Hotspot stopped"
}

# Main loop
log_info "════════════════════════════════════════════════════════"
log_info "WiFi Fallback Service v1.1 starting..."
log_info "NetworkManager available: $nm_available"
log_info "════════════════════════════════════════════════════════"

# Load and display initial configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log_info "Configuration loaded from $CONFIG_FILE:"
    log_info "  Primary SSID: ${MAIN_SSID:-<none>}"
    log_info "  Backup SSID: ${BACKUP_SSID:-<none>}"
    log_info "  Force Hotspot: $FORCE_HOTSPOT"
    
    # Store initial values
    last_main_ssid="$MAIN_SSID"
    last_backup_ssid="$BACKUP_SSID"
else
    log_error "Configuration file not found at $CONFIG_FILE"
fi

while true; do
    # Reload configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        
        # Check if SSIDs changed
        if [ "$last_main_ssid" != "$MAIN_SSID" ] || [ "$last_backup_ssid" != "$BACKUP_SSID" ]; then
            log_info "Network configuration changed:"
            log_info "  Primary: $last_main_ssid -> $MAIN_SSID"
            log_info "  Backup: $last_backup_ssid -> $BACKUP_SSID"
            last_main_ssid="$MAIN_SSID"
            last_backup_ssid="$BACKUP_SSID"
            connection_attempts=0  # Reset attempts for new config
        fi
    fi
    
    # Check if force hotspot state changed
    if [ "$last_force_state" != "$FORCE_HOTSPOT" ]; then
        log_info "Force hotspot changed from '$last_force_state' to '$FORCE_HOTSPOT'"
        last_force_state="$FORCE_HOTSPOT"
        
        if [ "$FORCE_HOTSPOT" = "true" ]; then
            # Force hotspot enabled
            if ! is_hotspot_active; then
                log_info "Force hotspot enabled - starting hotspot"
                start_hotspot
                hotspot_active=true
                wifi_connected=false
            fi
        else
            # Force hotspot disabled - FORCE DISCONNECT and try WiFi
            if is_hotspot_active; then
                clients=$(get_hotspot_clients)
                
                # Option 1: ALWAYS force disconnect when force hotspot is disabled
                # Uncomment the following block for immediate disconnect:
                
                # log_info "Force hotspot disabled - forcing disconnect of $clients clients"
                # stop_hotspot
                # hotspot_active=false
                # connection_attempts=0
                # continue  # Skip sleep, try WiFi immediately
                
                # Option 2: Only disconnect if no clients (current behavior)
                # This is safer but requires manual disconnect
                if [ "$clients" -eq 0 ]; then
                    log_info "Force hotspot disabled and no clients - switching to WiFi"
                    stop_hotspot
                    hotspot_active=false
                    connection_attempts=0
                    continue  # Skip sleep, try immediately
                else
                    log_info "Force hotspot disabled but $clients clients connected"
                    log_info "Waiting for clients to disconnect before switching to WiFi"
                    # Will check again in next loop iteration
                fi
            fi
        fi
    fi
    
    # Handle force hotspot mode
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        if ! is_hotspot_active; then
            log_warn "Force hotspot enabled but hotspot not active - starting"
            start_hotspot
            hotspot_active=true
        else
            # Verify NAT is working
            if ! sudo iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "192.168.66.0/24"; then
                log_warn "NAT rules missing, reapplying..."
                setup_nat
            fi
        fi
    else
        # Normal mode - check current state
        wifi_connected=false
        hotspot_active=false
        
        if is_wifi_connected; then
            wifi_connected=true
            connection_attempts=0
        elif is_hotspot_active; then
            hotspot_active=true
            
            # Check if we should try to reconnect
            clients=$(get_hotspot_clients)
            
            # If force hotspot was disabled but clients still connected, check periodically
            if [ "$clients" -eq 0 ]; then
                # No clients - we can try WiFi
                if [ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]; then
                    log_info "No hotspot clients - attempting WiFi connection"
                    stop_hotspot
                    hotspot_active=false
                    connection_attempts=0
                    continue  # Try immediately
                fi
            else
                log_debug "Hotspot has $clients connected clients - maintaining hotspot"
            fi
        fi
        
        # Not connected to anything - try to connect
        if [ "$wifi_connected" = false ] && [ "$hotspot_active" = false ]; then
            connection_attempts=$((connection_attempts + 1))
            
            # Try main network
            if [ -n "$MAIN_SSID" ] && [ $connection_attempts -le $MAX_RETRIES ]; then
                log_info "Connection attempt $connection_attempts/$MAX_RETRIES to primary network"
                if connect_to_wifi "$MAIN_SSID" "$MAIN_PASSWORD" "primary"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            # Try backup network
            elif [ -n "$BACKUP_SSID" ] && [ $connection_attempts -le $((MAX_RETRIES * 2)) ]; then
                log_info "Connection attempt $((connection_attempts - MAX_RETRIES))/$MAX_RETRIES to backup network"
                if connect_to_wifi "$BACKUP_SSID" "$BACKUP_PASSWORD" "backup"; then
                    wifi_connected=true
                    connection_attempts=0
                fi
            # Fall back to hotspot
            else
                log_info "All WiFi connection attempts failed - starting hotspot"
                if start_hotspot; then
                    hotspot_active=true
                    last_check_time=$(date +%s)
                fi
                connection_attempts=0
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
