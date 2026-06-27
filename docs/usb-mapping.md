# USB lane mapping in the device tree (Go2 carrier)

Why the Go2 dock needs a patched kernel DTB, and exactly what the patch changes —
**verified on hardware** (Orin Nano 8GB, JetPack 5.1.6).

## Background — padctl, lanes and ports

The Orin NX/Nano (T234) routes USB through the **XUSB pad controller** (`xusb_padctl`):

- **3 USB2 lanes** — `usb2-0`, `usb2-1`, `usb2-2`
- **3 USB3 (SuperSpeed) lanes** — `usb3-0`, `usb3-1`, `usb3-2`

Each USB3 **port** pairs a SuperSpeed lane with a USB2 **companion** (`nvidia,usb2-companion`),
and two controllers consume those lanes:

- **XUDC** — the USB **device-mode** controller. Brings up the **recovery RNDIS** gadget and
  the post-boot L4T USB device-mode gadget (`192.168.55.1`). Binds one USB2 (+ optionally one
  USB3) lane.
- **xHCI** — the USB **host** controller. Binds the host-side lanes (the ports you plug into).

The board's wiring (which physical connector lands on which lane) is described in the DTB.

## The Go2 dock's three USB connectors (verified)

| connector | USB2 lane | USB3 lane | speed | role |
|--|--|--|--|--|
| **Recovery Type-C** | `usb2-0` | `usb3-0` → **disabled** | **USB 2.0 only** | **device** — recovery + L4T gadget (`192.168.55.1`) |
| **USB-A** | `usb2-1` | `usb3-1` | **USB 3.0** ✅ | host — **the only SuperSpeed port** |
| **DP Type-C** | `usb2-2` | `usb3-2` (companion) | **USB 2.0 only** | host — the 4 SuperSpeed pairs carry **DisplayPort**, not USB3 |

Key findings:

- **Only the USB-A port does USB 3.0.** A SuperSpeed device there enumerates at 5 Gbps
  (`usb3-1`).
- **The recovery Type-C (`usb2-0`) is USB 2.0 only.** It's the OTG/device port; its
  SuperSpeed lane (`usb3-0`) is not routed to anything useful here, so it's **disabled**.
  Recovery RNDIS is a USB-2 gadget anyway, so this costs nothing.
- **The DP Type-C (`usb2-2`) is USB 2.0 only.** Its connector's four high-speed pairs are
  wired to **DisplayPort** (drive a monitor with a USB-C→DP/HDMI adapter), so no USB3 host
  is available there regardless of which SS lane is paired to it.

## What the carrier DTB does (vs the stock Nano/NX DTB)

1. **Realign companions / move XUDC to `usb3-0`** so the recovery Type-C (`usb2-0`) is the
   device/recovery port (stock binds XUDC to `usb3-1`).
2. **`fusb301@25` removed** — the FUSB301 Type-C CC controller is **not populated** on the
   Go2 carrier (its driver probe fails). The node and its OF-graph role-switch link are
   deleted so the kernel stops chasing a phantom chip.
3. **`usb3-0` disabled** — the recovery Type-C exposes no USB3 host; the lane is turned off
   and removed from both xHCI and XUDC.
4. **`usb2-0` → `mode = "peripheral"`** — that port is device-only. With no CC chip the OTG
   role never auto-resolves, so a boot unit (`50-force-usb-device-mode.sh`) drives
   `role=device` to bind the L4T gadget.

Result, by `phy-names` (controller → lanes it owns):

| controller | role | lanes |
|--|--|--|
| **XUDC** | device / recovery / gadget | `usb2-0` |
| **xHCI** | host | `usb2-0, usb2-1, usb2-2, usb3-1, usb3-2` |

## Full lane map (Go2, as shipped)

| SuperSpeed port | USB2 companion | USB2 mode | Controller | Connector / use |
|--|--|--|--|--|
| `usb3-0` | `usb2-0` | **peripheral** | XUDC | **disabled** (recovery Type-C is USB2 device only) |
| `usb3-1` | `usb2-1` | host | xHCI | **USB-A — USB 3.0** |
| `usb3-2` | `usb2-2` | host | xHCI | DP Type-C — USB2 + DisplayPort (no USB3) |

## Why FUSB301 matters (and why it's gone)

FUSB301 is a USB-C **CC/orientation/role** controller. On NVIDIA's reference DTB it drives
the `usb2-0` OTG role switch. The Go2 carrier **doesn't populate it**, so the role never
auto-resolves — the port defaults to `none` and neither host nor the device gadget comes up
on its own. We therefore pin the port to device (`mode="peripheral"`) and force `role=device`
at boot. (Device mode still needs that runtime nudge because, unlike host mode, the gadget
must be bound to the UDC — see `50-force-usb-device-mode.sh`.)

## Where it lives (node paths differ by L4T)

| | XUDC | xHCI | padctl |
|--|--|--|--|
| **R35** (5.1.6) | `/xudc@3550000` | `/xhci@3610000` | `/xusb_padctl@3520000` |
| **R36 / R39** (6.2.2 / 7.2) | `/bus@0/usb@3550000` | `/bus@0/usb@3610000` | `/bus@0/padctl@3520000` |

## Inspect a DTB

```bash
dtc -I dtb -O dts kernel.dtb | grep -A3 -iE 'xudc|xhci@|phy-names'   # controllers + lanes
dtc -I dtb -O dts kernel.dtb | grep -iE 'fusb|mode = |usb2-companion'
```

## Carrier-specific — not portable as-is

This map is **specific to the Go2 dock**. Other carriers (e.g. the G1) wire the SuperSpeed
lanes differently — always derive the mapping per board from the live tree
(`/sys/firmware/fdt`) and `lsusb -t`.
