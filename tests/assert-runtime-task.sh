#!/usr/bin/env sh

set -eu

fail() {
    echo "runtime task assertion failed: $*" >&2
    exit 1
}

[ "$(id -u)" -ne 0 ] || fail "task runs as root"

for capability_field in CapEff CapPrm CapAmb; do
    capability_value="$(awk -v field="${capability_field}:" '$1 == field { print $2 }' "/proc/$$/status")"
    [ "$capability_value" = "0000000000000000" ] \
        || fail "${capability_field} retains capabilities: ${capability_value}"
done

[ ! -e /etc/sudoers.d/node-firewall ] || fail "firewall sudo rule remains enabled"
[ -e /etc/sudoers.d/node-firewall.disabled ] || fail "disabled firewall sudo marker is missing"

if sudo -n /usr/local/bin/init-firewall.sh --check-runtime-capabilities >/dev/null 2>&1; then
    fail "firewall sudo permission remained available after bootstrap"
fi

if timeout 3 dig +tries=1 +time=1 @8.8.8.8 A example.com >/dev/null 2>&1; then
    fail "managed task reached an arbitrary DNS resolver"
fi
