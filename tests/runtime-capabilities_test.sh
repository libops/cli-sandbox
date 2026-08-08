#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <cli-sandbox-image>" >&2
    exit 2
fi

IMAGE="$1"
ALL_CAPABILITIES=(NET_ADMIN NET_RAW SETGID SETUID)

run_check() {
    local omitted="${1:-}"
    local -a args=(
        run --rm
        --cap-drop ALL
        --entrypoint sudo
    )
    local capability

    for capability in "${ALL_CAPABILITIES[@]}"; do
        if [ "$capability" != "$omitted" ]; then
            args+=(--cap-add "$capability")
        fi
    done
    args+=("$IMAGE" /usr/local/bin/init-firewall.sh --check-runtime-capabilities)
    docker "${args[@]}"
}

run_check

for capability in "${ALL_CAPABILITIES[@]}"; do
    if run_check "$capability" >/dev/null 2>&1; then
        echo "firewall capability check unexpectedly succeeded without ${capability}" >&2
        exit 1
    fi
done

full_run_args=(run --cap-drop ALL)
for capability in "${ALL_CAPABILITIES[@]}"; do
    full_run_args+=(--cap-add "$capability")
done

container_id=""
cleanup() {
    if [ -n "$container_id" ]; then
        docker rm -f "$container_id" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

container_id="$(docker "${full_run_args[@]}" \
    --detach \
    --env TASK_AGENT_MODEL_BASE_URL=http://10.42.17.9/v1 \
    "$IMAGE" \
    sh -euc 'touch /tmp/cli-sandbox-ready; exec sleep 300')"

ready=false
for _ in $(seq 1 180); do
    if docker exec "$container_id" test -e /tmp/cli-sandbox-ready 2>/dev/null; then
        ready=true
        break
    fi
    container_state="$(docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null || true)"
    if [ "$container_state" != "true" ]; then
        break
    fi
    sleep 1
done
if [ "$ready" != "true" ]; then
    docker logs "$container_id" >&2 || true
    echo "container did not complete firewall bootstrap" >&2
    exit 1
fi

docker exec "$container_id" sh -euc '
    test "$(id -u)" -ne 0
    test "$(awk '\''$1 == "CapEff:" { print $2 }'\'' /proc/self/status)" = 0000000000000000
    test ! -e /etc/sudoers.d/node-firewall
    test -e /etc/sudoers.d/node-firewall.disabled
    if sudo -n /usr/local/bin/init-firewall.sh --check-runtime-capabilities >/dev/null 2>&1; then
        echo "firewall sudo permission remained available after bootstrap" >&2
        exit 1
    fi
'

# Inspect the live namespace as root. The task process above remains the image's
# unprivileged node user; root is used here only by the external test harness.
docker exec --user root "$container_id" sh -euc '
    host_ip="$(ip -4 route show default | awk '\''$1 == "default" && $2 == "via" { print $3; exit }'\'')"
    host_network="${host_ip%.*}.0/24"
    if /usr/sbin/iptables -C INPUT -s "$host_network" -j ACCEPT 2>/dev/null; then
        echo "default startup installed a host-network INPUT rule" >&2
        exit 1
    fi
    if /usr/sbin/iptables -C OUTPUT -d "$host_network" -j ACCEPT 2>/dev/null; then
        echo "default startup installed a host-network OUTPUT rule" >&2
        exit 1
    fi
    if /usr/sbin/iptables -C OUTPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
        echo "default startup installed an unrestricted outbound SSH rule" >&2
        exit 1
    fi
    /usr/sbin/ipset test task-agent-model 10.42.17.9 >/dev/null 2>&1
    /usr/sbin/iptables -C OUTPUT -p tcp --dport 80 -m set --match-set task-agent-model dst -j ACCEPT
'

bootstrap_output="$(docker logs "$container_id" 2>&1)"
if ! grep -Fq "Allowing Task Agent model gateway 10.42.17.9/32 on TCP port 80" <<< "$bootstrap_output"; then
    echo "PSC model gateway was not added to the firewall" >&2
    exit 1
fi
if grep -Fq "Allowing access to Docker host network" <<< "$bootstrap_output"; then
    echo "default startup logged a host-network allowance" >&2
    exit 1
fi

cleanup
container_id=""

if docker "${full_run_args[@]}" \
    --rm \
    --env TASK_AGENT_MODEL_BASE_URL=http://169.254.169.254/v1 \
    "$IMAGE" true >/dev/null 2>&1; then
    echo "container started with the metadata service as its model gateway" >&2
    exit 1
fi

if docker "${full_run_args[@]}" \
    --rm \
    --env CLI_SANDBOX_ALLOW_HOST_NETWORK=TRUE \
    "$IMAGE" true >/dev/null 2>&1; then
    echo "container started with an ambiguous host-network opt-in" >&2
    exit 1
fi

echo "runtime capability tests passed"
