#!/bin/bash
# Regression tests for secret CLI exit statuses used by Telegram command handlers.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] || \
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
    echo "SKIP: bash 4.2+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "$0")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

assert_status() {
    local name="$1" want="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" -eq "$want" ]; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (got=%s want=%s)\n' "$name" "$got" "$want"
    fi
}

echo "Secret command status tests"

audit_log "test short audit log"
assert_status "audit_log succeeds when rotation is not needed" 0 "$?"

# Isolate CLI dispatch from host state while exercising the production cli_main.
load_settings() { :; }
load_secrets() { :; }
check_root() { :; }
log_info() { :; }

SECRET_ADD_STATUS=0
TEMPLATE_APPLY_STATUS=0
SECRET_REMOVE_STATUS=0

secret_add() { return "$SECRET_ADD_STATUS"; }
template_apply() { return "$TEMPLATE_APPLY_STATUS"; }
secret_remove() { return "$SECRET_REMOVE_STATUS"; }

cli_main secret add alice
assert_status "secret add without template reports success" 0 "$?"

cli_main secret add alice --template standard
assert_status "secret add with successful template reports success" 0 "$?"

TEMPLATE_APPLY_STATUS=1
cli_main secret add alice --template missing
assert_status "secret add propagates template failure" 1 "$?"
TEMPLATE_APPLY_STATUS=0

SECRET_ADD_STATUS=1
cli_main secret add duplicate
assert_status "secret add propagates creation failure" 1 "$?"
SECRET_ADD_STATUS=0

cli_main secret remove alice
assert_status "secret remove reports success" 0 "$?"

SECRET_REMOVE_STATUS=1
cli_main secret remove missing
assert_status "secret remove propagates removal failure" 1 "$?"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
