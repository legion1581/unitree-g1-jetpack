# Unitree G1 Custom JetPack

One script to **build, back up, restore, and flash** a custom NVIDIA **JetPack** image
for the **Unitree G1 custom carrier** (Jetson Orin NX) — for **multiple JetPack versions**
from a single branch.

Stock JetPack doesn't run cleanly on the G1's custom carrier — the USB3 lanes are wired
differently (so recovery RNDIS and the USB host ports don't work out of the box), and the
onboard WiFi/BT needs an out-of-tree driver. This repo wraps NVIDIA's BSP with those carrier
fixes plus a few rootfs tweaks, so a single `init` → `flash` gives you a working board.

> Everything is flashed **in place over the USB-C cable** — no need to remove the NVMe
> SSD from the robot. QSPI and the NVMe rootfs are written over the recovery initrd.

## Supported JetPacks

Pick one with `-j <ver>` (default **6.2.2**). Each lives under `versions/<ver>/`.

| JetPack | L4T | Kernel | Select with | Status |
|:--|:--|:--|:--|:--|
| **6.2.2** | 36.5.0 | 5.15.185-tegra | `-j 6.2.2` *(default)* | ✅ tested — WiFi · BT · static IP |
| **5.1.6** | 35.6.4 | 5.10.216-tegra | `-j 5.1.6` | ✅ tested — WiFi · BT · static IP |

What each image sets up:

- **Carrier-patched device tree** — corrected USB3 wiring so recovery RNDIS + USB host ports work.
- **MB2 boot fix** — lets the module boot on a carrier that has no EEPROM.
- **Ready-to-use rootfs** — login user, hostname, autologin, static IP, and the
  **RTL8852BU WiFi + Bluetooth** driver baked in (modules + firmware).

## Requirements

- An **x86_64 Ubuntu host** with `sudo` (the build/flash tooling is NVIDIA's; the rootfs
  steps run aarch64 under `qemu-user-static`, installed automatically if missing).
- The board's USB-C **flashing** port connected to the host. For `flash` / `backup` /
  `restore`, put the board in **recovery (RCM)** mode.

## Quick start

```bash
# choose the JetPack with -j (default is 6.2.2). Example: 5.1.6
JP=5.1.6

# 1. build a flash-ready BSP (download + extract + patch) into bsp/<ver>
./g1_custom_jetpack.sh -j $JP init

# 2. board in RECOVERY (RCM) with the USB-C flashing cable connected:
./g1_custom_jetpack.sh status            # confirm APX (bootROM recovery)
./g1_custom_jetpack.sh -j $JP flash all  # full flash (QSPI + NVMe rootfs)
```

After it boots: user **`unitree` / `123`**, hostname **`ubuntu`**, wired IP
**`192.168.123.164`** (on `eth0`), WiFi + BT up.

> `-j` can also be given as the `G1_JP` environment variable
> (e.g. `G1_JP=5.1.6 ./g1_custom_jetpack.sh init`).

## Recovery mode (RCM)

`flash`, `backup`, and `restore` need the NX module in **bootROM recovery (APX)**.
The PWR/REC buttons and the flashing port are on the NX board inside the G1's chest:

![G1-NX board — power LEDs, PWR/REC buttons, flashing port](docs/g1-nx-board.png)

> ① power indicator lights ② PWR button ③ REC button ④ flashing port

1. Power on the G1; wait until **all three power LEDs are steadily lit**.
2. Press and **hold PWR + REC together for ~2 s** — the LEDs go from three steady
   lights to two light (or all off).
3. Release **PWR**.
4. Wait ~2 s.
5. Release **REC**.

Connect the **USB-A → USB-C** cable from the host to the **flashing port** (④), then
confirm:

```bash
./g1_custom_jetpack.sh status     # -> APX — bootROM recovery (ready)
```

If the LEDs misbehave, use the alternative: power off → hold **REC** → power on while
holding REC → release **REC** after ~2 s.

> Button/port photo and procedure from Unitree's *G1-NX JetPack 6.2 Firmware & Image Update Guide*.

## Commands

All commands except `status` act on the JetPack chosen by `-j <ver>` (default 6.2.2).

```
-j, --jetpack <ver>     which JetPack to act on (6.2.2 | 5.1.6); default 6.2.2
init                    download + extract + patch a flash-ready BSP (into bsp/<ver>)
flash [all|qspi]        all = QSPI + NVMe rootfs (default); qspi = bootloader only
backup  [dir]           back up every partition over the initrd  (default: backups/<ver>)
restore [dir]           restore a backup over the initrd         (default: backups/<ver>)
status                  show recovery state (APX bootROM / RNDIS initrd) — version-independent
clean [all|bsp|backup]  remove this version's BSP and/or backups (keeps downloads)

options:  --yes   skip the confirmation prompt on destructive operations
```

Most operations need `sudo`; the script elevates the privileged steps itself.

## Repo layout

```
g1_custom_jetpack.sh        the one script (version-aware; -j selects the JetPack)
versions/<ver>/
  version.env               version knobs — URLs, board conf, kernel version, user/IP
  dtb/                      carrier-patched kernel DTB        -> kernel/dtb + bootloader
  firmware/                 rtl8852bu_fw{,.bin}, _config{,.bin} -> /lib/firmware/
  modules/                  8852bu.ko (WiFi), rtk_btusb.ko (BT) -> /lib/modules/<KVER>/updates/
  overlay/                  rootfs overlay copied onto /  (modprobe.d: 8852bu opts + blacklist)
misc/                       RTL8852BU WiFi/BT driver sources (DKMS debs + src) — shared
downloads/<ver>/            cached NVIDIA tarballs            (git-ignored)
bsp/<ver>/Linux_for_Tegra   extracted + patched BSP           (git-ignored)
backups/<ver>/              default backup/restore location   (git-ignored)
```

### Adding a JetPack version

Create `versions/<new>/` with a `version.env` (copy an existing one and adjust the
URLs / L4T / kernel / board conf), drop in the carrier-patched `dtb/`, the built
`modules/` + `firmware/`, and the `overlay/`. It's then selectable with `-j <new>`.

## Acknowledgements

A big thank you to RoboLegion community! Visit us at [RoboLegion](https://robolegion.com) for more information and support.

## Support

If you like this project, please consider buying me a coffee:

<a href="https://www.buymeacoffee.com/legion1581" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
