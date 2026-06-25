# misc — RTL8852BU WiFi/BT driver sources

Build inputs for the prebuilt modules shipped in `../modules/`. The repo ships
prebuilt `8852bu.ko` (WiFi) and `rtk_btusb.ko` (BT); these are kept here so the
modules can be rebuilt for a new kernel.

| File | What |
|------|------|
| `rtl8852bu-dkms_1.19.14_arm64.deb` | WiFi driver (`8852bu`), DKMS source. Builds `8852bu.ko`. |
| `rtkbtusb-dkms_1.19.14_arm64.deb`  | Bluetooth driver (`rtk_btusb`), DKMS source. Builds `rtk_btusb.ko`. |
| `rtl8852bu-1.19.14-src.zip`        | Plain (non-DKMS) `8852bu` (WiFi) source — `make` builds against `/lib/modules/$(uname -r)/build`. |
| `rtkbtusb-1.19.14-src.zip`         | Plain (non-DKMS) `rtk_btusb` (BT) source — `make` builds against `/lib/modules/$(uname -r)/build`. |

All three come from the Unitree G1 EDU vendor image (`/home/unitree/wifi-bt-deb/`).
The `rtkbtusb-1.19.14` source matters because the **stock NVIDIA BSP `rtk_btusb`
is too old** and does not know our combo's USB id `0bda:a85b`
(`can not find device pid in patch_table`); this 1.19.14 source has the 8852BU
table entry.

## Rebuild for a new kernel (on the target, headers installed)

```sh
# Bluetooth (no DKMS needed):
unzip rtkbtusb-1.19.14-src.zip && cd rtkbtusb-1.19.14
make -j"$(nproc)"          # -> rtk_btusb.ko   (uses /lib/modules/$(uname -r)/build)

# WiFi (no DKMS needed):
unzip rtl8852bu-1.19.14-src.zip && cd rtl8852bu-1.19.14
make -j"$(nproc)"          # -> 8852bu.ko
```

Then `strip --strip-debug` the `.ko`, drop it into `../modules/`, and re-run
`init`. The BT firmware (`rtl8852bu_fw`, `rtl8852bu_config`, …) lives in
`../firmware/`.
