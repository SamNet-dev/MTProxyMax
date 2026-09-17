#!/bin/bash
# Regression tests for init-system detection and autostart reporting.
#
# detect_init_system() tested for the presence of the `systemctl` *binary*, not for systemd
# actually running as PID 1. In a chroot, in a container that pulled systemd in as a
# dependency, or on a half-booted host, it reported "systemd" — and the systemd branch of
# setup_autostart() then ran `systemctl daemon-reload` and `systemctl enable` with no
# status check and printed "Auto-start enabled (systemd)" regardless. The user was told
# autostart was enabled when nothing had been enabled.
#
# The OpenRC branch directly below it already verifies (openrc_enable_service checks that
# the runlevel symlink landed) and returns 1 with a warning. These tests assert the
# systemd branch behaves the same way.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_init_XXXXXX')

# A systemctl whose behaviour is driven by the environment, so both "not booted" and
# "booted but enable fails" can be reproduced without a real init system.
FAKEBIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/systemctl" <<'SYSTEMCTL_EOF'
#!/bin/bash
case "${1:-}" in
is-system-running)
    echo "${FAKE_SYSTEMD_STATE:-offline}"
    [ "${FAKE_SYSTEMD_STATE:-offline}" = "offline" ] && exit 1
    exit 0
    ;;
is-enabled)
    echo "${FAKE_IS_ENABLED:-disabled}"
    [ "${FAKE_IS_ENABLED:-disabled}" = "enabled" ] && exit 0
    exit 1
    ;;
enable) exit "${FAKE_ENABLE_RC:-0}" ;;
*) exit 0 ;;
esac
SYSTEMCTL_EOF
chmod +x "$FAKEBIN/systemctl"
PATH="$FAKEBIN:$PATH"
export PATH

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e

# setup_autostart writes to ${SYSTEMD_DIR}; keep it inside the sandbox.
SYSTEMD_DIR="$TEST_TMPDIR/systemd"
mkdir -p "$SYSTEMD_DIR"

# Real systemd installs have this directory; its absence is how a not-booted host looks.
RUNDIR=/run/systemd/system
RUNDIR_PREEXISTED=0
[ -d "$RUNDIR" ] && RUNDIR_PREEXISTED=1

cleanup() {
    [ "$RUNDIR_PREEXISTED" -eq 0 ] && rmdir "$RUNDIR" 2>/dev/null
    rmdir /run/systemd 2>/dev/null
    rm -rf "$TEST_TMPDIR"
}
trap cleanup EXIT

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

assert_ne() {
    local name="$1" unwanted="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" != "$unwanted" ]; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s (unexpectedly %q)\n' "$name" "$got"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

LOG_SUCCESS=""
LOG_WARN=""
log_success() { LOG_SUCCESS="$*"; }
log_warn() { LOG_WARN="$*"; }
log_info() { :; }
log_error() { :; }

echo "init detection tests"

# The stub must be the systemctl that resolves, or none of this proves anything.
assert_eq "stub systemctl is on PATH" "$FAKEBIN/systemctl" "$(command -v systemctl)"
assert_eq "no OpenRC present to fall back to" "absent" \
    "$([ -x /sbin/openrc-run ] || command -v rc-service >/dev/null 2>&1 && echo present || echo absent)"

# --- systemctl exists but systemd is not running ---------------------------------
# This is the chroot / container / half-booted case.
rm -rf "$RUNDIR"
export FAKE_SYSTEMD_STATE=offline

assert_ne "binary present but not booted is not detected as systemd" "systemd" "$(detect_init_system)"

LOG_SUCCESS=""
LOG_WARN=""
setup_autostart >/dev/null 2>&1
assert_ne "setup_autostart does not report success" "0" "$?"
assert_eq "no success message is printed" "" "$LOG_SUCCESS"
assert_ne "a warning is printed instead" "" "$LOG_WARN"

# --- systemd running, but enabling the unit fails ---------------------------------
# The unit file is still written; what must not happen is reporting success.
mkdir -p "$RUNDIR"
export FAKE_SYSTEMD_STATE=running
export FAKE_ENABLE_RC=1
export FAKE_IS_ENABLED=disabled

assert_eq "booted systemd is detected" "systemd" "$(detect_init_system)"

LOG_SUCCESS=""
LOG_WARN=""
setup_autostart >/dev/null 2>&1
assert_ne "a failed enable does not report success" "0" "$?"
assert_eq "no success message on a failed enable" "" "$LOG_SUCCESS"

# --- and the happy path must still work -------------------------------------------
FAKE_ENABLE_RC=0
FAKE_IS_ENABLED=enabled
export FAKE_ENABLE_RC FAKE_IS_ENABLED

LOG_SUCCESS=""
LOG_WARN=""
setup_autostart >/dev/null 2>&1
assert_eq "a working enable reports success" "0" "$?"
assert_ne "success message is printed when it really succeeded" "" "$LOG_SUCCESS"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
