#!/bin/bash
set -e

STATIC_HOST=240

iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
if [ -z "$iface" ]; then
    echo "No default network interface found. Are you online?"
    exit 1
fi

svc=$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$iface" '
    /^Hardware Port:/ { port = substr($0, 16) }
    /^Device:/        { if ($2 == dev) { print port; exit } }')
[ -z "$svc" ] && svc="Wi-Fi"

router=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
mask=$(ipconfig getoption "$iface" subnet_mask 2>/dev/null)
cur_ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
[ -z "$mask" ] && mask="255.255.255.0"

if [ -z "$router" ]; then
    echo "Could not determine the router address."
    exit 1
fi

static_ip="${router%.*}.$STATIC_HOST"

if [ "$static_ip" != "$cur_ip" ] && ping -c 1 -t 1 "$static_ip" >/dev/null 2>&1; then
    echo "$static_ip is already in use. Change STATIC_HOST at the top of this script."
    exit 1
fi

sudo networksetup -setmanual "$svc" "$static_ip" "$mask" "$router"
sudo networksetup -setdnsservers "$svc" "$router"
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

new_ip=""
for _ in $(seq 1 6); do
    new_ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    [ "$new_ip" = "$static_ip" ] && break
    sleep 1
done

if [ "$new_ip" = "$static_ip" ]; then
    echo "Static IP set: $new_ip"
else
    echo "Expected $static_ip but got $new_ip. Run ./net/UnsetStaticIP.sh to return to DHCP."
    exit 1
fi
