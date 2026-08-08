#!/usr/bin/env bash

set -eou pipefail

egress_profile="${CLI_SANDBOX_EGRESS_PROFILE:-managed}"

case "${SKIP_EGRESS_FIREWALL:-false}" in
  false)
    if ! sudo /usr/local/bin/init-firewall.sh; then
      echo "Unable to set firewall" >&2
      echo "With --cap-drop=ALL, pass exactly: --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=SETGID --cap-add=SETUID" >&2
      exit 1
    fi
    ;;
  true)
    if [ "$egress_profile" != "interactive" ]; then
      echo "SKIP_EGRESS_FIREWALL=true is forbidden for the managed egress profile" >&2
      exit 1
    fi
    echo "WARNING: interactive sandbox started without an egress firewall" >&2
    ;;
  *)
    echo "SKIP_EGRESS_FIREWALL must be exactly true or false" >&2
    exit 1
    ;;
esac

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
