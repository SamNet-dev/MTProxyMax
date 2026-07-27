#!/bin/bash
# Regression tests for Telemt client_mss CLI commands and configuration generation.
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

echo "Telemt client_mss tests"

# 1. Default value test
assert_eq "out-of-the-box default CLIENT_MSS is empty" "" "$CLIENT_MSS"

# 2. Config generation when CLIENT_MSS is empty (off)
CLIENT_MSS=""
cfg=$(generate_telemt_config)
if echo "$cfg" | grep -q 'client_mss'; then
    assert_eq "client_mss omitted when off" "absent" "present"
else
    assert_eq "client_mss omitted when off" "absent" "absent"
fi

# 3. Config generation when CLIENT_MSS="tspu"
CLIENT_MSS="tspu"
cfg=$(generate_telemt_config)
if echo "$cfg" | grep -q 'client_mss = "tspu"'; then
    assert_eq "client_mss emitted when set to tspu" "present" "present"
else
    assert_eq "client_mss emitted when set to tspu" "present" "absent"
fi

# 4. run_client_mss status output
CLIENT_MSS=""
status_out=$(run_client_mss status)
if echo "$status_out" | grep -q 'off / disabled'; then
    assert_eq "status reports off mode" "present" "present"
else
    assert_eq "status reports off mode" "present" "absent"
fi

# 5. run_client_mss tspu command
run_client_mss tspu < /dev/null >/dev/null
assert_eq "run_client_mss tspu sets CLIENT_MSS" "tspu" "$CLIENT_MSS"
load_settings
assert_eq "CLIENT_MSS=tspu persisted in settings.conf" "tspu" "$CLIENT_MSS"

# 6. run_client_mss off command
run_client_mss off < /dev/null >/dev/null
assert_eq "run_client_mss off clears CLIENT_MSS" "" "$CLIENT_MSS"
load_settings
assert_eq "CLIENT_MSS='' persisted in settings.conf" "" "$CLIENT_MSS"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
