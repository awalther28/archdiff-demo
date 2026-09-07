#!/usr/bin/env bash
# Generate offline plan JSON for both roots and write them to
# plans/<branch>/{mgmt,prod}.plan.json.
#
# Runs with NO AWS account, NO state and NO network beyond the provider
# download on first init. Credentials are fake and live in a throwaway temp
# dir for the duration of the run; nothing credential-shaped is committed.
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

# --- fake, throwaway AWS profiles -----------------------------------------
AWS_TMP="$(mktemp -d)"
trap 'rm -rf "$AWS_TMP"' EXIT
for root in mgmt prod; do
  printf '[profile %s]\nregion = us-east-1\n\n' "$root" >> "$AWS_TMP/config"
  printf '[%s]\naws_access_key_id = fake\naws_secret_access_key = fake\n\n' "$root" >> "$AWS_TMP/credentials"
done
export AWS_CONFIG_FILE="$AWS_TMP/config"
export AWS_SHARED_CREDENTIALS_FILE="$AWS_TMP/credentials"
export AWS_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true
unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

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
