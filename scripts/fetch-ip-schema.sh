#!/usr/bin/env sh
# Materialise the real IP schema from Bitwarden Secrets Manager into the
# git-ignored file schema/ip-schema.yaml. Linux/macOS/WSL/Git Bash variant.
# Windows PowerShell variant: scripts/fetch-ip-schema.ps1
#
# Requires: `bws` on PATH and BWS_ACCESS_TOKEN set in the environment
# (the iac-deploy machine account token). The secret IP_SCHEMA_B64 holds the
# base64-encoded schema. The content is never printed.
set -eu

cd "$(dirname "$0")/.."
umask 077

command -v bws >/dev/null 2>&1 || { echo "error: bws not found on PATH" >&2; exit 1; }
[ -n "${BWS_ACCESS_TOKEN:-}" ] || { echo "error: BWS_ACCESS_TOKEN is not set" >&2; exit 1; }

BWS_OUT="$PWD/schema/ip-schema.yaml"
export BWS_OUT
trap 'rm -f "$BWS_OUT.tmp"' EXIT

# --shell sh keeps behaviour identical on Windows, where bws defaults to PowerShell.
if ! bws run --shell sh -- 'printf %s "$IP_SCHEMA_B64" | base64 -d > "$BWS_OUT.tmp"'; then
  echo "error: bws run failed (check token, project access and secret name IP_SCHEMA_B64)" >&2
  exit 1
fi

if ! grep -q '^schema_version:' "$BWS_OUT.tmp"; then
  echo "error: decoded file does not look like an IP schema (no schema_version)" >&2
  exit 1
fi

mv "$BWS_OUT.tmp" "$BWS_OUT"
echo "ok: wrote schema/ip-schema.yaml (git-ignored)"
