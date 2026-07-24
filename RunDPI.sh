#!/bin/bash
cd "$(dirname "$0")"

ciadpi_pid=""

cleanup() {
    trap - INT TERM EXIT
    [ -n "$ciadpi_pid" ] && kill -KILL "$ciadpi_pid" 2>/dev/null
}

trap cleanup INT TERM EXIT

./ciadpi --port 1080 \
    -r 1+s --oob 1 \
    -A torst,ssl_err -r 1+s --disorder 1 \
    -A torst,ssl_err -r 1+s --split 1+s &

ciadpi_pid=$!
wait "$ciadpi_pid"
