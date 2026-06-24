# Unitree G1 Jetpack 6.2.2

One script to **build, back up, restore, and flash** a custom NVIDIA **JetPack** image
for the **Unitree G1 custom carrier** (Jetson Orin NX).

**JetPack 6.2.2** · L4T 36.5.0 · kernel 5.15.185-tegra

Stock JetPack doesn't run cleanly on the G1's custom carrier — the USB3 lanes are wired
differently (so recovery RNDIS and the USB host ports don't work out of the box), and the
onboard WiFi/BT needs an out-of-tree driver. This repo wraps NVIDIA's BSP with those carrier
fixes plus a few rootfs tweaks, so a single `init` → `flash` gives you a working board.

What it sets up:

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

## Acknowledgements

A big thank you to RoboLegion community! Visit us at [RoboLegion](https://robolegion.com) for more information and support.

## Support

If you like this project, please consider buying me a coffee:

<a href="https://www.buymeacoffee.com/legion1581" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
