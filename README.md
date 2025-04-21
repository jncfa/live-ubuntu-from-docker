# Docs for builder

This is a dockerfile that contains a multi-stage build for a Ubuntu flavored image.

The stages are:
- init-build-cacher: downloads the base image and installs the necessary packages
- lite-image: installs the necessary packages and configures the system
- final-image: installs the necessary packages and configures the system
- final-image-iso-builder: builds the iso image
- iso-image: contains just the iso archive

## Building

To build the image, run the following command:

```bash
bash build.sh
```