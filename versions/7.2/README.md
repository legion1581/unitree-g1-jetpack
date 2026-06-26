# JetPack 7.2 — Go2 carrier (WIP)

**L4T 39.2.0** · kernel **6.8.12-1021-tegra** · Ubuntu 24.04

Per-version payload applied to NVIDIA's BSP by `g1_custom_jetpack.sh` (`-j 7.2`).
The Go2 dock has **no WiFi/BT**, so this image ships none.

## Patches

Named files in [`patches/`](patches/), applied in filename order by `apply_patches`.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched kernel DTB(s) (USB3 wiring + board-version) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (R39 ships 0x100, so it applies) |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.18/24` on **`enP8p1s0`** |

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP
- `dtb/` — carrier-patched kernel DTBs:
  - `tegra234-p3768-0000+p3767-0000-nv.dtb` — standard
  - `tegra234-p3768-0000+p3767-0000-nv-super.dtb` — Super (used by `--super`)

## Notes

- **L4T 39.2.0 = JetPack 7.2** (kernel 6.8, Ubuntu 24.04). USB3 `padctl` layout is the
  R36 `/bus@0/...` form.
- **Super mode (`--super`)** flashes NVIDIA's `jetson-orin-nano-devkit-super` board config
  (MAXN_SUPER + 40 W, ~100 → 157 TOPS on Orin NX 16 GB).
- ⚠️ **go2 branch WIP:** the DTBs here are still the **G1** carrier DTBs — swap in the Go2
  carrier DTBs before flashing a Go2 dock (the USB3 lane wiring differs: G1 puts the
  recovery lane on `usb3-0`, the Go2 dock keeps it on `usb3-1`).
