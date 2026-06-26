# JetPack 5.1.6 — Go2 carrier (WIP)

**L4T 35.6.4** · kernel **5.10.216-tegra** · Ubuntu 20.04

Per-version payload applied to NVIDIA's BSP by `go2_custom_jetpack.sh` (`-j 5.1.6`).
The Go2 dock has **no WiFi/BT**, so this image ships none.

## Patches

Named files in [`patches/`](patches/), applied in filename order by `apply_patches`.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched kernel DTB (USB3 wiring + board-version) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (carrier has no EEPROM) |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.18/24` on **`eth0`** |

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP
- `dtb/` — carrier-patched kernel DTBs (one per module variant; the flash conf
  auto-selects by EEPROM board SKU):
  - `tegra234-p3767-0000-p3768-0000-a0.dtb` — Orin **NX** (SKU 0000)
  - `tegra234-p3767-0003-p3768-0000-a0.dtb` — Orin **Nano 8GB** (SKU 0003) — the Go2 module

## Notes

- Wired NIC is **`eth0`** (this image boots `net.ifnames=0`).
- Both DTBs carry the **identical** carrier USB3 transform (XUDC → `usb3-0`, enable
  `usb3-2`, realign companions) — the same patch the G1 uses; only the module variant
  differs. The Nano (0003) is the actual Go2 dock module.
- ⚠️ **go2 branch WIP:** the USB3 wiring applied is the **G1 carrier's**. It's confirmed
  to bring up recovery RNDIS on the Go2 dock, but whether the Go2 carrier routes the
  USB3 **host** lanes identically to the G1 is still pending a hardware test.
