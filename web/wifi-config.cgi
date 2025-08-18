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
    
    # Save configuration
    cat > /etc/wifi-fallback.conf <<EOF
MAIN_SSID="$MAIN_SSID"
MAIN_PASSWORD="$MAIN_PASSWORD"
BACKUP_SSID="$BACKUP_SSID"
BACKUP_PASSWORD="$BACKUP_PASSWORD"
FORCE_HOTSPOT=$FORCE_HOTSPOT_VAL
EOF
    
    echo '<html><head><title>Configuration Saved</title>'
    echo '<style>body{font-family:Arial;margin:40px;text-align:center;} .container{max-width:500px;margin:0 auto;padding:30px;background:#f8f9fa;border-radius:10px;} .success{color:#155724;background:#d4edda;padding:15px;border-radius:5px;margin:20px 0;} .info{background:#cce5ff;padding:15px;border-radius:5px;margin:20px 0;}</style>'
    echo '</head><body><div class="container">'
    echo '<h1>✅ Configuration Saved Successfully!</h1>'
    
    if [ "$FORCE_HOTSPOT_VAL" = "true" ]; then
        echo '<div class="success"><strong>Force Hotspot Mode: ENABLED</strong><br>Device will stay in hotspot mode until this setting is disabled.</div>'
    else
        echo '<div class="success">'
        echo '<strong>Main Network:</strong> '"$MAIN_SSID"'<br>'
        if [ -n "$BACKUP_SSID" ]; then
            echo '<strong>Backup Network:</strong> '"$BACKUP_SSID"'<br>'
        fi
        echo '<strong>Force Hotspot:</strong> Disabled</div>'
    fi
    
    if [ "$ACTION" = "restart" ]; then
        echo '<div class="info">The WiFi service will restart in 3 seconds to apply changes immediately...</div>'
        echo '<p>The page will redirect in 10 seconds.</p>'
        echo '<script>setTimeout(function(){ window.location.href="/"; }, 10000);</script>'
        # Restart the service immediately
        (sleep 3; sudo systemctl restart wifi-fallback.service) &
    else
        echo '<div class="info">Settings saved! Changes will be applied automatically within 30 seconds.</div>'
        echo '<p><a href="/">← Back to Configuration</a></p>'
    fi
    
    echo '</div></body></html>'
    
else
    echo '<html><body><h1>Method not allowed</h1></body></html>'
fi
