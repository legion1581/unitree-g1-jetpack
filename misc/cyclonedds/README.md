# CycloneDDS runtime (aarch64)

`libddsc.so.0` — Eclipse CycloneDDS C runtime, needed by `video_hub_pc4` (and other Unitree DDS
modules). Not shipped by the base install or the video_hub `.upk`, and absent from a clean NVIDIA
rootfs, so `71`/`72`-style it's baked in by `74-rootfs-cyclonedds.sh` into
`/usr/lib/aarch64-linux-gnu/`. On a real robot it comes from the vendor SDK image.

Source: `unitree_sdk2/thirdparty/lib/aarch64/libddsc.so.0` (the build the Unitree binaries target).
Eclipse CycloneDDS, EPL-2.0 / EDL-1.0 — redistributable. Deps: libc/libpthread/libdl only.
Verified live on the 7.2 board: with this + eth0 + nvidia-l4t-gstreamer, video_hub streams.
