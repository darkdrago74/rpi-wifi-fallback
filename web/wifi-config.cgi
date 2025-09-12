#!/bin/bash

# Function to send JSON response
send_json_response() {
    echo "Content-Type: application/json"
    echo ""
    echo "$1"
}

# Function to send HTML response
send_html_response() {
    echo "Content-Type: text/html"
    echo ""
    echo "$1"
}

# Function to send plain text response
send_text_response() {
    echo "Content-Type: text/plain"
    echo ""
    echo "$1"
}

# Simple URL decode function
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# Handle GET requests for configuration
if [ "$REQUEST_METHOD" = "GET" ]; then
    # Parse query string
    QUERY_ACTION=$(echo "$QUERY_STRING" | grep -o 'action=[^&]*' | cut -d'=' -f2)
    
    if [ "$QUERY_ACTION" = "getconfig" ]; then
        # Return current configuration
        if [ -f /etc/wifi-fallback.conf ]; then
            send_text_response "$(cat /etc/wifi-fallback.conf)"
        else
            send_text_response ""
        fi
        exit 0
    elif [ "$QUERY_ACTION" = "gethostname" ]; then
        # Return hostname
        send_text_response "$(hostname)"
        exit 0
    else
        # Return the form page
        send_html_response "$(cat /var/www/html/index.html)"
        exit 0
    fi
fi

# Handle POST requests
if [ "$REQUEST_METHOD" = "POST" ]; then
    read POST_DATA
    
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
    
    # Generate response HTML
    HOSTNAME=$(hostname)
    
    HTML_RESPONSE='<!DOCTYPE html>
<html lang="en">
<head>
    <title>Configuration Saved</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            max-width: 500px;
            margin: 0 auto;
            padding: 30px;
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 20px;
        }
        .success {
            color: #155724;
            background: #d4edda;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border: 1px solid #c3e6cb;
        }
        .info {
            background: #cce5ff;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border: 1px solid #b8daff;
            color: #004085;
        }
        .warning {
            background: #fff3cd;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border: 1px solid #ffeeba;
            color: #856404;
        }
        .center { text-align: center; }
        a {
            color: #007bff;
            text-decoration: none;
            font-weight: 500;
        }
        a:hover { text-decoration: underline; }
        .button {
            display: inline-block;
            padding: 10px 20px;
            background: #007bff;
            color: white;
            border-radius: 6px;
            margin-top: 10px;
        }
        .button:hover {
            background: #0056b3;
            text-decoration: none;
        }
        .config-details {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 6px;
            margin: 15px 0;
            font-family: monospace;
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
        HTML_RESPONSE="$HTML_RESPONSE
        <div class='warning'>
            <strong>⚠️ Force Hotspot Mode: ENABLED</strong><br>
            The device will stay in hotspot mode until this setting is disabled.
        </div>"
    else
        HTML_RESPONSE="$HTML_RESPONSE
        <div class='success'>
            <strong>Configuration Updated:</strong><br>"
        
        if [ -n "$MAIN_SSID" ]; then
            HTML_RESPONSE="$HTML_RESPONSE
            • Primary Network: <strong>$MAIN_SSID</strong><br>"
        fi
        
        if [ -n "$BACKUP_SSID" ]; then
            HTML_RESPONSE="$HTML_RESPONSE
            • Backup Network: <strong>$BACKUP_SSID</strong><br>"
        fi
        
        HTML_RESPONSE="$HTML_RESPONSE
            • Force Hotspot: Disabled (Auto-fallback mode)
        </div>"
    fi
    
    if [ "$ACTION" = "restart" ]; then
        HTML_RESPONSE="$HTML_RESPONSE
        <div class='info'>
            <strong>🔄 Restarting WiFi service...</strong><br>
            The service will restart to apply changes immediately.
            <div class='spinner'></div>
        </div>
        <p class='center'>Page will redirect in 15 seconds...</p>
        <script>
            setTimeout(function(){ 
                window.location.href='/'; 
            }, 15000);
        </script>"
        
        # Restart the service in background
        (sleep 2; sudo systemctl restart wifi-fallback.service) &
    else
        HTML_RESPONSE="$HTML_RESPONSE
        <div class='info'>
            <strong>💾 Settings saved!</strong><br>
            Changes will be applied automatically within 30 seconds.
        </div>"
    fi
    
    HTML_RESPONSE="$HTML_RESPONSE
        <p class='center'>
            <a href='/' class='button'>← Back to Configuration</a>
        </p>
    </div>
</body>
</html>"
    
    send_html_response "$HTML_RESPONSE"
    
else
    # Handle other request methods
    HTML_RESPONSE='<!DOCTYPE html>
<html>
<head>
    <title>Method Not Allowed</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background: #f5f5f5;
        }
        .container {
            max-width: 500px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Method not allowed</h1>
        <p>This page only accepts POST requests.</p>
        <p><a href="/">Back to configuration</a></p>
    </div>
</body>
</html>'
    
    send_html_response "$HTML_RESPONSE"
fi
