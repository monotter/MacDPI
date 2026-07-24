#!/bin/bash
set -e

LABEL="com.macdpi"

if ! sudo launchctl print system/"$LABEL" >/dev/null 2>&1; then
    echo "The $LABEL service is not installed."
    echo "Install it with ./ServiceInstall.sh, or run ./Run.sh in the foreground."
    exit 1
fi

echo "Restarting $LABEL..."
sudo launchctl kickstart -k system/"$LABEL"
echo "Restarted. The config is regenerated from settings.conf on start."
