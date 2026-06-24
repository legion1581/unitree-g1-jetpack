# Unitree G1 Jetpack

One script to build, back up, restore and flash a custom **JetPack** image for the
**Unitree G1 custom carrier**.

It downloads a stock NVIDIA BSP, drops in **pre-patched DTB** (carrier USB3 wiring
so recovery RNDIS + USB work), applies a small set of rootfs tweaks (login user,
static IP, WiFi/BT driver), and flashes over the recovery initrd.


## One version per branch

The repo is **single-version**: the script reads `version.env` and the asset
folders (`dtb/`, `firmware/`, `modules/`, `overlay/`) straight from the root, and
each JetPack lives on its **own branch**. Check out the branch for the version you
want to build.

| JetPack | L4T | branch | status |
|---------|-----|--------|--------|
| 6.2.2   | 36.5.0 | `6.2.2` | ✅ working |
| 5.1.6   | 35.6.4 | `5.1.6` | planned |
| 7.2     | 39.2.0 | `7.2`   | planned |

```bash
git checkout 6.2.2
```

## Quick start

```bash
# 1. build a flash-ready BSP (download + extract + patch), into ./bsp/6.2.2
./g1_custom_jetpack.sh init

# 2. put the board in RECOVERY (RCM) mode + connect the USB-C flashing cable, then:
./g1_custom_jetpack.sh status          # confirm APX, then RNDIS once the initrd boots
./g1_custom_jetpack.sh flash all       # full flash (QSPI + NVMe rootfs)
```

After it boots: user **`unitree` / `123`**, wired IP **`192.168.123.164`**, WiFi + BT up.

## Commands

```
./g1_custom_jetpack.sh init                 download + extract + patch a BSP
./g1_custom_jetpack.sh flash [all|qspi]     all = QSPI+NVMe (default); qspi = bootloader only
./g1_custom_jetpack.sh backup  [dir]        back up every partition (default: ./backups)
./g1_custom_jetpack.sh restore [dir]        restore a backup        (default: ./backups)
./g1_custom_jetpack.sh status               recovery state (APX / RNDIS)
./g1_custom_jetpack.sh clean [all|bsp|backup]   remove the BSP and/or backups (keeps downloads)

options:  --yes (skip confirmation on destructive ops)
```

Most operations need `sudo`; the script elevates the privileged steps itself.

## What `init` does

1. **Download** the Driver Package + sample rootfs `.tbz2` from NVIDIA → `downloads/`.
2. **Extract** into `bsp/<v>/Linux_for_Tegra`, populate the rootfs, run `apply_binaries.sh`.
3. **Patch the BSP**: copy the carrier-patched kernel DTBs over the stock ones, and
   set the MB2 BCT `cvb_eeprom_read_size = 0x0` (boot enabler — the carrier has no EEPROM).
4. **Customize the rootfs**: create the login user (oem-config bypassed), write a
   NetworkManager static-IP profile, and install the RTL8852BU WiFi/BT modules +
   firmware + autoload/blacklist overlay.

## Repo layout

```
g1_custom_jetpack.sh          the one script (version-agnostic; same on every branch)
version.env                   URLs, board conf, kernel ver, user/IP — all version knobs
dtb/                          pre-patched kernel DTB (copied over the stock one)
firmware/                     rtl8852bu_fw, rtl8852bu_config  -> /lib/firmware/
modules/                      8852bu.ko, rtk_btusb.ko         -> /lib/modules/<KVER>/updates/
overlay/                      rootfs overlay copied onto /  (etc/modprobe.d, modules-load.d,
                              home/unitree/Desktop/RoboLegion/*.deb — chowned to the user)
downloads/                    cached tarballs            (git-ignored)
bsp/Linux_for_Tegra           extracted + patched BSP    (git-ignored)
```

## Acknowledgements

A big thank you to RoboLegion community! Visit us at [RoboLegion](https://robolegion.com) for more information and support.

Built on NVIDIA's Jetson Linux (L4T) BSP, and ships the Realtek RTL8852BU WiFi/BT driver.

## Support

If you like this project, please consider buying me a coffee:

<a href="https://www.buymeacoffee.com/legion1581" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
