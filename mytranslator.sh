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
echo "         $PLUGIN INSTALLER                 "
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

# 2. Detect Python Version
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
        PY_VER=$(echo "$PY_VER_RAW" | cut -d"." -f1,2)
    fi
fi

log "[INFO] Detected Python Version: Python $PY_VER"

# 3. Detect STB Architecture (Modified to match actual file names)
if [ -f /usr/lib/enigma.info ]; then
    INFO_ARCH=$(grep "^architecture=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"")
    case "$INFO_ARCH" in
        cortexa15hf-neon-vfpv4|armv7ahf-neon|armv71|armv7l)
            ARCH="arm"
            ;;
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        mips|mipsel)
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

log "[INFO] Detected Architecture: ${ARCH:-Unknown}"

# Verify supported arch and python
case "$ARCH" in
    arm|aarch64|mipsel)
        ;;
    *)
        log "[ERROR] Unsupported STB architecture: '$ARCH'. Aborting installation."
        log "[INFO] Supported architectures: arm, aarch64, mipsel"
        exit 1
        ;;
esac

# Verify Python version compatibility
case "$PY_VER" in
    3.13|3.14)
        log "[INFO] Python $PY_VER is supported."
        ;;
    *)
        log "[WARN] Detected Python version is $PY_VER."
        log "[INFO] Available packages are for Python 3.13 and 3.14."
        log "[INFO] Trying to find compatible package..."
        # Try to use 3.14 if available, otherwise 3.13
        if [ -n "$PY_VER" ]; then
            # Keep original version for now, we'll try both
            :
        fi
        ;;
esac

# 4. Try to find and download the correct package
install_package() {
    local try_arch="$1"
    local try_py="$2"
    local MY_TAR="${PKG_BASE}_${try_arch}_py${try_py}.tar.gz"
    local PLUGIN_URL="https://github.com/${USERNAME}/${REPO}/raw/refs/heads/main/${MY_TAR}"
    local TMP_FILE="$TMP_DIR/$MY_TAR"
    
    log "[INFO] Trying: $MY_TAR"
    
    # Download
    rm -f "$TMP_FILE"
    if has_cmd wget; then
        wget -q --no-check-certificate "$PLUGIN_URL" -O "$TMP_FILE"
    elif has_cmd curl; then
        curl -s -k -L "$PLUGIN_URL" -o "$TMP_FILE"
    fi
    
    if [ -s "$TMP_FILE" ]; then
        log "[INFO] Successfully downloaded: $MY_TAR"
        # Install
        if [ "$PKG_MANAGER" = "opkg" ]; then
            opkg install --force-reinstall --force-overwrite "$TMP_FILE"
        elif [ "$PKG_MANAGER" = "apt" ]; then
            dpkg -i "$TMP_FILE"
            apt-get install -f -y
        fi
        
        if [ $? -eq 0 ]; then
            rm -f "$TMP_FILE"
            return 0
        else
            rm -f "$TMP_FILE"
            return 1
        fi
    else
        rm -f "$TMP_FILE"
        return 1
    fi
}

# 5. Update Package Feeds
log "[INFO] Updating package feeds..."
if [ "$PKG_MANAGER" = "opkg" ]; then
    opkg update >/dev/null 2>&1 || log "[WARN] opkg update failed, attempting installation anyway..."
elif [ "$PKG_MANAGER" = "apt" ]; then
    apt-get update >/dev/null 2>&1 || log "[WARN] apt-get update failed, attempting installation anyway..."
fi

# 6. Try to install with detected architecture and Python versions
log "[INFO] Searching for compatible package..."

INSTALLED=0

# First try: exact match with detected Python
if [ -n "$PY_VER" ]; then
    if install_package "$ARCH" "$PY_VER"; then
        INSTALLED=1
    fi
fi

# Second try: try Python 3.14 if not installed
if [ $INSTALLED -eq 0 ] && [ "$PY_VER" != "3.14" ]; then
    log "[INFO] Trying Python 3.14 version..."
    if install_package "$ARCH" "3.14"; then
        INSTALLED=1
    fi
fi

# Third try: try Python 3.13 if not installed
if [ $INSTALLED -eq 0 ] && [ "$PY_VER" != "3.13" ]; then
    log "[INFO] Trying Python 3.13 version..."
    if install_package "$ARCH" "3.13"; then
        INSTALLED=1
    fi
fi

# Final check
if [ $INSTALLED -eq 0 ]; then
    log "[ERROR] Installation failed!"
    log "[ERROR] Could not find compatible package for:"
    log "[ERROR] Architecture: $ARCH"
    log "[ERROR] Python: $PY_VER"
    log "[INFO] Available packages:"
    log "  - mytranslator_aarch64_py3.13.tar.gz"
    log "  - mytranslator_aarch64_py3.14.tar.gz"
    log "  - mytranslator_arm_py3.13.tar.gz"
    log "  - mytranslator_arm_py3.14.tar.gz"
    log "  - mytranslator_mipsel_py3.13.tar.gz"
    log "  - mytranslator_mipsel_py3.14.tar.gz"
    exit 1
fi

# 7. Cleanup and Finalize
sync

echo "===================================================="
echo "          $PLUGIN_NAME INSTALLATION COMPLETE        "
echo "===================================================="
echo "[INFO] Installed successfully for $ARCH (Python $PY_VER)."
echo "[INFO] Please restart GUI / Enigma2 to activate changes."

exit 0
