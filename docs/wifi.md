# WiFi — connect (STA) and host (AP) with `nmcli`

The image uses **NetworkManager**, so `nmcli` is the right tool — profiles are saved under
`/etc/NetworkManager/system-connections/` and **auto-reconnect on every boot**. Avoid
`wpa_cli`/`wpa_supplicant` and `create_ap`: they fight NetworkManager (which owns the WiFi
interface), which is why the vendor's `wpa_cli` route is often "unavailable".

> **First-boot bootstrap:** you don't need WiFi to get in. The image boots with a wired
> static IP **`192.168.123.164`** on the point-to-point link, so SSH in over the cable and
> configure WiFi from there:
> ```bash
> ssh unitree@192.168.123.164
> ```
> The wired link has **no gateway**, so once WiFi is up it becomes the default route
> (internet), while your SSH stays pinned to the wired link — you won't get kicked off.

## 0. Interface & radio

```bash
nmcli device status            # find the wifi device name (e.g. wlxfc23cd9988d1)
nmcli radio wifi               # is the radio on?
nmcli radio wifi on            # enable if off
```

`nmcli` auto-picks the WiFi device for most commands, so you rarely need `ifname`.

## 1. Scan

```bash
nmcli device wifi rescan
nmcli device wifi list                                            # quick
nmcli -f IN-USE,SSID,SIGNAL,CHAN,SECURITY,BSSID device wifi list  # detailed
```

## 2. Connect as a client (STA)

Persistent — reconnects automatically on every boot:

```bash
nmcli device wifi connect "MySSID" password "MyPass"
# hidden network:
nmcli device wifi connect "MySSID" password "MyPass" hidden yes
```

Verify / manage:

```bash
nmcli -f GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY device show wlxfc23cd9988d1
nmcli connection show                    # list saved profiles
nmcli connection up    "MySSID"          # reconnect
nmcli connection down  "MySSID"          # disconnect (keeps the profile)
nmcli connection delete "MySSID"         # forget
```

## 3. Host an access point (AP)

NetworkManager does the whole job — no `hostapd` / `dnsmasq` / `create_ap` needed.

Quick built-in hotspot:

```bash
nmcli device wifi hotspot ssid MyAccessPoint password "MyPassw0rd"
nmcli -s -f 802-11-wireless-security.psk connection show Hotspot   # read the PSK back
nmcli connection down Hotspot                                      # stop it
```

More control (band/channel + DHCP + NAT sharing to the wired uplink):

```bash
nmcli connection add type wifi ifname wlxfc23cd9988d1 con-name g1-ap autoconnect no ssid MyAccessPoint
nmcli connection modify g1-ap 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
nmcli connection modify g1-ap wifi-sec.key-mgmt wpa-psk wifi-sec.psk "MyPassw0rd"
nmcli connection up g1-ap
```

`ipv4.method shared` makes NM spin up dnsmasq (DHCP) + NAT automatically — clients get an
IP and route out through the board's other uplink. That one line replaces the entire
`create_ap` + `hostapd` + `dnsmasq` recipe.

## 4. Teardown / reset

```bash
nmcli connection down g1-ap;   nmcli connection delete g1-ap
nmcli connection down Hotspot; nmcli connection delete Hotspot
```

## Caveats

- **One radio can't be STA + AP at the same time.** Starting a hotspot on the RTL8852BU
  drops any client connection on the same adapter (unless the driver advertises concurrent
  AP+STA — most don't). Test the two modes separately.
- **Test over the wired SSH link**, not over WiFi — switching to AP mode or reconnecting as
  a client bounces the WiFi, but the wired `192.168.123.164` session stays alive.
