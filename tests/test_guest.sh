#!/bin/bash
# Regression tests for disposable guest access creation.
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

assert_status() {
    assert_eq "$1" "$2" "$3"
}

# Exercise the production load_secrets function. Its read variables previously
# clobbered run_guest's local `label` through Bash dynamic scoping.
cat > "$SECRETS_FILE" <<'SECRETS'
# existing data
existing|0123456789abcdef0123456789abcdef|0|true|0|0|0|0||
SECRETS

load_settings() { :; }
check_root() { :; }
log_info() { :; }
log_success() { :; }
log_error() { :; }

CAPTURED_LABEL=""
CAPTURED_QUOTA=""
CAPTURED_EXPIRY=""
CAPTURED_NOTE=""
RELOADS=0

secret_add() {
    CAPTURED_LABEL="$1"
    return 0
}

secret_set_limits() {
    CAPTURED_LABEL="$1"
    CAPTURED_QUOTA="$4"
    CAPTURED_EXPIRY="$5"
    return 0
}

secret_edit_note() {
    CAPTURED_LABEL="$1"
    CAPTURED_NOTE="$2"
    return 0
}

reload_proxy_config() {
    RELOADS=$((RELOADS + 1))
    return 0
}

echo "Guest access tests"

run_guest trial24 24h
status=$?
assert_status "24h guest creation succeeds" 0 "$status"
assert_eq "label survives load_secrets" "trial24" "$CAPTURED_LABEL"
assert_eq "24h guest has no quota" "0" "$CAPTURED_QUOTA"
[[ "$CAPTURED_EXPIRY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
assert_status "24h guest gets RFC 3339 expiry" 0 "$?"
assert_eq "24h guest note is recorded" "🔥 Burner link (24h)" "$CAPTURED_NOTE"
assert_eq "configuration reloads once" "1" "$RELOADS"

CAPTURED_QUOTA=""
CAPTURED_EXPIRY=""
CAPTURED_NOTE=""
RELOADS=0

run_guest trial1g 1gb
status=$?
assert_status "quota guest creation succeeds" 0 "$status"
assert_eq "quota label survives load_secrets" "trial1g" "$CAPTURED_LABEL"
assert_eq "1gb is converted to bytes" "1073741824" "$CAPTURED_QUOTA"
assert_eq "quota-only guest has no expiry" "" "$CAPTURED_EXPIRY"
assert_eq "quota guest note is recorded" "🔥 Burner link (1gb)" "$CAPTURED_NOTE"
assert_eq "quota configuration reloads once" "1" "$RELOADS"

run_guest trial invalid
assert_status "invalid guest limit is rejected" 1 "$?"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
