#!/usr/bin/env bash

set -eou pipefail

sudo /usr/local/bin/init-firewall.sh \
  || (
        echo "Unable to set firewall" \
        echo "Make sure you pass these flags to docker run: --cap-add=NET_ADMIN --cap-add=NET_RAW" \
        && exit 1
      )

# sometimes i forget where i started after all the firewall rule stdout
ls -la

if [ "$#" -eq 0 ]; then
  exec /bin/bash -l
else
  exec "$@"
fi
