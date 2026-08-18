#!/usr/bin/env bash
# ============================================================================
#  Linux Mint (Cinnamon) post-install setup script
#  Target: Linux Mint 22.3 "Zena" (Ubuntu 24.04 LTS base)
#  No Flatpaks, no Snaps.
#  Idempotent - safe to re-run on an already-configured system.
# ============================================================================
set -euo pipefail

# ---- Config (EDIT THESE) ----------------------------------------------------
MYBASH_REPO="${MYBASH_REPO:-git@github.com:YOUR_USER/mybash.git}"
MYBASH_DIR="${MYBASH_DIR:-$HOME/.mybash}"

# ANSI helpers
bold=$'\e[1m'; green=$'\e[32m'; yellow=$'\e[33m'; reset=$'\e[0m'
say()  { printf "${bold}${green}[setup]${reset} %s\n" "$*"; }
warn() { printf "${bold}${yellow}[warn]${reset} %s\n" "$*"; }

# ---- --fix-wine: just clean up the WineHQ repo/key, then exit -----------------
# Useful when `apt update` reports NO_PUBKEY / "public key is not available" for winehq.
if [[ "${1:-}" == "--fix-wine" ]]; then
  say "Fixing WineHQ: removing all stale Wine repo + key state, then re-adding."
  sudo rm -f \
    /etc/apt/sources.list.d/winehq.list \
    /etc/apt/sources.list.d/winehq-*.list \
    /etc/apt/sources.list.d/winehq-*.sources \
    /etc/apt/keyrings/winehq.gpg \
    /usr/share/keyrings/winehq-archive.gpg \
    /usr/share/keyrings/winehq-archive.key \
    /etc/apt/trusted.gpg.d/winehq.gpg \
    /etc/apt/trusted.gpg.d/winehq-archive.gpg 2>/dev/null
  if command -v apt-key >/dev/null 2>&1; then
    sudo apt-key del "76F1A20FF987672F" 2>/dev/null || true
  fi
  sudo apt-get clean
  sudo rm -rf /var/lib/apt/lists/*
  sudo mkdir -pm755 /etc/apt/keyrings 2>/dev/null || true
  wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
    | gpg --dearmor | sudo tee /etc/apt/keyrings/winehq.gpg >/dev/null
  if ! sudo gpg --no-default-keyring --keyring=/etc/apt/keyrings/winehq.gpg --list-keys >/dev/null 2>&1; then
    echo "ERROR: WineHQ key failed to download. Check network and retry."
    exit 1
  fi
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/ubuntu/ noble main" \
    | sudo tee /etc/apt/sources.list.d/winehq.list >/dev/null
  echo "WineHQ repo cleaned and re-added. Running apt update..."
  sudo apt-get --allow-releaseinfo-change update
  echo "Done. WineHQ should be fixed now."
  exit 0
fi

# ------------------------------------------------------------------------------
say "Step 0: Update package lists & upgrade"
sudo apt update -y
sudo apt full-upgrade -y

# ---- 1. External apt repositories -------------------------------------------
say "Step 1: Set up external repositories"

# Google Chrome
if ! dpkg -s google-chrome-stable >/dev/null 2>&1; then
  say "Adding Google Chrome..."
  wget -q -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo apt install -y /tmp/google-chrome.deb || sudo apt-get -f install -y
fi

# VS Code
if ! dpkg -s code >/dev/null 2>&1; then
  say "Adding VS Code..."
  sudo mkdir -pm755 /etc/apt/keyrings 2>/dev/null || true
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg 2>/dev/null || \
  wget -qO- https://packages.microsoft.com/keys/msopentech.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  sudo apt update -y
  sudo apt install -y code
fi

# Microsoft Core Fonts (installed before WineHQ; accepts EULA non-interactively)
if ! dpkg -s ttf-mscorefonts-installer >/dev/null 2>&1; then
  say "Installing Microsoft Core Fonts..."
  echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | sudo debconf-set-selections
  sudo DEBIAN_FRONTEND=noninteractive apt install -y ttf-mscorefonts-installer || warn "Could not install ttf-mscorefonts-installer"
fi

# WineHQ
# Self-cleaning: a prior or partial run may have left wine repo entries or keys
# under several different paths. Remove ALL known variants so no stale key can
# survive, then (re)add freshly.
#
# Step A: drop every known wine source + key path.
sudo rm -f \
  /etc/apt/sources.list.d/winehq.list \
  /etc/apt/sources.list.d/winehq-*.list \
  /etc/apt/sources.list.d/winehq-*.sources \
  /etc/apt/keyrings/winehq.gpg \
  /usr/share/keyrings/winehq-archive.gpg \
  /usr/share/keyrings/winehq-archive.key \
  /etc/apt/trusted.gpg.d/winehq.gpg \
  /etc/apt/trusted.gpg.d/winehq-archive.gpg 2>/dev/null
# Drop the old WineHQ key from the legacy trusted keyring if a manual install put it there.
if command -v apt-key >/dev/null 2>&1; then
  sudo apt-key del "76F1A20FF987672F" 2>/dev/null || true
fi
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get --allow-releaseinfo-change update 2>/dev/null || sudo apt update -y
#
# Step B: (re)add the WineHQ repo with a freshly dearmored key.
sudo mkdir -pm755 /etc/apt/keyrings 2>/dev/null || true
# winehq.key is ASCII-armored; apt needs a dearmored binary keyring for signed-by
# (wget ships by default on Mint; curl may not be present yet at this step)
wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/winehq.gpg >/dev/null
# Guard: if the key didn't actually download, the keyring will be empty and apt
# will complain - fail loudly rather than shipping a broken repo.
if ! sudo gpg --no-default-keyring --keyring=/etc/apt/keyrings/winehq.gpg --list-keys >/dev/null 2>&1; then
  echo "ERROR: WineHQ key download failed / produced no key. Check network, then re-run."
  exit 1
fi
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/ubuntu/ noble main" \
  | sudo tee /etc/apt/sources.list.d/winehq.list >/dev/null
say "WineHQ: cleared all stale wine state and re-added cleanly."

# abraunegg OneDrive client (official OpenSuSE Build Service repo)
# NOTE: the old launchpad PPA (ppa:abraunegg/onedrive) no longer exists - the
# client is now published via the OBS repo below.
if ! dpkg -s onedrive >/dev/null 2>&1; then
  say "Adding OneDrive OBS repository..."
  wget -qO - https://download.opensuse.org/repositories/home:/npreining:/debian-ubuntu-onedrive/xUbuntu_24.04/Release.key \
    | gpg --dearmor | sudo tee /usr/share/keyrings/obs-onedrive.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/obs-onedrive.gpg] https://download.opensuse.org/repositories/home:/npreining:/debian-ubuntu-onedrive/xUbuntu_24.04/ ./" \
    | sudo tee /etc/apt/sources.list.d/onedrive.list >/dev/null
fi

sudo apt update -y

# ---- 2. Bulk apt install -----------------------------------------------------
say "Step 2: Installing repository packages"
# NOTE on updating:
#  - Onedrive *client* (adds the official OpenSUSE Build Service repo) & Dropbox
#    (official repo) stay current via plain 'sudo apt update && sudo apt upgrade'.
#  - OneDriveGUI (the AppImage wrapper) is versioned separately - update by
#    grabbing a new AppImage from https://github.com/bpozdena/OneDriveGUI/releases when new.
APT_CORE="git mc nano micro tmux btop bat ripgrep jq direnv net-tools ipcalc"
APT_CORE+=" fortune-mod lolcat cowsay arj rclone eza"
# fastfetch is NOT in the Ubuntu 24.04 (noble) repos that Mint 22.x uses, so it's
# installed separately via its official PPA further down (not via this apt list).
APT_CORE+=" p7zip p7zip-full filezilla remmina terminator unzip wget curl"
APT_CORE+=" ca-certificates gnupg lsb-release libfuse2t64 onedrive"
# Icon + theme packs (Mint-X-Yellow icons, Mint-Y-Dark-Teal apps, etc.)
# Note: Mint 22.x replaces mint-y-icons-legacy with mint-l-icons
APT_CORE+=" mint-x-icons mint-y-icons mint-l-icons mint-cursor-themes mint-themes"

# Install all packages in a loop so a single missing/renamed package won't fail the rest
for pkg in $APT_CORE; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    sudo apt install -y "$pkg" || warn "Package '$pkg' failed to install - verify name for your Mint version"
  fi
done

# Wine (winehq-stable) & Winetricks
if ! dpkg -s winehq-stable >/dev/null 2>&1; then
  say "Installing WineHQ Stable..."
  sudo apt install -y --install-recommends winehq-stable || sudo apt install -y winehq-stable || warn "Wine installation failed"
fi
if ! dpkg -s winetricks >/dev/null 2>&1; then
  say "Installing Winetricks..."
  sudo apt install -y winetricks || warn "Winetricks installation failed"
fi

# fastfetch isn't in the Ubuntu 24.04 (noble) repos, so install from its endorsed
# PPA (maintained by the fastfetch author, supports noble/22.x).
if ! command -v fastfetch >/dev/null 2>&1; then
  say "Installing fastfetch from its PPA (not in noble repos)..."
  sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
  sudo apt update -y
  sudo apt install -y fastfetch
fi

# ---- 3. AppImage helper ------------------------------------------------------
install_appimage() {
  local url="$1" name="$2"
  say "Installing AppImage: $name"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons"
  wget -q -O "$HOME/.local/bin/$name.AppImage" "$url"
  chmod +x "$HOME/.local/bin/$name.AppImage"
  local icon=""
  # try to pull an icon out of the AppImage
  ( "$HOME/.local/bin/$name.AppImage" --appimage-extract \
      'usr/share/icons/hicolor/256x256/apps/*.png' >/dev/null 2>&1 || true ) && icon="$(find squashfs-root -name '*.png' 2>/dev/null | head -1)"
  if [[ -n "$icon" ]]; then
    cp "$icon" "$HOME/.local/share/icons/$name.png" 2>/dev/null || true
    rm -rf squashfs-root
  fi
  cat > "$HOME/.local/share/applications/$name.desktop" <<EOF
[Desktop Entry]
Name=$name
Exec=$HOME/.local/bin/$name.AppImage
Type=Application
Categories=Utility;Network;
Terminal=false
$( [[ -n "$icon" ]] && echo "Icon=$HOME/.local/share/icons/$name.png" )
EOF
  update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
}

# OneDriveGUI (AppImage from GitHub releases)
install_appimage "https://github.com/bpozdena/OneDriveGUI/releases/latest/download/OneDriveGUI-1.3.2-x86_64.AppImage" "OneDriveGUI"

# ---- 4. Dropbox (official apt repo, so updates come via apt) -----------------
say "Installing Dropbox..."
# Add the official Dropbox apt repository (linux.dropbox.com) so it updates
# along with everything else on 'sudo apt upgrade' - no flatpak needed.
# NOTE: the old key URL (linux.dropbox.com/facts/keyring.gpg) returns 404 / "File
# Not Found" now - fetch the Dropbox repo signing key from Ubuntu's keyserver
# instead. Its fingerprint is 1C61A2656FB57B7E4DE0F4C1FC918B335044912E.
fetch_dropbox_key() {
  sudo mkdir -pm755 /etc/apt/keyrings 2>/dev/null || true
  # Always re-fetch (don't trust a possibly-stale file from a prior run).
  curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xFC918B335044912E" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/dropbox.gpg
  # Guard: ensure the key actually downloaded
  if ! sudo gpg --no-default-keyring --keyring=/etc/apt/keyrings/dropbox.gpg --list-keys >/dev/null 2>&1; then
    echo "ERROR: Dropbox key failed to download. Check network and re-run."
    exit 1
  fi
}
# Self-cleaning so a stale/broken key or repo entry from a prior run can't survive.
sudo rm -f /etc/apt/sources.list.d/dropbox.list 2>/dev/null
fetch_dropbox_key
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/dropbox.gpg] https://linux.dropbox.com/ubuntu noble main" \
  | sudo tee /etc/apt/sources.list.d/dropbox.list >/dev/null
sudo apt update -y
if ! dpkg -s dropbox >/dev/null 2>&1; then
  sudo apt install -y dropbox
fi

# ---- 5. Joplin (official installer handles desktop entry) -------------------
say "Installing Joplin..."
wget -qO- https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash

# ---- 6. NetRunner ANSI BBS client (mysticbbs) -------------------------------
say "Installing NetRunner..."
NETRUNNER_URL="https://mysticbbs.com/downloads/nr21_l64.zip"
tmp="$(mktemp -d)"
wget -q "$NETRUNNER_URL" -O "$tmp/nr.zip"
unzip -q "$tmp/nr.zip" -d "$tmp"
chmod +x "$tmp/netrunner"
sudo install -Dm755 "$tmp/netrunner" /usr/local/bin/netrunner
cat > "$HOME/.local/share/applications/netrunner.desktop" <<EOF
[Desktop Entry]
Name=NetRunner
Comment=ANSI BBS telnet/SSH client (mysticbbs)
Exec=/usr/local/bin/netrunner
Type=Application
Terminal=true
Categories=Network;
EOF
rm -rf "$tmp"
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

# ---- 7. MyBash from GitHub --------------------------------------------------
# We just clone the repo here - no auto-hooking into .bashrc. You finish the
# setup manually so you can review what it does (instructions printed below).
say "Cloning MyBash..."
if [[ ! -d "$MYBASH_DIR/.git" ]]; then
  git clone "$MYBASH_REPO" "$MYBASH_DIR" || warn "Could not clone MyBash - check MYBASH_REPO"
fi
cat << EOF

------------------------------------------------------------
MyBash cloned to: ${MYBASH_DIR}

To finish setting it up, continue manually:

    cd ${MYBASH_DIR}
    ./setup.sh

Then open a new terminal to pick up your new shell environment.
------------------------------------------------------------
EOF

say "All done. The MyBash setup is up to you:"
say "    cd '${MYBASH_DIR}' && ./setup.sh"

# ---- 8. Desktop customization ------------------------------------------------
# Applies the Mint-XP desktop, Mint-X-Yellow icons, Mint-Y-Dark-Teal apps,
# and sets wallpaper + startup/logoff sounds. Media files live next to this
# script wherever you pulled the repo from - safe to re-run.
say "Step 8: Applying desktop theme, wallpaper & sounds"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="${ASSET_DIR:-$SCRIPT_DIR}"

mkdir -p "$HOME/.local/share/themes" "$HOME/.local/share/sounds" \
         "$HOME/.local/share/backgrounds"

# 8a. Mint-XP desktop theme (Cinnamon spice) - download only if missing
if [[ ! -d "$HOME/.local/share/themes/Mint-XP/cinnamon" ]]; then
  say "Downloading Mint-XP desktop theme..."
  curl -sSL -o /tmp/mintxp.zip "https://cinnamon-spices.linuxmint.com/files/themes/Mint-XP.zip"
  python3 -c "import zipfile,sys; zipfile.ZipFile('/tmp/mintxp.zip').extractall('$HOME/.local/share/themes')" \
    || unzip -q /tmp/mintxp.zip -d "$HOME/.local/share/themes" 2>/dev/null \
    || sudo apt install -y unzip   # fallback: ensure unzip present
  rm -f /tmp/mintxp.zip
fi

# 8b. Mint-XP desktop theme
# Desktop / Window borders / Controls are driven by org.cinnamon.theme.
gsettings set org.cinnamon.theme name 'Mint-XP'

# 8c. Icon theme (Mint-X-Yellow)
gsettings set org.cinnamon.desktop.interface icon-theme 'Mint-X-Yellow'

# 8d. Application (Controls / GTK) theme
# Mint-Y-Dark-Teal drives the GTK widgets for app windows. This lives in the
# interface schema independently of the desktop theme (org.cinnamon.theme), so
# we can have Mint-XP desktop + Mint-Y-Dark-Teal apps at the same time.
gsettings set org.cinnamon.desktop.interface gtk-theme 'Mint-Y-Dark-Teal'

# 8e. Wallpaper (bliss.jpg)
# Assets are expected next to the script (in the cloned repo dir).
cp -f "$ASSET_DIR/bliss.jpg" "$HOME/.local/share/backgrounds/bliss.jpg"
gsettings set org.cinnamon.desktop.background picture-uri "file://$HOME/.local/share/backgrounds/bliss.jpg"
gsettings set org.cinnamon.desktop.background picture-options 'scaled'

# 8f. Startup / logoff sounds
# Cinnamon expects these in the system-wide dir (they show as "not found" if
# they only live under ~/.local). Copy into /usr/share/sounds and reference them.
sudo mkdir -p /usr/share/sounds
sudo cp -f "$ASSET_DIR/xp-startup.wav" /usr/share/sounds/xp-startup.wav
sudo cp -f "$ASSET_DIR/xp-shutdown.wav" /usr/share/sounds/xp-shutdown.wav
gsettings set org.cinnamon.sounds login-enabled true
gsettings set org.cinnamon.sounds login-file "file:///usr/share/sounds/xp-startup.wav"
gsettings set org.cinnamon.sounds logout-enabled true
gsettings set org.cinnamon.sounds logout-file "file:///usr/share/sounds/xp-shutdown.wav"

say "Desktop customizations applied. Re-login plays the XP startup/shutdown sounds."
