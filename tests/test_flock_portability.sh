#!/bin/bash
# Regression tests for lock acquisition on hosts whose flock is busybox's applet.
#
# busybox ships a `flock` that has no -w option. Because it is present on PATH,
# `command -v flock` succeeds and the "flock is unavailable, skip locking" guard never
# fires — but `flock -w 5 9` itself fails. On Alpine that made every traffic reset abort
# with a misleading "Could not acquire traffic lock" message, and made two save paths
# report success while writing nothing at all.
#
# The busybox behaviour is reproduced with a stub on PATH rather than by requiring an
# Alpine host, so this regression test runs on every platform in the CI matrix.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_flock_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"

# A flock that behaves like busybox's: it accepts -n/-s/-x/-u but rejects -w outright.
# FAKE_FLOCK_HOLD=1 additionally makes every acquire fail, to exercise the other branch.
FAKEBIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/flock" <<'FLOCK_EOF'
#!/bin/bash
for _a in "$@"; do
    case "$_a" in
    -w*) echo "flock: unrecognized option: w" >&2; exit 1 ;;
    esac
done
[ "${FAKE_FLOCK_HOLD:-0}" = "1" ] && exit 1
exit 0
FLOCK_EOF
chmod +x "$FAKEBIN/flock"
PATH="$FAKEBIN:$PATH"
export PATH

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
LAST_ERROR=""

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

check_root() { :; }
load_settings() { :; }
reload_proxy_config() { :; }
log_info() { :; }
log_success() { :; }
log_error() { LAST_ERROR="$*"; }
audit_log() { :; }

SECRETS_LABELS=(alice)
SECRETS_ENABLED=(true)

METRICS='# HELP test test
telemt_user_octets_from_client{user="alice"} 120
telemt_user_octets_to_client{user="alice"} 340'

_fetch_metrics() { printf '%s\n' "$METRICS"; }
curl() { printf '%s\n' "$METRICS"; }

echo "flock portability tests"

# The stub must really be the flock that resolves, or the test proves nothing.
assert_eq "busybox-style flock is the one on PATH" "$FAKEBIN/flock" "$(command -v flock)"

# --- a busybox flock must not prevent the lock from being taken -----------------
printf 'alice|1000|2000\n' >"$STATS_DIR/user_traffic"
printf 'alice|10|20\n' >"$STATS_DIR/user_traffic_snapshot"

secret_reset_traffic alice no_reload
assert_eq "traffic reset succeeds despite flock lacking -w" "0" "$?"
assert_eq "reset work actually happened" "present" \
    "$([ -f "$STATS_DIR/.traffic_reset_pending" ] && echo present || echo absent)"

# --- an unavailable lock must fail loudly, never silently succeed ---------------
# Both save paths used to `return 0` here, reporting success while writing nothing.
FAKE_FLOCK_HOLD=1
export FAKE_FLOCK_HOLD
printf 'alice|1000|2000\n' >"$STATS_DIR/user_traffic"
rm -f "$STATS_DIR/.traffic_reset_pending"

secret_reset_traffic alice no_reload
assert_eq "held lock makes the reset fail" "1" "$?"
assert_eq "held lock does not silently succeed" "absent" \
    "$([ -f "$STATS_DIR/.traffic_reset_pending" ] && echo present || echo absent)"

flush_traffic_to_disk
assert_eq "flush_traffic_to_disk fails when the lock is unavailable" "1" "$?"

unset FAKE_FLOCK_HOLD

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
