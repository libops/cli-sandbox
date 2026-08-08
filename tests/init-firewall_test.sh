#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2329

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../init-firewall.sh
source "${REPOSITORY_ROOT}/init-firewall.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equal() {
    local want="$1"
    local got="$2"
    local message="$3"
    [ "$got" = "$want" ] || fail "${message}: got '${got}', want '${want}'"
}

assert_rejected() {
    local value="$1"
    if parse_task_agent_model_base_url "$value" >/dev/null 2>&1; then
        fail "unsafe model URL was accepted: ${value}"
    fi
}

record_call() {
    local joined

    printf -v joined '%s ' "$@"
    calls+=("${joined% }")
}

test_psc_ipv4_allowance() {
    local -a calls=()

    ipset() {
        record_call "$@"
    }

    TASK_AGENT_MODEL_BASE_URL="http://10.42.17.9/v1"
    configure_task_agent_model_egress

    assert_equal "true" "$TASK_AGENT_MODEL_EGRESS_ENABLED" "PSC model egress state"
    assert_equal "10.42.17.9" "$TASK_AGENT_MODEL_EGRESS_HOST" "PSC model host"
    assert_equal "80" "$TASK_AGENT_MODEL_EGRESS_PORT" "PSC model port"
    assert_equal "1" "${#calls[@]}" "PSC ipset call count"
    assert_equal "add task-agent-model 10.42.17.9" "${calls[0]}" "PSC ipset entry"

    calls=()
    iptables() {
        record_call "$@"
    }
    install_task_agent_model_egress_rule
    assert_equal "1" "${#calls[@]}" "PSC firewall call count"
    assert_equal "-A OUTPUT -p tcp --dport 80 -m set --match-set task-agent-model dst -j ACCEPT" "${calls[0]}" "PSC firewall rule"
}

test_dns_allowance_is_exact() {
    local -a calls=()

    resolve_model_gateway_ipv4() {
        assert_equal "models.internal.example" "$1" "DNS lookup host" >&2
        printf '%s\n' "10.60.0.12" "10.60.0.13"
    }
    ipset() {
        record_call "$@"
    }

    TASK_AGENT_MODEL_BASE_URL="https://models.internal.example:8443/v1"
    configure_task_agent_model_egress

    assert_equal "8443" "$TASK_AGENT_MODEL_EGRESS_PORT" "DNS model port"
    assert_equal "2" "${#calls[@]}" "DNS ipset call count"
    assert_equal "add task-agent-model 10.60.0.12" "${calls[0]}" "first DNS ipset entry"
    assert_equal "add task-agent-model 10.60.0.13" "${calls[1]}" "second DNS ipset entry"
}

test_dns_rejects_unsafe_answers() {
    resolve_model_gateway_ipv4() {
        printf '%s\n' "10.60.0.12" "169.254.169.254"
    }
    ipset() { :; }

    TASK_AGENT_MODEL_BASE_URL="https://models.internal.example/v1"
    if configure_task_agent_model_egress >/dev/null 2>&1; then
        fail "DNS result containing the metadata IP was accepted"
    fi
}

test_invalid_urls() {
    local value
    local -a invalid=(
        ""
        "ftp://10.42.17.9/v1"
        "HTTP://10.42.17.9/v1"
        "http://user@10.42.17.9/v1"
        "http://user:pass@10.42.17.9/v1"
        "http://10.42.17.9:0/v1"
        "http://10.42.17.9:65536/v1"
        "http://10.42.17.9:not-a-port/v1"
        "http://10.42.17.9:80:90/v1"
        "http://[fd00::1]/v1"
        "http://999.42.17.9/v1"
        "http://010.42.17.9/v1"
        "http://127.0.0.1/v1"
        "http://169.254.169.254/v1"
        "http://224.0.0.1/v1"
        "http://models..example/v1"
        "http://models.example./v1"
        "http://-models.example/v1"
        "http://models.example-/v1"
        "http://models.example/v1?target=evil"
        "http://models.example/v1#evil"
        "http://models.example\\@evil/v1"
        $'http://models.example/\n/v1'
    )

    for value in "${invalid[@]}"; do
        assert_rejected "$value"
    done
}

test_empty_configuration_is_disabled() {
    TASK_AGENT_MODEL_BASE_URL=""
    TASK_AGENT_MODEL_EGRESS_ENABLED=true
    configure_task_agent_model_egress
    assert_equal "false" "$TASK_AGENT_MODEL_EGRESS_ENABLED" "empty model configuration"
}

test_host_network_is_default_denied() {
    local -a calls=()

    iptables() {
        record_call "$@"
    }

    CLI_SANDBOX_ALLOW_HOST_NETWORK=""
    configure_host_network_access
    install_host_network_access_rules
    assert_equal "false" "$CLI_SANDBOX_HOST_NETWORK_ENABLED" "unset host-network state"
    assert_equal "0" "${#calls[@]}" "unset host-network rule count"

    CLI_SANDBOX_ALLOW_HOST_NETWORK="false"
    configure_host_network_access
    install_host_network_access_rules
    assert_equal "false" "$CLI_SANDBOX_HOST_NETWORK_ENABLED" "false host-network state"
    assert_equal "0" "${#calls[@]}" "false host-network rule count"
}

test_host_network_explicit_opt_in() {
    local -a calls=()

    ip() {
        printf '%s\n' "default via 172.19.0.1 dev eth0"
    }
    iptables() {
        record_call "$@"
    }

    CLI_SANDBOX_ALLOW_HOST_NETWORK="true"
    configure_host_network_access
    install_host_network_access_rules

    assert_equal "true" "$CLI_SANDBOX_HOST_NETWORK_ENABLED" "enabled host-network state"
    assert_equal "172.19.0.0/24" "$CLI_SANDBOX_HOST_NETWORK" "enabled host network"
    assert_equal "2" "${#calls[@]}" "enabled host-network rule count"
    assert_equal "-A INPUT -s 172.19.0.0/24 -j ACCEPT" "${calls[0]}" "host-network input rule"
    assert_equal "-A OUTPUT -d 172.19.0.0/24 -j ACCEPT" "${calls[1]}" "host-network output rule"
}

test_host_network_rejects_ambiguous_values() {
    local value

    for value in "TRUE" "1" "yes" " true" "true "; do
        CLI_SANDBOX_ALLOW_HOST_NETWORK="$value"
        if configure_host_network_access >/dev/null 2>&1; then
            fail "ambiguous host-network opt-in was accepted: '${value}'"
        fi
    done
}

test_ssh_is_not_globally_allowed() {
    if grep -Eq 'iptables[[:space:]]+-A[[:space:]]+OUTPUT[[:space:]]+-p[[:space:]]+tcp[[:space:]]+--dport[[:space:]]+22[[:space:]]+-j[[:space:]]+ACCEPT' "${REPOSITORY_ROOT}/init-firewall.sh"; then
        fail "firewall globally allows outbound SSH instead of limiting it to provider IP ranges"
    fi
}

test_psc_ipv4_allowance
test_dns_allowance_is_exact
test_dns_rejects_unsafe_answers
test_invalid_urls
test_empty_configuration_is_disabled
test_host_network_is_default_denied
test_host_network_explicit_opt_in
test_host_network_rejects_ambiguous_values
test_ssh_is_not_globally_allowed

echo "init-firewall tests passed"
