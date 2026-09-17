#!/bin/bash
# Integration test: setup_autostart() / main_service_remove() against a REAL systemd.
#
# tests/test_telegram_service_openrc.sh stubs systemctl and asserts that the right
# command *would* be run. This does the real thing instead: the unit file is written to
# the real /etc/systemd/system, systemd is really asked to enable it, and `systemctl
# start` really has to reach the ExecStart binary. A stubbed test cannot catch a unit
# file that systemd refuses to parse, or an ExecStart path that does not exist — which
# is exactly the class of bug this covers.
#
# Requires root (writes /etc/systemd/system) on a host actually running systemd:
#   sudo bash tests/integration/autostart_systemd.sh
#
# Prints SKIP and exits 0 when the host is not running systemd, so it is harmless to
# run anywhere.

set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root — this writes to /etc/systemd/system." >&2
    echo "       sudo bash $0" >&2
    exit 1
fi

# `systemctl` merely existing is not proof that systemd is PID 1 — that false positive
# is precisely the bug this suite exists to surface, so gate on liveness, not presence.
SYSTEM_STATE=$(systemctl is-system-running 2>/dev/null || true)
case "$SYSTEM_STATE" in
"" | offline)
    echo "SKIP: systemd is not running as PID 1 (is-system-running: ${SYSTEM_STATE:-no response})" >&2
    exit 0
    ;;
esac

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
UNIT="/etc/systemd/system/mtproxymax.service"
WANTS="/etc/systemd/system/multi-user.target.wants/mtproxymax.service"
FAKE="/usr/local/bin/mtproxymax"
FAKE_LOG="/tmp/mtproxymax-fake.log"
FAKE_BACKUP="/tmp/mtproxymax-fake.backup"

# The unit hardcodes ExecStart=/usr/local/bin/mtproxymax. If something is really
# installed there, put it back afterwards rather than clobbering it.
FAKE_WAS_PRESENT=0
if [ -e "$FAKE" ]; then
    cp -a "$FAKE" "$FAKE_BACKUP" 2>/dev/null && FAKE_WAS_PRESENT=1
fi

# The generated unit declares `Requires=docker.service`, so `systemctl start` fails on the
# unmet dependency rather than on the unit under test when that service is absent. GitHub's
# ubuntu-24.04 runner has a real docker.service; a bare systemd container does not. Stub it
# only when genuinely missing, so a real Docker installation is never shadowed.
DOCKER_STUB="/etc/systemd/system/docker.service"
DOCKER_STUB_CREATED=0
if ! systemctl cat docker.service >/dev/null 2>&1; then
    cat >"$DOCKER_STUB" <<'DOCKER_EOF'
[Unit]
Description=Docker stub (MTProxyMax integration test)
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/bin/true

[Install]
WantedBy=multi-user.target
DOCKER_EOF
    DOCKER_STUB_CREATED=1
    systemctl daemon-reload >/dev/null 2>&1
fi

cleanup() {
    systemctl stop mtproxymax.service >/dev/null 2>&1
    systemctl disable mtproxymax.service >/dev/null 2>&1
    rm -f "$UNIT" "$WANTS"
    [ "$DOCKER_STUB_CREATED" -eq 1 ] && rm -f "$DOCKER_STUB"
    systemctl daemon-reload >/dev/null 2>&1
    if [ "$FAKE_WAS_PRESENT" -eq 1 ]; then
        cp -a "$FAKE_BACKUP" "$FAKE" 2>/dev/null
    else
        rm -f "$FAKE"
    fi
    rm -f "$FAKE_BACKUP"
}
trap cleanup EXIT

cat >"$FAKE" <<'FAKE_EOF'
#!/bin/bash
# Test double installed by tests/integration/autostart_systemd.sh, so that ExecStart and
# ExecStop have something real to invoke. Records the arguments it was called with.
printf '%s\n' "$*" >> /tmp/mtproxymax-fake.log
exit 0
FAKE_EOF
chmod +x "$FAKE"
: >"$FAKE_LOG"

MTPROXYMAX_SOURCE_ONLY=true source "$REPO_ROOT/mtproxymax.sh"
set +e

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

# Runs a command and reports its exit status, echoing captured output on failure so a
# rejected unit file shows its diagnostics instead of just "exit 1".
assert_cmd_ok() {
    local name="$1"
    shift
    local out rc
    out=$("$@" 2>&1)
    rc=$?
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$rc" -eq 0 ]; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s (exit %d)\n' "$name" "$rc"
        printf '%s\n' "$out" | sed 's/^/        | /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

file_state() { [ -e "$1" ] && echo present || echo absent; }

printf 'systemd state: %s\n' "$SYSTEM_STATE"

# --- the host must actually be what we think it is ----------------------------
assert_eq "host detects systemd" "systemd" "$(detect_init_system)"

# --- install ------------------------------------------------------------------
setup_autostart >/dev/null 2>&1
assert_eq "setup_autostart succeeds" "0" "$?"
assert_eq "unit file written" "present" "$(file_state "$UNIT")"

if command -v systemd-analyze >/dev/null 2>&1; then
    # --recursive-errors=yes is required for a non-zero exit; without it verify prints
    # warnings and still returns 0, which would make this assertion meaningless.
    assert_cmd_ok "systemd-analyze accepts the unit" \
        systemd-analyze verify --recursive-errors=yes "$UNIT"
fi

# is-enabled exits non-zero for "disabled", so compare stdout and keep set -e off.
assert_eq "unit is enabled" "enabled" "$(systemctl is-enabled mtproxymax.service 2>/dev/null)"

# --- start / stop -------------------------------------------------------------
systemctl start mtproxymax.service >/dev/null 2>&1
assert_eq "systemctl start succeeds" "0" "$?"
assert_eq "unit is active after start (RemainAfterExit=yes)" "active" \
    "$(systemctl is-active mtproxymax.service 2>/dev/null)"
assert_eq "ExecStart reached the mtproxymax binary" "start" "$(head -n1 "$FAKE_LOG" 2>/dev/null)"

systemctl stop mtproxymax.service >/dev/null 2>&1
assert_eq "unit is inactive after stop" "inactive" \
    "$(systemctl is-active mtproxymax.service 2>/dev/null)"
assert_eq "ExecStop reached the mtproxymax binary" "stop" "$(tail -n1 "$FAKE_LOG" 2>/dev/null)"

# --- remove -------------------------------------------------------------------
main_service_remove >/dev/null 2>&1
assert_eq "main_service_remove succeeds" "0" "$?"
assert_eq "unit file removed" "absent" "$(file_state "$UNIT")"
assert_eq "wants symlink removed" "absent" "$(file_state "$WANTS")"
assert_ne "unit is no longer enabled" "enabled" \
    "$(systemctl is-enabled mtproxymax.service 2>/dev/null)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
