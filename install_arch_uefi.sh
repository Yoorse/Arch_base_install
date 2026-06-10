#!/bin/bash
# Arch Linux minimal install script
# - UEFI / GPT
# - Btrfs with @ and @home subvolumes (zstd compression)
# - AMD Ryzen CPU
# - Swap partition
#
# Run this from the Arch live ISO as root.
# Usage: bash arch-install-uefi.sh

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DISK="/dev/nvme0n1"
PART="${DISK}p"
SWAP_SIZE="16GiB"
HOSTNAME="archlinux"
TIMEZONE="Europe/Copenhagen"
LOCALE="en_US.UTF-8"
KEYMAP="dk"
ROOT_PASSWORD="changeme"
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Setting up partitions on $DISK"
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 512MiB \
    set 1 esp on \
    mkpart primary linux-swap 512MiB $((512 + 16384))MiB \
    mkpart primary btrfs $((512 + 16384))MiB 100%

echo "==> Formatting partitions"
mkfs.fat -F32 "${PART}1"
mkswap "${PART}2"
mkfs.btrfs -f "${PART}3"

echo "==> Creating Btrfs subvolumes"
mount "${PART}3" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home

umount /mnt

echo "==> Mounting subvolumes"
mount -o subvol=@,defaults,noatime,compress=zstd "${PART}3" /mnt
mkdir -p /mnt/home
mount -o subvol=@home,defaults,noatime,compress=zstd "${PART}3" /mnt/home
mkdir -p /mnt/boot/efi
mount "${PART}1" /mnt/boot/efi
swapon "${PART}2"

echo "==> Installing base system"
pacstrap /mnt \
    base \
    base-devel \
    linux \
    linux-firmware \
    amd-ucode \
    grub \
    efibootmgr \
    btrfs-progs \
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

echo "==> Adding resume hook to mkinitcpio"
sed -i 's/^HOOKS=(\(.*\)filesystems\(.*\))/HOOKS=(\1filesystems resume\2)/' /etc/mkinitcpio.conf

echo "==> Generating initramfs"
mkinitcpio -P

echo "==> Adding resume parameter to GRUB"
SWAP_UUID=\$(blkid -s UUID -o value ${PART}2)
sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet resume=UUID=\$SWAP_UUID\"|" /etc/default/grub

echo "==> Installing GRUB (UEFI)"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Verifying GRUB modules"
ls /boot/grub/x86_64-efi/

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
