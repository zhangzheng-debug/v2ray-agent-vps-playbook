#!/usr/bin/env bash
set -Eeuo pipefail

domain="${1:-${DOMAIN:-}}"
token="${2:-${PROFILE_TOKEN:-}}"

if [[ -z "$domain" || -z "$token" ]]; then
  printf 'Usage: PROFILE_TOKEN=... %s <domain>\n' "$0" >&2
  exit 2
fi

if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
  printf 'Invalid domain.\n' >&2
  exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

printf 'domain=%s\n' "$domain"
if command -v getent >/dev/null 2>&1; then
  printf 'ipv4_addresses=' 
  getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true
  printf 'ipv6_addresses=' 
  getent ahostsv6 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true
fi

failures=0

check_endpoint() {
  local label="$1"
  local path="$2"
  local headers="$workdir/$label.headers"
  local body="$workdir/$label.body"
  local result status content_type bytes

  result="$(curl -sS --connect-timeout 10 --max-time 30 \
    -D "$headers" -o "$body" -w '%{http_code}|%{content_type}' \
    "https://$domain$path" || true)"
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
  if ! grep -Eq '^(proxies|proxy-groups|mixed-port|port):' "$body" 2>/dev/null; then
    printf 'FAIL %s: expected Clash YAML markers were not found.\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

check_endpoint profile "/s/clashMetaProfiles/$token"
check_endpoint provider "/s/clashMeta/$token"

if (( failures > 0 )); then
  printf 'endpoint_validation=failed count=%d\n' "$failures" >&2
  exit 1
fi

printf 'endpoint_validation=passed\n'
