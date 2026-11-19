# Debug analysis - hotspot not immediate / unstable after reboot (voron02rpi, 2026-11-17)

STATUS: RESOLVED 2026-11-19. All root causes confirmed live on voron02rpi (via ethernet
192.168.1.78) and fixed in `scripts/wifi-fallback.sh` v1.3 + `config/wifi-fallback.service`
+ `install.sh` (lighttpd port). See "Fixes applied" at the bottom.

## Observed behavior
- After reboot the Voron did NOT rejoin "BB Xin Chao"; hotspot `voron02rpi-hotspot`
  only appeared after ~4 minutes, and client connection to it was unreliable.
- Web config page at 192.168.66.66:8088 unreachable while on hotspot.
- Internet sharing via ethernet only started working after eth0 got its lease late.

## Root causes (in code)

### 1. Wrong password format in /etc/wifi-fallback.conf (main cause of not rejoining wifi)
- The prefilled `MAIN_PASSWORD` is the 64-hex **PMK** copied from
  `/etc/NetworkManager/system-connections/preconfigured.nmconnection` (`psk=` field),
  NOT the wifi passphrase.
- In `connect_wifi_wpa()` the script writes `psk="$password"` (QUOTED) into
  /tmp/wpa_temp.conf. wpa_supplicant rejects a quoted 64-hex psk (PMK must be
  UNQUOTED 64 hex). So the wpa_supplicant fallback can never authenticate.
- Fix at runtime: put the REAL passphrase of the SSID into MAIN_PASSWORD.
- Fix in code: detect 64-hex password and emit it unquoted:
  `$( [ ${#password} -eq 64 ] && echo "psk=$password" || echo "psk=\"$password\"" )`

### 2. The "~4 minute" delay before the hotspot appears is not a timer - it is the retry loop
Main loop: `CHECK_INTERVAL=30`, `MAX_RETRIES=4`. Each failed `connect_to_wifi` costs:
- cleanup_interface: ~6 s of sleeps
- connect_wifi_nm: ~7-10 s
- connect_wifi_wpa: up to 30 s auth wait + 15 s dhclient + 3 s
- plus 30 s sleep between loop iterations
=> roughly 4 attempts x ~60-90 s ~= 4-6 min before `start_hotspot` runs. Matches observation.
- Fix suggestion: MAX_RETRIES=2, wpa auth wait 30->10 s, and skip the wpa fallback when
  nmcli is available and the device is managed (nmcli path already covers it).

### 3. Hotspot flicker: every 5 min the script tears the hotspot down to retry wifi
When hotspot is active, `WIFI_CHECK_INTERVAL=300`: it scans, finds MAIN_SSID (router is up),
sees 0 clients, calls `stop_hotspot` + `continue` -> 4 wifi attempts fail (cause #1) ->
hotspot restart. So the AP disappears for several minutes on each 5-min cycle, which is
why clients "fail to connect immediately" / keep getting kicked.
- Fix suggestion: lengthen WIFI_CHECK_INTERVAL, and/or only stop the hotspot after a
  successful wifi connect (try connect on a spare interface is not possible on a single
  wlan0, so at minimum reduce MAX_RETRIES during hotspot recovery and restart hotspot
  immediately if the attempt fails - which the loop does, but only after ~4-6 min).

### 4. Boot race
`wifi-fallback.service` is `After=network.target` only. At boot it may run while
NetworkManager is still initializing wlan0 (which is `unmanaged` via
`/etc/NetworkManager/conf.d/99-unmanaged-devices.conf` written by install.sh), and
`nm_available` is evaluated ONCE at script start - if NM was not active yet, the
script uses only the broken wpa path for its whole lifetime.
- Fix suggestion: unit `After=NetworkManager.service NetworkManager-wait-online.service`,
  and re-evaluate `nm_available` inside the loop.

### 5. Things checked and OK
- hostapd.conf written by installer is correct (ssid=voron02rpi-hotspot, wpa_passphrase=raspberry,
  WPA2/CCMP, channel 7, nl80211) - hotspot password is `raspberry`.
- dnsmasq.conf binds only 192.168.66.66, except-interface lo/eth0 - should not clash with
  systemd-resolved; still verify with `systemctl status dnsmasq` when reachable.
- start_hotspot order is sane: IP added before hostapd/dnsmasq start.

## Additional causes confirmed live (2026-11-19)

5. **lighttpd crash loop**: port 80 on the printer is owned by nginx (Mainsail). The old
   script flipped lighttpd between 80 and 8088 at runtime; in wifi mode it sed'ed the port
   back to 80 and lighttpd died with `can't bind to socket: 0.0.0.0:80: Address already in use`
   -> config page dead. The trixie installer already pins 8088 permanently; bookworm now does
   the same at install time and the script never touches the port.
6. **FORCE_DISCONNECT re-triggered every loop**: the script `sed`-deletes the flag from the
   conf file, but `source` does not unset shell variables, so the in-memory
   FORCE_DISCONNECT stayed "true" and fired every 30 s (log spam). Fixed by unsetting the
   variable after consuming it.
7. **Stale NAT**: setup_nat ran once at hotspot start; eth0 plugged in later (or without a
   lease yet) never got forwarding rules. Now setup_nat is idempotent and re-run every loop
   while the hotspot is active; the external interface is detected dynamically (UP + has IP).

## Fixes applied (v1.3)
- `scripts/wifi-fallback.sh`: all of the above + MAX_RETRIES 4->2, CHECK_INTERVAL 30->20,
  wpa auth wait 30->12 s, dhclient timeout 15->8 s, NM re-checked every loop, NM connect now
  reloads + rescans + waits for wlan0 to leave "unmanaged", 64-hex PMK written unquoted,
  hotspot->wifi auto-switch is a single attempt with immediate hotspot restore on failure.
- `config/wifi-fallback.service`: After/Wants NetworkManager + wait-online (boot race).
- `install.sh`: lighttpd pinned to 8088 at install time.
