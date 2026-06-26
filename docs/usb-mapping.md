# USB3 lane mapping in the device tree (G1 carrier)

Why the G1 needs a patched kernel DTB at all, and exactly what the patch changes.

## Background — padctl, lanes and ports

The Orin NX (T234) routes USB through the **XUSB pad controller** (`xusb_padctl`). It has:

- **3 USB2 lanes** — `usb2-0`, `usb2-1`, `usb2-2`
- **3 USB3 (SuperSpeed) lanes** — `usb3-0`, `usb3-1`, `usb3-2`

Each USB3 **port** pairs a SuperSpeed lane with a USB2 **companion** (`nvidia,usb2-companion`),
and two host/device controllers consume those lanes:

- **XUDC** — the USB **device-mode** controller. This is what brings up the **recovery
  RNDIS** gadget (`192.168.55.1`) during flash/backup, and the device-mode networking. It
  binds **one** USB2 + one USB3 lane.
- **xHCI** — the USB **host** controller. It binds all the host-side lanes (the USB-A / hub
  ports you plug devices into).

The board's wiring (which physical connector lands on which lane) is described in the DTB.
If the DTB doesn't match the carrier, the wrong connector becomes device-mode and host ports
go dark.

## The G1 carrier problem

The stock NVIDIA devkit DTB binds **XUDC to `usb3-1`** and leaves **`usb3-2` disabled**. On
the **G1 carrier** that's wrong:

- the flashing USB-C is wired to a different SuperSpeed lane → **recovery RNDIS doesn't come
  up** (you can't flash/backup over the cable), and
- the extra host SuperSpeed port (`usb3-2`) is wired but disabled → **a USB host port is
  dead**.

## What the patched DTB does

The carrier patch ([`misc/`'s `20-usb3-dtb.py`](../misc/), applied at build time by
`10-install-carrier-dtb.sh`) rewires three things:

1. **XUDC → `usb3-0`** (move it off the stock `usb3-1`) — so the G1's flashing USB-C is the
   device-mode/recovery port.
2. **Enable `usb3-2`** (lane + port) — light up the extra host SuperSpeed port.
3. **Realign port companions** so each `usb3-N` pairs with `usb2-N`:
   `usb3-0 → usb2-0`, `usb3-1 → usb2-1`, `usb3-2 → usb2-2`.

Result, by `phy-names` (controller → lanes it owns):

| controller | stock | **G1 patched** |
|--|--|--|
| **XUDC** (device / recovery) | `usb2-0, usb3-1` | **`usb2-0, usb3-0`** |
| **xHCI** (host) | 4 phys (`usb3-2` off) | **6 phys** — `usb2-0/1/2 + usb3-0/1/2` |

A `board-version` string is also stamped into the root node so a flashed board is
identifiable (`g1nx-jetpack<ver>-robolegion-r<l4t>-<date>-vN`).

## Where it lives (node paths differ by L4T)

The padctl subtree (pads/lanes/ports) is identical across versions; only the **node paths**
move:

| | XUDC | xHCI | padctl |
|--|--|--|--|
| **R35** (5.1.6) | `/xudc@3550000` | `/xhci@3610000` | `/xusb_padctl@3520000` |
| **R36 / R39** (6.2.2 / 7.2) | `/bus@0/usb@3550000` | `/bus@0/usb@3610000` | `/bus@0/padctl@3520000` |

The patch tool auto-detects the layout, so the same fix applies to all three versions.

## Inspect a DTB

```bash
python3 misc/.../20-usb3-dtb.py <kernel.dtb> --check   # report current USB3 state
python3 misc/.../20-usb3-dtb.py <kernel.dtb> --dump    # print patched DTS, don't write
```
or decompile and read it directly:
```bash
dtc -I dtb -O dts kernel.dtb | grep -A3 -iE 'xudc|xhci@|phy-names'
```

## Carrier-specific — not portable as-is

This lane mapping is **specific to the G1 carrier**. Other Unitree carriers wire the lanes
differently — e.g. the **Go2** dock keeps **XUDC on `usb3-1`** (the stock lane) and only
enables `usb3-2`. So a DTB patched for the G1 will put recovery on the wrong port on a Go2,
and vice-versa: always derive the mapping per board.
