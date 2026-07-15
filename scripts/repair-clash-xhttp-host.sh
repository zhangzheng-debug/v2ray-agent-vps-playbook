#!/usr/bin/env bash
set -Eeuo pipefail

edge_host="${1:-${EDGE_HOST:-}}"
direct_host="${2:-${DIRECT_HOST:-}}"
agent_root="${3:-${V2RAY_AGENT_ROOT:-/etc/v2ray-agent}}"

if [[ -z "$edge_host" || -z "$direct_host" ]]; then
  printf 'Usage: %s <proxied-edge-host> <direct-host-or-ip> [v2ray-agent-root]\n' "$0" >&2
  exit 2
fi
if [[ ! "$edge_host" =~ ^[A-Za-z0-9.-]+$ || ! "$direct_host" =~ ^[A-Za-z0-9.:-]+$ ]]; then
  printf 'Invalid host value.\n' >&2
  exit 2
fi
if [[ ! -d "$agent_root" ]]; then
  printf 'v2ray-agent root not found.\n' >&2
  exit 2
fi
if ! command -v perl >/dev/null 2>&1; then
  printf 'perl is required for a block-scoped YAML replacement.\n' >&2
  exit 2
fi

mapfile -d '' files < <(
  find "$agent_root/subscribe/clashMeta" "$agent_root/subscribe_local/clashMeta" \
    -type f -size -2M -print0 2>/dev/null || true
)

targets=()
for file in "${files[@]}"; do
  if grep -q 'VLESS_Reality_XHTTP' "$file" && grep -q "server:[[:space:]]*$edge_host" "$file"; then
    targets+=("$file")
  fi
done

if (( ${#targets[@]} == 0 )); then
  printf 'repair_status=no_risky_rendered_clash_files\n'
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_root="$agent_root/playbook-backups/clash-subscriptions-$timestamp"
mkdir -p "$backup_root"

replacements=0
for file in "${targets[@]}"; do
  relative="${file#"$agent_root"/}"
  mkdir -p "$backup_root/$(dirname "$relative")"
  cp -a "$file" "$backup_root/$relative"

  count="$(EDGE_HOST="$edge_host" DIRECT_HOST="$direct_host" perl -0pi -e '
    BEGIN { $count = 0 }
    $count += s{(^[[:space:]]*-[[:space:]]+name:[^\r\n]*VLESS_Reality_XHTTP[^\r\n]*\r?\n(?:(?!^[[:space:]]*-[[:space:]]+name:).)*?^[[:space:]]*server:[[:space:]]*)\Q$ENV{EDGE_HOST}\E}{$1$ENV{DIRECT_HOST}}gms;
    END { print $count }
  ' "$file")"
  replacements=$((replacements + count))
done

if (( replacements == 0 )); then
  printf 'repair_status=failed_no_replacement backup_created=true\n' >&2
  exit 1
fi

remaining=0
for file in "${targets[@]}"; do
  if EDGE_HOST="$edge_host" perl -0777 -ne '
    exit 1 if m{^[[:space:]]*-[[:space:]]+name:[^\r\n]*VLESS_Reality_XHTTP[^\r\n]*\r?\n(?:(?!^[[:space:]]*-[[:space:]]+name:).)*?^[[:space:]]*server:[[:space:]]*\Q$ENV{EDGE_HOST}\E}ms;
  ' "$file"; then
    :
  else
    remaining=$((remaining + 1))
  fi
done

if (( remaining > 0 )); then
  printf 'repair_status=failed_verification files_with_risk=%d\n' "$remaining" >&2
  exit 1
fi

printf 'repair_status=passed files=%d replacements=%d backup_created=true\n' "${#targets[@]}" "$replacements"
printf 'warning=rerun_after_each_v2ray_agent_subscription_regeneration\n'
