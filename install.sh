#!/bin/bash
# MTProxyMax Quick Installer — SamNet Technologies
# Usage: curl -sL https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/install.sh | sudo bash
set -e
SCRIPT_URL="https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/mtproxymax.sh"
if [ "$(id -u)" -ne 0 ]; then echo "Run as root: curl -sL $SCRIPT_URL | sudo bash" >&2; exit 1; fi
curl -fsSL "$SCRIPT_URL" -o /tmp/mtproxymax.sh && bash /tmp/mtproxymax.sh install && rm -f /tmp/mtproxymax.sh
