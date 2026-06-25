# JetPack 7.2 — Unitree G1 carrier  ·  WIP (no WiFi/BT yet)

**L4T 39.2.0** · kernel **6.8.12-1021-tegra** · Ubuntu 24.04

Per-version payload applied to NVIDIA's BSP by the top-level `g1_custom_jetpack.sh`.
Select it with `-j 7.2`:

```bash
./g1_custom_jetpack.sh -j 7.2 flash all
```

After it boots: user **`unitree` / `123`**, hostname **`ubuntu`**, autologin, wired IP
**`192.168.123.164`**. **WiFi + BT are not set up yet** (see below).

## Status — what's done / not done

- ✅ **DTB** patched (USB3 carrier wiring + board-version) — recovery RNDIS + host ports.
- ✅ MB2 EEPROM fix, default user, static IP.
- ⛔ **WiFi/BT not built** — kernel 6.8 needs the RTL8852BU drivers compiled on-device.
  This folder ships **no `modules/` or `firmware/`**, and there is **no `50-rootfs-wifi-bt.sh`**.
  Plan: flash → boot → build `8852bu` + `rtk_btusb` on-device → drop the `.ko` + firmware
  into `modules/` + `firmware/` and add `50-rootfs-wifi-bt.sh` (copy from `../6.2.2`).

## Patches

Named files in [`patches/`](patches/), applied in filename order by `apply_patches`.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched DTB `tegra234-p3768-0000+p3767-0000-nv.dtb` over the stock one (USB3 wiring → recovery RNDIS + host ports) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (carrier has no EEPROM; R39 ships 0x100, so it applies) |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin, bypass oem-config |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.164/24` on **`eth0`** |

## Version notes

- **L4T 39.2.0 = JetPack 7.2** (kernel 6.8, Ubuntu 24.04). USB3 `padctl` layout is the
  R36 `/bus@0/...` form, so the carrier DTB patch is the same fix as 6.2.2.
- **`NET_IFACE` unverified** — set to `eth0` (assuming `net.ifnames=0`); confirm on first
  boot (`ip -br addr`) and adjust `version.env` if the NIC is named differently.
- **Static IP** assumes the rootfs uses NetworkManager; verify on Ubuntu 24.04 (it may use
  netplan/systemd-networkd — if so, `40-rootfs-static-ip.sh` will need adjusting).
