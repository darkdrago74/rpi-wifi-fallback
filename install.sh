#!/bin/bash
# RPi WiFi Fallback - Master Installer
# Automatically detects Debian version and selects the appropriate installer.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[MASTER_INSTALL]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Use: ./install.sh"
fi

if [ ! -f /etc/os-release ]; then
    error "Cannot detect OS: /etc/os-release not found."
fi

# Source OS release information
. /etc/os-release

log "Detected OS: $PRETTY_NAME"

# Check for forced mode via arguments
MODE=""
for arg in "$@"; do
    if [ "$arg" == "--legacy" ]; then
        MODE="legacy"
    elif [ "$arg" == "--antigravity" ]; then
        MODE="antigravity"
    fi
done

if [ -n "$MODE" ]; then
    log "Forcing mode: $MODE"
else
    # Auto-detect mode
    if [ "$ID" = "debian" ] || [ "$ID" = "raspbian" ]; then
        # Check version
        # Bookworm is 12, Trixie is 13+
        if [ "$VERSION_ID" -eq 12 ]; then
            MODE="legacy"
            log "Debian 12 (Bookworm) detected -> Selecting Legacy Installer"
        elif [ "$VERSION_ID" -ge 13 ]; then
            MODE="antigravity"
            log "Debian 13+ (Trixie or newer) detected -> Selecting Antigravity Installer"
        else
            # Older than 12? Or testing? Default to legacy for now if < 12
            if [ "$VERSION_ID" -lt 12 ]; then
                log "Older OS detected ($VERSION_ID). Attempting Legacy Installer..."
                MODE="legacy"
            else
                 # Fallback
                 log "Unknown version ($VERSION_ID). Defaulting to Legacy."
                 MODE="legacy"
            fi
        fi
    else
        log "Non-Debian OS detected ($ID). Defaulting to Legacy."
        MODE="legacy"
    fi
fi

# Execute selected installer
if [ "$MODE" = "antigravity" ]; then
    if [ -d "trixie" ]; then
        log "Handing over to Trixie (Antigravity) Installer..."
        cd trixie || error "Failed to enter trixie directory"
        # Ensure it is executable
        chmod +x install.sh
        exec ./install.sh "$@"
    else
        error "Trixie directory not found!"
    fi
else
    if [ -d "bookworm" ]; then
        log "Handing over to Bookworm (Legacy) Installer..."
        cd bookworm || error "Failed to enter bookworm directory"
        chmod +x install.sh
        exec ./install.sh "$@"
    else
        error "Bookworm directory not found!"
    fi
fi
