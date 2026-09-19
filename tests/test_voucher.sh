#!/bin/bash
# Regression tests for voucher creation and redemption.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
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

log_error() { :; }
log_success() { :; }
log_warn() { :; }
log_info() { :; }
reload_proxy_config() { return 0; }
get_public_ip() { echo 127.0.0.1; }

cat > "$SECRETS_FILE" <<'SECRETS'
existing|0123456789abcdef0123456789abcdef|0|true|0|0|0|0||
SECRETS

echo "Voucher tests"

voucher_create 1 50G 30 >/dev/null
code=$(cut -d'|' -f1 "$VOUCHERS_FILE")
[[ "$code" =~ ^MTP-[0-9A-F]{8}-[0-9A-F]{8}$ ]]
assert_eq "generated code has stable format" 0 "$?"

voucher_redeem "$code" tg_123 >/dev/null
assert_eq "new voucher redemption succeeds" 0 "$?"
assert_eq "existing users are preserved" 1 "$(grep -c '^existing|' "$SECRETS_FILE")"
assert_eq "new user is created" 1 "$(grep -c '^tg_123|' "$SECRETS_FILE")"
assert_eq "voucher is consumed after account creation" REDEEMED "$(cut -d'|' -f7 "$VOUCHERS_FILE")"
assert_eq "voucher records its account" tg_123 "$(cut -d'|' -f9 "$VOUCHERS_FILE")"

voucher_redeem "$code" tg_123 >/dev/null
assert_eq "the original owner can retry idempotently" 0 "$?"
assert_eq "owner retry does not duplicate the user" 1 "$(grep -c '^tg_123|' "$SECRETS_FILE")"

voucher_redeem "$code" tg_456 >/dev/null
assert_eq "a consumed voucher cannot be reused" 1 "$?"
assert_eq "failed reuse creates no user" 0 "$(grep -c '^tg_456|' "$SECRETS_FILE")"

# Repair the exact partial state produced by v1.4.1: the voucher says REDEEMED
# for an account that was never created because secret_add got wrong arguments.
repair_code="MTP-DEADBEEF-CAFEBABE"
echo "$repair_code|1073741824|30|15|5|standard|REDEEMED|old|tg_789|old" >> "$VOUCHERS_FILE"
voucher_redeem "$repair_code" tg_789 >/dev/null
assert_eq "legacy interrupted redemption is repaired" 0 "$?"
assert_eq "repair creates the originally assigned account" 1 "$(grep -c '^tg_789|' "$SECRETS_FILE")"

voucher_redeem "$repair_code" tg_790 >/dev/null
assert_eq "legacy recovery cannot transfer a voucher" 1 "$?"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
