#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

TASK_AGENT_MODEL_EGRESS_ENABLED=false
TASK_AGENT_MODEL_EGRESS_HOST=""
TASK_AGENT_MODEL_EGRESS_PORT=""
CLI_SANDBOX_HOST_NETWORK_ENABLED=false
CLI_SANDBOX_HOST_NETWORK=""
CLI_SANDBOX_EGRESS_PROFILE_VALUE=""

firewall_error() {
    echo "ERROR: $*" >&2
}

configure_egress_profile() {
    local profile="${CLI_SANDBOX_EGRESS_PROFILE:-managed}"

    case "$profile" in
        managed|interactive)
            CLI_SANDBOX_EGRESS_PROFILE_VALUE="$profile"
            ;;
        *)
            firewall_error "CLI_SANDBOX_EGRESS_PROFILE must be exactly managed or interactive"
            return 1
            ;;
    esac
}

configure_ipv6_firewall() {
    # Managed destinations are intentionally IPv4-only. Apply the IPv6 policy
    # before any untrusted process starts so an IPv6-enabled Docker network
    # cannot become a parallel fail-open egress path.
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
    ip6tables -F
    ip6tables -X
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
}

valid_ipv4() {
    local address="$1"
    local -a octets
    local octet

    [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$address"
    [ "${#octets[@]}" -eq 4 ] || return 1
    for octet in "${octets[@]}"; do
        # Avoid inet_aton-style octal ambiguity and keep ipset input canonical.
        [[ "$octet" == "0" || "$octet" != 0* ]] || return 1
        ((10#${octet} <= 255)) || return 1
    done
}

# Model gateways must never resolve to local, link-local (including the cloud
# metadata service), multicast, or reserved broadcast destinations.
safe_model_gateway_ipv4() {
    local address="$1"
    local first second _

    valid_ipv4 "$address" || return 1
    IFS='.' read -r first second _ <<< "$address"
    ((10#${first} != 0)) || return 1
    ((10#${first} != 127)) || return 1
    ! ((10#${first} == 169 && 10#${second} == 254)) || return 1
    ((10#${first} < 224)) || return 1
}

valid_dns_name() {
    local hostname="$1"
    local -a labels
    local label

    [ "${#hostname}" -le 253 ] || return 1
    [[ "$hostname" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "$hostname" != .* && "$hostname" != *. && "$hostname" != *..* ]] || return 1
    IFS='.' read -r -a labels <<< "$hostname"
    [ "${#labels[@]}" -gt 0 ] || return 1
    for label in "${labels[@]}"; do
        [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

parse_task_agent_model_base_url() {
    local base_url="$1"
    local remainder authority host port

    TASK_AGENT_MODEL_EGRESS_HOST=""
    TASK_AGENT_MODEL_EGRESS_PORT=""

    if [[ "$base_url" =~ [[:space:]\\?#] ]]; then
        firewall_error "TASK_AGENT_MODEL_BASE_URL must not contain whitespace, backslashes, a query, or a fragment"
        return 1
    fi
    case "$base_url" in
        http://*)
            remainder="${base_url#http://}"
            port=80
            ;;
        https://*)
            remainder="${base_url#https://}"
            port=443
            ;;
        *)
            firewall_error "TASK_AGENT_MODEL_BASE_URL must use http:// or https://"
            return 1
            ;;
    esac

    authority="${remainder%%/*}"
    if [ -z "$authority" ] || [[ "$authority" == *"@"* ]]; then
        firewall_error "TASK_AGENT_MODEL_BASE_URL must contain a host and must not contain userinfo"
        return 1
    fi
    # The image currently programs an IPv4 ipset. Reject IPv6 and ambiguous
    # multi-colon authorities instead of accidentally widening the rule.
    if [[ "$authority" == *:* ]]; then
        if [[ "${authority#*:}" == *:* ]]; then
            firewall_error "TASK_AGENT_MODEL_BASE_URL does not support IPv6 or multi-colon authorities"
            return 1
        fi
        host="${authority%%:*}"
        port="${authority##*:}"
        if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || ((10#${port} < 1 || 10#${port} > 65535)); then
            firewall_error "TASK_AGENT_MODEL_BASE_URL contains an invalid port"
            return 1
        fi
        port="$((10#${port}))"
    else
        host="$authority"
    fi

    if [[ "$host" =~ ^[0-9.]+$ ]]; then
        if ! safe_model_gateway_ipv4 "$host"; then
            firewall_error "TASK_AGENT_MODEL_BASE_URL contains an invalid or unsafe IPv4 destination"
            return 1
        fi
    elif ! valid_dns_name "$host"; then
        firewall_error "TASK_AGENT_MODEL_BASE_URL contains an invalid DNS hostname"
        return 1
    fi

    TASK_AGENT_MODEL_EGRESS_HOST="${host,,}"
    TASK_AGENT_MODEL_EGRESS_PORT="$port"
}

resolve_model_gateway_ipv4() {
    local hostname="$1"

    dig +noall +answer A "$hostname" | awk '$4 == "A" {print $5}' | sort -u
}

configure_task_agent_model_egress() {
    local base_url="${TASK_AGENT_MODEL_BASE_URL:-}"
    local resolved_output address
    local -a addresses

    TASK_AGENT_MODEL_EGRESS_ENABLED=false
    [ -n "$base_url" ] || return 0
    parse_task_agent_model_base_url "$base_url" || return 1

    if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "managed" ] \
        && ! valid_ipv4 "$TASK_AGENT_MODEL_EGRESS_HOST"; then
        firewall_error "TASK_AGENT_MODEL_BASE_URL must use a literal IPv4 address in the managed egress profile"
        return 1
    fi

    if valid_ipv4 "$TASK_AGENT_MODEL_EGRESS_HOST"; then
        addresses=("$TASK_AGENT_MODEL_EGRESS_HOST")
    else
        if ! resolved_output="$(resolve_model_gateway_ipv4 "$TASK_AGENT_MODEL_EGRESS_HOST")"; then
            firewall_error "Failed to resolve TASK_AGENT_MODEL_BASE_URL host"
            return 1
        fi
        mapfile -t addresses <<< "$resolved_output"
        if [ "${#addresses[@]}" -eq 0 ] || [ -z "${addresses[0]}" ]; then
            firewall_error "TASK_AGENT_MODEL_BASE_URL host did not resolve to an IPv4 address"
            return 1
        fi
        if [ "${#addresses[@]}" -gt 32 ]; then
            firewall_error "TASK_AGENT_MODEL_BASE_URL host resolved to too many IPv4 addresses"
            return 1
        fi
    fi

    for address in "${addresses[@]}"; do
        if ! safe_model_gateway_ipv4 "$address"; then
            firewall_error "TASK_AGENT_MODEL_BASE_URL resolved to an invalid or unsafe IPv4 destination"
            return 1
        fi
    done

    for address in "${addresses[@]}"; do
        echo "Allowing Task Agent model gateway ${address}/32 on TCP port ${TASK_AGENT_MODEL_EGRESS_PORT}"
        ipset add task-agent-model "$address"
    done
    TASK_AGENT_MODEL_EGRESS_ENABLED=true
}

validate_managed_model_gateway() {
    if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "managed" ] \
        && [ "$TASK_AGENT_MODEL_EGRESS_ENABLED" != "true" ]; then
        firewall_error "TASK_AGENT_MODEL_BASE_URL is required for the managed egress profile"
        return 1
    fi
}

check_runtime_capabilities() {
    local check_set="cli-sandbox-cap-check"
    local check_chain="CLI_SANDBOX_CAP_CHECK"

    if [ "$(id -u)" -ne 0 ]; then
        firewall_error "firewall initialization must run as root through the constrained sudo rule"
        return 1
    fi
    # Listing requires NET_ADMIN. Installing the ipset-backed rule exercises
    # the NET_RAW requirement used by the real firewall configuration.
    iptables -L -n >/dev/null
    ip6tables -L -n >/dev/null
    ipset create "$check_set" hash:ip
    iptables -N "$check_chain"
    iptables -A "$check_chain" -m set --match-set "$check_set" dst -j RETURN
    iptables -F "$check_chain"
    iptables -X "$check_chain"
    ipset destroy "$check_set"
}

install_task_agent_model_egress_rule() {
    if [ "$TASK_AGENT_MODEL_EGRESS_ENABLED" = "true" ]; then
        iptables -A OUTPUT -p tcp --dport "$TASK_AGENT_MODEL_EGRESS_PORT" -m set --match-set task-agent-model dst -j ACCEPT
    fi
}

configure_host_network_access() {
    local allow_host_network="${CLI_SANDBOX_ALLOW_HOST_NETWORK:-}"
    local host_ip

    CLI_SANDBOX_HOST_NETWORK_ENABLED=false
    CLI_SANDBOX_HOST_NETWORK=""
    case "$allow_host_network" in
        ""|false)
            return 0
            ;;
        true)
            if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" != "interactive" ]; then
                firewall_error "CLI_SANDBOX_ALLOW_HOST_NETWORK=true is forbidden for the managed egress profile"
                return 1
            fi
            ;;
        *)
            firewall_error "CLI_SANDBOX_ALLOW_HOST_NETWORK must be exactly true, false, or unset"
            return 1
            ;;
    esac

    host_ip="$(ip -4 route show default | awk '$1 == "default" && $2 == "via" { print $3; exit }')"
    if ! valid_ipv4 "$host_ip"; then
        firewall_error "Failed to detect a valid Docker host gateway IPv4 address"
        return 1
    fi

    CLI_SANDBOX_HOST_NETWORK="${host_ip%.*}.0/24"
    CLI_SANDBOX_HOST_NETWORK_ENABLED=true
}

install_host_network_access_rules() {
    if [ "$CLI_SANDBOX_HOST_NETWORK_ENABLED" = "true" ]; then
        echo "WARNING: Allowing access to Docker host network ${CLI_SANDBOX_HOST_NETWORK}"
        iptables -A INPUT -s "$CLI_SANDBOX_HOST_NETWORK" -j ACCEPT
        iptables -A OUTPUT -d "$CLI_SANDBOX_HOST_NETWORK" -j ACCEPT
    fi
}

revoke_firewall_sudo_reentry() {
    local sudoers_file="/etc/sudoers.d/node-firewall"

    if [ -e "$sudoers_file" ]; then
        # The agent only needs privilege for entrypoint bootstrap. Moving this
        # file to a name ignored by @includedir prevents a later task command
        # from rerunning the script with a different destination.
        mv "$sudoers_file" "${sudoers_file}.disabled"
    fi
}

main() {
if [ "${1:-}" = "--check-runtime-capabilities" ]; then
    check_runtime_capabilities
    return
fi

if [ "$(id -u)" -ne 0 ]; then
    firewall_error "firewall initialization must run as root through the constrained sudo rule"
    return 1
fi
configure_egress_profile
configure_ipv6_firewall

DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy general 2>/dev/null || true
ipset destroy google-all-ips 2>/dev/null || true
ipset destroy google-customer-ips 2>/dev/null || true
ipset destroy task-agent-model 2>/dev/null || true

if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "interactive" ] && [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "Docker runtime DNS is disabled"
fi

if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "interactive" ]; then
    # Interactive mode preserves live DNS for direct-provider CLI workflows.
    # Managed Task Agent runs never install these rules.
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -j ACCEPT
else
    # Docker's embedded resolver is reached over loopback and may be DNATed to
    # a high local port before the filter table. Reject its address explicitly,
    # then reject direct TCP/UDP DNS before the general loopback allowance.
    iptables -A OUTPUT -d 127.0.0.11 -j REJECT --reject-with icmp-port-unreachable
    iptables -A OUTPUT -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable
    iptables -A OUTPUT -p tcp --dport 53 -j REJECT --reject-with tcp-reset
fi
# Interactive GitHub SSH is admitted later through provider-published ranges.
# Never open TCP/22 globally: that would provide an unrestricted exfiltration
# path to any SSH server on the internet.
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create task-agent-model hash:ip
if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "interactive" ]; then
    ipset create general hash:net
    ipset create google-all-ips hash:net
    ipset create google-customer-ips hash:net
fi

# Managed mode accepts only the operator-provisioned literal PSC IPv4. The
# interactive profile may resolve a DNS hostname once for convenience.
configure_task_agent_model_egress
validate_managed_model_gateway
configure_host_network_access

if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "interactive" ]; then
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi
echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add general "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

for domain in \
    "api.anthropic.com" \
    "api.openai.com" \
    "auth.openai.com" \
    "chatgpt.com" \
    "generativelanguage.googleapis.com" \
    "googleapis.l.google.com" \
    "vuln.go.dev"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add general "$ip" || continue
    done < <(echo "$ips")
done

echo "Fetching gcloud customer IPs."
cloud_ips=$(curl -s https://www.gstatic.com/ipranges/cloud.json)
if [ -z "$cloud_ips" ]; then
    echo "ERROR: Failed to fetch Google Cloud Customer IPs"
    exit 1
fi
CLOUD_NETBLOCKS=$(echo "$cloud_ips" | jq -r '.prefixes[] | select(.ipv4Prefix) | .ipv4Prefix' | aggregate -q)
if [ -z "$CLOUD_NETBLOCKS" ]; then
    echo "ERROR: No IPv4 prefixes found in cloud.json"
    exit 1
fi
while read -r cidr; do
    echo "Blocking Google range $cidr"
    ipset add google-customer-ips "$cidr" 2>/dev/null || true
done < <(echo "$CLOUD_NETBLOCKS")

echo "Fetching all gcloud IPs."
goog_ips=$(curl -s https://www.gstatic.com/ipranges/goog.json)
if [ -z "$goog_ips" ]; then
    echo "ERROR: Failed to fetch Google All IPs"
    exit 1
fi
echo "Populating goog-all-ips ipset..."
GOOG_NETBLOCKS=$(echo "$goog_ips" | jq -r '.prefixes[] | select(.ipv4Prefix) | .ipv4Prefix' | aggregate -q)
if [ -z "$GOOG_NETBLOCKS" ]; then
    echo "ERROR: No IPv4 prefixes found in goog.json"
    exit 1
fi
while read -r cidr; do
    echo "Adding Google range $cidr"
    ipset add google-all-ips "$cidr" 2>/dev/null || true
done < <(echo "$GOOG_NETBLOCKS")
fi


install_host_network_access_rules
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# The managed profile installs only this exact IPv4 destination and TCP port.
# Interactive mode additionally installs its legacy service-network rules below.
install_task_agent_model_egress_rule
if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "interactive" ]; then
    # Preserve the original direct-provider convenience only after an operator
    # explicitly selects the non-managed profile.
    iptables -A OUTPUT -m set --match-set general dst -j ACCEPT
    iptables -A OUTPUT -m set --match-set google-customer-ips dst -j REJECT --reject-with icmp-admin-prohibited
    iptables -A OUTPUT -m set --match-set google-all-ips dst -j ACCEPT
fi

iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 --max-time 10 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
fi
echo "Firewall verification passed - unable to reach https://example.com as expected"

if [ "$CLI_SANDBOX_EGRESS_PROFILE_VALUE" = "interactive" ]; then
    if ! curl --connect-timeout 5 --max-time 10 https://api.github.com/zen >/dev/null 2>&1; then
        echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
        exit 1
    fi
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

revoke_firewall_sudo_reentry
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
