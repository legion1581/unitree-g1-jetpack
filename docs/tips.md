# Tips

Hardware notes for working with the Jetson (Orin NX / Orin Nano) on the Unitree Go2 / R1 dock
(both use the same Jetson carrier).

## Display output — DisplayPort over the Type-C

The Go2 dock's **DP Type-C** connector carries the Jetson's **DisplayPort** lines, so it's
the one to use to drive a monitor and bring up the desktop UI: plug a **USB-C → DP/HDMI**
adapter into it, connect a screen, and you get the Jetson's graphical output (login /
desktop) directly — handy for first-boot setup or debugging without SSH.

![Unitree Go2 dock connectors — the Type-C carrying DisplayPort](go2-dp-typec.png)

> That **DP Type-C** is **USB 2.0 only** for data — its four high-speed pairs carry
> DisplayPort, not USB3. For **USB 3.x** use the **USB-A** or the **recovery Type-C** (which
> becomes a USB3 host at runtime — see **[usb-mapping.md](usb-mapping.md)**).

## Carrier i2c devices (observed)

Scanned on hardware (`i2cdetect`) and cross-checked against the device tree. Useful when
poking at carrier hardware — most of these are **not** described in the DTB:

| bus | addr | in DTB? | device |
|--|--|--|--|
| i2c-1 (`c240000`) | `0x40` | yes (`ina3221@40`) | TI **INA3221** 3-channel power monitor (`UU` — driver-bound) |
| i2c-1 (`c240000`) | `0x38` | **no** | **PCF8574A** 8-bit I²C **GPIO expander** — undeclared, driverless (see below) |
| i2c-0 (`3160000`) | `0x50` | no (read by MB1/MB2) | Orin **module (CVM) EEPROM** — board id/sku/serial. Carrier (CVB) EEPROM at `0x56/0x57` is **absent** (why `20-mb2-eeprom-fix.sh` sets `cvb_eeprom_read_size=0`). |
| — | `0x25` | (deleted on R35) | `fusb301` CC chip — **not populated** (absent on every bus) |

### The `0x38` GPIO expander (PCF8574A)

- Address `0x38` is the **PCF8574A** base range (`0x38–0x3F`); the non-A part is `0x20–0x27`.
- It has **no register map** — a plain read returns the current pin state; a "register" read
  actually writes the command byte to the output latch (so don't probe it with `i2cget <reg>`).
- It's **not in the device tree and has no kernel driver**, so it sits at its power-on default
  and just straps carrier control lines. On this dock it reads `0x18` (`P4,P3` high, rest low).
  It most likely drives USB **mux/redriver enable / reset / power** straps — but the exact
  net-to-pin mapping needs the carrier schematic. It is **not** a CC/orientation controller
  (those live at other addresses: FUSB302 `0x22`, PTN5150 `0x1D`/`0x3D`, TUSB320/HD3SS3220
  `0x47`/`0x67`); Type-C orientation on this carrier is handled by autonomous hardware.
- Read its state without disturbing it (plain read, no register byte):
  ```bash
  sudo i2cget -y 1 0x38
  ```
