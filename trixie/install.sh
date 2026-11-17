#!/bin/bash
# Antigravity Installer for RPi WiFi Fallback
# Target OS: Debian Trixie (13)+
# Architecture: NetworkManager Native

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[ANTIGRAVITY]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Helper: Permissions Check (Strict Rule 3.0)
fix_perms() {
    local file=$1
    if [ -f "$file" ]; then
        sudo chown root:root "$file"
        sudo chmod 0600 "$file"
    fi
}

log "Starting Antigravity Installer..."

# 1. Environment Check
if [ "$EUID" -eq 0 ]; then
    error "Run as normal user (with sudo access), NOT root."
fi

# 2. Cleanup Legacy Artifacts
log "Cleaning up legacy packages (if any)..."
# We do not want dhcpcd or openresolv interfering with NetworkManager
sudo systemctl stop dhcpcd 2>/dev/null || true
sudo systemctl disable dhcpcd 2>/dev/null || true
# In Trixie, removing them might be safe, but let's just mask/disable to be safe against dependency removal requiring input
# Actually, prompt said PROHIBITED: isc-dhcp-server.
# We will ensure they are not active.

# 3. Cloud-Init Neutralization (Rule 3.1)
if [ -f /etc/netplan/50-cloud-init.yaml ]; then
    warn "Cloud-init configuration detected. This may interfere."
    log "Neutralizing cloud-init networking..."
    echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null
    # We should interpret the existing config to create a NM profile, but for now we assume fresh or user will configure.
    # TODO: Parse current wifi credentials from netplan if they exist.
fi

# 4. Install Dependencies
log "Installing Dependencies (NM, dnsmasq, lighttpd)..."
sudo apt update
sudo apt install -y network-manager dnsmasq-base curl grep lighttpd lighttpd-mod-cgi

# 5. NetworkManager Configuration
# Enable NM if not
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# 6. Generate Antigravity Access Point Profile
# Profile Name: Antigravity_AP
# SSID: Hotspot-<Hostname>
# Password: <Random> or 'raspberry' (Prompt warned against defaults, but we need a known start. Plan said random.)
# Key Mgmt: WPA2 (Rule 2.2)
# IP Method: shared (Rule: Equivalent to legacy dhcpd)

AP_SSID="$(hostname)-Rescue"
# Check if creds exist
if [ -f /boot/wifi_fallback_creds.txt ]; then
    AP_PASSWORD=$(grep "PASSWORD=" /boot/wifi_fallback_creds.txt | cut -d'=' -f2)
else
    # Minimize entropy issues by using simple random
    AP_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
    echo "SSID=$AP_SSID" | sudo tee /boot/wifi_fallback_creds.txt > /dev/null
    echo "PASSWORD=$AP_PASSWORD" | sudo tee -a /boot/wifi_fallback_creds.txt > /dev/null
fi

log "Configuring Fallback AP Profile: $AP_SSID"
# Using nmcli to create the connection
# priority -100 ensures it's only picked if nothing else is available (Rule 1.1 - Fallback)
# But wait, Fallback Mandate says "deterministically transition".
# If we rely on autoconnect priority, NM *should* drop to it. 
# However, the FSM script will force it up.

# Delete existing if any
sudo nmcli con delete "Antigravity_AP" 2>/dev/null || true

# Create
# ipv4.method shared triggers the internal dnsmasq
sudo nmcli con add type wifi ifname wlan0 con-name "Antigravity_AP" \
    autoconnect yes autoconnect-priority -100 \
    ssid "$AP_SSID" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$AP_PASSWORD" \
    ipv4.method shared ipv4.addr 192.168.66.66/24 \
    ipv6.method ignore \
    connection.permissions ""

# Ensure permissions (Rule 3.0)
# The file is in /etc/NetworkManager/system-connections/Antigravity_AP.nmconnection
sudo chmod 600 /etc/NetworkManager/system-connections/Antigravity_AP.nmconnection
sudo chown root:root /etc/NetworkManager/system-connections/Antigravity_AP.nmconnection

# 7. Install Watchdog Service & Script
log "Installing Watchdog FSM..."
# Copy watchdog script
sudo cp watchdog_check.sh /usr/local/bin/antigravity-watchdog.sh
sudo chmod +x /usr/local/bin/antigravity-watchdog.sh

# Create Systemd Service
cat <<EOF | sudo tee /etc/systemd/system/antigravity-watchdog.service > /dev/null
[Unit]
Description=Antigravity WiFi Fallback Watchdog
After=network.target NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/antigravity-watchdog.sh
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Create Systemd Timer (Interval 120s)
cat <<EOF | sudo tee /etc/systemd/system/antigravity-watchdog.timer > /dev/null
[Unit]
Description=Run Antigravity Watchdog every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=antigravity-watchdog.service

[Install]
WantedBy=timers.target
EOF

# Enable Timer
sudo systemctl daemon-reload
sudo systemctl enable antigravity-watchdog.timer
sudo systemctl start antigravity-watchdog.timer

# 8. Install Dispatcher Script
log "Installing NetworkManager Dispatcher..."
sudo cp dispatcher.sh /etc/NetworkManager/dispatcher.d/99-antigravity
sudo chown root:root /etc/NetworkManager/dispatcher.d/99-antigravity
sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-antigravity

# 9. Install Web Interface (Trixie/NM Compatible)
log "Installing Web Interface..."
sudo mkdir -p /var/www/html
sudo cp -r web/* /var/www/html/
# The CGI script needs to be in /usr/lib/cgi-bin/ usually
sudo mkdir -p /usr/lib/cgi-bin
if [ -f web/wifi-config.cgi ]; then
    sudo cp web/wifi-config.cgi /usr/lib/cgi-bin/
    sudo chmod +x /usr/lib/cgi-bin/wifi-config.cgi
    sudo chown www-data:www-data /usr/lib/cgi-bin/wifi-config.cgi
fi

# Enable Lighttpd CGI
sudo lighty-enable-mod cgi 2>/dev/null || true

# 9b. Configure Lighttpd Port to 8088 (Avoid conflict with Mainsail/Nginx on 80)
log "Configuring Web Server Port to 8088..."
sudo sed -i "s/server.port.*=.*/server.port = 8088/" /etc/lighttpd/lighttpd.conf
# Ensure the line exists if it wasn't replaced (e.g., if commented out or missing)
if ! grep -q "server.port.*=.*8088" /etc/lighttpd/lighttpd.conf; then
    echo "server.port = 8088" | sudo tee -a /etc/lighttpd/lighttpd.conf > /dev/null
fi

sudo systemctl restart lighttpd

# 10. Configure Sudoers for Web Interface (NMCLI for www-data)
# We need to allow www-data to use nmcli to scan and connect
log "Configuring permissions for Web Interface..."
cat <<EOF | sudo tee /etc/sudoers.d/wifi-fallback-web > /dev/null
www-data ALL=(ALL) NOPASSWD: /usr/bin/nmcli
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl start antigravity-watchdog.service
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart antigravity-watchdog.service
EOF
sudo chmod 440 /etc/sudoers.d/wifi-fallback-web

# 11. Create & Permission Config File
log "Setting up Configuration File..."
if [ ! -f /etc/wifi-fallback.conf ]; then
    sudo touch /etc/wifi-fallback.conf
fi
sudo chown www-data:www-data /etc/wifi-fallback.conf
sudo chmod 664 /etc/wifi-fallback.conf

success "Antigravity (Trixie) Installation Complete!"
echo "------------------------------------------------"
echo "Fallback Connection Details:"
echo "SSID: $AP_SSID"
echo "Password: $AP_PASSWORD"
echo "IP Address: 192.168.66.66"
echo "Web Config: http://192.168.66.66:8088"
echo "Credentials saved to: /boot/wifi_fallback_creds.txt"
echo "------------------------------------------------"
