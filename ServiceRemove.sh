#!/bin/bash
set -e

cd "$(dirname "$0")"
LABEL="com.macdpi"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo rm -f "$PLIST"
./net/UnsetStaticIP.sh 2>/dev/null || true

echo "Service removed."
