# WiFi — `nmcli` (scan · STA · AP)

The image uses NetworkManager, so use `nmcli` — connections are saved and auto-reconnect on
boot. SSH in over the wired static IP first: `ssh unitree@192.168.123.164`.

## Scan

```bash
nmcli device wifi list
```

## Connect (STA / client)

```bash
nmcli device wifi connect "MySSID" password "MyPass"
```

## Host an access point (AP)

```bash
nmcli device wifi hotspot ssid MyAccessPoint password "MyPassw0rd"
```
