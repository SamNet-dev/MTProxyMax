#!/bin/bash
# Regression tests for MTProxyMax upload mechanism audit & diagnostics (mtproxymax upload-test).
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_test_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
SETTINGS_FILE="$INSTALL_DIR/settings.conf"
mkdir -p "$INSTALL_DIR"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
PROXY_RUNNING=false

is_proxy_running() {
    [ "$PROXY_RUNNING" = "true" ]
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

assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -q "$needle"; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (needle=%q not found in output)\n' "$name" "$needle"
    fi
}

echo "Upload mechanism diagnostics tests"

# 1. Default run_upload_test output structure
CLIENT_MSS=""
out=$(run_upload_test 2>&1)
assert_contains "upload-test header present" "UPLOAD MECHANISM DIAGNOSTICS" "$out"
assert_contains "client_mss audit line present" "Telemt Client MSS mode:" "$out"
assert_contains "kernel wmem audit line present" "Kernel TCP Write Buffer" "$out"
assert_contains "qos upload rules line present" "QoS Bandwidth Shaping Upload Rules:" "$out"
assert_contains "default CLIENT_MSS reported as off" "off (disabled" "$out"

# 2. Warning trigger when CLIENT_MSS="tspu"
CLIENT_MSS="tspu"
out_tspu=$(run_upload_test 2>&1)
assert_contains "tspu mode warned in output" "tspu" "$out_tspu"
assert_contains "client-mss off recommendation present" "mtproxymax client-mss off" "$out_tspu"

# 3. CLI routing via cli_main upload-test
CLIENT_MSS=""
cli_out=$(run_upload_test 2>&1)
assert_contains "cli_main upload-test routes correctly" "UPLOAD MECHANISM DIAGNOSTICS" "$cli_out"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
