#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

agent_root="$tmp/etc/v2ray-agent"
mkdir -p "$agent_root/subscribe/clashMeta" "$agent_root/subscribe_local/clashMeta"
cp "$repo_root/tests/fixtures/provider-risky-edge-xhttp.yaml" \
  "$agent_root/subscribe/clashMeta/provider.yaml"

"$repo_root/scripts/repair-clash-xhttp-host.sh" \
  'edge.example.com' 'direct.example.com' "$agent_root"

provider="$agent_root/subscribe/clashMeta/provider.yaml"
if ! grep -A10 'VLESS_Reality_XHTTP' "$provider" | grep -q 'server: direct.example.com'; then
  printf 'XHTTP host was not repaired.\n' >&2
  exit 1
fi
if ! grep -A4 'SG-vless-ws-tls' "$provider" | grep -q 'server: edge.example.com'; then
  printf 'WS edge host changed unexpectedly.\n' >&2
  exit 1
fi
if [[ ! -d "$agent_root/playbook-backups" ]]; then
  printf 'Backup directory was not created.\n' >&2
  exit 1
fi

printf 'repair_clash_xhttp_tests=passed\n'
