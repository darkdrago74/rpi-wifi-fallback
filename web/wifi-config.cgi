#!/bin/bash
echo "Content-Type: text/html"
echo ""

# Parse POST data
if [ "$REQUEST_METHOD" = "POST" ]; then
    read POST_DATA
    
    # Simple URL decode function
    urldecode() {
        local url_encoded="${1//+/ }"
        printf '%b' "${url_encoded//%/\\x}"
    }
    
    # Extract parameters
    ACTION=$(echo "$POST_DATA" | grep -o 'action=[^&]*' | cut -d'=' -f2)
    MAIN_SSID=$(echo "$POST_DATA" | grep -o 'main_ssid=[^&]*' | cut -d'=' -f2)
    MAIN_PASSWORD=$(echo "$POST_DATA" | grep -o 'main_password=[^&]*' | cut -d'=' -f2)
    BACKUP_SSID=$(echo "$POST_DATA" | grep -o 'backup_ssid=[^&]*' | cut -d'=' -f2)
    BACKUP_PASSWORD=$(echo "$POST_DATA" | grep -o 'backup_password=[^&]*' | cut -d'=' -f2)
    FORCE_HOTSPOT=$(echo "$POST_DATA" | grep -o 'force_hotspot=[^&]*' | cut -d'=' -f2)
    
    # URL decode
    ACTION=$(urldecode "$ACTION")
    MAIN_SSID=$(urldecode "$MAIN_SSID")
    MAIN_PASSWORD=$(urldecode "$MAIN_PASSWORD")
    BACKUP_SSID=$(urldecode "$BACKUP_SSID")
    BACKUP_PASSWORD=$(urldecode "$BACKUP_PASSWORD")
    
    # Set force hotspot flag
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        FORCE_HOTSPOT_VAL="true"
    else
        FORCE_HOTSPOT_VAL="false"
    fi
    
    # Save configuration with sudo
    sudo bash -c "cat > /etc/wifi-fallback.conf" <<EOF
MAIN_SSID="$MAIN_SSID"
MAIN_PASSWORD="$MAIN_PASSWORD"
BACKUP_SSID="$BACKUP_SSID"
BACKUP_PASSWORD="$BACKUP_PASSWORD"
FORCE_HOTSPOT=$FORCE_HOTSPOT_VAL
EOF
    
    # Log the configuration change
    echo "$(date): [WEB-CONFIG] Configuration updated via web interface" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    
    echo '<!DOCTYPE html>'
    echo '<html><head><title>Configuration Saved</title>'
    echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
    echo '<style>'
    echo 'body{font-family:Arial;margin:0;padding:20px;background:#f5f5f5;}'
    echo '.container{max-width:500px;margin:0 auto;padding:30px;background:white;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.1);}'
    echo '.success{color:#155724;background:#d4edda;padding:15px;border-radius:5px;margin:20px 0;border:1px solid #c3e6cb;}'
    echo '.info{background:#cce5ff;padding:15px;border-radius:5px;margin:20px 0;border:1px solid #b8daff;color:#004085;}'
    echo '.warning{background:#f8d7da;padding:15px;border-radius:5px;margin:20px 0;border:1px solid #f5c6cb;color:#721c24;}'
    echo 'h1{color:#333;text-align:center;}'
    echo 'a{color:#007bff;text-decoration:none;}'
    echo 'a:hover{text-decoration:underline;}'
    echo '.center{text-align:center;}'
    echo '</style>'
    echo '</head><body><div class="container">'
    echo '<h1>✅ Configuration Saved!</h1>'
    
    if [ "$FORCE_HOTSPOT_VAL" = "true" ]; then
        echo '<div class="warning"><strong>⚠️ Force Hotspot Mode: ENABLED</strong><br>'
        echo 'The device will stay in hotspot mode until this setting is disabled.</div>'
    else
        echo '<div class="success">'
        if [ -n "$MAIN_SSID" ]; then
            echo '<strong>Primary Network:</strong> '"$MAIN_SSID"'<br>'
        fi
        if [ -n "$BACKUP_SSID" ]; then
            echo '<strong>Backup Network:</strong> '"$BACKUP_SSID"'<br>'
        fi
        echo '<strong>Force Hotspot:</strong> Disabled (Auto-fallback mode)</div>'
    fi
    
    if [ "$ACTION" = "restart" ]; then
        echo '<div class="info">🔄 <strong>Restarting WiFi service...</strong><br>'
        echo 'The service will restart in 3 seconds to apply changes immediately.</div>'
        echo '<p class="center">Page will redirect in 15 seconds...</p>'
        echo '<script>setTimeout(function(){ window.location.href="/"; }, 15000);</script>'
        # Restart the service in background
        (sleep 3; sudo systemctl restart wifi-fallback.service) &
    else
        echo '<div class="info">💾 <strong>Settings saved!</strong><br>'
        echo 'Changes will be applied automatically within 30 seconds.</div>'
    fi
    
    echo '<p class="center"><a href="/">← Back to Configuration</a></p>'
    echo '</div></body></html>'
    
else
    # GET request or other methods
    echo '<!DOCTYPE html>'
    echo '<html><head><title>Method Not Allowed</title></head>'
    echo '<body><h1>Method not allowed</h1>'
    echo '<p>This page only accepts POST requests.</p>'
    echo '<p><a href="/">Back to configuration</a></p>'
    echo '</body></html>'
fi
