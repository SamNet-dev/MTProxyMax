#!/bin/bash
# Regression tests for atomic Settings changes that require a proxy restart.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e

TESTS_RUN=0
TESTS_FAILED=0
PROXY_RUNNING=true
LAST_INFO=""

is_proxy_running() {
    [ "$PROXY_RUNNING" = "true" ]
}

log_info() {
    LAST_INFO="$*"
}

assert_eq() {
    local name="$1" want="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" = "$want" ]; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"
    fi
}

apply_test_setting() {
    local candidate="$1"
    confirm_settings_restart "test=${candidate}" || return 0
    TEST_SETTING="$candidate"
    SAVE_COUNT=$((SAVE_COUNT + 1))
    RESTART_COUNT=$((RESTART_COUNT + 1))
}

echo "Settings restart confirmation tests"

TEST_SETTING="old"
SAVE_COUNT=0
LAST_INFO=""
if confirm_settings_change "test=new" <<< ""; then
    TEST_SETTING="new"
    SAVE_COUNT=$((SAVE_COUNT + 1))
fi
assert_eq "empty answer declines non-restart change" "old" "$TEST_SETTING"
assert_eq "declined non-restart change is not saved" 0 "$SAVE_COUNT"
assert_eq "non-restart decline reports cancellation" "Change cancelled; settings were not modified" "$LAST_INFO"

TEST_SETTING="old"
SAVE_COUNT=0
if confirm_settings_change "test=new" <<< "y"; then
    TEST_SETTING="new"
    SAVE_COUNT=$((SAVE_COUNT + 1))
fi
assert_eq "explicit yes accepts non-restart change" "new" "$TEST_SETTING"
assert_eq "accepted non-restart change is saved" 1 "$SAVE_COUNT"

TEST_SETTING="old"
SAVE_COUNT=0
RESTART_COUNT=0
LAST_INFO=""
apply_test_setting "new" <<< "n"
assert_eq "decline keeps in-memory value" "old" "$TEST_SETTING"
assert_eq "decline does not save" 0 "$SAVE_COUNT"
assert_eq "decline does not restart" 0 "$RESTART_COUNT"
assert_eq "decline reports cancellation" "Change cancelled; settings were not modified" "$LAST_INFO"

TEST_SETTING="old"
SAVE_COUNT=0
RESTART_COUNT=0
apply_test_setting "new" <<< "y"
assert_eq "accept changes value" "new" "$TEST_SETTING"
assert_eq "accept saves once" 1 "$SAVE_COUNT"
assert_eq "accept restarts once" 1 "$RESTART_COUNT"

TEST_SETTING="old"
SAVE_COUNT=0
RESTART_COUNT=0
apply_test_setting "new" <<< ""
assert_eq "empty answer accepts default" "new" "$TEST_SETTING"

PROXY_RUNNING=false
TEST_SETTING="old"
SAVE_COUNT=0
RESTART_COUNT=0
apply_test_setting "new" < /dev/null
assert_eq "stopped proxy applies without prompt" "new" "$TEST_SETTING"
assert_eq "stopped proxy saves once" 1 "$SAVE_COUNT"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
