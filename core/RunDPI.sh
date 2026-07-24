#!/bin/bash
cd "$(dirname "$0")/.."

# Build the ciadpi command from settings.conf (the single source of truth).
PROXY_PORT=1080
CIADPI_ARGS=""
MAX_CONN=512
[ -f settings.conf ] && . ./settings.conf

# Each connection uses ~2 fds; make sure the fd limit clears the pool size. Run.sh
# already raises this, but do it here too so a standalone run isn't fd-starved.
ulimit -n $(( MAX_CONN * 4 )) 2>/dev/null || true

ciadpi_pid=""

cleanup() {
    trap - INT TERM EXIT
    [ -n "$ciadpi_pid" ] && kill -KILL "$ciadpi_pid" 2>/dev/null
}

trap cleanup INT TERM EXIT

# CIADPI_ARGS is intentionally unquoted so it splits into separate flags.
# shellcheck disable=SC2086
./bin/ciadpi --port "$PROXY_PORT" --max-conn "$MAX_CONN" $CIADPI_ARGS &

ciadpi_pid=$!
wait "$ciadpi_pid"
