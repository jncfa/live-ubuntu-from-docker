
ARG UBUNTU_VERSION=noble
ARG ROS_VERSION=jazzy
ARG TARGETARCH
ARG DISKNAME="Install RUbuntu"

FROM ubuntu:latest AS base
FROM base AS init-rootfs-cacher-base

ARG UBUNTU_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    debootstrap \
    ubuntu-keyring \
    && rm -rf /var/lib/apt/lists/*

FROM --platform=linux/amd64 init-rootfs-cacher-base AS init-rootfs-cacher-amd64
ARG UBUNTU_VERSION
ENV UBUNTU_MIRROR=http://archive.ubuntu.com/ubuntu/
RUN debootstrap --merged-usr --arch="amd64" --variant=minbase --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg "${UBUNTU_VERSION:?}" /rootfs "${UBUNTU_MIRROR:?}"

FROM --platform=linux/arm64 init-rootfs-cacher-base AS init-rootfs-cacher-arm64
ARG UBUNTU_VERSION
ENV UBUNTU_MIRROR=http://ports.ubuntu.com/ubuntu-ports/
RUN debootstrap --merged-usr --arch="arm64" --variant=minbase --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg "${UBUNTU_VERSION:?}" /rootfs "${UBUNTU_MIRROR:?}"

# unify stage
FROM init-rootfs-cacher-${TARGETARCH} AS init-rootfs-cacher
FROM scratch AS lite-image

ARG TARGETARCH
ARG UBUNTU_VERSION
ARG ROS_VERSION

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true
ENV LANG=C.UTF-8

COPY --link --from=init-rootfs-cacher /rootfs /

# base image setup (TODO: list references for this)
RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    dbus systemd-sysv \ 
    && rm -rf /var/lib/apt/lists/*

RUN dbus-uuidgen >/etc/machine-id && ln -fs /etc/machine-id /var/lib/dbus/machine-id && \
    dpkg-divert --local --rename --add /sbin/initctl && ln -s /bin/true /sbin/initctl

# install common programs
RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
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
    conntrack \
    lsb-release \
    iputils-ping \
    ca-certificates \
    software-properties-common \
    ubuntu-standard \
    ubuntu-desktop \
    ubuntu-keyring \
    binutils \
    && rm -rf /var/lib/apt/lists/*

# Install timezone
RUN ln -fs /usr/share/zoneinfo/UTC /etc/localtime \
    && apt-get update \
    && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*

# Install ROS2
#RUN sudo add-apt-repository universe \
#    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg \
#    && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_VERSION} main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null \
#    && apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
#    ros-${ROS_VERSION}-ros-base \
#    python3-argcomplete \
#    && rm -rf /var/lib/apt/lists/*

# clean-up
RUN truncate -s 0 /etc/machine-id
RUN rm /sbin/initctl && dpkg-divert --rename --remove /sbin/initctl

FROM lite-image AS final-image
ARG TARGETARCH
ARG UBUNTU_VERSION

# add diversion back
RUN dpkg-divert --local --rename --add /sbin/initctl && ln -s /bin/true /sbin/initctl

# Install language
RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    locales \
    && locale-gen C.UTF-8 \
    && update-locale LC_ALL=C.UTF-8 LANG=C.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# adds the rest of the system that doesnt make sense in a container environment
RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    systemd \
    systemd-resolved \
    systemd-timesyncd \
    systemd-oomd \
    polkitd \
    cryptsetup \
    debianutils \
    dosfstools \
    e2fsprogs \
    fdisk \
    gdisk \
    gettext \
    iproute2 \
    iptables \
    lvm2 \
    nbd-client \
    nfs-common \
    open-iscsi \
    open-vm-tools \
    openssh-server \
    parted \
    efibootmgr \
    plymouth \
    plymouth-theme-ubuntu-gnome-logo \
    && rm -rf /var/lib/apt/lists/*


RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    initramfs-tools \
    kmod \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    linux-lowlatency \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    ubiquity \
    ubiquity-casper \
    ubiquity-frontend-gtk \
    ubiquity-slideshow-ubuntu \
    ubiquity-ubuntu-artwork \    
    casper \
    discover \
    discover-data \
    grub-common \
    grub-efi-${TARGETARCH}-signed \
    laptop-detect \
    locales \
    mtools \
    net-tools \
    network-manager \
    os-prober \
    shim-signed \
    user-setup \
    wireless-tools \
    && rm -rf /var/lib/apt/lists/*

# remove diversion
RUN rm /sbin/initctl && dpkg-divert --rename --remove /sbin/initctl
RUN kernel=$(ls /lib/modules | head -n1) && depmod -a "${kernel}" && update-initramfs -u -v -k "${kernel}"

RUN dpkg-query -W --showformat='${Package} ${Version}\n' > /tmp/filesystem.manifest

# prepare the common image layout
FROM base AS iso-builder-base
ARG DISKNAME
ARG TARGETARCH
ARG UBUNTU_VERSION
ENV PACKAGES_TO_REMOVE="ubiquity casper user-setup discover discover-data os-prober laptop-detect"

RUN mkdir -p /image/casper && mkdir -p /image/boot/grub && mkdir -p /image/install

RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    xorriso \
    squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

RUN cat <<EOF > /image/boot/grub/grub.cfg 
    search --set=root --file /ubuntu
    
    insmod all_video
    
    set default="0"
    set timeout=30
    
    menuentry "Try Ubuntu FS without installing" {
        linux /casper/vmlinuz boot=casper nopersistent toram quiet splash ---
        initrd /casper/initrd
    }
    
    menuentry "Install Ubuntu FS" {
        linux /casper/vmlinuz boot=casper only-ubiquity quiet splash ---
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

RUN cat <<EOF > /image/README.diskdefines
#define DISKNAME  ${DISKNAME}
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  ${TARGETARCH}
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF

RUN --mount=type=bind,from=final-image,source=/,dst=/rootfs,ro \
    cp /rootfs/boot/vmlinuz-*-*-* /image/casper/vmlinuz && \
    cp /rootfs/boot/initrd.img-*-*-* /image/casper/initrd

# make squashfs and get fs size
RUN --mount=type=bind,from=final-image,source=/,dst=/rootfs,ro \
    mksquashfs /rootfs /image/casper/filesystem.squashfs \
    -noappend -no-duplicates -no-recovery \
    -wildcards \
    -comp xz -b 1M -Xdict-size 100% \
    -e "var/cache/apt/archives/*" \
    -e "root/*" \
    -e "root/.*" \
    -e "tmp/*" \
    -e "tmp/.*" \
    -e "swapfile" && \ 
    printf $(du -sx --block-size=1 /rootfs | cut -f1) | tee /image/casper/filesystem.size

# create manifests for casper
RUN --mount=type=bind,from=final-image,source=/,dst=/rootfs,ro \
    cp /rootfs/tmp/filesystem.manifest /image/casper/filesystem.manifest && \
    cp /image/casper/filesystem.manifest /image/casper/filesystem.manifest-desktop && \
    for i in ${PACKAGES_TO_REMOVE}; do \
    sed -i "/${i}/d" /image/casper/filesystem.manifest-desktop; \
    done 

# Generate md5sum.txt. Generate it two times, to get the own checksum right.
RUN find /image -type f -print0 | xargs -0 md5sum > "/image/md5sum.txt"

FROM iso-builder-base AS iso-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends \
    xorriso \
    mtools \
    grub-common \
    grub-efi \
    grub-efi-${TARGETARCH}-signed \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /build/ && cd /image && grub-mkrescue -v --set_all_file_dates 'Jan 1 00:00:00 UTC 1970' \
    --modification-date=1970010100000000 --fonts="ter-u16n" \
    --locales="" --themes="" -o /build/image.iso \
    -volid "RUBUNTU" -J -graft-points \
    "." 

FROM scratch AS iso-archive
ARG TARGETARCH
COPY --link --from=iso-builder /build /