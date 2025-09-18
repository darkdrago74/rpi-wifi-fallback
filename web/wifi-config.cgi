#!/bin/bash

# CGI script for WiFi configuration - FIXED VERSION
# Properly handles POST data parsing and file permissions

# Function to send response
send_response() {
    echo "Content-Type: $1"
    echo ""
    shift
    echo "$@"
}

# URL decode function
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# Function to parse URL parameters
parse_param() {
    local param_name="$1"
    local data="$2"
    # Extract value for the parameter, handling both middle and end positions
    echo "$data" | sed -n "s/.*${param_name}=\([^&]*\).*/\1/p"
}

# Handle GET requests
if [ "$REQUEST_METHOD" = "GET" ]; then
    QUERY_ACTION=$(echo "$QUERY_STRING" | grep -o 'action=[^&]*' | cut -d'=' -f2)
    
    if [ "$QUERY_ACTION" = "getconfig" ]; then
        if [ -f /etc/wifi-fallback.conf ]; then
            send_response "text/plain" "$(cat /etc/wifi-fallback.conf)"
        else
            send_response "text/plain" ""
        fi
        exit 0
    elif [ "$QUERY_ACTION" = "gethostname" ]; then
        send_response "text/plain" "$(hostname)"
        exit 0
    fi
fi

# Handle POST requests
if [ "$REQUEST_METHOD" = "POST" ]; then
    read POST_DATA
    
    # Debug log the raw POST data
    echo "$(date): [WEB-CONFIG] Received POST data: $POST_DATA" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    
    # Parse POST data using improved method
    ACTION=$(parse_param "action" "$POST_DATA")
    MAIN_SSID=$(parse_param "main_ssid" "$POST_DATA")
    MAIN_PASSWORD=$(parse_param "main_password" "$POST_DATA")
    BACKUP_SSID=$(parse_param "backup_ssid" "$POST_DATA")
    BACKUP_PASSWORD=$(parse_param "backup_password" "$POST_DATA")
    FORCE_HOTSPOT=$(parse_param "force_hotspot" "$POST_DATA")
    
    # URL decode values
    ACTION=$(urldecode "$ACTION")
    MAIN_SSID=$(urldecode "$MAIN_SSID")
    MAIN_PASSWORD=$(urldecode "$MAIN_PASSWORD")
    BACKUP_SSID=$(urldecode "$BACKUP_SSID")
    BACKUP_PASSWORD=$(urldecode "$BACKUP_PASSWORD")
    
    # Debug log the parsed values
    echo "$(date): [WEB-CONFIG] Parsed values:" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    echo "$(date): [WEB-CONFIG]   ACTION='$ACTION'" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    echo "$(date): [WEB-CONFIG]   MAIN_SSID='$MAIN_SSID'" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    echo "$(date): [WEB-CONFIG]   MAIN_PASSWORD='$MAIN_PASSWORD'" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    echo "$(date): [WEB-CONFIG]   BACKUP_SSID='$BACKUP_SSID'" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    echo "$(date): [WEB-CONFIG]   FORCE_HOTSPOT='$FORCE_HOTSPOT'" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    
    # Set force hotspot value
    if [ "$FORCE_HOTSPOT" = "true" ]; then
        FORCE_HOTSPOT_VAL="true"
    else
        FORCE_HOTSPOT_VAL="false"
    fi
    
    # Create temporary file first, then move it
    TEMP_CONFIG="/tmp/wifi-fallback.conf.tmp"
    
    # Write configuration to temporary file
    cat > "$TEMP_CONFIG" <<EOF
MAIN_SSID="$MAIN_SSID"
MAIN_PASSWORD="$MAIN_PASSWORD"
BACKUP_SSID="$BACKUP_SSID"
BACKUP_PASSWORD="$BACKUP_PASSWORD"
FORCE_HOTSPOT=$FORCE_HOTSPOT_VAL
EOF
    
    # Copy temp file to final location with sudo
    sudo cp "$TEMP_CONFIG" /etc/wifi-fallback.conf
    rm -f "$TEMP_CONFIG"
    
    # Verify the file was written correctly
    if [ -f /etc/wifi-fallback.conf ]; then
        echo "$(date): [WEB-CONFIG] Configuration saved successfully" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
        echo "$(date): [WEB-CONFIG] Saved configuration:" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
        cat /etc/wifi-fallback.conf | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    else
        echo "$(date): [WEB-CONFIG] ERROR: Failed to save configuration" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    fi
    
    # Generate response HTML
    RESPONSE='<!DOCTYPE html>
<html>
<head>
    <title>Configuration Saved</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            margin: 0;
        }
        .container {
            max-width: 500px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            text-align: center;
        }
        h1 { color: #333; }
        .success {
            background: #d4edda;
            color: #155724;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border: 1px solid #c3e6cb;
        }
        .info {
            background: #cce5ff;
            color: #004085;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border: 1px solid #b8daff;
        }
        .warning {
            background: #fff3cd;
            color: #856404;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border: 1px solid #ffeeba;
        }
        .button {
            display: inline-block;
            padding: 10px 20px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 6px;
            margin-top: 20px;
        }
        .button:hover {
            background: #0056b3;
        }
        .spinner {
            border: 3px solid #f3f3f3;
            border-top: 3px solid #007bff;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 20px auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Configuration Saved!</h1>'
    
    if [ "$FORCE_HOTSPOT_VAL" = "true" ]; then
        RESPONSE="$RESPONSE
        <div class='warning'>
            <strong>Force Hotspot Mode: ENABLED</strong><br>
            Device will remain in hotspot mode
        </div>"
    else
        RESPONSE="$RESPONSE
        <div class='success'>
            <strong>WiFi Networks Configured:</strong><br>"
        [ -n "$MAIN_SSID" ] && RESPONSE="$RESPONSE Primary: $MAIN_SSID<br>"
        [ -n "$BACKUP_SSID" ] && RESPONSE="$RESPONSE Backup: $BACKUP_SSID<br>"
        RESPONSE="$RESPONSE</div>"
    fi
    
    if [ "$ACTION" = "restart" ]; then
        RESPONSE="$RESPONSE
        <div class='info'>
            <strong>Applying Configuration...</strong><br>
            The service is restarting to connect to WiFi
            <div class='spinner'></div>
        </div>
        <p>If WiFi connection succeeds, you'll lose connection to this hotspot.</p>
        <p>Page will refresh in 20 seconds...</p>
        <script>setTimeout(function(){ window.location.href='/'; }, 20000);</script>"
        
        # Restart service in background with delay
        (sleep 3; sudo systemctl restart wifi-fallback.service) &
    else
        RESPONSE="$RESPONSE
        <div class='info'>
            Settings saved. The service will check for changes within 30 seconds.
        </div>"
    fi
    
    RESPONSE="$RESPONSE
        <a href='/' class='button'>← Back to Configuration</a>
    </div>
</body>
</html>"
    
    send_response "text/html" "$RESPONSE"
fi
