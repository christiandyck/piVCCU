#!/bin/bash

CCU_VERSION=2.29.23
CCU_DOWNLOAD_SPLASH_URL="http://www.eq-3.de/service/downloads.html?id=268"
CCU_DOWNLOAD_URL="http://www.eq-3.de/Downloads/Software/HM-CCU2-Firmware_Updates/HM-CCU-$CCU_VERSION/HM-CCU-$CCU_VERSION.tar.gz"

PKG_BUILD=19

CURRENT_DIR=$(pwd)
WORK_DIR=$(mktemp -d)

PKG_VERSION=$CCU_VERSION-$PKG_BUILD

TARGET_DIR=$WORK_DIR/pivccu-$PKG_VERSION
CNT_ROOT=$TARGET_DIR/var/lib/piVCCU
CNT_ROOTFS=$CNT_ROOT/rootfs

cd $WORK_DIR

# download firmware image
wget -O /dev/null --save-cookies=cookies.txt --keep-session-cookies $CCU_DOWNLOAD_SPLASH_URL
wget -O ccu.tar.gz --load-cookies=cookies.txt --referer=$CCU_DOWNLOAD_SPLASH_URL $CCU_DOWNLOAD_URL

tar xf ccu.tar.gz

mkdir -p $CNT_ROOT

ubireader_extract_files -k -o rootfs rootfs.ubi
mv rootfs/*/root $CNT_ROOTFS

cd $CNT_ROOTFS

patch -l -p1 < $CURRENT_DIR/pivccu/firmware.patch
sed -i "s/@@@pivccu_version@@@/$PKG_VERSION/g" $CNT_ROOTFS/www/config/cp_maintenance.cgi
wget -q -O $CNT_ROOTFS/firmware/dualcopro_si1002_update_blhm.eq3 https://raw.githubusercontent.com/eq-3/occu/eea64da6f8ad5b2016df4fceb671439dc2643e35/firmware/HM-MOD-UART/dualcopro_si1002_update_blhm.eq3

rm -rf $CNT_ROOTFS/dev/*

mkdir $CNT_ROOTFS/dev/pts
mkdir $CNT_ROOTFS/dev/shm
mkdir $CNT_ROOTFS/dev/net

mknod -m 666 $CNT_ROOTFS/dev/console c 136 1
mknod -m 666 $CNT_ROOTFS/dev/null c 1 3
mknod -m 666 $CNT_ROOTFS/dev/random c 1 8
mknod -m 666 $CNT_ROOTFS/dev/tty c 5 0
mknod -m 666 $CNT_ROOTFS/dev/urandom c 1 9
mknod -m 666 $CNT_ROOTFS/dev/zero c 1 5
mknod -m 666 $CNT_ROOTFS/dev/net/tun c 10 200

mkdir -p $CNT_ROOTFS/media/sd-mmcblk0

mkdir -p $CNT_ROOTFS/etc/piVCCU
cp -p $CURRENT_DIR/pivccu/container/* $CNT_ROOTFS/etc/piVCCU

mkdir -p $CNT_ROOT/userfs
mkdir -p $CNT_ROOT/localfs
mkdir -p $CNT_ROOT/sdcardfs
touch $CNT_ROOT/sdcardfs/.initialised

mkdir -p $TARGET_DIR/etc/piVCCU
cp -p $CURRENT_DIR/pivccu/host/lxc.config $TARGET_DIR/etc/piVCCU

cp -p $CURRENT_DIR/pivccu/host/*.sh $CNT_ROOT

mkdir -p $TARGET_DIR/lib/systemd/system/
cp -p $CURRENT_DIR/pivccu/host/pivccu.service $TARGET_DIR/lib/systemd/system/

mkdir -p $TARGET_DIR/DEBIAN

cat <<EOT >> $TARGET_DIR/DEBIAN/control
Package: pivccu
Version: $PKG_VERSION
Architecture: armhf
Maintainer: Alexander Reinert <alex@areinert.de>
Depends: pivccu-kernel-modules
Pre-Depends: lxc, bridge-utils, systemd
Section: misc
Priority: extra
Homepage: https://github.com/alexreinert/piVCCU
Description: piVCCU - Homematic CCU LXC container
  This package contains piVCCU - a Homematic CCU LXC container
EOT

echo /etc/piVCCU/lxc.config >> $TARGET_DIR/DEBIAN/conffiles
echo /lib/systemd/system/pivccu.service >> $TARGET_DIR/DEBIAN/conffiles

cat <<EOT >> $TARGET_DIR/DEBIAN/postinst
#!/bin/sh
systemctl enable pivccu.service
systemctl start pivccu.service || true

if [ ! -e /usr/sbin/pivccu-attach ]; then
  ln -s /var/lib/piVCCU/pivccu-attach.sh /usr/sbin/pivccu-attach
fi
if [ ! -e /usr/sbin/pivccu-info ]; then
  ln -s /var/lib/piVCCU/pivccu-info.sh /usr/sbin/pivccu-info
fi
if [ ! -e /usr/sbin/pivccu-device ]; then
  ln -s /var/lib/piVCCU/pivccu-device.sh /usr/sbin/pivccu-device
fi

BRIDGE=\`brctl show | sed -n 2p | awk '{print \$1}'\`
if [ -z "\$BRIDGE" ]; then
  echo "WARNING: No network bridge could be detected."
fi

sed -i 's/alexreinert.github.io/www.pivccu.de/g' /etc/apt/sources.list
for file in \`find /etc/apt/sources.list.d/*.list -type f 2>/dev/null\`; do
  sed -i 's/alexreinert.github.io/www.pivccu.de/g' \$file
done
EOT

chmod +x $TARGET_DIR/DEBIAN/postinst

cat <<EOT >> $TARGET_DIR/DEBIAN/prerm
#!/bin/sh
systemctl stop pivccu.service
systemctl disable pivccu.service

rm -f /usr/sbin/pivccu-attach
rm -f /usr/sbin/pivccu-info
rm -f /usr/sbin/pivccu-device
EOT

chmod +x $TARGET_DIR/DEBIAN/prerm

cd $WORK_DIR

dpkg-deb --build pivccu-$PKG_VERSION

cp pivccu-*.deb $CURRENT_DIR

