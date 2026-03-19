#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

if [ -t 0 ] && [ -t 1 ]; then
  exec /bin/copilot
fi

printf '%s\n' \
  'copilot-cli container is ready.' \
  'Run it interactively to launch GitHub Copilot CLI:' \
  '  docker run --rm -it <image>' \
  'Or pass a command explicitly:' \
  '  docker run --rm <image> copilot --help'

