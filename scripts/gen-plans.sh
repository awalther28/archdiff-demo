#!/usr/bin/env bash
# Generate offline plan JSON for both roots, for LOCAL inspection only.
#
# Output goes to plans/<ref>/{mgmt,prod}.plan.json. plans/ is gitignored and
# nothing in the repo consumes it: plan JSON is a build artifact, and CI
# (.github/workflows/archdiff-pr.yml via the archdiff analyze action) plans
# both sides of every pull request itself. This script exists so you can
# look at a plan, or feed two of them to scripts/effective_permissions.py,
# without waiting for CI.
#
# Runs with NO AWS account, NO state and NO network beyond the provider
# download on first init. Credentials are fake (the literal string "fake",
# both in the provider blocks and in the environment below); nothing
# credential-shaped is committed. Account identity is passed via -var
# account_id, never derived from a profile.
#
# Usage:
#   scripts/gen-plans.sh              plan the working tree
#                                     -> plans/<current-branch>/
#   scripts/gen-plans.sh REF [REF...] plan each committed ref, checked out
#                                     in a temporary worktree so the working
#                                     tree is untouched -> plans/<ref>/
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLANS="$REPO/plans"

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

# Share provider binaries between the two roots (and between worktrees).
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$REPO/.tofu-plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
export TF_IN_AUTOMATION=1

# plan_tree SRC LABEL: plan live/{mgmt,prod} under SRC into plans/LABEL/.
plan_tree() {
  local src="$1" label="$2" out="$PLANS/$2" root
  mkdir -p "$out"
  for root in mgmt prod; do
    echo "==> $label: $root (account $(account_for "$root")) -> plans/$label/$root.plan.json"
    (
      cd "$src/live/$root"
      tofu init -input=false -no-color >/dev/null
      tofu plan -refresh=false -input=false -no-color -out=tfplan \
        -var "account_id=$(account_for "$root")" >/dev/null
      tofu show -json tfplan > "$out/$root.plan.json"
      rm -f tfplan
    )
  done
}

WORKTREE=""
cleanup() {
  if [ -n "$WORKTREE" ]; then
    git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ $# -eq 0 ]; then
  plan_tree "$REPO" "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
else
  for ref in "$@"; do
    git -C "$REPO" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null \
      || { echo "not a commit: $ref" >&2; exit 1; }
    WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/gen-plans.XXXXXX")"
    git -C "$REPO" worktree add --quiet --detach "$WORKTREE" "$ref"
    plan_tree "$WORKTREE" "$ref"
    cleanup
    WORKTREE=""
  done
fi
echo "done. plans/ is gitignored; nothing here is meant to be committed."
