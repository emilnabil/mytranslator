#!/bin/sh

# =========================================================================
# One-liner execution command:
# wget -qO - https://raw.githubusercontent.com/emilnabil/mytranslator/refs/heads/main/mytranslator.sh | /bin/sh
# =========================================================================

PLUGIN_NAME="MyTranslator"
PKG_BASE="mytranslator"
VERSION=""
USERNAME="emilnabil"
REPO="mytranslator"

# Workspace paths
TMP_DIR="/var/volatile/tmp"
[ -d "$TMP_DIR" ] || TMP_DIR="/tmp"

PKG_MANAGER=""
PYTHON_VERSION=""
PY_VER=""
ARCH=""

log() {
    echo "$1"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

echo "===================================================="
echo "         $PLUGIN_NAME IPK INSTALLER                 "
echo "===================================================="

# 1. Detect Package Manager
if has_cmd opkg; then
    PKG_MANAGER="opkg"
elif has_cmd apt-get; then
    PKG_MANAGER="apt"
else
    log "[ERROR] No supported package manager (opkg/apt) found!"
    exit 1
fi
log "[INFO] Package manager detected: ${PKG_MANAGER}"

# 2. Detect Python Version (Formatted with decimal, e.g., 3.14)
if has_cmd python3; then
    PYTHON_VERSION="3"
    PY_VER=$(python3 -c 'import sys; print("%d.%d" % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
elif has_cmd python; then
    PYTHON_VERSION="2"
    PY_VER=$(python -c 'import sys; print("%d.%d" % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
fi

# Fallback for Python version from enigma.info
if [ -z "$PY_VER" ] && [ -f /usr/lib/enigma.info ]; then
    PY_VER_RAW=$(grep "^python=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"")
    if [ -n "$PY_VER_RAW" ]; then
        # Extract just the Major.Minor parts (e.g., 3.14.1 -> 3.14)
        PY_VER=$(echo "$PY_VER_RAW" | cut -d"." -f1,2)
    fi
fi

log "[INFO] Detected Python Version: Python $PY_VER"

# 3. Detect STB Architecture
# Method A: Check /usr/lib/enigma.info
if [ -f /usr/lib/enigma.info ]; then
    INFO_ARCH=$(grep "^architecture=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"")
    case "$INFO_ARCH" in
        cortexa15hf-neon-vfpv4|armv7ahf-neon|aarch64)
            ARCH="$INFO_ARCH"
            ;;
    esac
fi

# Method B: Check /etc/opkg/arch.conf
if [ -z "$ARCH" ] && [ -f /etc/opkg/arch.conf ]; then
    if grep -q "cortexa15hf-neon-vfpv4" /etc/opkg/arch.conf; then
        ARCH="cortexa15hf-neon-vfpv4"
    elif grep -q "armv7ahf-neon" /etc/opkg/arch.conf; then
        ARCH="armv7ahf-neon"
    elif grep -q "aarch64" /etc/opkg/arch.conf; then
        ARCH="aarch64"
    fi
fi

# Method C: Kernel architecture fallback
if [ -z "$ARCH" ]; then
    UNAME_M=$(uname -m)
    case "$UNAME_M" in
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        armv7l|arm*)
            ARCH="cortexa15hf-neon-vfpv4"
            ;;
    esac
fi

log "[INFO] Detected Architecture: ${ARCH:-Unknown}"

# Verify supported arch and python
case "$ARCH" in
    cortexa15hf-neon-vfpv4|armv7ahf-neon|aarch64)
        ;;
    *)
        log "[ERROR] Unsupported STB architecture: '$ARCH'. Aborting installation."
        exit 1
        ;;
esac

case "$PY_VER" in
    3.13|3.14)
        ;;
    *)
        log "[WARN] Detected Python version is $PY_VER (Official IPKs are for 3.13/3.14)."
        ;;
esac

# 4. Construct IPK File Name and Download URL
MY_TAR="${PKG_BASE}_${ARCH}_py${PY_VER}.tar.gz"
PLUGIN_URL="https://github.com/${USERNAME}/${REPO}/raw/refs/heads/main/${MY_TAR}"
TMP_FILE="$TMP_DIR/$MY_TAR"

log "[INFO] Target Package: $MY_TAR"
log "[INFO] Download Link: $PLUGIN_URL"

# 5. Update Package Feeds (Allows tar.gz to resolve its own dependencies automatically)
log "[INFO] Updating package feeds..."
if [ "$PKG_MANAGER" = "opkg" ]; then
    opkg update >/dev/null 2>&1 || log "[WARN] opkg update failed, attempting installation anyway..."
elif [ "$PKG_MANAGER" = "apt" ]; then
    apt-get update >/dev/null 2>&1 || log "[WARN] apt-get update failed, attempting installation anyway..."
fi

# 6. Download My Tar Archive
log "[INFO] Downloading IPK package..."
rm -f "$TMP_FILE"

if has_cmd wget; then
    wget -q --no-check-certificate "$PLUGIN_URL" -O "$TMP_FILE"
elif has_cmd curl; then
    curl -s -k -L "$PLUGIN_URL" -o "$TMP_FILE"
fi

if [ ! -s "$TMP_FILE" ]; then
    log "[ERROR] Download failed or file not found on GitHub!"
    log "[ERROR] Checked URL: $PLUGIN_URL"
    rm -f "$TMP_FILE"
    exit 1
fi

# 7. Install the IPK
log "[INFO] Installing package..."
if [ "$PKG_MANAGER" = "opkg" ]; then
    opkg install --force-reinstall --force-overwrite "$TMP_FILE"
elif [ "$PKG_MANAGER" = "apt" ]; then
    dpkg -i "$TMP_FILE"
    apt-get install -f -y
fi

if [ $? -ne 0 ]; then
    log "[ERROR] Installation failed!"
    rm -f "$TMP_FILE"
    exit 1
fi

# 8. Cleanup and Finalize
rm -f "$TMP_FILE"
sync

echo "===================================================="
echo "          $PLUGIN_NAME INSTALLATION COMPLETE        "
echo "===================================================="
echo "[INFO] Installed successfully for $ARCH (Python $PY_VER)."
echo "[INFO] Please restart GUI / Enigma2 to activate changes."

exit 0
