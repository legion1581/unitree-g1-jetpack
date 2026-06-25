# misc — RTL8852BU WiFi/BT driver sources

Build inputs for the prebuilt modules shipped in `../modules/`. The repo ships
prebuilt `8852bu.ko` (WiFi) and `rtk_btusb.ko` (BT); these are kept here so the
modules can be rebuilt for a new kernel.

| File | What |
|------|------|
| `rtl8852bu-dkms_1.19.14_arm64.deb` | WiFi driver (`8852bu`), DKMS source. Builds `8852bu.ko`. |
| `rtkbtusb-dkms_1.19.14_arm64.deb`  | Bluetooth driver (`rtk_btusb`), DKMS source. Builds `rtk_btusb.ko`. |
| `rtl8852bu-1.19.14-src.zip`        | Plain (non-DKMS) `8852bu` (WiFi) source — `make` builds against `/lib/modules/$(uname -r)/build`. Builds on kernels up to ~6.3. |
| `rtkbtusb-1.19.14-src.zip`         | Plain (non-DKMS) `rtk_btusb` (BT) source — `make` builds against `/lib/modules/$(uname -r)/build`. |
| `rtl8852bu-1.19.14-k6.8-src.zip`   | **WiFi source patched for kernel 6.8** (JetPack 7.2 / Ubuntu 24.04). Same as above + the 6.4–6.8 API fixes below baked in. Builds `8852bu.ko` on 6.8. |
| `rtl8852bu-1.19.14-kernel-6.8.patch` | The diff alone (3 files) — `patch -p1 <` it onto a fresh `rtl8852bu-1.19.14` to reproduce the 6.8 source. |

The DKMS debs and the two `1.19.14-src.zip` sources come from the Unitree G1 EDU
vendor image (`/home/unitree/wifi-bt-deb/`).
The `rtkbtusb-1.19.14` source matters because the **stock NVIDIA BSP `rtk_btusb`
is too old** and does not know our combo's USB id `0bda:a85b`
(`can not find device pid in patch_table`); this 1.19.14 source has the 8852BU
table entry.

## Rebuild for a new kernel (on the target, headers installed)

```sh
# Bluetooth (no DKMS needed):
unzip rtkbtusb-1.19.14-src.zip && cd rtkbtusb-1.19.14
make -j"$(nproc)"          # -> rtk_btusb.ko   (uses /lib/modules/$(uname -r)/build)

# WiFi (no DKMS needed) — kernel <= 6.3:
unzip rtl8852bu-1.19.14-src.zip && cd rtl8852bu-1.19.14
make -j"$(nproc)"          # -> 8852bu.ko

# WiFi on kernel 6.8 (JetPack 7.2): use the patched source, pass -Wno-error
# (Ubuntu's noble kernel sets CONFIG_WERROR, which turns the driver's harmless
#  -Wmissing-prototypes warnings into errors):
unzip rtl8852bu-1.19.14-k6.8-src.zip && cd rtl8852bu-1.19.14
make -j"$(nproc)" USER_EXTRA_CFLAGS="-Wno-error"   # -> 8852bu.ko
```

Then `strip --strip-debug` the `.ko`, drop it into `../modules/`, and re-run
`init`. The BT firmware (`rtl8852bu_fw`, `rtl8852bu_config`, …) lives in
`../firmware/`.

### The 6.8 WiFi fixes (`rtl8852bu-1.19.14-kernel-6.8.patch`)

The 1.19.14 source only guards kernels up to ~6.3. Three changes make it build on 6.8:

| file | 6.x change | fix |
|------|-----------|-----|
| `include/osdep_service_linux.h` | 6.8 removed `strlcpy()` | alias `strlcpy` → `strscpy` (return value is unused at the call sites) |
| `os_dep/linux/ioctl_cfg80211.c` | 6.7 changed `.change_beacon` to take `struct cfg80211_ap_update *` | guard the signature; alias `info = &params->beacon` (AP-mode path) |
| `os_dep/linux/usb_intf.c` | 6.4 removed `usb_driver.drvwrap` | use the direct `.usbdrv.driver.shutdown` member |

For the BT driver, the JetPack 7.2 image already ships a current `rtk_btusb` (v3.1),
so `rtkbtusb-1.19.14` only needs rebuilding on older images (5.1.6 / 6.2.2).
