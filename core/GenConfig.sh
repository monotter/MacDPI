#!/bin/bash
# Generate the sing-box config from settings.conf.
#
# By default the config is printed to stdout (Run.sh pipes it straight into
# sing-box, so it never touches disk). Pass --out <path> to write a file instead,
# e.g. to inspect what would be generated.
#
#   core/GenConfig.sh                 # print config to stdout
#   core/GenConfig.sh --out cfg.json  # write config to cfg.json (validated)
#   core/GenConfig.sh --settings f    # use a different settings file
set -e

cd "$(dirname "$0")/.."

CONF="settings.conf"
OUT=""   # empty = stdout

while [ $# -gt 0 ]; do
    case "$1" in
        --stdout)   OUT="" ;;
        --out)      OUT="$2"; shift ;;
        --settings) CONF="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -f "$CONF" ] || { echo "Settings file '$CONF' not found." >&2; exit 1; }

# Defaults, overridden by whatever settings.conf sets.
PROXY_PORT=1080
DOH_SERVER=1.1.1.1
MODE=selective
BLOCK_QUIC=true
CIADPI_ARGS=""
APPS=()
DOMAINS=()

# Source the settings. Prefix bare names with ./ so `.` reads the file, not $PATH.
src="$CONF"
case "$src" in /*|./*|../*) ;; *) src="./$src" ;; esac
# shellcheck source=../settings.conf disable=SC1090
. "$src"

# Bind direct traffic to the real default interface (fall back to en0).
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
[ -z "$iface" ] && iface="en0"

# Print a JSON array of strings from the given arguments.
json_strings() {
    local out="" item
    for item in "$@"; do
        [ -n "$out" ] && out="$out, "
        out="$out\"$item\""
    done
    printf '[%s]' "$out"
}

# Rules that always apply: sniff, DNS hijack, mDNS/LAN/ciadpi carve-outs.
rules='      {
        "inbound": ["tun-in"],
        "action": "sniff"
      },
      {
        "port": [53],
        "action": "hijack-dns"
      },
      {
        "port": [5353],
        "network": ["udp"],
        "outbound": "direct"
      },
      {
        "process_name": ["ciadpi"],
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      }'

if [ "$BLOCK_QUIC" = "true" ]; then
    rules="$rules,
      {
        \"port\": [443],
        \"network\": [\"udp\"],
        \"action\": \"reject\",
        \"method\": \"drop\"
      }"
fi

if [ "$MODE" = "global" ]; then
    # Everything TCP goes through the proxy; keep all UDP direct (desync is TCP-only).
    rules="$rules,
      {
        \"network\": [\"udp\"],
        \"outbound\": \"direct\"
      }"
    final="ciadpi-proxy"
else
    if [ "${#APPS[@]}" -gt 0 ]; then
        rules="$rules,
      {
        \"process_name\": $(json_strings "${APPS[@]}"),
        \"outbound\": \"ciadpi-proxy\"
      }"
    fi
    if [ "${#DOMAINS[@]}" -gt 0 ]; then
        rules="$rules,
      {
        \"domain_suffix\": $(json_strings "${DOMAINS[@]}"),
        \"outbound\": \"ciadpi-proxy\"
      }"
    fi
    final="direct"
fi

json=$(cat <<EOF
{
  "log": {
    "disabled": false,
    "level": "warn",
    "output": "logs/box.log",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "doh-cf",
        "server": "$DOH_SERVER"
      }
    ],
    "final": "doh-cf"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "ciadpi-proxy",
      "server": "127.0.0.1",
      "server_port": $PROXY_PORT
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
$rules
    ],
    "final": "$final",
    "default_interface": "$iface"
  }
}
EOF
)

# Validate against sing-box if it is built. Failing here means the settings are
# bad; nothing is emitted so a broken config never reaches sing-box.
have_box=false
if [ -x ./bin/sing-box ] && ./bin/sing-box version >/dev/null 2>&1; then
    have_box=true
    if ! printf '%s\n' "$json" | ./bin/sing-box check -c /dev/stdin >/dev/null 2>&1; then
        echo "Generated config failed sing-box validation:" >&2
        printf '%s\n' "$json" | ./bin/sing-box check -c /dev/stdin >&2 || true
        exit 1
    fi
fi

if [ -z "$OUT" ]; then
    # Stdout mode: only the JSON goes to stdout; status to stderr.
    printf '%s\n' "$json"
    echo "Generated config — mode=$MODE, proxy port=$PROXY_PORT, interface=$iface." >&2
else
    # File mode: write, then pretty-print in place if we have the binary.
    printf '%s\n' "$json" > "$OUT"
    [ "$have_box" = true ] && ./bin/sing-box format -w -c "$OUT" >/dev/null 2>&1
    echo "Wrote $OUT — mode=$MODE, proxy port=$PROXY_PORT, interface=$iface." >&2
fi
