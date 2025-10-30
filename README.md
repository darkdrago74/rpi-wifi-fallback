# Raspberry Pi WiFi Fallback Hotspot   (Working!!!  --- but not with Trixie version of Debian..... yet)

🚀 Automatic WiFi fallback system that creates a hotspot when your configured networks are unavailable. Perfect for 3D printers, IoT projects, and headless Raspberry Pi setups!
To uninstall the wifi fallback system, perform it with your machine's ethernet cable plugged

## Also, in case klipper is installed AFTER the wifi fallback, when using KIAUH to install mainsail, some errors will get trigered if you leave the default port to 80. This will also create problems with Octoeverywhere which will then show the main page of the rpi-wifi-fallback script, instead of mainsail/fluidd. 
The best approach is to Install the script on a fully working machine (after Mainsail installation and Octoeverwhere)

## ✨ Features

- 🔄 **Automatic fallback** to hotspot mode when WiFi fails
- 🌐 **Dual WiFi support** (primary + backup networks)
- 🔌 **Ethernet Bridge**: When ethernet cable is plugged into the RPi, internet connectivity is shared through the hotspot connection
- 📱 **Mobile-friendly web interface** for easy configuration
- 🖨️ **3D Printer integration** - works perfectly with Klipper/Mainsail/Fluidd
- 🔧 **Manual hotspot mode** - enable on-demand for coworker access
- 📊 **Activity logging** and status monitoring
- ⚡ **Lightweight** - uses only ~5MB RAM

## 🚀 Quick Installation

Make sure git is install on your machine first
```bash
sudo apt-get install -y git
```
then
```bash
git clone https://github.com/darkdrago74/rpi-wifi-fallback.git
cd rpi-wifi-fallback
chmod +x *.sh scripts/*.sh web/*.cgi
./install.sh
sudo reboot
```

### Alternative One-Liner Install

```bash
curl -fsSL https://raw.githubusercontent.com/darkdrago74/rpi-wifi-fallback/main/install.sh | DEBIAN_FRONTEND=noninteractive bash
```

<img src="images/installfinished.png" width="600" alt="Install finished">

## 🔧 Configuration
Automatic Setup

Once installed and rpi rebooted, 
Wait for hotspot to appear.
Connect to hotspot: [hostname]-hotspot (password: raspberry)
Open web interface: http://192.168.66.66:8088
Configure networks and *SAVE & CONNECT*

<img src="images/webconfig1.png" width="600" alt="webconfig1">

<img src="images/webconfig2.png" width="600" alt="webconfig2">

<img src="images/force reconnect2.png" width="600" alt="forcing2">

#Manual Hotspot Control 
Perfect for allowing coworkers to access your 3D printer or machine:

### Enable manual hotspot (even when WiFi is working)
hotspot on

### Check current status
hotspot status

### Disable manual hotspot (return to WiFi)
hotspot off


🛡️ Safety & Maintenance

### 
Make the troubleshooting files executable
```bash
cd rpi-wifi-fallback/
chmod +x reset.sh
chmod +x check.sh
chmod +x backup.sh
chmod +x uninstall.sh
```

Check Installation Status
```bash
./check.sh
```
Reset System (if having issues)
```bash
./reset.sh  # Resets to defaults without uninstalling
```
Complete Uninstall !!!! Please perform it with the ethernet cable plugged and with an ssh connection with the ethernet connection IP
Wifi credentials will be save and reconnect the rpi to it after reboot.
```bash
./uninstall.sh  # Removes everything, restores original state
```
Create Backup Before Installing
```bash
./backup.sh    # Creates backup of original configs
./install.sh   # Then install normally
```

🖨️ 3D Printer Integration
When in hotspot mode, you get dual access:

🖨️ Klipper/Mainsail: http://192.168.66.66 (port 80)
⚙️ WiFi Configuration: http://192.168.66.66:8088 (port 8088)

Perfect for 3D Printing Scenarios:

Remote printing - reliable WiFi with automatic fallback
Coworker access - enable hotspot manually for team access
Print farm management - consistent connectivity across multiple printers
OctoPrint/Mainsail - never lose access to your printer interface

🎯 How It Works

Normal Operation: Connects to primary WiFi network
Primary Fails: Tries backup network (few attempts each)
All Fail: Automatically creates hotspot
Manual Override: Force hotspot mode anytime with hotspot on
Smart Recovery: Automatically reconnects when networks return

📋 Requirements

Raspberry Pi with WiFi capability
Raspberry Pi OS (or compatible Debian-based OS)
Internet connection for installation

🌐 Access Points
During Normal WiFi Operation

Access via your printer's normal IP address

During Hotspot Mode

Connect to: [hostname]-hotspot
Password: raspberry
Printer Interface: http://192.168.66.66
WiFi Config: http://192.168.66.66:8088
Friendly URLs: http://printer.local, http://mainsail.local

📱 Mobile Responsive
The web interface automatically adapts to:

📱 Phones: Full-width, touch-friendly interface
📱 Tablets: Centered layout with comfortable margins
💻 Desktop: Clean, centered design

🔨 Manual Installation
See manual installation guide for step-by-step setup instructions.
🚀 Advanced Features

Force hotspot mode: Keep hotspot active even when WiFi is available
Dual network fallback: Primary → Backup → Hotspot
Port separation: No conflicts with existing web services
DNS resolution: Friendly local domain names
Logging: Full activity logs for troubleshooting

🛠️ Troubleshooting
bash# Check service status
sudo systemctl status wifi-fallback

# View recent logs
sudo tail -f /var/log/wifi-fallback.log

# Manual restart
sudo systemctl restart wifi-fallback

# Check current hotspot status
hotspot status
🤝 Contributing
Issues and pull requests welcome! This project is designed to be:

Simple to install and use
Reliable in production
Well-documented
Community-friendly

📄 License
MIT License - feel free to use this in your projects!
