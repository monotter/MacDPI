#!/bin/bash
set -m

cd "$(dirname "$0")"

if [ ! -x ./ciadpi ] || ! ./ciadpi --version >/dev/null 2>&1 \
   || [ ! -x ./sing-box ] || ! ./sing-box version >/dev/null 2>&1; then
    echo "Binaries missing or not runnable on this machine. Building..."
    ./Build.sh
fi

sudo sysctl -w kern.maxfiles=9999999999 >/dev/null
sudo sysctl -w kern.maxfilesperproc=9999999999 >/dev/null
ulimit -n 1048576

net_iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net_svc=$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$net_iface" '
    /^Hardware Port:/ { port = substr($0, 16) }
    /^Device:/        { if ($2 == dev) { print port; exit } }')
[ -z "$net_svc" ] && net_svc="Wi-Fi"

: > box.log 2>/dev/null || true

( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 60; done ) &
keepalive_pid=$!

( while kill -0 "$$" 2>/dev/null; do
    if [ -f box.log ] && [ "$(stat -f%z box.log 2>/dev/null || echo 0)" -gt 10485760 ]; then
        : > box.log
    fi
    sleep 30
  done ) &
logcap_pid=$!

dpi_pid=""
box_pid=""

cleanup() {
    trap - INT TERM EXIT
    echo
    echo "Stopping..."

    [ -n "$keepalive_pid" ] && kill -KILL -"$keepalive_pid" 2>/dev/null
    [ -n "$logcap_pid" ] && kill -KILL -"$logcap_pid" 2>/dev/null

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

    ./UnsetStaticIP.sh

    echo "Stopped."
}

trap cleanup INT TERM EXIT

./RunDPI.sh &
dpi_pid=$!

./SetStaticIP.sh || echo "Static IP not set; bypass still works but disconnects may occur."

sudo networksetup -setdnsservers "$net_svc" 1.1.1.1
sudo dscacheutil -flushcache 2>/dev/null; sudo killall -HUP mDNSResponder 2>/dev/null

./RunSingBox.sh &
box_pid=$!

wait
