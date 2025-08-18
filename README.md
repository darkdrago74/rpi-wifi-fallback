# Raspberry Pi WiFi Fallback Hotspot Raspberry Pi WiFi Fallback Hotspot
 Automatic WiFi fallback system that creates a hotspot when your configured networks are unavailable.
 
 Possibility to manually enforce the hotspot mode on the IP address 192.168.66.66:8080 through the command hotspot on
 #### 


### 
�
�
 Quick Install 
�
�

 ```bash ```bash
 git clone https://github.com/darkdrago74/rpi-wifi-fallback.git
 
 cd rpi-wifi-fallback && ./install.sh

 OR

 curl -fsSL https://raw.githubusercontent.com/darkdrago74/rpi-wifi-fallback/main/install.sh |  bash




 Features: 
 
 🔄
 Automatic fallback to hotspot mode
 
 🌐
 Dual WiFi network support (main + backup)
 
 📱
 Mobile-friendly web interface
 
 🔧
 Force hotspot mode for maintenance
 
 📊
 Activity logging
 
 ⚡
 Lightweight (~5MB RAM usage)

 
 📋
 Requirements :
 
 Raspberry Pi with WiFi capability
 
 Raspberry Pi OS (Debian-based)
 
 Internet connection for installation

 
 🔧
 Configuration
 After installation, configure via:
 
 Web interface: 
 http://192.168.66.66:8080 (when in hotspot mode)
 
 Hotspot name: 
[hostname]-hotspot

 Hotspot password: 
raspberry


 🎯
 Perfect For
 
 3D Printers
 IoT projects
 Remote monitoring systems
 Home automation
 Any headless Pi setup
 
 📖
 Documentation
 
 See manual installation guide for step-by-step setup.
 
Notes

•	The script tries main network first (4 attempts, 30s each)

•	Then tries backup network (4 attempts, 30s each)

•	Hotspot activates only after both networks fail completely

•	Automatically switches back to WiFi when any network becomes available

•	Web configurator replaces existing WiFi settings - it doesn't add to them

•	Lightweight: ~5MB RAM usage

•	Logs all activity for troubleshooting


Customization

Edit /usr/local/bin/wifi-fallback.sh to modify:

•	HOTSPOT_SSID: Hotspot name

•	HOTSPOT_PASSWORD: Hotspot password

•	CHECK_INTERVAL: How often to check connection (seconds)

•	MAX_RETRIES: Failed attempts per network before trying next (4 = 2 minutes per network)

