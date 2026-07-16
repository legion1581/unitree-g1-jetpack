# USB lane mapping on the Go2 carrier

Why the Go2 dock needs a patched kernel DTB (+ a small boot unit), and exactly what they do
— **verified on hardware** (Orin Nano 8GB, JetPack 5.1.6 / 6.2.2 / 7.2).

## Background — padctl, lanes and ports

The Orin NX/Nano (T234) routes USB through the **XUSB pad controller** (`padctl`):

- **3 USB2 lanes** — `usb2-0`, `usb2-1`, `usb2-2`
- **3 USB3 (SuperSpeed) lanes** — `usb3-0`, `usb3-1`, `usb3-2`

Each USB3 **port** pairs a SuperSpeed lane with a USB2 **companion** (`nvidia,usb2-companion`),
consumed by two controllers:

- **XUDC** — the USB **device-mode** controller. Brings up the **recovery RNDIS** gadget
  (during flashing) and, if left in device mode, the L4T gadget (`192.168.55.1`). Binds `usb2-0`.
- **xHCI** — the USB **host** controller. Binds the host-side lanes (the ports you plug into).

## The Go2 dock's three USB connectors (verified)

| connector | USB2 lane | USB3 lane | speed | role |
|--|--|--|--|--|
| **Recovery Type-C** | `usb2-0` | `usb3-0` | **USB 3.x host** ✅ (at runtime) | host — *also* device-capable for flashing (recovery RNDIS) |
| **USB-A** | `usb2-1` | `usb3-1` | **USB 3.0** ✅ | host (SuperSpeed, 5 Gbps) |
| **DP Type-C** | `usb2-2` | `usb3-2` (companion) | **USB 2.0 only** | host — the 4 SuperSpeed pairs carry **DisplayPort**, not USB3 |

Key findings:

- **The recovery Type-C hosts USB 3.x** once the boot unit runs (see below) — a RealSense
  D435i enumerates there at SuperSpeed. It stays **device-capable** too: at flash time it comes
  up as the RNDIS gadget (`usb0`) so `l4t_initrd_flash --network usb0` works.
- **Orientation-independent** — flipping the Type-C cable keeps USB3 on `usb3-0`. The carrier
  steers the SuperSpeed mux in **hardware** (no CC/mux config from us); `fusb301` is *not* it
  (it's unpopulated). See "orientation" below.
- **USB-A does USB 3.0** (`usb3-1`, 5 Gbps).
- **DP Type-C is USB 2.0 only** — its four high-speed pairs are wired to **DisplayPort**
  (USB-C→DP/HDMI adapter drives a monitor), so no USB3 host there regardless of SS lane.

## How the recovery Type-C becomes a host — two independent pieces

Host on `usb2-0` is **not** baked into the DTB. It can't be: `l4t` flash copies `kernel/dtb`
into the rootfs and rewrites the extlinux `FDT`, so the **recovery-initrd DTB and the runtime
DTB are the same file** — a `mode="host"` DTB would kill the flash-time RNDIS gadget and
`l4t_initrd_flash` would hang at "Waiting for target to boot-up". So:

1. **DTB (flashable, device-capable):**
   - `usb2-0` → `mode = "otg"` + `usb-role-switch` (device by default → recovery RNDIS binds).
   - `usb3-0` **enabled** (vanilla R36/R39 ship it disabled) and added to the xHCI
     `phys`/`phy-names`, so the port *can* do SuperSpeed once handed to xHCI.
   - `board-version` stamped (`go2{nx,nano}[-super]-jetpack<ver>-robolegion-r<l4t>-<date>-v2.1`).
2. **Boot unit (`50-enable-typec-host.sh` → `enable-typec-host.service`), at runtime:**
   - **VBUS** — the connector's bus power runs through a load switch gated by SoC pin
     **`PP.06`**; until it's driven high the port sources no VBUS and a device never powers up
     (Unitree does this from `/etc/rc.local`, which this image doesn't ship).
   - **role** — with VBUS on, writing `role=host` to `usb2-0`'s role switch hands `usb3-0`'s
     SuperSpeed to xHCI.

RCM/bootROM recovery is silicon-level and the unit lives in the flashed rootfs (not the
recovery initrd), so **flashing is unaffected**. To use the port as a **device/gadget**
instead: `systemctl stop enable-typec-host` (releases VBUS) and
`echo device > /sys/class/usb_role/usb2-0-role-switch/role`.

### Driving PP.06 differs by kernel (why the unit is `Type=simple`)

| JetPack | kernel | gpio interface | how the unit drives PP.06 |
|--|--|--|--|
| 5.1.6 | 5.10 | legacy `/sys/class/gpio` | `echo 1 > …/PP.06/value` — **persists** after the process exits |
| 6.2.2 / 7.2 | 5.15 / 6.8 | sysfs-gpio removed → **libgpiod** | `gpioset --mode=signal $(gpiofind PP.06)=1` — the line **reverts when released**, so the process must **hold** it |

The chardev GPIO model releases a line when the owning fd closes (by design — unlike sysfs,
which leaks). So on JP6/JP7 the unit keeps `gpioset` alive for its lifetime; `systemctl stop`
releases VBUS → device mode. The pad-mux poke (`devmem 0x02430030 = 0x004`) is the same on all
three (portable: `busybox` → `devmem2` → `python3`).

Result — controllers by `phy-names` (once the unit has run):

| controller | role | lanes |
|--|--|--|
| **XUDC** | device / recovery gadget | `usb2-0` |
| **xHCI** | host | `usb2-0, usb2-1, usb2-2, usb3-0, usb3-1, usb3-2` |

## Orientation & CC — handled in hardware

The Go2 carrier does **not** populate `fusb301` (`0x25` is absent on every i2c bus), yet the
recovery Type-C is orientation-independent for USB3. So a separate autonomous CC/redriver on
the carrier steers the SuperSpeed mux with no host software — nothing for us to configure.
(The R35/5.1.6 DTB *did* list a `fusb301@25` node; since it's unpopulated we delete it so the
kernel stops chasing a phantom chip. The R36/R39 DTBs have no such node for this port.)

## Where it lives (node paths differ by L4T)

| | XUDC | xHCI | padctl |
|--|--|--|--|
| **R35** (5.1.6) | `/xudc@3550000` | `/xhci@3610000` | `/xusb_padctl@3520000` |
| **R36 / R39** (6.2.2 / 7.2) | `/bus@0/usb@3550000` | `/bus@0/usb@3610000` | `/bus@0/padctl@3520000` |

## Inspect a DTB

```bash
dtc -I dtb -O dts kernel.dtb | grep -A4 'usb2-0 {'                 # mode = "otg"
dtc -I dtb -O dts kernel.dtb | grep -A3 'usb3-0 {'                 # status = "okay"
dtc -I dtb -O dts kernel.dtb | grep 'phy-names = "usb2-0'          # xHCI has usb3-0
dtc -I dtb -O dts kernel.dtb | grep board-version
```

## Carrier-specific — not portable as-is

This map is **specific to the Go2 dock**. Other carriers (e.g. the G1) wire the SuperSpeed
lanes differently — always derive the mapping per board from the live tree
(`/sys/firmware/fdt`) and `lsusb -t`.
