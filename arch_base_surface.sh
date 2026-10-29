#!/bin/bash
# Arch Linux minimal install script — Microsoft Surface (eMMC)
# - UEFI / GPT
# - eMMC storage (/dev/mmcblk0 -> partitions /dev/mmcblk0p1, p2, p3)
# - Btrfs with @ and @home subvolumes (zstd compression)
# - Intel CPU (intel-ucode)
# - Small swap partition (64 GB disk)
# - linux-surface kernel from the linux-surface pacman repo
#
# Run this from the Arch live ISO as root.
# Usage: bash install_arch_surface.sh

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DISK="/dev/mmcblk0"
PART="${DISK}p"            # eMMC and NVMe partitions get a "p" before the number
SWAP_MIB=4096              # 4 GiB swap; set to RAM size if you want hibernation
HOSTNAME="surface"
TIMEZONE="Europe/Copenhagen"
LOCALE="en_US.UTF-8"
KEYMAP="dk"
ROOT_PASSWORD="changeme"
INSTALL_SURFACE_KERNEL=1   # 1 = add linux-surface repo + kernel, 0 = skip
# ──────────────────────────────────────────────────────────────────────────────

# ─── Safety checks ────────────────────────────────────────────────────────────
if [ ! -b "$DISK" ]; then
    echo "!! $DISK not found. Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    exit 1
fi

if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "!! Not booted in UEFI mode. Aborting."
    exit 1
fi

echo "==> Target disk:"
lsblk "$DISK"
read -rp "ALL DATA ON $DISK WILL BE ERASED. Type YES to continue: " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "Aborted."; exit 1; }

# Unmount anything left over from a previous attempt
swapoff -a || true
umount -R /mnt 2>/dev/null || true

# eMMC has extra hardware partitions (mmcblk0boot0/boot1, mmcblk0rpmb).
# We only ever touch the main user area: /dev/mmcblk0.

echo "==> Wiping old signatures on $DISK"
wipefs -af "$DISK"

echo "==> Setting up partitions on $DISK"
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart primary linux-swap 513MiB $((513 + SWAP_MIB))MiB \
    mkpart primary btrfs $((513 + SWAP_MIB))MiB 100%

# Give udev a moment to create the partition device nodes
partprobe "$DISK" || true
udevadm settle

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
pacstrap -K /mnt \
    base \
    base-devel \
    linux \
    linux-firmware \
    intel-ucode \
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

if [ "${INSTALL_SURFACE_KERNEL}" = "1" ]; then
    echo "==> Adding linux-surface repository"
    curl -fsSL -o /tmp/surface.asc \
        https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
    pacman-key --add /tmp/surface.asc
    pacman-key --finger 56C464BAAC421453
    pacman-key --lsign-key 56C464BAAC421453
    cat <<REPO >> /etc/pacman.conf

[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
REPO
    pacman -Syu --noconfirm
    pacman -S --noconfirm --needed linux-surface linux-surface-headers iptsd
fi

# Only the old udev-based initramfs needs the 'resume' hook.
# The newer systemd-based one handles resume by itself.
if grep -q '^HOOKS=.*\budev\b' /etc/mkinitcpio.conf; then
    echo "==> Adding resume hook to mkinitcpio"
    sed -i 's/^HOOKS=(\(.*\)filesystems\(.*\))/HOOKS=(\1filesystems resume\2)/' /etc/mkinitcpio.conf
fi

echo "==> Generating initramfs"
mkinitcpio -P

echo "==> Adding resume parameter to GRUB"
SWAP_UUID=\$(blkid -s UUID -o value ${PART}2)
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 resume=UUID=\$SWAP_UUID\"|" /etc/default/grub

echo "==> Installing GRUB (UEFI)"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
# Fallback path, in case the Surface firmware ignores the GRUB NVRAM entry
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Setting root password"
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "==> Enabling sudo for wheel group"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> Cleaning up"
rm /chroot-setup.sh
EOF

chmod +x /mnt/chroot-setup.sh

echo "==> Entering chroot"
arch-chroot /mnt /bin/bash /chroot-setup.sh

echo ""
echo "==> Installation complete!"
echo "    Reboot and remove the live media."
echo "    Login as root and create your user:  useradd -m -G wheel <name> && passwd <name>"
echo "    In GRUB, pick the linux-surface entry under 'Advanced options' if it isn't the default."
