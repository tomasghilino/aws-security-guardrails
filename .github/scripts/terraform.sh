#!/usr/bin/env bash
# terraform.sh plan <stack>       plan one stack and check it with conftest
# terraform.sh apply <stack>...   the same, then apply what was checked, one stack after another
set -euo pipefail

mode=$1
shift

# terraform and conftest run in containers pinned by digest, with the job's aws credentials
tf() {
  local vars
  vars=$(env | grep -o '^TF_VAR_[a-z_]*' | sed 's/^/-e /' || true)
  # shellcheck disable=SC2086
  docker run --rm -v "$PWD:/work" -w "/work/infra/$stack" \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION \
    -e TF_IN_AUTOMATION=1 -e TF_INPUT=0 $vars \
    "$TERRAFORM_IMAGE" "$@"
}

# leaves the checked plan in ci.tfplan and sets changes to 0 for none, 2 for some
# (called on its own line: bash ignores set -e inside a function called from || or if)
plan() {
  changes=0
  tf init -lockfile=readonly -no-color
  tf plan -out=ci.tfplan -detailed-exitcode -no-color || changes=$?
  [ "$changes" -ne 1 ] || exit 1

  # the json holds account ids and emails, so it stays on the runner
  tf show -json ci.tfplan >"infra/$stack/plan.json"
  docker run --rm --network none -v "$PWD:/work" -w /work "$CONFTEST_IMAGE" \
    test --no-color --policy policy "infra/$stack/plan.json"

  summary=$(tf show -no-color ci.tfplan | grep -E '^(Plan:|No changes)' || true)
  echo "| $stack | ${summary:-no changes} |" >>"$GITHUB_STEP_SUMMARY"
}

echo "| stack | plan |" >>"$GITHUB_STEP_SUMMARY"
echo "| --- | --- |" >>"$GITHUB_STEP_SUMMARY"

for stack in "$@"; do
  echo "::group::$mode $stack"
  plan

  if [ "$changes" -eq 2 ] && [ "$mode" = apply ]; then
    tf apply -no-color ci.tfplan
  elif [ "$changes" -eq 2 ] && [ "${FAIL_ON_CHANGES:-false}" = true ]; then
    echo "::error::$stack has drifted from the code: something was changed outside terraform"
    exit 1
  fi
  echo "::endgroup::"
done
