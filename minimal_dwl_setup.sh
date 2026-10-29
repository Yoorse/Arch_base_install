#!/bin/bash
# Minimal dwl setup script
# - dwl built from source
# - Waybar as status bar
# - Foot as terminal emulator
# - ly as login manager
# - Optional Surface / Intel tweaks (GPU video acceleration, brightness, scaling)
#
# Run this as your user after base Arch install.
# Usage: bash minimal_dwl_setup.sh

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DWL_DIR="$HOME/builds/dwl"
KEYMAP="dk"
SCALE="1.5"        # Screen scaling: 1 for normal screens, 1.5–2 for HiDPI (Surface)
INTEL_GPU=1        # 1 = install Intel GPU / VA-API packages, 0 = skip
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Installing dependencies"
sudo pacman -S --needed --noconfirm \
    git \
    base-devel \
    go \
    wayland \
    wayland-protocols \
    libxkbcommon \
    pixman \
    xcb-util-wm \
    mesa \
    foot \
    waybar \
    wofi \
    xdg-user-dirs \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    tllist \
    fcft \
    ttf-dejavu \
    noto-fonts \
    ttf-font-awesome \
    brightnessctl

if [ "$INTEL_GPU" = "1" ]; then
    echo "==> Installing Intel GPU and video acceleration packages"
    sudo pacman -S --needed --noconfirm \
        intel-media-driver \
        libva-utils \
        vulkan-intel
fi

echo "==> Installing yay"
if ! command -v yay &> /dev/null; then
    rm -rf /tmp/yay
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd ~
fi

echo "==> Installing ly login manager"
yay -S --needed --noconfirm ly
sudo systemctl enable ly@tty2.service
sudo systemctl disable getty@tty2.service

echo "==> Getting dwl source"
mkdir -p "$HOME/builds"
if [ -d "$DWL_DIR/.git" ]; then
    git -C "$DWL_DIR" pull
else
    git clone https://codeberg.org/dwl/dwl.git "$DWL_DIR"
fi

# Arch ships wlroots as versioned packages (wlroots0.19, wlroots0.20, ...).
# Install whichever version this dwl checkout's Makefile asks for.
echo "==> Installing matching wlroots"
WLR_VER=$(grep -oP 'wlroots-\K[0-9]+\.[0-9]+' "$DWL_DIR/Makefile" | head -1 || true)
if [ -z "$WLR_VER" ]; then
    echo "!! Could not detect wlroots version from dwl Makefile, falling back to 0.20"
    WLR_VER="0.20"
fi
echo "    dwl wants wlroots $WLR_VER"
sudo pacman -S --needed --noconfirm "wlroots${WLR_VER}"

echo "==> Creating dwl config"
cp "$DWL_DIR/config.def.h" "$DWL_DIR/config.h"

# Keyboard layout: add a .layout line above the default ".options = NULL,"
# (the stock config has no .layout line to replace)
sed -i "s/^\(\s*\)\.options = NULL,/\1.layout = \"$KEYMAP\",\n\1.options = NULL,/" "$DWL_DIR/config.h"
if grep -q "\.layout = \"$KEYMAP\"" "$DWL_DIR/config.h"; then
    echo "    Keyboard layout set to $KEYMAP"
else
    echo "!! Could not set layout in config.h (XKB_DEFAULT_LAYOUT in start-dwl.sh still applies)"
fi

# Screen scaling: change the scale field of the default (NULL) monitor rule
sed -i -E "s/^(\s*\{ NULL,\s*[0-9.]+f?,\s*[0-9]+,\s*)[0-9.]+f?(,\s*&layouts)/\1${SCALE}\2/" "$DWL_DIR/config.h"
if grep -qE "\{ NULL,\s*[0-9.]+f?,\s*[0-9]+,\s*${SCALE}," "$DWL_DIR/config.h"; then
    echo "    Monitor scale set to $SCALE"
else
    echo "!! Could not set scale in config.h — edit monrules by hand"
fi

echo "==> Building and installing dwl"
cd "$DWL_DIR"
make clean
make
sudo make install
cd ~

echo "==> Creating dwl session file"
sudo mkdir -p /usr/share/wayland-sessions
sudo bash -c 'cat > /usr/share/wayland-sessions/dwl.desktop <<EOF
[Desktop Entry]
Name=dwl
Comment=dwm for Wayland
Exec=/home/'"$USER"'/start-dwl.sh
Type=Application
EOF'

echo "==> Creating dwl startup script"
# waybar is started via dwl's -s option, so it runs after the compositor is up
cat > "$HOME/start-dwl.sh" <<EOF
#!/bin/bash
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=dwl
export XDG_CURRENT_DESKTOP=dwl
export XKB_DEFAULT_LAYOUT=$KEYMAP
exec dwl -s waybar
EOF
chmod +x "$HOME/start-dwl.sh"

echo "==> Setting up waybar config"
mkdir -p "$HOME/.config/waybar"
cat > "$HOME/.config/waybar/config.jsonc" <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": [],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network", "backlight", "battery"],

    "clock": {
        "format": "{:%H:%M  %a %d %b}",
        "tooltip-format": "<tt>{calendar}</tt>"
    },
    "pulseaudio": {
        "format": "VOL {volume}%",
        "format-muted": "VOL muted",
        "on-click": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    },
    "network": {
        "format-wifi": "WIFI {essid}",
        "format-ethernet": "LAN",
        "format-disconnected": "offline"
    },
    "backlight": {
        "format": "BRI {percent}%",
        "on-scroll-up": "brightnessctl set +5%",
        "on-scroll-down": "brightnessctl set 5%-"
    },
    "battery": {
        "format": "BAT {capacity}%",
        "format-charging": "BAT {capacity}% +"
    }
}
EOF
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

echo "==> Adding user to video group (for brightness control)"
sudo usermod -aG video "$USER"

echo "==> Setting up XDG user directories"
xdg-user-dirs-update

echo ""
echo "==> dwl setup complete!"
echo "    Reboot, then log in via ly to start dwl."
echo "    Your startup script is at: ~/start-dwl.sh"
echo "    dwl source is at: $DWL_DIR"
echo "    To change scaling later: edit monrules in $DWL_DIR/config.h, then make && sudo make install"
