#!/bin/bash
# Regression tests for date handling on hosts whose `date` is busybox's applet.
#
# `date -d` is GNU-only, `date -r <epoch>` is BSD-only (busybox's -r reads the timestamp
# of a *file*), and `date -v+1d` is BSD-only. On Alpine every one of those branches
# failed, so guest links, vouchers and onboarding silently produced an empty expiry — and
# the voucher fallback produced *now* rather than now+N days, i.e. a link that never
# expires.
#
# The busybox behaviour is reproduced with a stub on PATH so the regression is caught on
# every platform, not only on Alpine.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] || {
    [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]
}; then
    echo "SKIP: bash 4.2+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

REAL_DATE=$(command -v date)

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_date_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR"

# A date that behaves like busybox's. The distinction is precisely this: busybox `date`
# exists and formats fine, but it cannot do GNU relative arithmetic. So `-d "@epoch"` and
# `-d "+24 hours"` are rejected, while `-D FMT -d STRING` (busybox's own absolute-parse
# form, which _iso_to_epoch already uses) is accepted. `-r` and `-v` are rejected too —
# busybox has no epoch-reference form and no BSD-style relative form.
FAKEBIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKEBIN"
# Index-based, not shift-based: `shift` would consume "$@" and the delegation below
# would end up calling the real date with no arguments at all.
cat >"$FAKEBIN/date" <<DATE_EOF
#!/bin/bash
_args=("\$@")
_n=\${#_args[@]}
_i=0
while [ "\$_i" -lt "\$_n" ]; do
    case "\${_args[\$_i]}" in
    -d)
        _i=\$((_i + 1))
        case "\${_args[\$_i]:-}" in
        @* | +*)
            echo "date: invalid date '\${_args[\$_i]}'" >&2
            exit 1
            ;;
        esac
        ;;
    -r | -v*)
        echo "date: unsupported option '\${_args[\$_i]}'" >&2
        exit 1
        ;;
    esac
    _i=\$((_i + 1))
done
exec "$REAL_DATE" "\$@"
DATE_EOF
chmod +x "$FAKEBIN/date"
PATH="$FAKEBIN:$PATH"
export PATH

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
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
        printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_match() {
    local name="$1" pattern="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$got" =~ $pattern ]]; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s (got=%q does not match %s)\n' "$name" "$got" "$pattern"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

check_root() { :; }
load_settings() { :; }
load_secrets() { :; }
log_info() { :; }
log_success() { :; }
log_error() { :; }
secret_add() { return 0; }
secret_edit_note() { return 0; }
reload_proxy_config() { return 0; }

CAPTURED_EXPIRY=""
secret_set_limits() {
    CAPTURED_EXPIRY="$5"
    return 0
}

echo "date portability tests"

# The stub must really be the date that resolves, or the test proves nothing.
assert_eq "busybox-style date is the one on PATH" "$FAKEBIN/date" "$(command -v date)"
assert_eq "the stub still supports plain formatting" "$(date +%Y)" "$(command date +%Y)"

# --- expiry must be computed, not silently dropped ------------------------------
CAPTURED_EXPIRY=""
run_guest trial24 24h
assert_eq "24h guest creation succeeds despite date lacking -d" "0" "$?"
assert_match "24h guest gets an RFC 3339 expiry" \
    '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$CAPTURED_EXPIRY"

CAPTURED_EXPIRY=""
run_guest trial7d 7d
assert_eq "7d guest creation succeeds despite date lacking -d" "0" "$?"
assert_match "7d guest gets a date-only expiry" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CAPTURED_EXPIRY"

# Well-formed is not enough — the value must actually be in the future by the right
# amount. Compares against bash's own epoch arithmetic, not against `date`.
CAPTURED_EXPIRY=""
run_guest trial30d 30d
expected=$(TZ=UTC printf '%(%Y-%m-%d)T' "$(($(command date +%s) + 30 * 86400))")
assert_eq "30d expiry lands on the correct calendar day" "$expected" "$CAPTURED_EXPIRY"

# --- month length must not silently fall back to 31 -----------------------------
# The old code left last_day=31 whenever both date branches failed, so a monthly quota
# reset fired on the wrong day for every month shorter than 31 days.
assert_eq "_last_day_of_month 2026-02" "28" "$(_last_day_of_month 2026 2)"
assert_eq "_last_day_of_month 2024-02 (leap)" "29" "$(_last_day_of_month 2024 2)"
assert_eq "_last_day_of_month 2000-02 (400yr leap)" "29" "$(_last_day_of_month 2000 2)"
assert_eq "_last_day_of_month 1900-02 (not a leap year)" "28" "$(_last_day_of_month 1900 2)"
assert_eq "_last_day_of_month 2026-04" "30" "$(_last_day_of_month 2026 4)"
assert_eq "_last_day_of_month 2026-12" "31" "$(_last_day_of_month 2026 12)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
