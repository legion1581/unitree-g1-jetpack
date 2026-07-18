# JetPack 5.1.6 — Unitree G1 carrier

**L4T 35.6.4** · kernel **5.10.216-tegra**

Per-version payload applied to NVIDIA's BSP by the top-level `g1_custom_jetpack.sh`.
Select it with `-j 5.1.6`:

```bash
./g1_custom_jetpack.sh -j 5.1.6 flash all
```

After it boots: user **`unitree` / `123`**, hostname **`ubuntu`**, autologin, wired IP
**`192.168.123.164`** on `eth0`, WiFi + BT up.

## Patches — every change in one place

Every change made to the image (BSP and rootfs) is an individual, named file in
[`patches/`](patches/), applied in filename order by `apply_patches`. Open that folder
and you see the whole patch set. They're sourced with `version.env`, `$LFT` (the BSP),
`$VDIR` (this dir), `$DTBS`, `$KVER` and the helpers in scope.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched DTB `tegra234-p3767-0000-p3768-0000-a0.dtb` over the stock one (fixes USB3 wiring so recovery RNDIS + host ports work) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (carrier has no EEPROM); already 0x0 on R35, so a no-op here |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin, bypass oem-config |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.164/24` on **`eth0`** |
| `50-rootfs-wifi-bt.sh` | rootfs — RTL8852BU WiFi+BT modules + firmware + overlay + `btusb_bak` |
| `60-fix-nvrestore-bugs.sh` | BSP — fixes two R35 `nvrestore_partitions.sh` bugs (secondary GPT written to a nonexistent `/dev/gpt_2`; `conv=sparse` without pre-erase leaves the previous flash's bytes in zero regions) so a `restore` boots **regardless of what was flashed before** |

10–20 and 60 patch the BSP; 30–50 run against the extracted rootfs. Add or change a step
by editing/dropping a `NN-name.sh` in `patches/` — no edits to the main script.

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP for this version
- `dtb/` — carrier-patched kernel DTB: `tegra234-p3767-0000-p3768-0000-a0.dtb`
- `modules/` — `8852bu.ko` (WiFi), `rtk_btusb.ko` (BT) → `/lib/modules/5.10.216-tegra/updates/`
- `firmware/` — `rtl8852bu_fw{,.bin}`, `rtl8852bu_config{,.bin}` → `/lib/firmware/`
- `overlay/` — rootfs overlay (modprobe.d: 8852bu options + `blacklist btusb`)

## Version notes

- **Wired NIC is `eth0`**, not the predictable `enP8p1s0` — the image boots `net.ifnames=0`,
  so `40-rootfs-static-ip.sh` binds the keyfile to `eth0` (via `NET_IFACE` in `version.env`).
- **BT**: the stock R35.6.4 BSP ships an `rtk_btusb` too old for our combo (no `0bda:a85b`
  in its patch table). The `rtk_btusb.ko` in `modules/` is built from `rtkbtusb-1.19.14`
  (see `../../misc/5.1.6-6.2.2/`), which does know the chip.
