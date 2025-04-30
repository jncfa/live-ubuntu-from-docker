# Docs for builder

This is a dockerfile that contains a multi-stage build for a Ubuntu flavored image, supporting both arm64 and amd64 architectures.

The stages are:
- init-rootfs-cacher: prepares the inital rootfs using debootstrap
- init-rootfs: debootstrapped rootfs
- lite-image: image that contains most packages, but no desktop environment
- live-image: complete image with desktop environment, kernel, and installer
- squashfs-builder: converts the rootfs to a squashfs image
- iso-builder: converts the squashfs image to an iso image
- iso-archive: contains just the iso archive

## Building

To build the image, run the following command:

```bash
bash build.sh
```