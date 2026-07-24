#!/bin/bash
set -e

cd "$(dirname "$0")"
DIR="$(pwd)"
LABEL="com.macdpi"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

case "$DIR/" in
    "$HOME"/Desktop/*|"$HOME"/Documents/*|"$HOME"/Downloads/*)
        echo "The service cannot run from Desktop, Documents, or Downloads."
        echo "macOS blocks background daemons from reading those folders."
        echo "Move this project elsewhere (for example ~/MacDPI) and run this again."
        exit 1 ;;
esac

if [ ! -x ./bin/ciadpi ] || ! ./bin/ciadpi --version >/dev/null 2>&1 \
   || [ ! -x ./bin/sing-box ] || ! ./bin/sing-box version >/dev/null 2>&1; then
    ./bin/Build.sh
fi

tmp=$(mktemp)
cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DIR/Run.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>MACDPI_SERVICE</key>
        <string>1</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$DIR/logs/service.log</string>
    <key>StandardErrorPath</key>
    <string>$DIR/logs/service.log</string>
</dict>
</plist>
EOF

# launchd opens the log paths at launch, so the folder must exist first.
mkdir -p logs

sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo cp "$tmp" "$PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
rm -f "$tmp"
sudo launchctl bootstrap system "$PLIST"

echo "Service installed and started as $LABEL."
echo "It runs at every boot. Remove it with ./ServiceRemove.sh"
