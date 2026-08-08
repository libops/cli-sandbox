#!/usr/bin/env sh

set -eu

fail() {
    echo "runtime firewall assertion failed: $*" >&2
    exit 1
}

host_ip="$(ip -4 route show default | awk '$1 == "default" && $2 == "via" { print $3; exit }')"
host_network="${host_ip%.*}.0/24"

if /usr/sbin/iptables -C INPUT -s "$host_network" -j ACCEPT 2>/dev/null; then
    fail "managed startup installed a host-network INPUT rule"
fi
if /usr/sbin/iptables -C OUTPUT -d "$host_network" -j ACCEPT 2>/dev/null; then
    fail "managed startup installed a host-network OUTPUT rule"
fi
if /usr/sbin/iptables -C OUTPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
    fail "managed startup installed unrestricted outbound SSH"
fi
if /usr/sbin/iptables -C OUTPUT -p udp --dport 53 -j ACCEPT 2>/dev/null; then
    fail "managed startup installed unrestricted UDP DNS"
fi
if /usr/sbin/iptables -C OUTPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
    fail "managed startup installed unrestricted TCP DNS"
fi
/usr/sbin/iptables -C OUTPUT -d 127.0.0.11 -j REJECT --reject-with icmp-port-unreachable \
    || fail "managed startup did not reject Docker's embedded DNS resolver"
if /usr/sbin/iptables-save -t nat | grep -F '127.0.0.11' >/dev/null; then
    fail "managed startup restored Docker's embedded DNS NAT rules"
fi
if /usr/sbin/ipset list general >/dev/null 2>&1; then
    fail "managed startup created the broad general service ipset"
fi
if /usr/sbin/ipset list google-all-ips >/dev/null 2>&1; then
    fail "managed startup created the broad Google service ipset"
fi

/usr/sbin/ipset test task-agent-model 10.42.17.9 >/dev/null 2>&1 \
    || fail "model gateway address is absent from its ipset"
/usr/sbin/iptables -C OUTPUT -p tcp --dport 80 -m set --match-set task-agent-model dst -j ACCEPT \
    || fail "exact model gateway rule is absent"

/usr/sbin/ip6tables -S INPUT | grep -Fx -- '-P INPUT DROP' >/dev/null \
    || fail "IPv6 INPUT policy is not DROP"
/usr/sbin/ip6tables -S FORWARD | grep -Fx -- '-P FORWARD DROP' >/dev/null \
    || fail "IPv6 FORWARD policy is not DROP"
/usr/sbin/ip6tables -S OUTPUT | grep -Fx -- '-P OUTPUT DROP' >/dev/null \
    || fail "IPv6 OUTPUT policy is not DROP"
