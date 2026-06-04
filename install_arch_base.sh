#!/bin/bash
# Arch Linux minimal install script
# - Legacy BIOS / MBR
# - Btrfs with @ and @home subvolumes (no compression)
# - User: toor (sudo, network, audio)
#
# Run this from the Arch live ISO as root.
# Usage: bash arch-install.sh

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DISK="/dev/sda"
HOSTNAME="archlinux"
TIMEZONE="Europe/Copenhagen"
LOCALE="en_US.UTF-8"
KEYMAP="dk"
USERNAME="username"
USER_PASSWORD="changeme"
ROOT_PASSWORD="changeme"
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Setting up partitions on $DISK"
parted -s "$DISK" \
    mklabel msdos \
    mkpart primary btrfs 1MiB 100% \
    set 1 boot on

# Leave space at end for swap inside the OS via a swapfile, or add a swap partition:
# If you want a dedicated swap partition, adjust the above and uncomment below:
#
# parted -s "$DISK" \
#     mklabel msdos \
#     mkpart primary btrfs 1MiB 90% \
#     mkpart primary linux-swap 90% 100% \
#     set 1 boot on
# mkswap "${DISK}2"

echo "==> Formatting ${DISK}1 as Btrfs"
mkfs.btrfs -f "${DISK}1"

echo "==> Mounting and creating subvolumes"
mount "${DISK}1" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home

umount /mnt

echo "==> Mounting subvolumes"
mount -o subvol=@ "${DISK}1" /mnt
mkdir -p /mnt/home
mount -o subvol=@home "${DISK}1" /mnt/home

echo "==> Installing base system"
pacstrap /mnt \
    base \
    base-devel \
    linux \
    linux-firmware \
    grub \
    btrfs-progs \
    networkmanager \
    sudo \
    vim

echo "==> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Entering chroot"
arch-chroot /mnt /bin/bash <<CHROOT

set -euo pipefail

echo "==> Setting timezone"
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

echo "==> Setting locale"
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "==> Setting hostname"
echo "${HOSTNAME}" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

echo "==> Enabling NetworkManager"
systemctl enable NetworkManager

echo "==> Installing GRUB (legacy BIOS)"
grub-install --target=i386-pc ${DISK}
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Creating user: ${USERNAME}"
useradd -m -G sudo,network,audio "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "==> Enabling sudo for wheel/sudo group"
sed -i 's/^# %sudo/%sudo/' /etc/sudoers

CHROOT

echo ""
echo "==> Installation complete!"
echo "    Reboot and remove the live media."
echo "    Login as: ${USERNAME}"
