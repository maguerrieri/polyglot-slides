#!/usr/bin/env bash
# Deploy preflight: prove the authenticated clasp session can drive the Apps
# Script API before anything is pushed, and name the fix when it cannot.
#
#   tools/preflight.sh
#
# Runs the read-only `clasp list-versions` (the same call #38 added inline in
# deploy.yml) and diagnoses its failure modes -- each has a different owner
# and a different fix, and the raw error points at the wrong one:
#
#   invalid_rapt              Google Workspace session control rejected the
#                             deploy account's refresh token (reauth policy).
#                             Fix: trusted-app exemption in the Admin console,
#                             not a new token (CLAUDE.md).
#   User has not enabled the  The deploying account never flipped the per-user
#   Apps Script API           toggle at script.google.com/home/usersettings.
#   anything else             Printed as-is.
#
# Only clasp's own stdout/stderr is ever printed. The credential file that
# clasp_config_auth points at is never read or echoed here.
set -uo pipefail

if ! command -v clasp >/dev/null 2>&1; then
  echo "error: clasp not found on PATH" >&2
  exit 1
fi

output="$(clasp list-versions 2>&1)"
status=$?

if [ "$status" -eq 0 ]; then
  echo "preflight ok: clasp list-versions succeeded"
  exit 0
fi

printf '%s\n' "$output"
echo

hint() { # hint <message>: the diagnosis, also as an Actions error annotation
  echo "preflight failed: $1" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::$1"
  fi
}

case "$output" in
  *invalid_rapt*)
    hint "Workspace session-control reauth rejected the deploy token (invalid_rapt). Re-minting CLASPRC_JSON only buys one session; the fix is the Admin-console trusted-app exemption for clasp's OAuth client -- see CLAUDE.md 'CI deploys authenticate as a user' and README > Release pipeline > One-time setup."
    ;;
  *"User has not enabled the Apps Script API"*)
    hint "The deploying account has not turned on the per-user Apps Script API toggle at https://script.google.com/home/usersettings (README > Release pipeline > One-time setup, step 1). Only that account can flip it."
    ;;
  *)
    hint "clasp list-versions exited $status; raw output above."
    ;;
esac
exit "$status"
