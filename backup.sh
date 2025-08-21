
#!/bin/bash
# Create backup of system files before installation

BACKUP_DIR="/home/$USER/wifi-fallback-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup in $BACKUP_DIR..."

# Backup existing configurations
[ -f /etc/hostapd/hostapd.conf ] && sudo cp /etc/hostapd/hostapd.conf "$BACKUP_DIR/"
[ -f /etc/dnsmasq.conf ] && sudo cp /etc/dnsmasq.conf "$BACKUP_DIR/"
[ -f /etc/lighttpd/lighttpd.conf ] && sudo cp /etc/lighttpd/lighttpd.conf "$BACKUP_DIR/"
[ -f /var/www/html/index.html ] && sudo cp /var/www/html/index.html "$BACKUP_DIR/"

# Create restore script
cat > "$BACKUP_DIR/restore.sh" <<EOF
#!/bin/bash
echo "Restoring original configurations..."
[ -f hostapd.conf ] && sudo cp hostapd.conf /etc/hostapd/
[ -f dnsmasq.conf ] && sudo cp dnsmasq.conf /etc/
[ -f lighttpd.conf ] && sudo cp lighttpd.conf /etc/lighttpd/
[ -f index.html ] && sudo cp index.html /var/www/html/
sudo systemctl restart lighttpd
echo "Original configurations restored!"
EOF

chmod +x "$BACKUP_DIR/restore.sh"
echo "✅ Backup created at: $BACKUP_DIR"
echo "To restore: cd $BACKUP_DIR && ./restore.sh"
