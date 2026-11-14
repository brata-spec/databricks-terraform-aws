#!/usr/bin/env bash
# Run Terraform for one target, in dependency order.
#
#   scripts/tf.sh <plan|apply> account
#   scripts/tf.sh <plan|apply> <team> <env> [workspace|config|all]   (default: all)
#
#   account          -> account-level/                 state: account-level/terraform.tfstate
#   <team> <env>     -> workspace-level/_template/workspace  state: workspace/<team>/<env>/terraform.tfstate
#                    -> workspace-level/_template/config     state: workspace-config/<team>/<env>/terraform.tfstate
#   values           -> workspace-level/<team>/<env>.tfvars
#
# Needs: TF_STATE_BUCKET, AWS_REGION, AWS credentials, DATABRICKS_CLIENT_ID/SECRET,
#        TF_VAR_databricks_account_id, TF_VAR_deployer_client_id.
# Plan text goes to $OUT_DIR/<name>.txt for the PR comment.
set -euo pipefail

usage() { echo "usage: tf.sh <plan|apply> account | <team> <env> [workspace|config|all]" >&2; exit 2; }

ACTION="${1:-}"; TARGET="${2:-}"; ENVIRONMENT="${3:-}"; LAYER="${4:-all}"
[[ "$ACTION" == plan || "$ACTION" == apply ]] || usage
[[ -n "$TARGET" ]] || usage

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/.plans}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is not set}"
: "${AWS_REGION:?AWS_REGION is not set}"
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
export TF_IN_AUTOMATION=1
mkdir -p "$OUT_DIR"

state_exists() {
  aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$1" >/dev/null 2>&1
}

# run <name> <dir> <state-key> <var-file> [prerequisite-state-key]
run() {
  local name="$1" dir="$2" key="$3" varfile="$4" needs="${5:-}"
  local out="$OUT_DIR/$name.txt"
  # One .terraform dir per run: the _template roots are shared by every team.
  export TF_DATA_DIR="$ROOT/.terraform-data/$name"

  echo "::group::terraform $ACTION $name"

  if [[ -n "$needs" ]] && ! state_exists "$needs"; then
    if [[ "$ACTION" == plan ]]; then
      echo "Skipped: '$needs' does not exist yet. It is created when the earlier layer is applied." | tee "$out"
      echo "::endgroup::"
      return 0
    fi
    echo "Missing prerequisite state '$needs'. Apply the earlier layer first." >&2
    exit 1
  fi

  terraform -chdir="$dir" init -input=false -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="key=$key" \
    -backend-config="region=$AWS_REGION"

  if [[ "$ACTION" == plan ]]; then
    local rc=0 planfile="$TF_DATA_DIR/tfplan"
    terraform -chdir="$dir" plan -input=false -no-color -lock-timeout=5m \
      -detailed-exitcode -var-file="$varfile" -out="$planfile" 2>&1 | tee "$out.log" || rc=$?
    if [[ $rc -eq 1 ]]; then
      { echo "Plan failed:"; tail -n 60 "$out.log"; } >"$out"
      echo "::endgroup::"
      exit 1
    fi
    terraform -chdir="$dir" show -no-color "$planfile" >"$out"
    rm -f "$out.log"
  else
    terraform -chdir="$dir" apply -input=false -auto-approve -lock-timeout=5m -var-file="$varfile"
    terraform -chdir="$dir" output
  fi

  echo "::endgroup::"
}

if [[ "$TARGET" == account ]]; then
  run "account" "$ROOT/account-level" "account-level/terraform.tfstate" "$ROOT/account-level/account.tfvars"
  exit 0
fi

TEAM="$TARGET"
[[ "$ENVIRONMENT" == dev || "$ENVIRONMENT" == prod ]] || usage
[[ "$TEAM" =~ ^[a-z][a-z0-9]{1,14}$ ]] || { echo "bad team name '$TEAM'" >&2; exit 2; }
VARFILE="$ROOT/workspace-level/$TEAM/$ENVIRONMENT.tfvars"
[[ -f "$VARFILE" ]] || { echo "no such file: workspace-level/$TEAM/$ENVIRONMENT.tfvars" >&2; exit 2; }
TPL="$ROOT/workspace-level/_template"

case "$LAYER" in
  workspace | all)
    run "workspace-$TEAM-$ENVIRONMENT" "$TPL/workspace" "workspace/$TEAM/$ENVIRONMENT/terraform.tfstate" \
      "$VARFILE" "account-level/terraform.tfstate"
    ;;&
  config | all)
    run "config-$TEAM-$ENVIRONMENT" "$TPL/config" "workspace-config/$TEAM/$ENVIRONMENT/terraform.tfstate" \
      "$VARFILE" "workspace/$TEAM/$ENVIRONMENT/terraform.tfstate"
    ;;
  workspace | config | all) ;;
  *) usage ;;
esac
