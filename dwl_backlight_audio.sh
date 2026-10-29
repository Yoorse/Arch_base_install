#!/bin/bash
# Add brightness and volume key bindings to dwl
# - Brightness: brightnessctl (XF86MonBrightnessUp/Down)
# - Volume: wpctl / PipeWire (XF86AudioRaiseVolume/LowerVolume/Mute)
#
# Safe to run more than once: it skips if the bindings are already there.
# Usage: bash dwl_media_keys.sh

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DWL_DIR="$HOME/builds/dwl"
STEP="5%"
# ──────────────────────────────────────────────────────────────────────────────

CONFIG="$DWL_DIR/config.h"

if [ ! -f "$CONFIG" ]; then
    echo "!! $CONFIG not found. Run minimal_dwl_setup.sh first."
    exit 1
fi

if grep -q "brupcmd" "$CONFIG"; then
    echo "==> Media keys already in config.h, nothing to do."
    exit 0
fi

echo "==> Installing brightnessctl (if missing)"
sudo pacman -S --needed --noconfirm brightnessctl

echo "==> Backing up config.h"
cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"

echo "==> Adding commands after termcmd"
sed -i "/^static const char \*termcmd\[\]/a\\
static const char *brupcmd[]    = { \"brightnessctl\", \"set\", \"+${STEP}\", NULL };\\
static const char *brdowncmd[]  = { \"brightnessctl\", \"set\", \"${STEP}-\", NULL };\\
static const char *volupcmd[]   = { \"wpctl\", \"set-volume\", \"-l\", \"1.0\", \"@DEFAULT_AUDIO_SINK@\", \"${STEP}+\", NULL };\\
static const char *voldowncmd[] = { \"wpctl\", \"set-volume\", \"@DEFAULT_AUDIO_SINK@\", \"${STEP}-\", NULL };\\
static const char *mutecmd[]    = { \"wpctl\", \"set-mute\", \"@DEFAULT_AUDIO_SINK@\", \"toggle\", NULL };" "$CONFIG"

echo "==> Adding key bindings to keys[]"
sed -i "/^static const Key keys\[\] = {/a\\
\t/* media keys */\\
\t{ 0, XKB_KEY_XF86MonBrightnessUp,   spawn, {.v = brupcmd} },\\
\t{ 0, XKB_KEY_XF86MonBrightnessDown, spawn, {.v = brdowncmd} },\\
\t{ 0, XKB_KEY_XF86AudioRaiseVolume,  spawn, {.v = volupcmd} },\\
\t{ 0, XKB_KEY_XF86AudioLowerVolume,  spawn, {.v = voldowncmd} },\\
\t{ 0, XKB_KEY_XF86AudioMute,         spawn, {.v = mutecmd} }," "$CONFIG"

# dwl's default launcher is bemenu, but the setup script installs wofi
if grep -q '"bemenu-run"' "$CONFIG" && command -v wofi &> /dev/null; then
    echo "==> Switching app launcher (Mod+p) from bemenu to wofi"
    sed -i 's/{ "bemenu-run", NULL }/{ "wofi", "--show", "drun", NULL }/' "$CONFIG"
fi

# Verify both edits landed
if ! grep -q "brupcmd\[\]" "$CONFIG" || ! grep -q "XKB_KEY_XF86MonBrightnessUp" "$CONFIG"; then
    echo "!! Could not patch config.h (anchor lines not found). Restore from the .bak file."
    exit 1
fi

echo "==> Making sure you are in the video group"
if ! id -nG "$USER" | grep -qw video; then
    sudo usermod -aG video "$USER"
    echo "    Added. Log out and back in for it to take effect."
fi

echo "==> Rebuilding dwl"
cd "$DWL_DIR"
make
sudo make install
cd ~

echo ""
echo "==> Done! Log out and back in (via ly) to use the new keys."
echo "    If a key does nothing, press Fn once to toggle media/F-keys,"
echo "    or run 'wev' to see what the key sends."
