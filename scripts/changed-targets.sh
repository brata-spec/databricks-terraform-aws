#!/usr/bin/env bash
# Work out which targets a change touches.
#
#   scripts/changed-targets.sh --base <git-ref> [--env dev|prod]
#   scripts/changed-targets.sh --all [--env dev|prod] [--team <team>]
#
# Prints (and appends to $GITHUB_OUTPUT when set):
#   account=true|false
#   targets=[{"team":"de","env":"dev"}, ...]
#
# Rules:
#   modules/**, workspace-level/_template/**, scripts/tf.sh  -> every team/env
#   account-level/**                                         -> account
#   workspace-level/<team>/<env>.tfvars                      -> that team/env
#   .github/workflows/**, scripts/changed-targets.sh         -> account + every team/env
#   bootstrap/**, docs                                       -> nothing (bootstrap is applied by hand)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE=""; ALL=false; ENV_FILTER=""; TEAM_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    --env) ENV_FILTER="$2"; shift 2 ;;
    --team) TEAM_FILTER="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ "$TEAM_FILTER" == all ]] && TEAM_FILTER=""

all_targets() {
  for f in workspace-level/*/*.tfvars; do
    local team env
    team="$(basename "$(dirname "$f")")"; env="$(basename "$f" .tfvars)"
    [[ "$team" == _* ]] && continue
    [[ "$env" == dev || "$env" == prod ]] || continue
    echo "$team $env"
  done
}

account=false
declare -A picked=()

if $ALL; then
  account=true
  while read -r t e; do picked["$t $e"]=1; done < <(all_targets)
else
  [[ -n "$BASE" ]] || { echo "need --base or --all" >&2; exit 2; }
  # New branch / first push: no usable base -> treat as everything
  if [[ "$BASE" =~ ^0+$ ]] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
    account=true
    while read -r t e; do picked["$t $e"]=1; done < <(all_targets)
  else
    while read -r path; do
      case "$path" in
        modules/* | workspace-level/_template/* | scripts/tf.sh)
          while read -r t e; do picked["$t $e"]=1; done < <(all_targets) ;;
        .github/workflows/* | .github/actions/* | scripts/changed-targets.sh)
          account=true
          while read -r t e; do picked["$t $e"]=1; done < <(all_targets) ;;
        account-level/*)
          account=true ;;
        workspace-level/*/*.tfvars)
          t="$(basename "$(dirname "$path")")"; e="$(basename "$path" .tfvars)"
          # only if the file still exists (deleting a team is a manual destroy)
          [[ "$t" != _* && ( "$e" == dev || "$e" == prod ) && -f "$path" ]] && picked["$t $e"]=1 ;;
      esac
    done < <(git diff --name-only "$BASE" HEAD)
  fi
fi

json="["; sep=""
for k in $(printf '%s\n' "${!picked[@]}" | tr ' ' ':' | sort); do
  t="${k%%:*}"; e="${k##*:}"
  [[ -n "$ENV_FILTER" && "$e" != "$ENV_FILTER" ]] && continue
  [[ -n "$TEAM_FILTER" && "$t" != "$TEAM_FILTER" ]] && continue
  json+="$sep{\"team\":\"$t\",\"env\":\"$e\"}"; sep=","
done
json+="]"

echo "account=$account"
echo "targets=$json"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  { echo "account=$account"; echo "targets=$json"; } >>"$GITHUB_OUTPUT"
fi
