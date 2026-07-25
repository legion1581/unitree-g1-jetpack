# OpenSSL 1.1 runtime libs (aarch64)

`libcrypto.so.1.1` + `libssl.so.1.1` for the Unitree binaries, which are built against OpenSSL 1.1
(JetPack 5.1 / Ubuntu 20.04). JetPack 6.2.2 (22.04) and 7.2 (24.04) ship only OpenSSL 3.0
(`libcrypto.so.3`), so `master_service` fails with `libcrypto.so.1.1: cannot open shared object
file` without these. Installed into `/usr/lib/aarch64-linux-gnu/` by `71-rootfs-openssl-1.1.sh`
(20.04 ships 1.1 by default, so 5.1.6 skips it).

Open source (OpenSSL, Apache-2.0), redistributable. Extracted from the Ubuntu 20.04 `libssl1.1`
package; identical to the libs validated on a 24.04 board.
