#!/bin/bash

# Antigravity CGI Script (Trixie)
# Compatible with NetworkManager and Antigravity Watchdog FSM

# Function to send response
send_response() {
    echo "Content-Type: $1; charset=utf-8"
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
    echo "$(date): [WEB-CONFIG] Received POST data via Trixie CGI" | sudo tee -a /var/log/wifi-fallback.log >/dev/null
    
    # Parse POST data
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
    
    # Copy temp file to final location
    # Note: Install script ensures broken permissions for www-data on this file,
    # or we use sudo tee if installed with sudoers permission for tee (not currently).
    # Assuming install.sh did `chmod 664` and `chown www-data` so we can write directly.
    cp "$TEMP_CONFIG" /etc/wifi-fallback.conf
    rm -f "$TEMP_CONFIG"
    
    # RESPONSE GENERATION
    HOSTNAME=$(hostname)
    RESPONSE='<!DOCTYPE html>
<html>
<head>
    <title>Configuration Saved</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: sans-serif; padding: 20px; background: #f0f2f5; }
        .container { max-width: 500px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
        .success { color: green; margin: 20px 0; }
        .button { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Configuration Saved!</h1>'

    if [ "$ACTION" = "restart" ]; then
        RESPONSE="$RESPONSE
        <div class='success'>
            <p><strong>Applying Configuration...</strong></p>
            <p>The system is triggering the connection logic.</p>
        </div>
        <script>setTimeout(function(){ window.location.href='/'; }, 15000);</script>"
        
        # Trigger Antigravity FSM
        # FORCE IMMEDIATE SCAN: Remove the last scan marker so FSM scans now.
        rm -f /tmp/antigravity_last_scan
        
        # We start the service. If it's already running, it's fine. 
        # But for "Connect Now", we want to force a scan/connect loop.
        # The FSM checks config every run.
        (sleep 2; sudo systemctl start antigravity-watchdog.service) &
    else
        RESPONSE="$RESPONSE
        <div class='success'>
            <p>Settings saved.</p>
        </div>
        <a href='/' class='button'>Back</a>"
    fi

    RESPONSE="$RESPONSE
    </div>
</body>
</html>"
    
    send_response "text/html" "$RESPONSE"
fi
