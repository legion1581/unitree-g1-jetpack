# JetPack 6.2.2 — Unitree G1 carrier

**L4T 36.5.0** · kernel **5.15.185-tegra**

Per-version payload applied to NVIDIA's BSP by the top-level `g1_custom_jetpack.sh`.
Select it with `-j 6.2.2`:

```bash
./g1_custom_jetpack.sh -j 6.2.2 flash all
```

After it boots: user **`unitree` / `123`**, hostname **`ubuntu`**, autologin, wired IP
**`192.168.123.164`** on `enP8p1s0`, WiFi + BT up.

## Patches — every change in one place

Every change made to the image (BSP and rootfs) is an individual, named file in
[`patches/`](patches/), applied in filename order by `apply_patches`. Open that folder
and you see the whole patch set. They're sourced with `version.env`, `$LFT` (the BSP),
`$VDIR` (this dir), `$DTBS`, `$KVER` and the helpers in scope.

| step | what it changes |
|--|--|
| `10-install-carrier-dtb.sh` | BSP — drop the carrier-patched DTB `tegra234-p3768-0000+p3767-0000-nv.dtb` over the stock one (fixes USB3 wiring so recovery RNDIS + host ports work) |
| `20-mb2-eeprom-fix.sh` | BSP — MB2 `cvb_eeprom_read_size -> 0x0` (carrier has no EEPROM); R36 ships 0x100, so this one applies |
| `30-rootfs-user.sh` | rootfs — user `unitree` / hostname `ubuntu` / autologin, bypass oem-config |
| `40-rootfs-static-ip.sh` | rootfs — NetworkManager keyfile: `192.168.123.164/24` on **`enP8p1s0`** |
| `50-rootfs-wifi-bt.sh` | rootfs — RTL8852BU WiFi+BT modules + firmware + overlay + `btusb_bak` |

10–20 patch the BSP; 30+ run against the extracted rootfs. Add or change a step by
editing/dropping a `NN-name.sh` in `patches/` — no edits to the main script.

## Payload

- `version.env` — URLs, board conf, kernel version, user/IP for this version
- `dtb/` — carrier-patched kernel DTBs (USB3 wiring + board-version):
  - `tegra234-p3768-0000+p3767-0000-nv.dtb` — standard
  - `tegra234-p3768-0000+p3767-0000-nv-super.dtb` — Super (used by `--super`)
- `modules/` — `8852bu.ko` (WiFi), `rtk_btusb.ko` (BT) → `/lib/modules/5.15.185-tegra/updates/`
- `firmware/` — `rtl8852bu_fw`, `rtl8852bu_config` → `/lib/firmware/`
- `overlay/` — rootfs overlay (modprobe.d / modules-load.d for WiFi/BT)

## Version notes

- **Wired NIC is set to `enP8p1s0`** in `version.env`. If a boot shows the static IP
  unapplied, the image likely boots `net.ifnames=0` (NIC = `eth0`, as on 5.1.6) — set
  `NET_IFACE="eth0"` and reflash. Unverified on a 6.2.2 boot.
- **BT**: this version ships its own `rtk_btusb.ko` (built for 5.15.185-tegra) that already
  knows the `0bda:a85b` combo — it does not rely on the stock BSP driver.
- **Super mode (`--super`) — 100 → [157 TOPS](https://developer.nvidia.com/blog/nvidia-jetpack-6-2-brings-super-mode-to-nvidia-jetson-orin-nano-and-jetson-orin-nx-modules/)
  on the Orin NX 16 GB.** `./g1_custom_jetpack.sh -j 6.2.2 --super flash` flashes NVIDIA's
  `jetson-orin-nano-devkit-super` board config (`BOARD_CONF_SUPER`) — the `-nv-super`
  kernel DTB + super BPMP DTB whose `…-super` compatible makes `nvpower.sh` select the
  **MAXN_SUPER** nvpmodel conf (adds `MAXN_SUPER` + a **40 W** mode, GPU up to 1173 MHz,
  default 40 W). The carrier USB3 fix is applied to **both** DTBs. Super Mode landed in
  JetPack 6.2, so it works on this R36.5 image as well as on 7.2. Caveats: Orin NX draws
  far more power in Super — confirm the carrier rail + cooling; early-FAB modules (TS1/EB1)
  are rejected by NVIDIA's super overlay.
