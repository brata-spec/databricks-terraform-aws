#!/usr/bin/env bash
# Markdown summary of saved plans, for $GITHUB_STEP_SUMMARY and approvers.
#   scripts/plan-summary.sh <plans-dir> [<title>]
# Prints one row per layer (<name>.txt) found anywhere under <plans-dir>.
set -euo pipefail
DIR="${1:?usage: plan-summary.sh <plans-dir> [title]}"; TITLE="${2:-Terraform plan}"

echo "### $TITLE"
echo
echo "| Layer | Result |"
echo "|---|---|"
found=false
while IFS= read -r f; do
  found=true
  name="$(basename "$f" .txt)"
  line="$(grep -m1 -E '^(Plan: |No changes\.|Skipped: |Plan failed)' "$f" || echo "see job log")"
  line="${line//|/\\|}"
  echo "| \`$name\` | $line |"
done < <(find "$DIR" -name '*.txt' | sort)
$found || echo "| - | no plans |"
echo
