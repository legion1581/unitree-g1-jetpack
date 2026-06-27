# JetPack 5.1.6 — Go2 carrier

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
| `50-force-usb-device-mode.sh` | rootfs — boot unit forcing usb2-0 role → `device` (no CC chip; binds the L4T gadget @ `192.168.55.1`) |

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP
- `dtb/` — carrier-patched kernel DTBs (one per module variant; the flash conf
  auto-selects by EEPROM board SKU):
  - `tegra234-p3767-0000-p3768-0000-a0.dtb` — Orin **NX** (SKU 0000)
  - `tegra234-p3767-0003-p3768-0000-a0.dtb` — Orin **Nano 8GB** (SKU 0003) — the Go2 module

## Notes

- Wired NIC is **`eth0`** (this image boots `net.ifnames=0`).
- Both DTBs carry the **identical** carrier transform; only the module variant differs.
  The Nano (0003) is the actual Go2 dock module.

### Go2 carrier USB map (verified on hardware)

The DTB is tuned to the Go2 dock's real wiring (differs from the G1):

| lane | connector | role | notes |
|--|--|--|--|
| `usb3-1` ↔ `usb2-1` | USB-A | host | **SuperSpeed works** (5 Gbps verified) |
| `usb2-2` (`usb3-2` companion) | DP Type-C | host | **USB2 only** — the 4 SS pairs carry DisplayPort, no USB3 |
| `usb2-0` (`usb3-0`) | flashing Type-C | **device** | recovery + L4T gadget; SS lane unused → disabled |

Carrier DTB changes vs the stock Nano/NX DTB:
- **`fusb301@25` removed** — the FUSB301 Type-C CC chip is **not populated** on the Go2
  carrier (probe fails). Node + its OF-graph role-switch link are deleted.
- **`usb3-0` disabled** — the flashing Type-C exposes no USB3 host; the lane is turned
  off and dropped from xHCI/XUDC.
- **`usb2-0` → `mode = "peripheral"`** — that port is device-only (recovery + USB gadget).
  Because there's no CC chip the role won't auto-resolve, so `50-force-usb-device-mode.sh`
  drives `role=device` on boot, which binds the L4T gadget (reach the board at
  `192.168.55.1` over the flashing cable, in addition to `192.168.123.18` on Ethernet).
