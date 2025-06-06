ARG UBUNTU_VERSION=noble
ARG ROS_VERSION=kilted
ARG TARGETARCH
ARG OS_NAME="ROS2-Kilted"
ARG DISKNAME="Install ${OS_NAME}"
ARG KERNEL_VARIANT="linux-lowlatency"

FROM ubuntu:${UBUNTU_VERSION} AS base
ENV DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION
ARG ROS_VERSION
ARG TARGETARCH

# hadolint ignore=DL3022
COPY --link --from=local-context apt.conf.d/ /etc/apt/apt.conf.d/

FROM base AS init-rootfs-cacher-base
RUN apt-get update && apt-get install -y  \
    apt-utils \
    debootstrap \
    ubuntu-keyring \
    && rm -rf /var/lib/apt/lists/*

# separate stage to set ubuntu mirrors according to target arch

# hadolint ignore=DL3029
FROM --platform=linux/amd64 init-rootfs-cacher-base AS init-rootfs-cacher-amd64
ENV UBUNTU_MIRROR=http://archive.ubuntu.com/ubuntu/

# hadolint ignore=DL3029
FROM --platform=linux/arm64 init-rootfs-cacher-base AS init-rootfs-cacher-arm64
ENV UBUNTU_MIRROR=http://ports.ubuntu.com/ubuntu-ports/

# unify stage and inherit env vars accordingly
# hadolint ignore=DL3006
FROM init-rootfs-cacher-${TARGETARCH:?} AS init-rootfs-cacher

# added all components to make sure we have all the packages we need
# minbase variant can be used but it is extremely tricky to specify all packages we need
# as we get minor breakages all over the place
RUN debootstrap --merged-usr --arch="${TARGETARCH}" \
    --components=main,restricted,universe,multiverse \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    "${UBUNTU_VERSION:?}" /rootfs "${UBUNTU_MIRROR:?}" \
    # delete resolv.conf to prevent it from being copied to the final image (systemd autogenerates it)
    && rm /rootfs/etc/resolv.conf \
    # apt cache is also not needed (and makes the image bigger)
    && rm -rf /rootfs/var/cache/apt/archives/* && rm -rf /rootfs/var/lib/apt/lists/*

FROM scratch AS init-rootfs

ENV DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION
ARG ROS_VERSION
ARG TARGETARCH

COPY --link --from=init-rootfs-cacher /rootfs /

# add our custom apt.conf.d docker hooks
# hadolint ignore=DL3022
COPY --link --from=local-context apt.conf.d/ /etc/apt/apt.conf.d/

ENTRYPOINT [ "/bin/bash" ]

FROM init-rootfs AS lite-image

# base image setup (TODO: list references for this)
RUN apt-get update && apt-get install -y  \
    apt-utils \
    libterm-readline-gnu-perl \
    dbus \
    && rm -rf /var/lib/apt/lists/*

RUN truncate -s 0 /etc/machine-id && ln -fs /etc/machine-id /var/lib/dbus/machine-id

# install common programs
RUN apt-get update && apt-get install -y  \
    jq \
    tar \
    curl \
    file \
    gawk \
    less \
    nano \
    sudo \
    wget \
    zstd \
    gnupg \
    xz-utils \
    iputils-ping \
    net-tools \
    ca-certificates \
    software-properties-common \
    apparmor \
    binutils \
    man \
    manpages \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Install ROS2 because I want it :D
# hadolint ignore=DL4006
RUN add-apt-repository universe \
    && curl -vL -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/1.1.0/ros2-apt-source_1.1.0.$(. /etc/os-release && echo $VERSION_CODENAME)_all.deb" \
    && apt-get install -y /tmp/ros2-apt-source.deb \
    && apt-get update && apt-get install -y ros-dev-tools "ros-${ROS_VERSION}-desktop" \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/profile.d && echo "source /opt/ros/${ROS_VERSION}/setup.bash" >> /etc/profile.d/10_source_ros.sh

FROM lite-image AS live-image

ARG KERNEL_VARIANT

# Install timezone
RUN ln -fs /usr/share/zoneinfo/UTC /etc/localtime \
    && apt-get update && apt-get install -y  \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# install packages that should be included for a more complete system
RUN apt-get update && apt-get install -y  \
    yaru-theme-gnome-shell \
    yaru-theme-gtk \
    yaru-theme-icon \
    yaru-theme-sound \
    ubuntu-wallpapers \
    gsettings-ubuntu-schemas \
    xserver-xorg \
    ubuntu-keyring \
    libpam-gnome-keyring \
    gnome-keyring \
    gnome-characters \
    gnome-session  \
    ubuntu-desktop \
    apport-gtk \
    policykit-desktop-privileges \
    ubuntu-drivers-common \
    rtkit \
    fwupd \
    fwupd-signed \
    gnome-disk-utility \
    usb-creator-gtk \
    command-not-found \
    && rm -rf /var/lib/apt/lists/*

# add a very cute bg as default
# hadolint ignore=DL3022
COPY --link --from=local-context cute-bg.png /usr/share/backgrounds/ubuntu-robotics.png
RUN cat <<EOF > /usr/share/glib-2.0/schemas/20_better-background.gschema.override
[org.gnome.desktop.background:ubuntu]
picture-uri='file:///usr/share/backgrounds/ubuntu-robotics.png'
[org.gnome.desktop.screensaver:ubuntu]
picture-uri='file:///usr/share/backgrounds/ubuntu-robotics.png'
EOF

# compile schema to set the new bg
RUN glib-compile-schemas /usr/share/glib-2.0/schemas

# install network manager
RUN apt-get update && apt-get install -y  \
    network-manager \
    network-manager-config-connectivity-ubuntu \
    network-manager-gnome \
    network-manager-openvpn \
    network-manager-openvpn-gnome \
    network-manager-pptp \
    network-manager-pptp-gnome \
    && rm -rf /var/lib/apt/lists/*

# add more customizations to the image
RUN apt-get update && apt-get install -y  \
    avahi-daemon \
    avahi-utils \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# plymouth shows the cute splash screen during boot
RUN apt-get update && apt-get install -y  \
    plymouth \
    plymouth-label \
    plymouth-theme-spinner \
    plymouth-themes \
    plymouth-theme-ubuntu-text \
    && rm -rf /var/lib/apt/lists/*

# requirements for grub bootloader
RUN apt-get update && apt-get install -y  \
    grub-common \
    grub-efi \
    "grub-efi-${TARGETARCH}-signed" \
    shim-signed \
    && rm -rf /var/lib/apt/lists/*

# disable network manager for installer (to speed up installation)
RUN rm -f /etc/systemd/system/multi-user.target.wants/NetworkManager.service /etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service

# re-enable after install
RUN debconf-set-selections <<EOF
ubiquity ubiquity/success_command string /bin/bash -c "ln -s /lib/systemd/system/NetworkManager.service /target/etc/systemd/system/multi-user.target.wants/NetworkManager.service && ln -s /lib/systemd/system/NetworkManager-wait-online.service /target/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"
ubiquity mirror/suite string ${UBUNTU_VERSION}
EOF

# packages for live-boot
RUN apt-get update && apt-get install -y  \
    ubiquity \
    ubiquity-casper \
    ubiquity-frontend-gtk \
    ubiquity-ubuntu-artwork \
    ubiquity-frontend-debconf \
    ubiquity-slideshow-ubuntu \
    localechooser-data \
    casper \
    mtools \
    && rm -rf /var/lib/apt/lists/*

# install kernel, firmware and register initramfs
RUN apt-get update && apt-get install -y  \
    initramfs-tools \
    && rm -rf /var/lib/apt/lists/*

# kernel installation needs to be done after ubiquity to prevent having multiple
# initrds generated
# hadolint ignore=DL4006
RUN apt-get update && apt-get install -y  \
    kmod \
    "${KERNEL_VARIANT}" \
    linux-firmware \
    && rm -rf /var/lib/apt/lists/*  \
    && kernel=$(ls /lib/modules | head -n1) && depmod -a "${kernel}" && update-initramfs -u -v -k "${kernel}"

# generate manifests for later use
RUN PACKAGES_TO_REMOVE="ubiquity ubiquity-casper ubiquity-frontend-gtk ubiquity-ubuntu-artwork ubiquity-frontend-debconf ubiquity-slideshow-ubuntu casper mtools localechooser-data discover discover-data os-prober laptop-detect" &&  \
    dpkg-query -W --showformat='${Package} ${Version}\n' > /tmp/filesystem.manifest \
    && cp /tmp/filesystem.manifest /tmp/filesystem.manifest-desktop && \
    for i in ${PACKAGES_TO_REMOVE}; do \
    sed -i "/${i}/d" /tmp/filesystem.manifest-desktop; \
    done

# delete all docker hooks we installed
RUN rm -f /etc/apt.conf.d/docker-*

# use hostplatform to build squashfs to speed up build
# hadolint ignore=DL3029
ARG BUILDPLATFORM
FROM --platform="${BUILDPLATFORM}" base AS squashfs-builder
RUN apt-get update && apt-get install -y  \
    squashfs-tools \
    initramfs-tools \
    && rm -rf /var/lib/apt/lists/*

# extract kernel, initramfs, and make squashfs for casper
RUN --mount=type=bind,from=live-image,source=/,dst=/rootfs,ro \
    mkdir -p /image/casper && \
    cp /rootfs/boot/vmlinuz-*-*-* /image/casper/vmlinuz && \
    cp /rootfs/boot/initrd.img-*-*-* /image/casper/initrd

# hadolint ignore=DL4006
RUN --mount=type=bind,from=live-image,source=/,dst=/rootfs,ro \
    printf "$(du -sx --block-size=1 /rootfs | cut -f1)" | tee /image/casper/filesystem.size && \
    mksquashfs /rootfs /image/casper/filesystem.squashfs \
    -noappend -no-duplicates -no-recovery \
    -wildcards \
    -comp zstd \
    -e "var/cache/apt/archives/*" \
    -e "root/*" \
    -e "root/.*" \
    -e "tmp/*" \
    -e "tmp/.*" \
    -e ".dockerenv" \
    -e "sys/*" \
    -e "sys/.*" \
    -e "proc/*" \
    -e "proc/.*" \
    -e "swapfile"

# fetch manifests
COPY --link --from=live-image /tmp/filesystem.manifest /image/casper/filesystem.manifest
COPY --link --from=live-image /tmp/filesystem.manifest-desktop /image/casper/filesystem.manifest-desktop

# prepare ISO image layout and build image
FROM base AS iso-builder
ARG DISKNAME
ARG TARGETARCH
ARG UBUNTU_VERSION
ARG OS_NAME
ENV LANG=C.UTF-8
ARG ROS_VERSION

RUN mkdir -p /image/casper /image/boot/grub /image/.disk

# EFI packages are needed for UEFI boot support (seems to be handled automatically by grub-mkrescue)
RUN apt-get update && apt-get install -y  \
    mtools \
    xorriso \
    grub-common \
    grub-efi \
    "grub-efi-${TARGETARCH}-signed" \
    shim-signed \
    apt-utils \
    && rm -rf /var/lib/apt/lists/*

# grub config to make ISO bootable
RUN cat <<EOF > /image/boot/grub/grub.cfg
    insmod all_video

    set default="0"
    set timeout=5

    menuentry "Try or install Ubuntu" {
        set gfxpayload=keep
        linux /casper/vmlinuz boot=casper maybe-ubiquity quiet splash ---
        initrd /casper/initrd
    }

    menuentry "Check disc for defects" {
        linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
        initrd /casper/initrd
    }

    grub_platform
    if [ "\$grub_platform" = "efi" ]; then
    menuentry 'UEFI Firmware Settings' {
        fwsetup
    }
    fi
EOF

# the following files are needed in order to make this ISO compatible
# with tools like usb-creator-gtk
RUN touch /image/.disk/base_installable && cat > /image/.disk/cd_type <<EOF
full_cd/single
EOF

RUN cat > /image/.disk/info <<EOF
    ${OS_NAME} based on Ubuntu ${UBUNTU_VERSION} Live Image - ${TARGETARCH}
EOF

# get all generated files from squashfs builder
COPY --link --from=squashfs-builder /image/ /image/

# create a dummy apt repo that contains nothing to make apt-setup happy
RUN mkdir -p /image/pool && cd /image/pool && apt-ftparchive packages . > Packages && apt-ftparchive release . > Release

# Generate md5sum.txt. Generate it two times, to get the own checksum right.
# hadolint ignore=DL3003,DL4006
RUN cd /image && find . -type f -print0 | xargs -0 md5sum > "/image/md5sum.txt"

# build iso
# hadolint ignore=DL3003
RUN mkdir -p /build/ && cd /image && grub-mkrescue \
    # reproducability stuff
    --set_all_file_dates 'Jan 1 00:00:00 UTC 1970' \
    --modification-date=1970010100000000 \
    # joliet is needed for windows to be able to read the iso
    -joliet -iso-level 3 \
    -o /build/image.iso \
    "."

FROM scratch AS iso-archive
ARG TARGETARCH
COPY --link --from=iso-builder /build /
COPY --link --from=iso-builder /image/casper/filesystem.manifest /
COPY --link --from=iso-builder /image/casper/filesystem.manifest-desktop /
