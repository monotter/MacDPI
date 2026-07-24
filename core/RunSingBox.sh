#!/bin/bash
cd "$(dirname "$0")/.."

# The config is generated on the fly and fed to sing-box through fd 0
# (/dev/stdin) — it is never written to disk. sudo preserves fd 0, and exec keeps
# sing-box a single process so the teardown in Run.sh is unchanged.
exec sudo ./bin/sing-box run -c /dev/stdin < <(./core/GenConfig.sh --stdout)
