#!/usr/bin/env bash
# Generate offline plan JSON for both roots and write them to
# plans/<branch>/{mgmt,prod}.plan.json.
#
# Runs with NO AWS account, NO state and NO network beyond the provider
# download on first init. Credentials are fake (the literal string "fake",
# both in the provider blocks and in the environment below); nothing
# credential-shaped is committed. Account identity is passed via -var
# account_id, never derived from a profile.
#
# Usage: scripts/gen-plans.sh [branch-name]   (defaults to the current branch)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${1:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD)}"
OUT="$REPO/plans/$BRANCH"
mkdir -p "$OUT"

account_for() {
  case "$1" in
    mgmt) echo 999988887777 ;;
    prod) echo 111122223333 ;;
    *) echo "unknown root: $1" >&2; exit 1 ;;
  esac
}

# --- fake environment credentials ------------------------------------------
# The provider blocks already carry access_key/secret_key = "fake"; these
# env vars make the run self-contained regardless and keep the SDK away from
# ~/.aws, IMDS and any ambient profile.
export AWS_ACCESS_KEY_ID=fake
export AWS_SECRET_ACCESS_KEY=fake
export AWS_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true
unset AWS_PROFILE AWS_SESSION_TOKEN AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE

# Share provider binaries between the two roots.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$REPO/.tofu-plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
export TF_IN_AUTOMATION=1

for root in mgmt prod; do
  dir="$REPO/live/$root"
  echo "==> $root (account $(account_for "$root")) -> plans/$BRANCH/$root.plan.json"
  (
    cd "$dir"
    tofu init -input=false -no-color >/dev/null
    tofu plan -refresh=false -input=false -no-color -out=tfplan \
      -var "account_id=$(account_for "$root")" >/dev/null
    tofu show -json tfplan > "$OUT/$root.plan.json"
    rm -f tfplan
  )
done
echo "done."
