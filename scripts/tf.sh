#!/usr/bin/env bash
# Run Terraform for one target, layer by layer, in dependency order.
#
#   scripts/tf.sh plan        account | <team> <env> [workspace|config|all]
#   scripts/tf.sh apply-saved account | <team> <env> [workspace|config|all]
#   scripts/tf.sh apply       account | <team> <env> [workspace|config|all]   (plan+apply in one go; local use)
#
#   plan         saves  $OUT_DIR/<name>.tfplan  + .txt (readable) + .lock.hcl + a status marker:
#                <name>.changes | <name>.nochanges | <name>.skipped (earlier layer not applied yet)
#   apply-saved  applies exactly the saved plan (prod: what the approver saw).
#                .nochanges -> nothing to do; .skipped -> the earlier layer now exists, so plan+apply now.
#
#   <name> = account | workspace-<team>-<env> | config-<team>-<env>
#
# Env: TF_STATE_BUCKET, AWS_REGION, AWS creds, DATABRICKS_CLIENT_ID/SECRET, TF_VAR_databricks_account_id,
#      TF_VAR_deployer_client_id. Optional: OUT_DIR (default .plans), TF_LOCK=false for speculative PR plans.
set -euo pipefail

usage() { echo "usage: tf.sh <plan|apply-saved|apply> account | <team> <env> [workspace|config|all]" >&2; exit 2; }

ACTION="${1:-}"; TARGET="${2:-}"; ENVIRONMENT="${3:-}"; LAYER="${4:-all}"
case "$ACTION" in plan | apply-saved | apply) ;; *) usage ;; esac
[[ -n "$TARGET" ]] || usage

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$(mkdir -p "${OUT_DIR:-$ROOT/.plans}" && cd "${OUT_DIR:-$ROOT/.plans}" && pwd)"
LOCK="${TF_LOCK:-true}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is not set}"
: "${AWS_REGION:?AWS_REGION is not set}"
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
export TF_IN_AUTOMATION=1

state_exists() { aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$1" >/dev/null 2>&1; }

init() { # init <name> <dir> <key>
  # One .terraform dir per target: the _template roots are shared by every team.
  export TF_DATA_DIR="$ROOT/.terraform-data/$1"
  terraform -chdir="$2" init -input=false -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="key=$3" \
    -backend-config="region=$AWS_REGION"
}

# layer <name> <dir> <state-key> <var-file> [prerequisite-state-key]
layer() {
  local name="$1" dir="$2" key="$3" varfile="$4" needs="${5:-}"
  local base="$OUT_DIR/$name"
  echo "::group::terraform $ACTION $name"

  case "$ACTION" in
    plan)
      rm -f "$base".{tfplan,txt,changes,nochanges,skipped,lock.hcl}
      if [[ -n "$needs" ]] && ! state_exists "$needs"; then
        echo "Skipped: '$needs' does not exist yet; this layer is planned when the earlier one is applied." | tee "$base.txt"
        touch "$base.skipped"
        echo "::endgroup::"; return 0
      fi
      init "$name" "$dir" "$key"
      local rc=0
      terraform -chdir="$dir" plan -input=false -no-color -lock="$LOCK" -lock-timeout=5m \
        -detailed-exitcode -var-file="$varfile" -out="$base.tfplan" 2>&1 | tee "$base.log" || rc=$?
      case $rc in
        0) touch "$base.nochanges" ;;
        2) touch "$base.changes" ;;
        *) { echo "Plan failed:"; tail -n 60 "$base.log"; } >"$base.txt"; echo "::endgroup::"; exit 1 ;;
      esac
      terraform -chdir="$dir" show -no-color "$base.tfplan" >"$base.txt"
      cp "$dir/.terraform.lock.hcl" "$base.lock.hcl" 2>/dev/null || true
      rm -f "$base.log"
      ;;

    apply-saved)
      if [[ -f "$base.nochanges" ]]; then
        echo "No changes in the saved plan for $name."
      elif [[ -f "$base.tfplan" ]]; then
        # same provider versions as at plan time
        [[ -f "$base.lock.hcl" ]] && cp "$base.lock.hcl" "$dir/.terraform.lock.hcl"
        init "$name" "$dir" "$key"
        terraform -chdir="$dir" apply -input=false -lock-timeout=5m "$base.tfplan"
        terraform -chdir="$dir" output
      elif [[ -f "$base.skipped" ]]; then
        [[ -z "$needs" ]] || state_exists "$needs" || { echo "Prerequisite '$needs' still missing." >&2; exit 1; }
        echo "No saved plan: '$needs' did not exist at plan time. Planning and applying $name now."
        init "$name" "$dir" "$key"
        terraform -chdir="$dir" apply -input=false -auto-approve -lock-timeout=5m -var-file="$varfile"
        terraform -chdir="$dir" output
      else
        echo "No saved plan for $name in $OUT_DIR. Run 'tf.sh plan' first." >&2; exit 1
      fi
      ;;

    apply)
      if [[ -n "$needs" ]] && ! state_exists "$needs"; then
        echo "Missing prerequisite state '$needs'. Apply the earlier layer first." >&2; exit 1
      fi
      init "$name" "$dir" "$key"
      terraform -chdir="$dir" apply -input=false -auto-approve -lock-timeout=5m -var-file="$varfile"
      terraform -chdir="$dir" output
      ;;
  esac
  echo "::endgroup::"
}

if [[ "$TARGET" == account ]]; then
  layer "account" "$ROOT/account-level" "account-level/terraform.tfstate" "$ROOT/account-level/account.tfvars"
  exit 0
fi

TEAM="$TARGET"
[[ "$ENVIRONMENT" == dev || "$ENVIRONMENT" == prod ]] || usage
[[ "$TEAM" =~ ^[a-z][a-z0-9]{1,14}$ ]] || { echo "bad team name '$TEAM'" >&2; exit 2; }
VARFILE="$ROOT/workspace-level/$TEAM/$ENVIRONMENT.tfvars"
[[ -f "$VARFILE" ]] || { echo "no such file: workspace-level/$TEAM/$ENVIRONMENT.tfvars" >&2; exit 2; }
TPL="$ROOT/workspace-level/_template"

case "$LAYER" in workspace | config | all) ;; *) usage ;; esac
if [[ "$LAYER" == workspace || "$LAYER" == all ]]; then
  layer "workspace-$TEAM-$ENVIRONMENT" "$TPL/workspace" "workspace/$TEAM/$ENVIRONMENT/terraform.tfstate" \
    "$VARFILE" "account-level/terraform.tfstate"
fi
if [[ "$LAYER" == config || "$LAYER" == all ]]; then
  # In 'plan', config is planned against the CURRENT workspace state. If the workspace plan
  # has changes that config depends on, config shows them on the next run.
  layer "config-$TEAM-$ENVIRONMENT" "$TPL/config" "workspace-config/$TEAM/$ENVIRONMENT/terraform.tfstate" \
    "$VARFILE" "workspace/$TEAM/$ENVIRONMENT/terraform.tfstate"
fi
