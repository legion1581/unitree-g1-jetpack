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
| `50-enable-typec-host.sh` | rootfs — boot unit that makes the recovery Type-C a USB host: drives `PP.06` (VBUS) high **and** sets `usb2-0` role=host |

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

### Carrier DTB changes + recovery Type-C host (same approach as 5.1.6, R36 layout)

All four DTBs get the identical Go2-carrier transform:
- **`usb2-0` → `mode = "otg"`** (from vanilla `peripheral`) with its `usb-role-switch` kept —
  device-capable so flash-time recovery RNDIS (`usb0`) still binds, but switchable to host.
- **`usb3-0` enabled** — vanilla ships it disabled; the lane + port are turned on and the
  phy is added to the xHCI `phys`/`phy-names` (so the recovery Type-C can do SuperSpeed).
- **`board-version`** stamped (`go2{nx,nano}[-super]-jetpack6.2.2-robolegion-r36.5.0-…-v2.1`).

(No `fusb301` node exists in the R36 DTB for this port, so there's nothing to remove — unlike
the R35/5.1.6 DTB.)

> **Host is a runtime step**, not baked into the DTB — `l4t` flash forces the runtime DTB to
> equal the recovery-initrd DTB, so a `mode="host"` DTB would break flash-time RNDIS. The DTB
> ships `otg`; `50-enable-typec-host.sh` promotes the port to host on boot by (1) driving
> **`PP.06`** (VBUS) high and (2) writing `role=host` to `usb2-0`'s role switch — with VBUS on,
> that hands `usb3-0`'s SuperSpeed to xHCI. RCM/bootROM recovery is silicon-level, so flashing
> is unaffected. To use the port as a device/gadget (`192.168.55.1`) instead: stop the unit,
> `echo device > /sys/class/usb_role/usb2-0-role-switch/role`, `echo 0 > /sys/class/gpio/PP.06/value`.

See **[../../docs/usb-mapping.md](../../docs/usb-mapping.md)** for the full Go2 USB map.

### Super mode (`--super`)

Flashes NVIDIA's `jetson-orin-nano-devkit-super` board config (MAXN_SUPER + 40 W). TOPS
boost: **Orin NX 16 GB 100 → 157**, **Orin Nano 8 GB 40 → 67**. Draws much more power —
confirm the Go2 rail + cooling first.

> ⚠️ Base image hardware-verified on the Go2 dock (Orin Nano, JetPack 6.2.2). The recovery
> Type-C **host** change (otg + `usb3-0` + `PP.06`/role=host) is verified on 5.1.6 and ported
> here identically, but is **pending on-hardware confirmation on 6.2.2** — flash-test it.
