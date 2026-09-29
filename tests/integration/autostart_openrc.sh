#!/bin/bash
# Integration test: setup_autostart() / main_service_remove() against a REAL OpenRC.
#
# Covers the non-systemd path added for Alpine (#130). tests/test_telegram_service_openrc.sh
# verifies that the right rc-update/rc-service commands *would* be invoked, using stubs.
# This runs the real thing: the init script is written to the real /etc/init.d, rc-update
# really registers it in a runlevel, and rc-service really executes it.
#
# Intended to run in a throwaway Alpine container:
#   docker run --rm -v "$PWD:/src" -w /src alpine:3.20 sh -c '
#       apk add --no-cache bash openrc && bash tests/integration/autostart_openrc.sh'
#
# Prints SKIP and exits 0 when OpenRC is not present, so it is harmless to run anywhere.

set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

if [ ! -x /sbin/openrc-run ] || ! command -v rc-service >/dev/null 2>&1; then
    echo "SKIP: OpenRC not present on this host" >&2
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root — this writes to /etc/init.d." >&2
    echo "       sudo bash $0" >&2
    exit 1
fi

# OpenRC's verify_boot() refuses to run any service unless it believes the system was
# booted by OpenRC. In a container nothing booted it, so the marker has to be created.
SOFTLEVEL_CREATED=0
if [ ! -e /run/openrc/softlevel ]; then
    mkdir -p /run/openrc
    : >/run/openrc/softlevel
    SOFTLEVEL_CREATED=1
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
INITD="/etc/init.d/mtproxymax"
RUNLEVEL_LINK="/etc/runlevels/default/mtproxymax"
DOCKER_STUB="/etc/init.d/docker"
DOCKER_STUB_CREATED=0
FAKE="/usr/local/bin/mtproxymax"
FAKE_LOG="/tmp/mtproxymax-fake.log"
FAKE_BACKUP="/tmp/mtproxymax-fake.backup"

FAKE_WAS_PRESENT=0
if [ -e "$FAKE" ]; then
    cp -a "$FAKE" "$FAKE_BACKUP" 2>/dev/null && FAKE_WAS_PRESENT=1
fi

# The generated init script declares `depend() { need docker; }`. OpenRC refuses to start
# a service whose hard dependencies cannot be resolved (`ERROR: mtproxymax needs service(s)
# docker`), so a stub is required for the start assertion below to exercise OUR script
# rather than failing on the host's dependency graph.
if [ ! -e "$DOCKER_STUB" ]; then
    cat >"$DOCKER_STUB" <<'DOCKER_EOF'
#!/sbin/openrc-run
description="Docker stub (MTProxyMax integration test)"

start() {
    ebegin "Starting docker (stub)"
    eend 0
}

stop() {
    ebegin "Stopping docker (stub)"
    eend 0
}
DOCKER_EOF
    chmod +x "$DOCKER_STUB"
    DOCKER_STUB_CREATED=1
fi

cleanup() {
    rc-service mtproxymax stop >/dev/null 2>&1
    rc-update del mtproxymax default >/dev/null 2>&1
    rm -f "$INITD" "$RUNLEVEL_LINK"
    [ "$DOCKER_STUB_CREATED" -eq 1 ] && rm -f "$DOCKER_STUB"
    [ "$SOFTLEVEL_CREATED" -eq 1 ] && rm -f /run/openrc/softlevel
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
# Test double installed by tests/integration/autostart_openrc.sh, so that the generated
# init script's start()/stop() have something real to invoke.
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

assert_cmd_ok() {
    local name="$1"
    shift
    local out rc
    out=$("$@" 2>&1)
    rc=$?
    # OpenRC tries to enrol each service in cgroup v1 hierarchies that are read-only in a
    # container, emitting one "can't create /sys/fs/cgroup/.../tasks" line per controller.
    # That is environmental noise rather than test signal, and it buries the real error.
    out=$(printf '%s\n' "$out" | grep -v '/sys/fs/cgroup/.*/tasks')
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$rc" -eq 0 ]; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s (exit %d)\n' "$name" "$rc"
        printf '%s\n' "$out" | sed 's/^/        | /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_file_contains() {
    local name="$1" needle="$2" file="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF -- "$needle" "$file" 2>/dev/null; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s (missing %q in %s)\n' "$name" "$needle" "$file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

file_state() { [ -e "$1" ] && echo present || echo absent; }

# --- the host must actually be what we think it is ----------------------------
assert_eq "host detects openrc" "openrc" "$(detect_init_system)"

# --- install ------------------------------------------------------------------
setup_autostart >/dev/null 2>&1
assert_eq "setup_autostart succeeds" "0" "$?"
assert_eq "init script written" "present" "$(file_state "$INITD")"
assert_eq "init script is executable" "yes" "$([ -x "$INITD" ] && echo yes || echo no)"
assert_eq "init script has openrc-run shebang" "#!/sbin/openrc-run" "$(head -n1 "$INITD" 2>/dev/null)"

# The dependency declarations matter independently of whether they can be resolved here;
# rc-service refuses to start a service with unmet hard deps, so this is load-bearing.
assert_file_contains "declares need docker" "need docker" "$INITD"
assert_file_contains "declares need net" "need net" "$INITD"

# The invariant openrc_enable_service() checks: rc-update's exit status is not trusted,
# the runlevel symlink actually landing is. Guards the #130 bug class.
assert_eq "runlevel symlink created" "present" "$(file_state "$RUNLEVEL_LINK")"

# --- start / stop -------------------------------------------------------------
# OpenRC keeps a dependency cache; without it a service's state is indeterminate and
# rc-service refuses every start with "already starting". On a real host the cache is
# built during boot; in a container nothing boots OpenRC, so it has to be built by hand.
# Note this must come *after* setup_autostart, so the new service is in the graph.
rc-update -u >/dev/null 2>&1

assert_cmd_ok "rc-service start succeeds" rc-service mtproxymax start
assert_eq "start() reached the mtproxymax binary" "start" "$(head -n1 "$FAKE_LOG" 2>/dev/null)"

assert_cmd_ok "rc-service stop succeeds" rc-service mtproxymax stop
assert_eq "stop() reached the mtproxymax binary" "stop" "$(tail -n1 "$FAKE_LOG" 2>/dev/null)"

# --- remove -------------------------------------------------------------------
main_service_remove >/dev/null 2>&1
assert_eq "main_service_remove succeeds" "0" "$?"
assert_eq "init script removed" "absent" "$(file_state "$INITD")"
assert_eq "runlevel symlink removed" "absent" "$(file_state "$RUNLEVEL_LINK")"
assert_ne "service no longer registered with rc-update" "mtproxymax" \
    "$(rc-update show default 2>/dev/null | awk '{print $1}' | grep -x mtproxymax)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
