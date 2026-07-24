#!/bin/bash
set -m

cd "$(dirname "$0")"

if [ ! -x ./bin/ciadpi ] || ! ./bin/ciadpi --version >/dev/null 2>&1 \
   || [ ! -x ./bin/sing-box ] || ! ./bin/sing-box version >/dev/null 2>&1; then
    echo "Binaries missing or not runnable on this machine. Building..."
    ./bin/Build.sh
fi

# Validate the config from settings.conf before touching the network, so a bad
# settings file fails fast. The real config is generated later, straight into
# sing-box, and never written to disk (see core/RunSingBox.sh).
./core/GenConfig.sh --stdout >/dev/null || { echo "Config invalid. Fix settings.conf."; exit 1; }

sudo sysctl -w kern.maxfiles=9999999999 >/dev/null
sudo sysctl -w kern.maxfilesperproc=9999999999 >/dev/null
ulimit -n 1048576

net_iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net_svc=$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$net_iface" '
    /^Hardware Port:/ { port = substr($0, 16) }
    /^Device:/        { if ($2 == dev) { print port; exit } }')
[ -z "$net_svc" ] && net_svc="Wi-Fi"

mkdir -p logs
: > logs/box.log 2>/dev/null || true

( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 60; done ) &
keepalive_pid=$!

( while kill -0 "$$" 2>/dev/null; do
    if [ -f logs/box.log ] && [ "$(stat -f%z logs/box.log 2>/dev/null || echo 0)" -gt 10485760 ]; then
        : > logs/box.log
    fi
    sleep 30
  done ) &
logcap_pid=$!

# When running as the service, watch settings.conf and restart on change so edits
# take effect without a manual restart. A clean exit here lets launchd relaunch
# us, which regenerates the config from the new settings.
confwatch_pid=""
if [ -n "$MACDPI_SERVICE" ]; then
    conf_mtime() { stat -f %m settings.conf 2>/dev/null || echo 0; }
    last_conf=$(conf_mtime)
    ( while kill -0 "$$" 2>/dev/null; do
        if [ "$(conf_mtime)" != "$last_conf" ]; then
            echo "settings.conf changed — restarting to apply."
            kill -TERM "$$" 2>/dev/null
            break
        fi
        sleep 5
      done ) &
    confwatch_pid=$!
fi

dpi_pid=""
box_pid=""

cleanup() {
    trap - INT TERM EXIT
    echo
    echo "Stopping..."

    [ -n "$keepalive_pid" ] && kill -KILL -"$keepalive_pid" 2>/dev/null
    [ -n "$logcap_pid" ] && kill -KILL -"$logcap_pid" 2>/dev/null
    [ -n "$confwatch_pid" ] && kill -KILL -"$confwatch_pid" 2>/dev/null

    if [ -n "$box_pid" ]; then
        sudo -n kill -TERM -"$box_pid" 2>/dev/null || kill -TERM -"$box_pid" 2>/dev/null
    fi

    if [ -n "$dpi_pid" ]; then
        kill -KILL -"$dpi_pid" 2>/dev/null
    fi

    if [ -n "$box_pid" ]; then
        for _ in $(seq 1 10); do
            sudo -n kill -0 -"$box_pid" 2>/dev/null || break
            sleep 0.5
        done
        sudo -n kill -KILL -"$box_pid" 2>/dev/null
    fi

    ./net/UnsetStaticIP.sh

    echo "Stopped."
}

trap cleanup INT TERM EXIT

./core/RunDPI.sh &
dpi_pid=$!

./net/SetStaticIP.sh || echo "Static IP not set; bypass still works but disconnects may occur."

sudo networksetup -setdnsservers "$net_svc" 1.1.1.1
sudo dscacheutil -flushcache 2>/dev/null; sudo killall -HUP mDNSResponder 2>/dev/null

./core/RunSingBox.sh &
box_pid=$!

wait
