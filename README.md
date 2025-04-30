# Build your own Ubuntu Live Image with Docker

This is a example dockerfile that contains a multi-stage Buildkit build for a Ubuntu flavored image, supporting both arm64 and amd64 architectures.

The stages are:
- init-rootfs-cacher: prepares the inital rootfs using debootstrap
- init-rootfs: debootstrapped rootfs
- lite-image: image that contains most packages, but no desktop environment
- live-image: complete image with desktop environment, kernel, and installer
- squashfs-builder: converts the rootfs to a squashfs image
- iso-builder: builds the live ISO image
- iso-archive: dummy docker stage that just copies the iso to the result folder

## Building

To build the image, run the following command:

```bash
bash build.sh
```

## Credits

Useful resources for this project:
- Live Custom Ubuntu: https://github.com/mvallim/live-custom-ubuntu-from-scratch
- T2 Ubuntu Linux: https://github.com/t2linux/T2-Ubuntu
- Archboot: https://github.com/tpowa/Archboot