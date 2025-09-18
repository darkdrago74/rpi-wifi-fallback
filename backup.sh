#!/bin/bash

# Create backup of system files before installation
# This helps restore original configurations if needed

BACKUP_DIR="/home/$USER/wifi-fallback-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup in $BACKUP_DIR..."
echo ""

# Backup existing configurations
echo "Backing up existing configurations..."

if [ -f /etc/hostapd/hostapd.conf ]; then
    sudo cp /etc/hostapd/hostapd.conf "$BACKUP_DIR/"
    echo "  ✅ Backed up hostapd.conf"
fi

if [ -f /etc/dnsmasq.conf ]; then
    sudo cp /etc/dnsmasq.conf "$BACKUP_DIR/"
    echo "  ✅ Backed up dnsmasq.conf"
fi

if [ -f /etc/lighttpd/lighttpd.conf ]; then
    sudo cp /etc/lighttpd/lighttpd.conf "$BACKUP_DIR/"
    echo "  ✅ Backed up lighttpd.conf"
fi

if [ -f /var/www/html/index.html ]; then
    sudo cp /var/www/html/index.html "$BACKUP_DIR/"
    echo "  ✅ Backed up index.html"
fi

if [ -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf ]; then
    sudo cp /etc/NetworkManager/conf.d/99-unmanaged-devices.conf "$BACKUP_DIR/"
    echo "  ✅ Backed up NetworkManager config"
fi

if [ -f /etc/dhcpcd.conf ]; then
    sudo cp /etc/dhcpcd.conf "$BACKUP_DIR/"
    echo "  ✅ Backed up dhcpcd.conf"
fi

# Backup iptables rules
echo "Backing up firewall rules..."
sudo iptables-save > "$BACKUP_DIR/iptables.rules"
echo "  ✅ Backed up iptables rules"

# Create restore script
echo ""
echo "Creating restore script..."
cat > "$BACKUP_DIR/restore.sh" <<'EOF'
#!/bin/bash
echo "Restoring original configurations..."

# Restore configuration files
[ -f hostapd.conf ] && sudo cp hostapd.conf /etc/hostapd/
[ -f dnsmasq.conf ] && sudo cp dnsmasq.conf /etc/
[ -f lighttpd.conf ] && sudo cp lighttpd.conf /etc/lighttpd/
[ -f index.html ] && sudo cp index.html /var/www/html/
[ -f 99-unmanaged-devices.conf ] && sudo cp 99-unmanaged-devices.conf /etc/NetworkManager/conf.d/
[ -f dhcpcd.conf ] && sudo cp dhcpcd.conf /etc/

# Restore iptables rules
[ -f iptables.rules ] && sudo iptables-restore < iptables.rules

# Restart services
sudo systemctl restart lighttpd
sudo systemctl restart wpa_supplicant
sudo systemctl restart dhcpcd

echo "Original configurations restored!"
echo "You may need to reboot for all changes to take effect."
EOF

chmod +x "$BACKUP_DIR/restore.sh"

echo ""
echo "✅ Backup created successfully!"
echo ""
echo "📁 Backup location: $BACKUP_DIR"
echo ""
echo "To restore original settings later:"
echo "  cd $BACKUP_DIR"
echo "  ./restore.sh"
echo ""
echo "It's recommended to keep this backup until you're sure"
echo "the WiFi Fallback system is working correctly."
