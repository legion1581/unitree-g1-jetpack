# JetPack 7.2 — Unitree G1 carrier

**L4T 39.2.0** · kernel **6.8.12-1021-tegra** · Ubuntu 24.04

Per-version payload applied to NVIDIA's BSP by the top-level `g1_custom_jetpack.sh`.
Select it with `-j 7.2`:

```bash
./g1_custom_jetpack.sh -j 7.2 flash all
```

After it boots: user **`unitree` / `123`**, hostname **`ubuntu`**, autologin, wired IP
**`192.168.123.164`** on `enP8p1s0`, **WiFi + BT up**.

## Status — verified on hardware

- ✅ **DTB** patched (USB3 carrier wiring + board-version) — recovery RNDIS + host ports.
- ✅ **MB2 EEPROM fix**, default user, static IP.
- ✅ **WiFi** — `8852bu.ko` rebuilt for kernel 6.8 (the 1.19.14 vendor source needed
  three small 6.4–6.8 API fixes; see `misc/`). Scans 2.4 + 5 GHz, sees APs.
- ✅ **BT** — the 7.2 image already ships a current `rtk_btusb` (v3.1) that knows the
  `0bda:a85b` combo; it only lacked firmware. We ship the `rtl8852bu_fw` /
  `rtl8852bu_config` blobs and the controller comes up (`hci0`, Powered: yes).

## Patches

Named files in [`patches/`](patches/), applied in filename order by `apply_patches`.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched DTB `tegra234-p3768-0000+p3767-0000-nv.dtb` over the stock one (USB3 wiring → recovery RNDIS + host ports) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (carrier has no EEPROM; R39 ships 0x100, so it applies) |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin, bypass oem-config |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.164/24` on **`enP8p1s0`** |
| `50-rootfs-wifi-bt.sh` | rootfs — install `8852bu.ko` (WiFi) + `rtl8852bu_*` firmware (BT) + overlay; depmod |

10–20 patch the BSP; 30+ run against the extracted rootfs.

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP for this version
- `dtb/` — carrier-patched kernel DTBs (USB3 wiring + board-version):
  - `tegra234-p3768-0000+p3767-0000-nv.dtb` — standard
  - `tegra234-p3768-0000+p3767-0000-nv-super.dtb` — Super (used by `--super`)
- `modules/dkms/8852bu.ko` — WiFi, rebuilt for **6.8.12-1021-tegra** → `/lib/modules/<KVER>/updates/`
- `firmware/` — `rtl8852bu_fw`, `rtl8852bu_config` (BT) → `/lib/firmware/`
- `overlay/` — modprobe.d (8852bu opts + in-box BT blacklist) / modules-load.d

> Unlike 6.2.2, this version **does not** ship its own `rtk_btusb.ko` — the R39 image's
> bundled v3.1 driver already recognises the combo, so only the BT firmware is needed.

## Version notes

- **L4T 39.2.0 = JetPack 7.2** (kernel 6.8, Ubuntu 24.04). USB3 `padctl` layout is the
  R36 `/bus@0/...` form, so the carrier DTB patch is the same fix as 6.2.2.
- **NIC name is `enP8p1s0`** — the 7.2 image uses predictable names (not `net.ifnames=0`),
  so the static IP binds to `enP8p1s0`, not `eth0`.
- **Super mode (`--super`)** — `./g1_custom_jetpack.sh -j 7.2 --super flash` flashes
  NVIDIA's `jetson-orin-nano-devkit-super` board config (`BOARD_CONF_SUPER`). That uses
  the `-nv-super` kernel DTB + super BPMP DTB; the DTB's `…-super` compatible makes
  `nvpower.sh` symlink the **MAXN_SUPER** nvpmodel conf (adds `MAXN_SUPER` + a **40 W**
  mode, default 40 W) instead of the standard `MAXN/10W/15W/25W`. The carrier USB3 fix
  is applied to **both** DTBs, so recovery/USB still work either way. Caveats: Orin NX
  pulls far more power in Super — confirm the G1 carrier's VDD_IN rail and cooling first;
  and an early-FAB module (TS1/EB1) is rejected by NVIDIA's super overlay.
- **Rebuilding WiFi for a newer kernel**: the patched source is in
  `misc/7.2/rtl8852bu-1.19.14-k6.8-src.zip` (and the diff in
  `misc/7.2/rtl8852bu-1.19.14-kernel-6.8.patch`). Build with
  `make USER_EXTRA_CFLAGS="-Wno-error"` against the on-device headers, then drop the
  stripped `8852bu.ko` into `modules/dkms/`.
