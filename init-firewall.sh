#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy github-anthropic 2>/dev/null || true
ipset destroy google-all-ips 2>/dev/null || true
ipset destroy google-customer-ips 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create github-anthropic hash:net
ipset create google-all-ips hash:net
ipset create google-customer-ips hash:net

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
    ipset add github-anthropic "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

for domain in \
    "api.anthropic.com" \
    "generativelanguage.googleapis.com" \
    "googleapis.l.google.com"; do
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
        ipset add github-anthropic "$ip" || continue
    done < <(echo "$ips")
done

GOOGLE_CLOUD_CUSTOMER_IP_URL="https://www.gstatic.com/ipranges/cloud.json"
echo "Fetching gcloud customer IPs $GOOGLE_CLOUD_CUSTOMER_IP_URL."
cloud_ips=$(curl -s $GOOGLE_CLOUD_CUSTOMER_IP_URL)
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

# Get all IPs in Google Cloud
GOOGLE_ALL_IP_URL="https://www.gstatic.com/ipranges/goog.json"
echo "Fetching gcloud full ip ranges $GOOGLE_ALL_IP_URL."
goog_ips=$(curl -s $GOOGLE_ALL_IP_URL)
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


HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow GitHub and Anthropic
iptables -A OUTPUT -m set --match-set github-anthropic dst -j ACCEPT
# Block all Google Cloud customer IPs
# since this rule is after github-anthropic ACCEPT it shouldn't block any IPs in both sets
iptables -A OUTPUT -m set --match-set google-customer-ips dst -j REJECT --reject-with icmp-admin-prohibited
# Allow complement of All Google IPs and Customer Google Cloud IPs
# since this rule is after google-customer-ips REJECT it should allow
# IPs used by google not assigned to customers
iptables -A OUTPUT -m set --match-set google-all-ips dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
