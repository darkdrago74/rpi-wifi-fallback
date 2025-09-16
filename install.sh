#!/bin/bash

# RPi WiFi Fallback Hotspot - Installer v2.5 with Connection Preservation
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback
# Version: 2.5.0 - Preserves active WiFi during installation

set -e  # Exit on any error

# Auto-fix permissions if needed
if [[ ! -x "$0" ]]; then
    echo "Making install script executable..."
    chmod +x "$0"
    exec "$0" "$@"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check Debian/Raspberry Pi OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$VERSION_CODENAME" == "bookworm" ]] || [[ "$VERSION_CODENAME" == "bullseye" ]] || [[ "$VERSION_CODENAME" == "buster" ]]; then
        log "✅ Detected compatible OS: $PRETTY_NAME"
    else
        warning "Untested OS version: $PRETTY_NAME - continuing anyway"
    fi
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Use: ./install.sh"
fi

log "Starting RPi WiFi Fallback Installation v2.5..."
log "=================================================================="

# CRITICAL: Detect and preserve current WiFi connection
PRESERVE_WIFI=false
CURRENT_SSID=""
CURRENT_IP=""

if iwgetid wlan0 >/dev/null 2>&1; then
    CURRENT_SSID=$(iwgetid wlan0 -r)
    CURRENT_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [ -n "$CURRENT_SSID" ] && [ -n "$CURRENT_IP" ]; then
        PRESERVE_WIFI=true
        warning "⚠️  Active WiFi connection detected!"
        info "   SSID: $CURRENT_SSID"
        info "   IP: $CURRENT_IP"
        info "   Installation will preserve this connection"
        
        # Save current wpa_supplicant config
        if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
            sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /tmp/wpa_backup.conf
            info "   WiFi config backed up to /tmp/wpa_backup.conf"
        fi
    fi
fi

# Update system
log "Updating system packages..."
sudo apt update

# Clear problematic iptables rules but keep SSH
log "Preparing iptables..."
sudo iptables -F INPUT 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true

# ALWAYS ensure SSH access
sudo iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Install packages
log "Installing required packages..."
sudo apt install -y \
    hostapd \
    dnsmasq \
    lighttpd \
    git \
    iptables \
    iw \
    wireless-tools \
    net-tools \
    curl \
    wget

# Install iptables-persistent
log "Installing iptables-persistent..."
log "➡️  If prompted about saving rules, select YES"
sudo apt install -y iptables-persistent netfilter-persistent

# Enable services
sudo systemctl enable netfilter-persistent 2>/dev/null || true
sudo systemctl start netfilter-persistent 2>/dev/null || true

# Enable IP forwarding
log "Enabling IP forwarding..."
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Handle NetworkManager CAREFULLY
if [ "$PRESERVE_WIFI" = true ]; then
    log "Configuring NetworkManager (preserving WiFi)..."
    
    if command -v NetworkManager >/dev/null 2>&1 && systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
        warning "NetworkManager detected - will be configured AFTER reboot"
        warning "This prevents losing your current WiFi connection"
        
        # Create the config but don't apply it yet
        sudo mkdir -p /etc/NetworkManager/conf.d/
        cat <<'EOF' | sudo tee /etc/NetworkManager/conf.d/99-unmanaged-devices.conf.pending >/dev/null
[keyfile]
# Let wifi-fallback manage wlan0
unmanaged-devices=interface-name:wlan0
EOF
        
        # Create activation script for after reboot
        sudo tee /usr/local/bin/wifi-fallback-activate > /dev/null <<'EOF'
#!/bin/bash
# Activate wifi-fallback NetworkManager config after reboot
if [ -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf.pending ]; then
    mv /etc/NetworkManager/conf.d/99-unmanaged-devices.conf.pending \
       /etc/NetworkManager/conf.d/99-unmanaged-devices.conf
    nmcli general reload 2>/dev/null || true
    nmcli device set wlan0 managed no 2>/dev/null || true
    systemctl disable wifi-fallback-activate.service
    rm -f /etc/systemd/system/wifi-fallback-activate.service
    rm -f /usr/local/bin/wifi-fallback-activate
fi
EOF
        sudo chmod +x /usr/local/bin/wifi-fallback-activate
        
        # Create one-time service to run after reboot
        sudo tee /etc/systemd/system/wifi-fallback-activate.service > /dev/null <<'EOF'
[Unit]
Description=Activate WiFi Fallback NetworkManager Config
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-fallback-activate
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl enable wifi-fallback-activate.service
        
        info "NetworkManager will be configured after reboot"
    fi
else
    # No active WiFi, safe to configure now
    log "Configuring NetworkManager (no active WiFi)..."
    
    if command -v NetworkManager >/dev/null 2>&1 && systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
        sudo mkdir -p /etc/NetworkManager/conf.d/
        cat <<'EOF' | sudo tee /etc/NetworkManager/conf.d/99-unmanaged-devices.conf >/dev/null
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
        
        if command -v nmcli >/dev/null 2>&1; then
            sudo timeout 5 nmcli general reload 2>/dev/null || true
            sudo timeout 5 nmcli device set wlan0 managed no 2>/dev/null || true
        fi
    fi
fi

# Handle dhcpcd
if systemctl is-enabled --quiet dhcpcd 2>/dev/null; then
    log "Configuring dhcpcd..."
    
    if [ "$PRESERVE_WIFI" = true ]; then
        warning "dhcpcd config will be updated after reboot"
        # Create pending config
        echo "# Added by wifi-fallback installer" | sudo tee -a /etc/dhcpcd.conf.pending
        echo "denyinterfaces wlan0" | sudo tee -a /etc/dhcpcd.conf.pending
    else
        if ! grep -q "denyinterfaces wlan0" /etc/dhcpcd.conf 2>/dev/null; then
            echo "# Added by wifi-fallback installer" | sudo tee -a /etc/dhcpcd.conf
            echo "denyinterfaces wlan0" | sudo tee -a /etc/dhcpcd.conf
        fi
    fi
fi

# Stop services but NOT if WiFi is active
log "Configuring services..."
if [ "$PRESERVE_WIFI" = false ]; then
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    sudo killall dhclient 2>/dev/null || true
    sudo pkill -f "dhclient.*wlan0" 2>/dev/null || true
else
    warning "Skipping network service stops to preserve WiFi"
fi

sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Create directories
log "Creating directories..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /var/log
sudo mkdir -p /usr/lib/cgi-bin
sudo mkdir -p /etc/iptables

# Install scripts
log "Installing WiFi fallback script..."
if [ -f scripts/wifi-fallback.sh ]; then
    sudo cp scripts/wifi-fallback.sh /usr/local/bin/
    sudo chmod +x /usr/local/bin/wifi-fallback.sh
else
    error "scripts/wifi-fallback.sh not found!"
fi

if [ -f config/wifi-fallback.service ]; then
    sudo cp config/wifi-fallback.service /etc/systemd/system/
else
    error "config/wifi-fallback.service not found!"
fi

# Create dnsmasq configuration
log "Creating dnsmasq configuration..."
sudo tee /etc/dnsmasq.conf > /dev/null <<'EOF'
interface=wlan0
bind-interfaces
listen-address=192.168.66.66
dhcp-range=192.168.66.10,192.168.66.50,255.255.255.0,24h
dhcp-option=3,192.168.66.66
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
server=8.8.4.4
no-resolv
log-queries
log-dhcp
address=/gw.local/192.168.66.66
address=/hotspot.local/192.168.66.66
address=/config.local/192.168.66.66
except-interface=eth0
except-interface=lo
cache-size=150
no-negcache
EOF

# Create hostapd configuration
log "Creating hostapd configuration..."
HOSTNAME=$(hostname)
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan0
driver=nl80211
ssid=${HOSTNAME}-hotspot
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# Configure iptables
log "Configuring iptables rules..."
sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -j ACCEPT
sudo iptables -A FORWARD -o wlan0 -j ACCEPT
sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 67:68 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT

sudo netfilter-persistent save

# Install web interface
log "Installing web interface..."
[ -f web/index.html ] && sudo cp web/index.html /var/www/html/
[ -f web/wifi-config.cgi ] && sudo cp web/wifi-config.cgi /usr/lib/cgi-bin/
[ -f /usr/lib/cgi-bin/wifi-config.cgi ] && sudo chmod +x /usr/lib/cgi-bin/wifi-config.cgi
[ -f /usr/lib/cgi-bin/wifi-config.cgi ] && sudo chown www-data:www-data /usr/lib/cgi-bin/wifi-config.cgi

# Configure sudo for www-data
if ! sudo grep -q "www-data.*wifi-fallback" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: /bin/bash -c *wifi-fallback.conf*, /bin/systemctl restart wifi-fallback.service, /usr/bin/tee -a /var/log/wifi-fallback.log" | sudo tee -a /etc/sudoers
fi

# Install control scripts
[ -f scripts/hotspot-control.sh ] && sudo cp scripts/hotspot-control.sh /usr/local/bin/hotspot-control
[ -f /usr/local/bin/hotspot-control ] && sudo chmod +x /usr/local/bin/hotspot-control

# Create hotspot command
sudo tee /usr/local/bin/hotspot > /dev/null <<'EOF'
#!/bin/bash
case "$1" in
    on) sudo /usr/local/bin/hotspot-control on ;;
    off) sudo /usr/local/bin/hotspot-control off ;;
    status) sudo /usr/local/bin/hotspot-control status ;;
    restart) sudo /usr/local/bin/hotspot-control restart ;;
    *) echo "Usage: hotspot {on|off|status|restart}" ;;
esac
EOF
sudo chmod +x /usr/local/bin/hotspot

# Configure lighttpd
log "Configuring web server..."
sudo lighttpd-enable-mod cgi 2>/dev/null || true
if ! grep -q "cgi.assign" /etc/lighttpd/lighttpd.conf; then
    echo 'cgi.assign = ( ".cgi" => "" )' | sudo tee -a /etc/lighttpd/lighttpd.conf
fi

# Unmask hostapd
sudo systemctl unmask hostapd 2>/dev/null || true

# Enable services
log "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable lighttpd 2>/dev/null || true
sudo systemctl enable wifi-fallback.service 2>/dev/null || true

# Create initial config
if [ ! -f /etc/wifi-fallback.conf ]; then
    log "Creating initial configuration..."
    
    # If we have current WiFi, pre-populate it
    if [ "$PRESERVE_WIFI" = true ] && [ -n "$CURRENT_SSID" ]; then
        # Try to extract password from wpa_supplicant
        CURRENT_PSK=$(sudo grep -A3 "ssid=\"$CURRENT_SSID\"" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null | grep "psk=" | cut -d'"' -f2 | head -1)
        
        sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID="$CURRENT_SSID"
MAIN_PASSWORD="$CURRENT_PSK"
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false
EOF
        info "Current WiFi saved to configuration"
    else
        sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false
EOF
    fi
fi

# Create log file
sudo touch /var/log/wifi-fallback.log
sudo chmod 644 /var/log/wifi-fallback.log

# DON'T start service if WiFi is active
if [ "$PRESERVE_WIFI" = true ]; then
    warning "⚠️  Service NOT started to preserve WiFi connection"
    info "   Service will start automatically after reboot"
else
    log "Starting WiFi fallback service..."
    sudo systemctl restart lighttpd 2>/dev/null || true
    sudo systemctl start wifi-fallback.service 2>/dev/null || true
fi

HOSTNAME=$(hostname)

log "=================================================================="
log "✅ Installation completed!"
log ""

if [ "$PRESERVE_WIFI" = true ]; then
    warning "⚠️  IMPORTANT: WiFi connection preserved!"
    info "   Your current connection to $CURRENT_SSID is still active"
    info "   The WiFi fallback system will activate after reboot"
    log ""
fi

info "📡 Hotspot: ${HOSTNAME}-hotspot (password: raspberry)"
info "🌐 Config: http://192.168.66.66:8080 (in hotspot mode)"
log ""
warning "⚠️  REBOOT REQUIRED to complete installation"
info "   sudo reboot"
log ""
info "After reboot:"
info "• The system will use your current WiFi as primary network"
info "• Fallback to hotspot if WiFi fails"
info "• Check status: hotspot status"
