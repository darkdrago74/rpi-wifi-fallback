#!/bin/bash
# This is just the section that needs to be updated in install.sh
# Find the section around line 120-140 where hostapd.conf is created

# Create hostapd configuration
log "Creating hostapd configuration..."
HOSTNAME=$(hostname)
if [ -f config/hostapd.conf ]; then
    # Use sed to replace the template variable with actual hostname
    sed "s/\$(hostname)/${HOSTNAME}/g" config/hostapd.conf | sudo tee /etc/hostapd/hostapd.conf > /dev/null
    log "Created hostapd config with hostname: ${HOSTNAME}"
else
    # Fallback if config file doesn't exist
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
    log "Created hostapd config from template with hostname: ${HOSTNAME}"
fi
