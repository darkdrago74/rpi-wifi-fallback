#!/bin/bash

# WiFi Fallback System Reset Script v2.2
# Compatible with version 0.6-alpha and later

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Resetting WiFi Fallback System to Default State...${NC}"
echo "======================================================"

# Stop the service
echo -e "${YELLOW}Stopping WiFi fallback service...${NC}"
sudo systemctl stop wifi-fallback.service 2>/dev/null || true

# Kill all related processes
echo -e "${YELLOW}Stopping all network processes...${NC}"
sudo killall -9 wpa_supplicant 2>/dev/null || true
sudo killall -9 hostapd 2>/dev/null || true
sudo killall -9 dnsmasq 2>/dev/null || true
sudo killall -9 dhclient 2>/dev/null || true
sudo killall -9 dhcpcd 2>/dev/null || true

# Stop NetworkManager from managing wlan0 temporarily
if systemctl is-active --quiet NetworkManager; then
    echo -e "${YELLOW}Temporarily stopping NetworkManager on wlan0...${NC}"
    sudo nmcli device set wlan0 managed no 2>/dev/null || true
fi

# Clear any stuck network states
echo -e "${YELLOW}Clearing network states...${NC}"
sudo ip addr flush dev wlan0 2>/dev/null || true
sudo ip link set wlan0 down
sleep 2
sudo ip link set wlan0 up

# Reset configuration to defaults but keep network settings
echo -e "${YELLOW}Resetting configuration...${NC}"
if [ -f /etc/wifi-fallback.conf ]; then
    # Backup current config
    sudo cp /etc/wifi-fallback.conf /tmp/wifi-fallback.conf.reset-backup.$(date +%Y%m%d_%H%M%S)
    
    # Extract current network settings
    source /etc/wifi-fallback.conf
    
    # Ask user what to do
    echo ""
    echo -e "${BLUE}Current configuration:${NC}"
    [ -n "$MAIN_SSID" ] && echo "  Primary SSID: $MAIN_SSID"
    [ -n "$BACKUP_SSID" ] && echo "  Backup SSID: $BACKUP_SSID"
    echo "  Force Hotspot: $FORCE_HOTSPOT"
    echo ""
    
    read -p "Do you want to keep your WiFi network settings? (Y/n): " -r keep_settings
    
    if [[ "$keep_settings" =~ ^[Nn]$ ]]; then
        # Full reset - clear everything
        sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false
EOF
        echo -e "${GREEN}✅ Configuration fully reset (networks cleared)${NC}"
    else
        # Keep networks but reset force hotspot
        sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID="$MAIN_SSID"
MAIN_PASSWORD="$MAIN_PASSWORD"
BACKUP_SSID="$BACKUP_SSID"
BACKUP_PASSWORD="$BACKUP_PASSWORD"
FORCE_HOTSPOT=false
EOF
        echo -e "${GREEN}✅ Configuration reset (networks kept, force hotspot disabled)${NC}"
    fi
else
    # Create new default config
    sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false
EOF
    echo -e "${GREEN}✅ Created default configuration${NC}"
fi

# Stop hotspot services
echo -e "${YELLOW}Stopping hotspot services...${NC}"
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true

# Reset lighttpd port
echo -e "${YELLOW}Resetting web server port...${NC}"
sudo sed -i "s/server.port.*=.*/server.port = 80/" /etc/lighttpd/lighttpd.conf
sudo systemctl restart lighttpd

# Clear iptables NAT rules
echo -e "${YELLOW}Clearing NAT rules...${NC}"
sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i wlan0 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -o wlan0 -j ACCEPT 2>/dev/null || true

# Clear logs
echo -e "${YELLOW}Clearing logs...${NC}"
sudo rm -f /var/log/wifi-fallback.log
sudo touch /var/log/wifi-fallback.log
sudo chmod 644 /var/log/wifi-fallback.log

# Clear ARP cache
echo -e "${YELLOW}Clearing ARP cache...${NC}"
sudo ip neigh flush all

# Re-enable NetworkManager for wlan0
if systemctl is-active --quiet NetworkManager; then
    echo -e "${YELLOW}Re-enabling NetworkManager management...${NC}"
    # NetworkManager should still ignore wlan0 per our config
    # This is just to ensure clean state
fi

# Start fresh
echo -e "${YELLOW}Starting WiFi fallback service...${NC}"
sudo systemctl start wifi-fallback.service

# Wait a moment for service to initialize
sleep 3

# Show status
echo ""
echo -e "${GREEN}✅ System reset complete!${NC}"
echo "======================================================"

# Get current state
source /etc/wifi-fallback.conf

if [ -n "$MAIN_SSID" ] || [ -n "$BACKUP_SSID" ]; then
    echo -e "${BLUE}📶 WiFi networks configured:${NC}"
    [ -n "$MAIN_SSID" ] && echo "   Primary: $MAIN_SSID"
    [ -n "$BACKUP_SSID" ] && echo "   Backup: $BACKUP_SSID"
    echo ""
    echo -e "${YELLOW}The system will try to connect to configured networks.${NC}"
else
    echo -e "${YELLOW}⚠️  No WiFi networks configured!${NC}"
    echo "The system will activate hotspot mode in ~30 seconds."
    echo ""
    HOSTNAME=$(hostname)
    echo -e "${BLUE}📡 Hotspot details:${NC}"
    echo "   SSID: ${HOSTNAME}-hotspot"
    echo "   Password: raspberry"
    echo "   Config URL: http://192.168.66.66:8080"
fi

echo ""
echo -e "${BLUE}📋 Useful commands:${NC}"
echo "   Check status: hotspot status"
echo "   View logs: sudo tail -f /var/log/wifi-fallback.log"
echo "   Network diagnostics: netdiag"
echo "   Force hotspot: hotspot on"
echo "   Configure via web: http://192.168.66.66:8080 (in hotspot mode)"
echo ""

# Run diagnostics
if command -v netdiag >/dev/null 2>&1; then
    echo -e "${BLUE}📊 Current network status:${NC}"
    echo "======================================================"
    netdiag
fi
