#!/usr/bin/env bash

set -eou pipefail

if [ "${SKIP_EGRESS_FIREWALL:-false}" != "true" ]; then
  sudo /usr/local/bin/init-firewall.sh \
    || (
          echo "Unable to set firewall" \
          echo "Make sure you pass these flags to docker run: --cap-add=NET_ADMIN --cap-add=NET_RAW" \
          && exit 1
        )
fi

# sometimes i forget where i started after all the firewall rule stdout
ls -la

if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

if [ "$#" -eq 0 ]; then
  exec /bin/bash -l
else
  exec "$@"
fi
