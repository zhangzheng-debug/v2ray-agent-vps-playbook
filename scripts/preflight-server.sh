#!/usr/bin/env bash
set -Eeuo pipefail

section() {
  printf '\n## %s\n' "$1"
}

run_if_present() {
  local command_name="$1"
  shift
  if command -v "$command_name" >/dev/null 2>&1; then
    "$@"
  else
    printf '%s: not installed\n' "$command_name"
  fi
}

section "Identity and operating system"
printf 'utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'euid=%s\n' "$EUID"
uname -a
if [[ -r /etc/os-release ]]; then
  grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release
fi

section "Resources"
run_if_present df df -h /
run_if_present free free -h
run_if_present timedatectl timedatectl show -p NTPSynchronized -p Timezone --value

section "Addresses and routes"
run_if_present ip ip -brief -4 address
run_if_present ip ip -brief -6 address
run_if_present ip ip -4 route
run_if_present ip ip -6 route

section "External connectivity"
if command -v curl >/dev/null 2>&1; then
  printf 'ipv4_https=' 
  curl -4 -sS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}\n' https://www.cloudflare.com/ || true
  printf 'ipv6_https=' 
  curl -6 -sS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}\n' https://www.cloudflare.com/ || true
else
  printf 'curl: not installed\n'
fi

section "Listening sockets"
run_if_present ss ss -lntup

section "Relevant services"
if command -v systemctl >/dev/null 2>&1; then
  for service in nginx apache2 caddy xray sing-box; do
    printf '%-12s active=%-8s enabled=%s\n' \
      "$service" \
      "$(systemctl is-active "$service" 2>/dev/null || true)" \
      "$(systemctl is-enabled "$service" 2>/dev/null || true)"
  done
else
  printf 'systemctl: not installed\n'
fi

section "Firewall summaries"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
fi
if command -v nft >/dev/null 2>&1; then
  nft list ruleset 2>/dev/null | sed -n '1,180p' || true
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -S 2>/dev/null || true
fi

section "Nginx and certificate tooling"
if command -v nginx >/dev/null 2>&1; then
  nginx -t || true
fi
for tool in openssl certbot acme.sh; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%s=%s\n' "$tool" "$(command -v "$tool")"
  fi
done

section "Warnings"
if [[ "$EUID" -ne 0 ]]; then
  printf 'WARN: run as root for a complete read-only report.\n'
fi
printf 'This script made no configuration changes. Review output before installation.\n'
