# Raspberry Pi WiFi Fallback Hotspot (Working on Bookworm and Trixie)
**Universal Support: Debian 12 (Bookworm) & Debian 13 (Trixie)**

🚀 Automatic WiFi fallback system that creates a hotspot when your configured networks are unavailable. Perfect for 3D printers, IoT projects, and headless Raspberry Pi setups!

## 💾 Supported Operating Systems
The installer **automatically detects your OS** and installs the correct engine:

| OS Version | Engine Name | Technology Stack | Folder |
|------------|-------------|------------------|--------|
| **Debian 13 (Trixie)+** | **Antigravity** | NetworkManager Native, Dispatcher Scripts, Systemd Timer | `trixie/` |
| **Debian 12 (Bookworm)** | **Legacy** | hostapd, dnsmasq, custom shell scripts | `bookworm/` |

---

## 🚀 Installation

1. **Install Git:**
   ```bash
   sudo apt-get install -y git
   ```

2. **Clone and Install:**
   ```bash
   git clone https://github.com/darkdrago74/rpi-wifi-fallback.git
   cd rpi-wifi-fallback
   chmod +x install.sh
   ./install.sh
   ```

3. **Reboot:**
   ```bash
   sudo reboot
   ```

---

## 🔧 Configuration & Usage

Once installed, if the Pi cannot connect to a known WiFi network, it will launch a hotspot.

### 🟢 Scenario A: Debian 13 (Trixie) - Antigravity Engine

*   **Hotspot Name:** `Hotspot-<Hostname>-Rescue` (e.g., `Hotspot-raspberrypi-Rescue`)
*   **Password:** Found in `/boot/wifi_fallback_creds.txt` (or default `raspberry` if not generated)
*   **Gateway IP:** `192.168.66.66`
*   **Web Interface:** http://192.168.66.66:8088
*   **SSH Access:** `ssh user@192.168.66.66`

**Updates on Trixie:**
- The Web Interface allows you to save credentials.
- The system checks connectivity every 2 minutes.
- To "Force Connect" immediately after saving on the web UI, wait ~15 seconds for the system to trigger a scan.

### 🟠 Scenario B: Debian 12 (Bookworm) - Legacy Engine

*   **Hotspot Name:** `[hostname]-hotspot`
*   **Password:** `raspberry`
*   **Gateway IP:** `192.168.66.66`
*   **Web Configuration:** http://192.168.66.66:8088
*   **Printer Interface:** http://192.168.66.66 (Port 80)

---

## 🛠️ Troubleshooting

### For Debian 13 (Trixie)
The Antigravity engine uses **NetworkManager** natively.

**Check Status:**
```bash
# Check the Watchdog Timer
systemctl status antigravity-watchdog.timer

# Check the Watchdog Service (Last run)
systemctl status antigravity-watchdog.service

# Check logs
journalctl -t Antigravity-FSM
journalctl -t Antigravity-Dispatcher
```

**Manual Control:**
```bash
# Force fallback mode manually
sudo nmcli con up Antigravity_AP

# Check active connection
nmcli con show --active
```

---

### For Debian 12 (Bookworm)
The Legacy engine uses `hostapd` and custom services.

**Check Status:**
```bash
sudo systemctl status wifi-fallback
```

**Manual Control:**
```bash
# Turn hotspot on
hotspot on

# Turn hotspot off
hotspot off

# Check status
hotspot status
```

**View Logs:**
```bash
sudo tail -f /var/log/wifi-fallback.log
```

---

## 🧹 Uninstalling
**Important:** Connect via Ethernet before uninstalling to ensure you don't lose access.

```bash
cd rpi-wifi-fallback
./uninstall.sh
```

---

## � License
MIT License
