#!/bin/bash
# Build Open NavG for a device (default: venu2).
#   scripts/build.sh            -> bin/OpenNavG.prg
#   scripts/build.sh --test     -> bin/OpenNavG-test.prg (unit tests included)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
DEVICE="${DEVICE:-venu2}"
mkdir -p bin
if [ "${1:-}" = "--test" ]; then
  monkeyc -f monkey.jungle -d "$DEVICE" -y "$CIQ_DEV_KEY" -o bin/OpenNavG-test.prg -t -w
else
  monkeyc -f monkey.jungle -d "$DEVICE" -y "$CIQ_DEV_KEY" -o bin/OpenNavG.prg -w
fi
