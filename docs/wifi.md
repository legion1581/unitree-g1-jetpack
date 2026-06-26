# WiFi — `nmcli` (scan · STA · AP)

The image uses NetworkManager, so use `nmcli` — connections are saved and auto-reconnect on
boot. SSH in over the wired static IP first: `ssh unitree@192.168.123.164`.

Works the same on **all three images (5.1.6 · 6.2.2 · 7.2)** — they all use NetworkManager,
and `nmcli` auto-picks the WiFi device, so the interface name doesn't matter.

## Scan

```bash
sudo nmcli device wifi rescan
sudo nmcli device wifi list
```

## Connect (STA / client)

```bash
sudo nmcli device wifi connect "MySSID" password "MyPass"
```

## Host an access point (AP)

```bash
sudo nmcli device wifi hotspot ssid MyAccessPoint password "MyPassw0rd"
```
