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
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg 2>/dev/null || \
  wget -qO- https://packages.microsoft.com/keys/msopentech.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
fi

# WineHQ
if ! grep -rq "dl.winehq.org/wine-builds" /etc/apt/sources.list.d/ 2>/dev/null; then
  say "Adding WineHQ repo..."
  sudo mkdir -pm755 /etc/apt/keyrings 2>/dev/null || true
  sudo wget -q -O /etc/apt/keyrings/winehq.gpg https://dl.winehq.org/wine-builds/winehq.key
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/ubuntu/ noble main" \
    | sudo tee /etc/apt/sources.list.d/winehq.list >/dev/null
fi

# abraunegg OneDrive client (PPA)
if ! dpkg -s onedrive >/dev/null 2>&1; then
  say "Adding OneDrive PPA..."
  sudo add-apt-repository -y ppa:abraunegg/onedrive
fi

sudo apt update -y

# ---- 2. Bulk apt install -----------------------------------------------------
say "Step 2: Installing repository packages"
# NOTE on updating:
#  - Onedrive *client* (ppa:abraunegg/onedrive) & Dropbox (official repo) stay
#    current via plain 'sudo apt update && sudo apt upgrade'.
#  - OneDriveGUI (the AppImage wrapper) is versioned separately - update by
#    grabbing a new AppImage from https://github.com/bpozdena/OneDriveGUI/releases when new.
APT_CORE="git mc nano micro tmux btop bat ripgrep jq direnv net-tools ipcalc"
APT_CORE+=" fortune-mod lolcat cowsay arj rclone duf fastfetch eza"
APT_CORE+=" p7zip p7zip-full filezilla remmina terminator unzip wget curl"
APT_CORE+=" ca-certificates gnupg lsb-release libfuse2t64"

# zenmap/nmap intentionally excluded per request.
sudo apt install -y $APT_CORE || warn "Some repo packages failed - verify names for your Mint version"

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
if ! grep -rq "linux.dropbox.com" /etc/apt/sources.list.d/ 2>/dev/null; then
  sudo mkdir -pm755 /etc/apt/keyrings 2>/dev/null || true
  wget -qO- https://linux.dropbox.com/facts/keyring.gpg | sudo gpg --dearmor \
    -o /etc/apt/keyrings/dropbox.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/dropbox.gpg] https://linux.dropbox.com/ubuntu noble main" \
    | sudo tee /etc/apt/sources.list.d/dropbox.list >/dev/null
  sudo apt update -y
fi
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
say "Cloning MyBash..."
if [[ ! -d "$MYBASH_DIR/.git" ]]; then
  git clone "$MYBASH_REPO" "$MYBASH_DIR" || warn "Could not clone MyBash - check MYBASH_REPO"
fi
if [[ -d "$MYBASH_DIR/.git" ]] && ! grep -q 'mybash' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# MyBash\nexport PATH="$HOME/.local/bin:$PATH"\nsource "%s/init.sh"\n' "$MYBASH_DIR" >> "$HOME/.bashrc"
  say "MyBash hooked into .bashrc"
fi

say "Done. Open a new terminal or 'source ~/.bashrc'"
