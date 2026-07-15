#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="$repo_root/tests/fixtures/full-profile-safe.yaml"
safe_provider="$repo_root/tests/fixtures/provider-safe.yaml"
risky_provider="$repo_root/tests/fixtures/provider-risky-edge-xhttp.yaml"

PROFILE_FILE="$profile" \
PROVIDER_FILE="$safe_provider" \
EDGE_DOMAIN='edge.example.com' \
DIRECT_HOST='direct.example.com' \
  "$repo_root/scripts/verify-endpoints.sh" 'edge.example.com'

if PROFILE_FILE="$profile" \
  PROVIDER_FILE="$risky_provider" \
  EDGE_DOMAIN='edge.example.com' \
  DIRECT_HOST='direct.example.com' \
  "$repo_root/scripts/verify-endpoints.sh" 'edge.example.com'; then
  printf 'Risky XHTTP fixture unexpectedly passed Bash verification.\n' >&2
  exit 1
fi

printf 'verify_endpoints_bash_tests=passed\n'
