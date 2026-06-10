#!/bin/bash
# Minimal dwl setup script
# - dwl built from source
# - Waybar as status bar
# - Foot as terminal emulator
# - ly as login manager
#
# Run this as your user after base Arch install.
# Usage: bash dwl-setup.sh

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DWL_DIR="$HOME/builds/dwl"
KEYMAP="dk"
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Installing dependencies"
sudo pacman -S --noconfirm \
    git \
    base-devel \
    wayland \
    wayland-protocols \
    wlroots \
    libxkbcommon \
    pixman \
    xcb-util-wm \
    foot \
    waybar \
    wofi \
    xdg-user-dirs \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    tllist \
    fcft

echo "==> Installing yay"
if ! command -v yay &> /dev/null; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd ~
fi

echo "==> Installing ly login manager"
yay -S --noconfirm ly
sudo systemctl enable ly

echo "==> Cloning dwl source"
mkdir -p "$HOME/builds"
git clone https://codeberg.org/dwl/dwl.git "$DWL_DIR"

echo "==> Creating dwl config"
cp "$DWL_DIR/config.def.h" "$DWL_DIR/config.h"

# Set Danish keyboard layout
sed -i 's/.rules = NULL/.rules = NULL/' "$DWL_DIR/config.h"
sed -i 's/.layout = NULL/.layout = "dk"/' "$DWL_DIR/config.h"

echo "==> Building and installing dwl"
cd "$DWL_DIR"
make
sudo make install

echo "==> Creating dwl session file"
sudo bash -c 'cat > /usr/share/wayland-sessions/dwl.desktop <<EOF
[Desktop Entry]
Name=dwl
Comment=dwm for Wayland
Exec=/home/'"$USER"'/start-dwl.sh
Type=Application
EOF'

echo "==> Creating dwl startup script"
cat > "$HOME/start-dwl.sh" <<EOF
#!/bin/bash
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=dwl
export XDG_CURRENT_DESKTOP=dwl
waybar &
exec dwl
EOF
chmod +x "$HOME/start-dwl.sh"

echo "==> Setting up waybar config"
mkdir -p "$HOME/.config/waybar"
cp /etc/xdg/waybar/config.jsonc "$HOME/.config/waybar/config.jsonc"
cp /etc/xdg/waybar/style.css "$HOME/.config/waybar/style.css"

echo "==> Setting up foot config"
mkdir -p "$HOME/.config/foot"
cp /etc/xdg/foot/foot.ini "$HOME/.config/foot/foot.ini" 2>/dev/null || cat > "$HOME/.config/foot/foot.ini" <<EOF
[main]
term=xterm-256color
font=monospace:size=11

[colors]
background=1d2021
foreground=ebdbb2
EOF

echo "==> Setting up XDG user directories"
xdg-user-dirs-update

echo ""
echo "==> dwl setup complete!"
echo "    Log out and log back in via ly to start dwl."
echo "    Your startup script is at: ~/start-dwl.sh"
echo "    dwl source is at: $DWL_DIR"
