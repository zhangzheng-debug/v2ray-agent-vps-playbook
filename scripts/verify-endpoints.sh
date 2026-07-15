#!/usr/bin/env bash
set -Eeuo pipefail

domain="${1:-${DOMAIN:-}}"
token="${2:-${PROFILE_TOKEN:-}}"
edge_domain="${EDGE_DOMAIN:-$domain}"
direct_host="${DIRECT_HOST:-}"
allow_ipv6_profile="${ALLOW_IPV6_PROFILE:-false}"
profile_file="${PROFILE_FILE:-}"
provider_file="${PROVIDER_FILE:-}"
using_local_files=false

if [[ -n "$profile_file" || -n "$provider_file" ]]; then
  using_local_files=true
  if [[ -z "$profile_file" || -z "$provider_file" ]]; then
    printf 'Set both PROFILE_FILE and PROVIDER_FILE for local fixture validation.\n' >&2
    exit 2
  fi
fi

if [[ -z "$domain" || ( "$using_local_files" == "false" && -z "$token" ) ]]; then
  printf 'Usage: PROFILE_TOKEN=... %s <domain>\n' "$0" >&2
  exit 2
fi

if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ || ! "$edge_domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
  printf 'Invalid domain.\n' >&2
  exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

printf 'domain=%s\n' "$domain"
if [[ "$using_local_files" == "false" ]] && command -v getent >/dev/null 2>&1; then
  printf 'ipv4_addresses='
  getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true
  printf 'ipv6_addresses='
  getent ahostsv6 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true
fi

failures=0

check_endpoint() {
  local label="$1"
  local path="$2"
  local local_file="$3"
  local headers="$workdir/$label.headers"
  local body="$workdir/$label.body"
  local result status content_type bytes

  if [[ -n "$local_file" ]]; then
    cp "$local_file" "$body"
    : > "$headers"
    result='200|text/yaml; local-fixture'
  else
    result="$(curl -sS --connect-timeout 10 --max-time 30 \
      -D "$headers" -o "$body" -w '%{http_code}|%{content_type}' \
      "https://$domain$path" || true)"
  fi
  status="${result%%|*}"
  content_type="${result#*|}"
  bytes="$(wc -c < "$body" 2>/dev/null || printf '0')"

  printf '%s status=%s type=%s bytes=%s\n' "$label" "$status" "${content_type:-unknown}" "$bytes"

  if [[ "$status" != "200" ]]; then
    printf 'FAIL %s: expected HTTP 200.\n' "$label" >&2
    failures=$((failures + 1))
  fi
  if grep -Eiq '^cf-mitigated:[[:space:]]*challenge' "$headers" 2>/dev/null; then
    printf 'FAIL %s: Cloudflare challenge detected.\n' "$label" >&2
    failures=$((failures + 1))
  fi
  if grep -Eiq '<!doctype html|<html' "$body" 2>/dev/null; then
    printf 'FAIL %s: response is HTML, not YAML.\n' "$label" >&2
    failures=$((failures + 1))
  fi

  if [[ "$label" == "profile" ]]; then
    if ! grep -Eq '^mode:[[:space:]]*rule[[:space:]]*$' "$body" ||
      ! grep -Eq '^proxy-groups:' "$body" || ! grep -Eq '^rules:' "$body"; then
      printf 'FAIL profile: expected a full rule profile with proxy-groups and rules.\n' >&2
      failures=$((failures + 1))
    fi
    if [[ "$allow_ipv6_profile" != "true" ]] && grep -Eq '^ipv6:[[:space:]]*true[[:space:]]*$' "$body"; then
      printf 'FAIL profile: ipv6=true without ALLOW_IPV6_PROFILE=true.\n' >&2
      failures=$((failures + 1))
    fi
  else
    if ! grep -Eq '^proxies:' "$body" || grep -Eq '^proxy-groups:|^rules:' "$body"; then
      printf 'FAIL provider: expected only a proxy provider list.\n' >&2
      failures=$((failures + 1))
    fi
  fi
}

check_endpoint profile "/s/clashMetaProfiles/$token" "$profile_file"
check_endpoint provider "/s/clashMeta/$token" "$provider_file"

provider="$workdir/provider.body"
audit_result="$(awk -v edge="$edge_domain" -v direct="$direct_host" '
  function reset_block() {
    server=""; port=0; network="tcp"; reality=0; ws=0; nodes++
  }
  function finish_block() {
    if (nodes == 0) return
    if (reality) realities++
    if (ws) websockets++
    if (server == edge && reality) bad_reality_edge++
    if (server == edge && port != 443 && port != 2053 && port != 2083 && port != 2087 && port != 2096 && port != 8443) bad_edge_port++
    if (reality && direct != "" && server != direct) bad_direct_host++
  }
  /^  - name:/ { finish_block(); reset_block(); next }
  nodes > 0 && /^[[:space:]]+server:/ { server=$2; gsub(/["'\'' ]/, "", server) }
  nodes > 0 && /^[[:space:]]+port:/ { port=$2 + 0 }
  nodes > 0 && /^[[:space:]]+network:/ { network=$2; ws=(network == "ws") }
  nodes > 0 && /^[[:space:]]+reality-opts:/ { reality=1 }
  END {
    finish_block()
    printf "nodes=%d realities=%d websockets=%d bad_reality_edge=%d bad_edge_port=%d bad_direct_host=%d", nodes, realities, websockets, bad_reality_edge, bad_edge_port, bad_direct_host
    if (nodes < 2 || realities < 1 || websockets < 1 || bad_reality_edge || bad_edge_port || bad_direct_host) exit 1
  }
' "$provider")" || {
  printf 'FAIL node routing audit: %s\n' "$audit_result" >&2
  failures=$((failures + 1))
}
printf 'node_routing_audit %s\n' "$audit_result"

if (( failures > 0 )); then
  printf 'endpoint_validation=failed count=%d\n' "$failures" >&2
  exit 1
fi

printf 'endpoint_validation=passed\n'
