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
| `50-enable-typec-host.sh` | rootfs — boot unit that makes the recovery Type-C a USB host: drives `PP.06` (VBUS) high **and** sets `usb2-0` role=host |

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

### Go2 carrier USB map

| lane | connector | role | notes |
|--|--|--|--|
| `usb3-0` ↔ `usb2-0` | Recovery Type-C | **host** (otg → host at runtime) | USB 3.x host (RealSense trains SuperSpeed, verified). Needs the boot unit — see below. |
| `usb3-1` ↔ `usb2-1` | USB-A | host | SuperSpeed (5 Gbps, verified) |
| `usb2-2` (`usb3-2` companion) | DP Type-C | host | **USB2 only** — the 4 SS pairs carry DisplayPort, no USB3 |

Carrier DTB changes vs the stock Nano/NX DTB:
- **`fusb301@25` removed** — the FUSB301 Type-C CC chip is **not populated** on the Go2
  carrier (probe fails). Node + its OF-graph role-switch link are deleted.
- **carrier USB3 wiring** — `usb3-0`/`usb3-2` enabled, companions aligned (`usb3-N ↔
  usb2-N`); all three SuperSpeed lanes active.
- **`usb2-0` stays `mode = "otg"` + `usb-role-switch`** — device-capable, so the flash-time
  recovery RNDIS gadget (`usb0`) still binds and `l4t_initrd_flash --network usb0` works.
  The host role is applied at **runtime**, not baked into the DTB (see below).

> **Why host is a runtime step, not a DTB setting.** `l4t` flash forces the runtime DTB to
> be the *same file* as the recovery-initrd DTB (`flash.sh` copies `kernel/dtb` into the
> rootfs and rewrites the extlinux `FDT`). A `mode="host"` DTB would kill the flash-time
> RNDIS gadget → `l4t_initrd_flash` times out at "Waiting for target to boot-up". So the
> DTB ships `otg` (flashable), and `50-enable-typec-host.sh` promotes the port to host on
> boot. This mirrors Unitree's stock flow (device-mode flash, host enabled from userspace).
>
> **Two things make it host**, both done by the boot unit:
> 1. **VBUS** — the connector's bus power runs through a load switch gated by SoC pin
>    **`PP.06`**; until driven high the port sources no VBUS and a device never powers up.
> 2. **role** — with VBUS on, writing `role=host` to `usb2-0`'s role switch hands `usb3-0`'s
>    SuperSpeed to the xHCI host controller.
>
> ✅ Verified on the Go2 dock: after a clean flash + boot, a RealSense D435i auto-enumerates
> on the recovery Type-C at SuperSpeed (orientation-independent — the carrier steers the SS
> mux in hardware). RCM/bootROM recovery is silicon-level, so **flashing is unaffected**.
>
> To use the port as a **device/gadget** instead (e.g. the `192.168.55.1` RNDIS gadget),
> stop the unit and revert: `systemctl stop enable-typec-host`, then
> `echo device > /sys/class/usb_role/usb2-0-role-switch/role` and `echo 0 > /sys/class/gpio/PP.06/value`.
> ⚠️ Don't leave the port sourcing VBUS (host) while cabled to another host (your laptop) —
> two VBUS sources on one link is out of spec.
