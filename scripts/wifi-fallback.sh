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
    
    # Nuclear option - stop ALL network management
    sudo systemctl stop wpa_supplicant@wlan0 2>/dev/null || true
    sudo systemctl stop wpa_supplicant 2>/dev/null || true  
    sudo systemctl stop dhcpcd 2>/dev/null || true
    sudo killall -9 wpa_supplicant dhclient dhcpcd 2>/dev/null || true
    
    # Wait for processes to die
    sleep 3
    
    # Completely reset interface
    sudo ip link set wlan0 down
    sudo ip addr flush dev wlan0
    sudo ip link set wlan0 up
    sleep 2
    
    # Set static IP for hotspot
    sudo ip addr add 192.168.66.66/24 dev wlan0
    
    # Now try to start hostapd
    sudo systemctl start hostapd
    if ! sudo systemctl is-active hostapd; then
        log_message "ERROR: hostapd failed to start"
        return 1
    fi
    
    sudo systemctl start dnsmasq
    if ! sudo systemctl is-active dnsmasq; then
        log_message "ERROR: dnsmasq failed to start"  
        return 1
    fi
    # After starting services, verify they're actually working
    sleep 5
    if iwgetid wlan0 2>/dev/null; then
        log_message "ERROR: Still in client mode, hotspot failed"
        return 1
    fi

    # Check if hotspot is broadcasting
    if ! sudo iwlist wlan0 scan | grep -q "LinuxforRoro-hotspot"; then
        log_message "WARNING: Hotspot may not be broadcasting properly"
    fi
    log_message "Hotspot services started successfully"
}

stop_hotspot() {
    log_message "Stopping hotspot mode"
    
    # Stop services
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    
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
            start_hotspot
            hotspot_active=true
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
            start_hotspot
            hotspot_active=true
            main_retry_count=0
            backup_retry_count=0
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
    
    sleep $CHECK_INTERVAL
done
