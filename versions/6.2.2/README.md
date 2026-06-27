# JetPack 6.2.2 — Go2 carrier

**L4T 36.5.0** · kernel **5.15.185-tegra** · Ubuntu 22.04

Per-version payload applied to NVIDIA's BSP by `go2_custom_jetpack.sh` (`-j 6.2.2`).
The Go2 dock has **no WiFi/BT**, so this image ships none.

## Patches

Named files in [`patches/`](patches/), applied in filename order by `apply_patches`.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched kernel DTB(s) (USB wiring + board-version) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (carrier has no EEPROM) |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.18/24` on **`enP8p1s0`** |
| `50-force-usb-device-mode.sh` | rootfs — boot unit forcing usb2-0 role → `device` (no CC chip; binds the L4T gadget @ `192.168.55.1`) |

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP
- `dtb/` — carrier-patched kernel DTBs (one per module variant **and** Super; the flash
  conf auto-selects by EEPROM board SKU + `--super`):
  - `tegra234-p3768-0000+p3767-0000-nv.dtb` — Orin **NX** (SKU 0000)
  - `tegra234-p3768-0000+p3767-0000-nv-super.dtb` — Orin **NX**, Super
  - `tegra234-p3768-0000+p3767-0003-nv.dtb` — Orin **Nano 8GB** (SKU 0003) — the Go2 module
  - `tegra234-p3768-0000+p3767-0003-nv-super.dtb` — Orin **Nano 8GB**, Super

## Notes

- Wired NIC is **`enP8p1s0`**.

### Carrier DTB changes (same set as 5.1.6, R36 layout)

All four DTBs get the identical Go2-carrier transform — the USB3 wiring fix plus:
- **`fusb301@25` removed** — the FUSB301 Type-C CC chip is **not populated** on the Go2
  carrier; node + its OF-graph role-switch link are deleted.
- **`usb3-0` disabled** — the flashing Type-C exposes no USB3 host; the lane is turned off
  and dropped from xHCI/XUDC.
- **`usb2-0` → `mode = "peripheral"`** — device-only (recovery + USB gadget). With no CC
  chip the role won't auto-resolve, so `50-force-usb-device-mode.sh` drives `role=device`
  on boot to bind the L4T gadget (`192.168.55.1`).

See **[../../docs/usb-mapping.md](../../docs/usb-mapping.md)** for the full Go2 USB map
(only the USB-A is USB 3.0; both Type-C ports are USB 2.0).

### Super mode (`--super`)

Flashes NVIDIA's `jetson-orin-nano-devkit-super` board config (MAXN_SUPER + 40 W). TOPS
boost: **Orin NX 16 GB 100 → 157**, **Orin Nano 8 GB 40 → 67**. Draws much more power —
confirm the Go2 rail + cooling first.

> ✅ Hardware-verified on the Go2 dock (Orin Nano, JetPack 6.2.2).
