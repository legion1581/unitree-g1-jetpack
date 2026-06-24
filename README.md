# Unitree G1 Jetpack

One script to **build, back up, restore, and flash** a custom NVIDIA **JetPack** image
for the **Unitree G1 custom carrier** (Jetson Orin NX).

Stock JetPack doesn't run cleanly on the G1's custom carrier — the USB3 lanes are wired
differently (so recovery RNDIS and the USB host ports don't work out of the box), and the
onboard WiFi/BT needs an out-of-tree driver. This repo wraps NVIDIA's BSP with those carrier
fixes plus a few rootfs tweaks, so a single `init` → `flash` gives you a working board.

What it sets up:

- **Carrier-patched device tree** — corrected USB3 wiring so recovery RNDIS + USB host ports work.
- **MB2 boot fix** — lets the module boot on a carrier that has no EEPROM.
- **Ready-to-use rootfs** — login user, hostname, autologin, static IP, and the
  **RTL8852BU WiFi + Bluetooth** driver baked in (modules + firmware).

The patched **DTB is distributed** (in `dtb/`), not generated — no `dtc`, no kernel-DTS surgery.

## One version per branch

Each JetPack version lives on its **own branch**. The script reads `version.env` and the
asset folders (`dtb/`, `firmware/`, `modules/`, `overlay/`) from the repo root, so checking
out a branch is how you pick the version to build.

| JetPack | L4T    | branch  | status     |
|---------|--------|---------|------------|
| 6.2.2   | 36.5.0 | `6.2.2` | ✅ working |
| 5.1.6   | 35.6.4 | `5.1.6` | planned    |
| 7.2     | 39.2.0 | `7.2`   | planned    |

```bash
git checkout 6.2.2
```

## Requirements

- An **x86_64 Ubuntu host** with `sudo` (the build/flash tooling is NVIDIA's; the rootfs
  steps run aarch64 under `qemu-user-static`, installed automatically if missing).
- The board's USB-C **flashing** port connected to the host. For `flash` / `backup` /
  `restore`, put the board in **recovery (RCM)** mode.

## Quick start

```bash
git checkout 6.2.2

# 1. build a flash-ready BSP (download + extract + patch) into ./bsp
./g1_custom_jetpack.sh init

# 2. board in RECOVERY (RCM) with the USB-C flashing cable connected:
./g1_custom_jetpack.sh status      # confirm APX (bootROM recovery)
./g1_custom_jetpack.sh flash all   # full flash (QSPI + NVMe rootfs)
```

After it boots: user **`unitree` / `123`**, hostname **`ubuntu`**, wired IP
**`192.168.123.164`**, WiFi + BT up.

## Commands

```
init                    download + extract + patch a flash-ready BSP (into ./bsp)
flash [all|qspi]        all = QSPI + NVMe rootfs (default); qspi = bootloader only
backup  [dir]           back up every partition over the initrd  (default: ./backups)
restore [dir]           restore a backup over the initrd         (default: ./backups)
status                  show recovery state (APX bootROM / RNDIS initrd)
clean [all|bsp|backup]  remove the BSP and/or backups (keeps downloads)

options:  --yes   skip the confirmation prompt on destructive operations
```

Most operations need `sudo`; the script elevates the privileged steps itself.

## What `init` does

1. **Download** the Driver Package + sample rootfs `.tbz2` from NVIDIA → `downloads/` (cached).
2. **Extract** into `bsp/Linux_for_Tegra`, populate the rootfs, run `apply_binaries.sh`.
3. **Patch the BSP** — copy the carrier-patched kernel DTB over the stock one and set the
   MB2 BCT `cvb_eeprom_read_size = 0x0`.
4. **Customize the rootfs** — create the login user (oem-config bypassed, license accepted),
   set hostname + autologin, write a NetworkManager static-IP profile, and install the
   RTL8852BU WiFi/BT modules + firmware + autoload/blacklist overlay.

The result is a ready-to-flash `bsp/Linux_for_Tegra`.

## Repo layout

```
g1_custom_jetpack.sh   the one script (version-agnostic; identical on every branch)
version.env            all version knobs — URLs, board conf, kernel version, user/IP
dtb/                   carrier-patched kernel DTB        -> kernel/dtb + bootloader
firmware/              rtl8852bu_fw, rtl8852bu_config    -> /lib/firmware/
modules/               8852bu.ko, rtk_btusb.ko           -> /lib/modules/<KVER>/updates/
overlay/               rootfs overlay copied onto /
                         etc/modprobe.d, etc/modules-load.d   (WiFi/BT autoload + blacklist)
                         home/unitree/Desktop/RoboLegion/     (WiFi/BT .deb, chowned to the user)
downloads/             cached NVIDIA tarballs            (git-ignored)
bsp/Linux_for_Tegra    extracted + patched BSP           (git-ignored)
```

## Adding a JetPack version

Branch off and swap the per-version assets:

```bash
git checkout -b 5.1.6
```

- edit `version.env` (download URLs, `L4T_VER`, `KVER`, flash-config paths, DTB name);
- replace `dtb/` with that version's carrier-patched DTB;
- rebuild the WiFi/BT `modules/` against that kernel and drop them in;
- leave `g1_custom_jetpack.sh` untouched — it's version-agnostic.

## Acknowledgements

A big thank you to RoboLegion community! Visit us at [RoboLegion](https://robolegion.com) for more information and support.

Built on NVIDIA's Jetson Linux (L4T) BSP, and ships the Realtek RTL8852BU WiFi/BT driver.

## Support

If you like this project, please consider buying me a coffee:

<a href="https://www.buymeacoffee.com/legion1581" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
