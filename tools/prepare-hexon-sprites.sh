#!/usr/bin/env bash
# Backwards-compatible wrapper: HEXON now builds through the shared pipeline.
set -euo pipefail
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/prepare-character-sprites.sh" ohm-1 "$@"
