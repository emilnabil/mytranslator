#!/bin/sh

# =========================================================================
# One-liner execution command:
# wget -qO - https://github.com/emilnabil/mytranslator/raw/refs/heads/main/mytranslator.sh | /bin/sh
# =========================================================================

PLUGIN_NAME="MyTranslator"
PKG_BASE="mytranslator"
USERNAME="emilnabil"
REPO="mytranslator"

# Workspace paths
TMP_DIR="/var/volatile/tmp"
[ -d "$TMP_DIR" ] || TMP_DIR="/tmp"

PY_VER=""
ARCH=""

log() {
    echo "$1"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

echo "===================================================="
echo "         $PLUGIN_NAME INSTALLER                     "
echo "===================================================="

# 1. Check for required tools
if ! has_cmd tar; then
    log "[ERROR] 'tar' command not found! Please install tar first."
    exit 1
fi

# 2. Detect Python Version
if has_cmd python3; then
    PY_VER=$(python3 -c 'import sys; print("%d.%d" % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
elif has_cmd python; then
    PY_VER=$(python -c 'import sys; print("%d.%d" % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
fi

# Fallback for Python version from enigma.info
if [ -z "$PY_VER" ] && [ -f /usr/lib/enigma.info ]; then
    PY_VER_RAW=$(grep "^python=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"")
    if [ -n "$PY_VER_RAW" ]; then
        PY_VER=$(echo "$PY_VER_RAW" | cut -d"." -f1,2)
    fi
fi

# Check if Python version is supported (3.13 or 3.14)
case "$PY_VER" in
    3.13|3.14)
        log "[INFO] Python version: $PY_VER ✓"
        ;;
    *)
        log "[ERROR] Unsupported Python version: $PY_VER"
        log "[INFO] This plugin requires Python 3.13 or 3.14"
        exit 1
        ;;
esac

# 3. Detect STB Architecture
# Method A: Check /usr/lib/enigma.info
if [ -f /usr/lib/enigma.info ]; then
    INFO_ARCH=$(grep "^architecture=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"")
    case "$INFO_ARCH" in
        *cortexa15hf-neon-vfpv4*|*armv7ahf-neon*|*armv71*|*armv7l*)
            ARCH="arm"
            ;;
        *aarch64*|*arm64*)
            ARCH="aarch64"
            ;;
        *mips*|*mipsel*)
            ARCH="mipsel"
            ;;
    esac
fi

# Method B: Check /etc/opkg/arch.conf
if [ -z "$ARCH" ] && [ -f /etc/opkg/arch.conf ]; then
    if grep -q "cortexa15hf-neon-vfpv4\|armv7ahf-neon\|armv71\|armv7l" /etc/opkg/arch.conf; then
        ARCH="arm"
    elif grep -q "aarch64\|arm64" /etc/opkg/arch.conf; then
        ARCH="aarch64"
    elif grep -q "mips\|mipsel" /etc/opkg/arch.conf; then
        ARCH="mipsel"
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
            ARCH="arm"
            ;;
        mips|mipsel)
            ARCH="mipsel"
            ;;
    esac
fi

# Verify architecture is supported
case "$ARCH" in
    arm|aarch64|mipsel)
        log "[INFO] Architecture: $ARCH ✓"
        ;;
    *)
        log "[ERROR] Unsupported architecture: $ARCH"
        log "[INFO] Supported architectures: arm, aarch64, mipsel"
        exit 1
        ;;
esac

# 4. Construct package filename and download
PKG_FILE="${PKG_BASE}_${ARCH}_py${PY_VER}.tar.gz"
PKG_URL="https://github.com/${USERNAME}/${REPO}/raw/refs/heads/main/${PKG_FILE}"
TMP_FILE="$TMP_DIR/${PKG_FILE}"

log "[INFO] Looking for: $PKG_FILE"
log "[INFO] Download URL: $PKG_URL"

# 5. Download the package
log "[INFO] Downloading package..."
rm -f "$TMP_FILE"

if has_cmd wget; then
    wget -q --no-check-certificate "$PKG_URL" -O "$TMP_FILE"
elif has_cmd curl; then
    curl -s -k -L "$PKG_URL" -o "$TMP_FILE"
else
    log "[ERROR] Neither wget nor curl found!"
    exit 1
fi

# Check if download was successful
if [ ! -s "$TMP_FILE" ]; then
    log "[ERROR] Download failed!"
    log "[ERROR] Package not found: $PKG_FILE"
    log "[ERROR] URL: $PKG_URL"
    log ""
    log "[INFO] Available packages:"
    log "  • mytranslator_aarch64_py3.13.tar.gz"
    log "  • mytranslator_aarch64_py3.14.tar.gz"
    log "  • mytranslator_arm_py3.13.tar.gz"
    log "  • mytranslator_arm_py3.14.tar.gz"
    log "  • mytranslator_mipsel_py3.13.tar.gz"
    log "  • mytranslator_mipsel_py3.14.tar.gz"
    rm -f "$TMP_FILE"
    exit 1
fi

log "[INFO] Download successful! ($PKG_FILE)"
log "[INFO] File size: $(du -h "$TMP_FILE" | cut -f1)"

# 6. Extract the package directly to root (/)
log "[INFO] Extracting package to system root (/):"
log "[INFO] tar -xzf $TMP_FILE -C /"

if tar -xzf "$TMP_FILE" -C / 2>/dev/null; then
    log "[INFO] Extraction successful! ✓"
else
    log "[ERROR] Failed to extract package!"
    log "[ERROR] The package may be corrupted or incompatible."
    rm -f "$TMP_FILE"
    exit 1
fi

# 7. Set proper permissions for plugin files
log "[INFO] Setting permissions..."

# Find and set permissions for Python files
if [ -d "/usr/lib/enigma2/python/Plugins/Extensions/MyTranslator" ]; then
    chmod -R 755 "/usr/lib/enigma2/python/Plugins/Extensions/MyTranslator"
    find "/usr/lib/enigma2/python/Plugins/Extensions/MyTranslator" -name "*.py" -exec chmod 644 {} \; 2>/dev/null
    log "[INFO] Permissions set for MyTranslator plugin"
elif [ -d "/usr/lib/enigma2/python/Plugins/Extensions" ]; then
    # Try to find any MyTranslator directory
    find "/usr/lib/enigma2/python/Plugins/Extensions" -type d -name "*MyTranslator*" -exec chmod -R 755 {} \; 2>/dev/null
    log "[INFO] Permissions set for MyTranslator plugin"
fi

# Set permissions for any .sh or .py files in common locations
find /usr/lib/enigma2 -name "*.py" -exec chmod 644 {} \; 2>/dev/null
find /usr/lib/enigma2 -type d -exec chmod 755 {} \; 2>/dev/null

# 8. Cleanup
log "[INFO] Cleaning up temporary files..."
rm -f "$TMP_FILE"

# 9. Sync filesystem
sync

echo "===================================================="
echo "          $PLUGIN_NAME INSTALLATION COMPLETE        "
echo "===================================================="
echo "[INFO] Installed: $PKG_FILE"
echo "[INFO] Architecture: $ARCH"
echo "[INFO] Python Version: $PY_VER"
echo ""
echo "[INFO] Files extracted to: /"
echo "[INFO] Plugin location: /usr/lib/enigma2/python/Plugins/Extensions/MyTranslator"
echo ""
echo "[INFO] Please restart GUI / Enigma2 to activate."
echo "===================================================="

exit 0
