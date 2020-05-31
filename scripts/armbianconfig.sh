#!/bin/bash

PATCH=$(cat /patch)

# This script will be run in chroot under qemu.

DEVICE=$(cat /etc/os-release | grep ^VOLUMIO_HARDWARE | tr -d 'VOLUMIO_HARDWARE="')
echo "device=${DEVICE}"

echo "Initializing.."
. init.sh

echo "Creating \"fstab\""
echo "# ${DEVICE} fstab" > /etc/fstab
echo "" >> /etc/fstab
echo "proc            /proc           proc    defaults        0       0
UUID=${UUID_BOOT} /boot           vfat    defaults,utf8,user,rw,umask=111,dmask=000        0       1
tmpfs   /var/log                tmpfs   size=20M,nodev,uid=1000,mode=0777,gid=4, 0 0
tmpfs   /var/spool/cups         tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /var/spool/cups/tmp     tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /tmp                    tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /dev/shm                tmpfs   defaults,nosuid,noexec,nodev        0 0
" > /etc/fstab

echo "Alsa Card Ordering"
echo "
# USB DACs will have device number 5 in whole Volumio device range
options snd-usb-audio index=5" >> /etc/modprobe.d/alsa-base.conf


if [ "$DEVICE" = "nanopineo2" ] || [ "$DEVICE" = "nanopineoplus2" ]; then
	echo "Fixing armv8 deprecated instruction emulation with armv7 rootfs"
	echo "abi.cp15_barrier=2" >> /etc/sysctl.conf
fi

apt-get update
apt-get -y install u-boot-tools liblircclient0 lirc aptitude bc

echo "Installing additonal packages"
apt-get install -qq -y dialog debconf-utils lsb-release aptitude

echo "Adding custom modules overlayfs, squashfs and nls_cp437"
echo "overlay" >> /etc/initramfs-tools/modules
echo "overlayfs" >> /etc/initramfs-tools/modules
echo "squashfs" >> /etc/initramfs-tools/modules
echo "nls_cp437" >> /etc/initramfs-tools/modules
echo "fuse" >> /etc/initramfs-tools/modules

echo "Copying volumio initramfs updater"
cd /root/
mv volumio-init-updater /usr/local/sbin

#On The Fly Patch
if [ "$PATCH" = "volumio" ]; then
echo "No Patch To Apply"
else
echo "Applying Patch ${PATCH}"
PATCHPATH=/${PATCH}
cd $PATCHPATH
#Check the existence of patch script
if [ -f "patch.sh" ]; then
sh patch.sh
else
echo "Cannot Find Patch File, aborting"
fi
if [ -f "install.sh" ]; then
sh install.sh
fi
cd /
rm -rf ${PATCH}
fi
rm /patch

echo "Installing winbind here, since it freezes networking"
apt-get update
apt-get install -y winbind libnss-winbind


echo "Install device tree compiler with overlays support"
wget -P /tmp http://ftp.debian.org/debian/pool/main/d/device-tree-compiler/device-tree-compiler_1.4.7-3_armhf.deb
dpkg -i /tmp/device-tree-compiler_1.4.7-3_armhf.deb
rm /tmp/device-tree-compiler_1.4.7-3_armhf.deb


if [ "$DEVICE" = "cubietruck" ]; then
echo "Install ACPI and power button support"
apt-get install -y acpid
echo "event=button/power
action=/etc/acpi/powerbtn.sh %e" >>/etc/acpi/events/power

echo "exec poweroff" >>/etc/acpi/powerbtn.sh
chmod +x /etc/acpi/powerbtn.sh

echo "exec acpid -c /etc/acpi/events -s /var/run/acpid.socket" >>/etc/init/acpid.conf
fi


#echo "adding gpio group and udev rules"
#groupadd -f --system gpio
#usermod -aG gpio volumio
#touch /etc/udev/rules.d/99-gpio.rules
#echo "SUBSYSTEM==\"gpio\", ACTION==\"add\", RUN=\"/bin/sh -c '
#        chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio;\
#        chown -R root:gpio /sys$DEVPATH && chmod -R 770 /sys$DEVPATH\
#'\"" > /etc/udev/rules.d/99-gpio.rules

echo "Cleaning APT Cache and remove policy file"
rm -f /var/lib/apt/lists/*archive*
apt-get clean
rm /usr/sbin/policy-rc.d

#First Boot operations
echo "Signalling the init script to re-size the volumio data partition"
touch /boot/resize-volumio-datapart

echo "Creating initramfs 'volumio.initrd'"
mkinitramfs-custom.sh -o /tmp/initramfs-tmp

if [ "$DEVICE" = "nanopineo2" ] || [ "$DEVICE" = "nanopineoplus2" ]; then
echo "Creating uInitrd from 'volumio.initrd' for arm64"
mkimage -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d /boot/volumio.initrd /boot/uInitrd
else
echo "Creating uInitrd from 'volumio.initrd' for arm"
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d /boot/volumio.initrd /boot/uInitrd
fi

mkimage -A arm -T script -C none -d /boot/boot.cmd /boot/boot.scr
echo "Cleaning up"
rm /boot/volumio.initrd
