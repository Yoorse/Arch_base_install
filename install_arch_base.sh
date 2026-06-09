#!/bin/bash
# Arch Linux minimal install script
# - Legacy BIOS / MBR
# - EXT4 root partition
# - 8GB swap on first partition
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
ROOT_PASSWORD="changeme"
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Setting up partitions on $DISK"
parted -s "$DISK" \
    mklabel msdos \
    mkpart primary linux-swap 1MiB 8GiB \
    mkpart primary ext4 8GiB 100% \
    set 2 boot on

echo "==> Formatting partitions"
mkswap "${DISK}1"
mkfs.ext4 -F "${DISK}2"

echo "==> Mounting partitions"
mount "${DISK}2" /mnt
swapon "${DISK}1"

echo "==> Installing base system"
pacstrap /mnt \
    base \
    base-devel \
    linux \
    linux-firmware \
    grub \
    networkmanager \
    sudo \
    vim

echo "==> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Writing chroot script"
cat > /mnt/chroot-setup.sh <<EOF
#!/bin/bash
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
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo "==> Enabling NetworkManager"
systemctl enable NetworkManager

echo "==> Generating initramfs"
mkinitcpio -P

echo "==> Installing GRUB (legacy BIOS)"
grub-install --target=i386-pc --recheck --no-floppy ${DISK}
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Verifying GRUB modules"
ls /boot/grub/i386-pc/

echo "==> Setting root password"
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "==> Enabling sudo for sudo group"
sed -i 's/^# %sudo/%sudo/' /etc/sudoers

echo "==> Cleaning up"
rm /chroot-setup.sh
EOF

chmod +x /mnt/chroot-setup.sh

echo "==> Entering chroot"
arch-chroot /mnt /bin/bash /chroot-setup.sh

echo ""
echo "==> Installation complete!"
echo "    Reboot and remove the live media."
echo "    Login as root and create your user."
