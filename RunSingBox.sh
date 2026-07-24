#!/bin/bash
cd "$(dirname "$0")"

exec sudo ./sing-box run -c ./config.json
