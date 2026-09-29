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

# --- the generated daemon must carry its own copy of the lock helpers ------------
# The bot daemon is emitted from a single-quoted heredoc and never sources the
# manager, so every helper it calls has to be defined inside that heredoc. These two
# helpers were added only to the manager, which left the generated daemon calling an
# undefined _lock_fd: save_traffic() then returned 1 and persisted no counters at all.
# Everything above passes either way, because it exercises the manager, not the daemon.
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_FULL="$TEST_TMPDIR/daemon_full.sh"
awk "/<<[[:space:]]*'TELEGRAM_SCRIPT'/{f=1;next} /^TELEGRAM_SCRIPT\$/{f=0} f" \
    "$TEST_ROOT/mtproxymax.sh" >"$DAEMON_FULL"
assert_eq "generated daemon captured" "yes" \
    "$([ -s "$DAEMON_FULL" ] && echo yes || echo no)"

# Declarations and function bodies only: stop before the cleanup trap so that
# sourcing this cannot start the daemon's main loop.
DAEMON_PRELUDE="$TEST_TMPDIR/daemon_prelude.sh"
awk '/^trap /{exit} {print}' "$DAEMON_FULL" >"$DAEMON_PRELUDE"

assert_eq "daemon defines _lock_fd" "yes" \
    "$(grep -qE '^_lock_fd\(\)' "$DAEMON_FULL" && echo yes || echo no)"
assert_eq "daemon defines _flock_supports_wait" "yes" \
    "$(grep -qE '^_flock_supports_wait\(\)' "$DAEMON_FULL" && echo yes || echo no)"

# Exercise the daemon's own save_traffic(), not the manager's.
DAEMON_HARNESS="$TEST_TMPDIR/daemon_save_traffic.sh"
cat >"$DAEMON_HARNESS" <<'HARNESS_EOF'
#!/bin/bash
source "$2"
INSTALL_DIR="$1"
TRAFFIC_FILE="${INSTALL_DIR}/relay_stats/cumulative_traffic"
USER_TRAFFIC_FILE="${INSTALL_DIR}/relay_stats/user_traffic"
mkdir -p "${INSTALL_DIR}/relay_stats"
_cum_in=700; _cum_out=900
_cum_user_in=([alice]=11); _cum_user_out=([alice]=22)
_prev_user_in=([alice]=1); _prev_user_out=([alice]=2)
_prev_total_in=5; _prev_total_out=6
save_traffic
echo "rc=$?"
HARNESS_EOF

DAEMON_INSTALL="$TEST_TMPDIR/daemon_install"
daemon_run() {
    rm -rf "$DAEMON_INSTALL"
    bash "$DAEMON_HARNESS" "$DAEMON_INSTALL" "$DAEMON_PRELUDE" 2>&1
}
daemon_file() { cat "$DAEMON_INSTALL/relay_stats/$1" 2>/dev/null; }

# The daemon is the only writer of accounting in production, and this is the path
# that silently stopped persisting on every distro, not just Alpine.
_dout=$(daemon_run)
assert_eq "daemon save_traffic succeeds under busybox flock" "rc=0" \
    "$(printf '%s\n' "$_dout" | grep '^rc=')"
assert_eq "daemon wrote cumulative_traffic" "700|900" "$(daemon_file cumulative_traffic)"
assert_eq "daemon wrote user_traffic" "alice|11|22" "$(daemon_file user_traffic)"
assert_eq "daemon wrote user_traffic_snapshot" "alice|1|2" \
    "$(daemon_file user_traffic_snapshot)"
assert_eq "daemon wrote global_traffic_snapshot" "5|6" \
    "$(daemon_file global_traffic_snapshot)"

# A lock that is genuinely held must fail loudly rather than persist nothing.
FAKE_FLOCK_HOLD=1
export FAKE_FLOCK_HOLD
_dout=$(daemon_run)
assert_eq "daemon save_traffic fails when the lock is held" "rc=1" \
    "$(printf '%s\n' "$_dout" | grep '^rc=')"
assert_eq "daemon reports the failure on stderr" "yes" \
    "$(printf '%s\n' "$_dout" | grep -q 'traffic not saved' && echo yes || echo no)"
unset FAKE_FLOCK_HOLD

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
