#!/bin/bash
set -e

iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
[ -z "$iface" ] && iface="en0"

svc=$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$iface" '
    /^Hardware Port:/ { port = substr($0, 16) }
    /^Device:/        { if ($2 == dev) { print port; exit } }')
[ -z "$svc" ] && svc="Wi-Fi"

sudo networksetup -setdhcp "$svc"
sudo networksetup -setdnsservers "$svc" "Empty"
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

for _ in 1 2 3 4 5; do
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    [ -n "$ip" ] && break
    sleep 2
done
echo "Back on DHCP. IP: ${ip:-acquiring...}"
