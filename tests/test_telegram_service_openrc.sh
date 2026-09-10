#!/bin/bash
# Regression tests for Telegram bot / autostart service installation across init systems.
#
# Covers the non-systemd path added for Alpine/OpenRC: the Telegram bot service and the
# main autostart service must be installed via OpenRC instead of silently doing nothing,
# and a host with neither init system must fail loudly rather than reporting success.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_test_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
SETTINGS_FILE="$INSTALL_DIR/settings.conf"
INITD_DIR="$TEST_TMPDIR/etc/init.d"
SYSTEMD_DIR="$TEST_TMPDIR/etc/systemd/system"
mkdir -p "$INSTALL_DIR" "$INITD_DIR" "$SYSTEMD_DIR"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

CMD_LOG="$TEST_TMPDIR/cmd.log"
WARN_LOG="$TEST_TMPDIR/warn.log"
: > "$CMD_LOG"
: > "$WARN_LOG"

check_root() { :; }
log_success() { :; }
log_info() { :; }
log_warn() { echo "$*" >> "$WARN_LOG"; }
log_error() { echo "$*" >> "$WARN_LOG"; }

# Shadow the init-system binaries so nothing touches the host.
RC_SERVICE_STATUS=0
SYSTEMCTL_STATUS=0
systemctl() { echo "systemctl $*" >> "$CMD_LOG"; return "$SYSTEMCTL_STATUS"; }
rc-update() { echo "rc-update $*" >> "$CMD_LOG"; return 0; }
rc-service() { echo "rc-service $*" >> "$CMD_LOG"; return "$RC_SERVICE_STATUS"; }

FAKE_INIT="openrc"
detect_init_system() { echo "$FAKE_INIT"; }

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

assert_file_contains() {
    local name="$1" needle="$2" file="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF -- "$needle" "$file" 2>/dev/null; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (missing %q in %s)\n' "$name" "$needle" "$file"
    fi
}

assert_log_contains() {
    local name="$1" needle="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF -- "$needle" "$CMD_LOG" 2>/dev/null; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (missing %q in command log)\n' "$name" "$needle"
    fi
}

assert_warn_contains() {
    local name="$1" needle="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF -- "$needle" "$WARN_LOG" 2>/dev/null; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (missing %q in warning log)\n' "$name" "$needle"
    fi
}

reset_state() {
    FAKE_INIT="${1:-openrc}"
    RC_SERVICE_STATUS=0
    SYSTEMCTL_STATUS=0
    : > "$CMD_LOG"
    : > "$WARN_LOG"
    rm -f "$INITD_DIR/mtproxymax" "$INITD_DIR/mtproxymax-telegram"
    rm -f "$SYSTEMD_DIR/mtproxymax.service" "$SYSTEMD_DIR/mtproxymax-telegram.service"
}

TELEGRAM_INIT="$INITD_DIR/mtproxymax-telegram"
MAIN_INIT="$INITD_DIR/mtproxymax"
TELEGRAM_UNIT="$SYSTEMD_DIR/mtproxymax-telegram.service"
MAIN_UNIT="$SYSTEMD_DIR/mtproxymax.service"

echo "Telegram service init-system tests"

# ── OpenRC: telegram bot service ─────────────────────────────
reset_state openrc
setup_telegram_service
assert_eq "openrc setup succeeds" "0" "$?"

assert_file_contains "init script declares supervise-daemon" "supervisor=supervise-daemon" "$TELEGRAM_INIT"
assert_file_contains "init script respawns after 10s" "respawn_delay=10" "$TELEGRAM_INIT"
assert_file_contains "init script respawns indefinitely" "respawn_max=0" "$TELEGRAM_INIT"
assert_file_contains "init script needs net and docker" "need net docker" "$TELEGRAM_INIT"
assert_file_contains "init script points at generated daemon" \
    "command_args=\"${INSTALL_DIR}/mtproxymax-telegram.sh\"" "$TELEGRAM_INIT"
assert_file_contains "init script separates stderr" \
    "error_log=\"/var/log/mtproxymax-telegram.err\"" "$TELEGRAM_INIT"
assert_file_contains "start_pre guards on the generated daemon" \
    "if [ ! -f \"\${command_args}\" ]; then" "$TELEGRAM_INIT"

if [ -x "$TELEGRAM_INIT" ]; then
    assert_eq "init script is executable" "yes" "yes"
else
    assert_eq "init script is executable" "yes" "no"
fi

# Runtime variables must survive generation unexpanded.
assert_file_contains "RC_SVCNAME stays literal" 'pidfile="/run/${RC_SVCNAME}.pid"' "$TELEGRAM_INIT"
if grep -qF 'pidfile="/run/.pid"' "$TELEGRAM_INIT" 2>/dev/null; then
    assert_eq "RC_SVCNAME not expanded at generation time" "literal" "expanded"
else
    assert_eq "RC_SVCNAME not expanded at generation time" "literal" "literal"
fi

assert_log_contains "service added to default runlevel" "rc-update add mtproxymax-telegram default"
assert_log_contains "service restarted via rc-service" "rc-service mtproxymax-telegram restart"

# ── OpenRC: restart / stop / remove / status helpers ─────────
reset_state openrc
setup_telegram_service >/dev/null
: > "$CMD_LOG"

telegram_restart_service
assert_eq "restart succeeds when unit installed" "0" "$?"
assert_log_contains "restart uses rc-service" "rc-service mtproxymax-telegram restart"

telegram_stop_service
assert_log_contains "stop uses rc-service" "rc-service mtproxymax-telegram stop"

telegram_remove_service
assert_log_contains "remove stops the service" "rc-service mtproxymax-telegram stop"
assert_log_contains "remove deletes from runlevel" "rc-update del mtproxymax-telegram default"
if [ -f "$TELEGRAM_INIT" ]; then
    assert_eq "remove deletes init script" "deleted" "kept"
else
    assert_eq "remove deletes init script" "deleted" "deleted"
fi

# restart must report failure once the service definition is gone.
telegram_restart_service
assert_eq "restart fails when unit absent" "1" "$?"

reset_state openrc
setup_telegram_service >/dev/null
RC_SERVICE_STATUS=0
if telegram_service_running; then
    assert_eq "status true when rc-service succeeds" "true" "true"
else
    assert_eq "status true when rc-service succeeds" "true" "false"
fi
RC_SERVICE_STATUS=1
if telegram_service_running; then
    assert_eq "status false when rc-service fails" "false" "true"
else
    assert_eq "status false when rc-service fails" "false" "false"
fi

# ── OpenRC: start failure must not be reported as success ────
reset_state openrc
RC_SERVICE_STATUS=1
setup_telegram_service
assert_eq "openrc start failure returns nonzero" "1" "$?"
assert_warn_contains "openrc start failure warns" "rc-service mtproxymax-telegram status"

# ── No init system: loud failure, no silent no-op ────────────
reset_state none
setup_telegram_service
assert_eq "no-init-system setup returns nonzero" "1" "$?"
if [ -f "$TELEGRAM_INIT" ]; then
    assert_eq "no-init-system writes no init script" "absent" "present"
else
    assert_eq "no-init-system writes no init script" "absent" "absent"
fi
assert_warn_contains "no-init-system warns it is not running" "is NOT running"

reset_state none
if telegram_service_running; then
    assert_eq "status false with no init system" "false" "true"
else
    assert_eq "status false with no init system" "false" "false"
fi

# ── systemd behaviour unchanged, but now path-injectable ─────
reset_state systemd
setup_telegram_service
assert_eq "systemd setup succeeds" "0" "$?"
assert_file_contains "systemd unit written to SYSTEMD_DIR" "MTProxyMax Telegram Bot Service" "$TELEGRAM_UNIT"
assert_file_contains "systemd unit restarts on failure" "Restart=on-failure" "$TELEGRAM_UNIT"
assert_log_contains "systemd enables the unit" "systemctl enable mtproxymax-telegram.service"
assert_log_contains "systemd restarts the unit" "systemctl restart mtproxymax-telegram.service"

reset_state systemd
setup_telegram_service >/dev/null
: > "$CMD_LOG"
telegram_remove_service
assert_log_contains "systemd remove disables the unit" "systemctl disable mtproxymax-telegram.service"
if [ -f "$TELEGRAM_UNIT" ]; then
    assert_eq "systemd remove deletes unit file" "deleted" "kept"
else
    assert_eq "systemd remove deletes unit file" "deleted" "deleted"
fi

# ── Autostart service ────────────────────────────────────────
reset_state openrc
setup_autostart
assert_eq "autostart openrc succeeds" "0" "$?"
assert_file_contains "autostart script starts the manager" "/usr/local/bin/mtproxymax start" "$MAIN_INIT"
assert_file_contains "autostart script stops the manager" "/usr/local/bin/mtproxymax stop" "$MAIN_INIT"
assert_file_contains "autostart script requires docker" "need docker" "$MAIN_INIT"
assert_log_contains "autostart added to default runlevel" "rc-update add mtproxymax default"
if [ -x "$MAIN_INIT" ]; then
    assert_eq "autostart script is executable" "yes" "yes"
else
    assert_eq "autostart script is executable" "yes" "no"
fi

reset_state none
setup_autostart
assert_eq "autostart with no init system returns nonzero" "1" "$?"
if [ -f "$MAIN_INIT" ]; then
    assert_eq "autostart writes no init script when unsupported" "absent" "present"
else
    assert_eq "autostart writes no init script when unsupported" "absent" "absent"
fi

reset_state systemd
setup_autostart
assert_eq "autostart systemd succeeds" "0" "$?"
assert_file_contains "autostart unit written to SYSTEMD_DIR" "MTProxyMax Telegram Proxy" "$MAIN_UNIT"
assert_log_contains "autostart unit enabled" "systemctl enable mtproxymax.service"

reset_state systemd
setup_autostart >/dev/null
: > "$CMD_LOG"
main_service_remove
assert_log_contains "autostart remove disables the unit" "systemctl disable mtproxymax.service"
if [ -f "$MAIN_UNIT" ]; then
    assert_eq "autostart remove deletes unit file" "deleted" "kept"
else
    assert_eq "autostart remove deletes unit file" "deleted" "deleted"
fi

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
