#!/bin/bash
# Regression tests for Issue #152: run_heal safe liveness probing and non-destructive recovery.
#
# run_heal must not destroy a healthy, running proxy container on a transient Docker inspect
# hiccup, must require two consecutive failed probes before declaring the container down,
# and must delegate lifecycle management to start_proxy_container rather than calling
# `docker rm -f` unconditionally.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT=$(mktemp -d) || { echo "SKIP: cannot create temp dir" >&2; exit 0; }
trap 'rm -rf "$TEST_ROOT"' EXIT

export INSTALL_DIR="$TEST_ROOT"
export CONFIG_DIR="$TEST_ROOT/mtproxy"
export SETTINGS_FILE="$TEST_ROOT/settings.conf"
export SECRETS_FILE="$TEST_ROOT/secrets.conf"
export STATS_DIR="$TEST_ROOT/relay_stats"
mkdir -p "$CONFIG_DIR" "$STATS_DIR"

MTPROXYMAX_SOURCE_ONLY=true source "${SCRIPT_DIR}/../mtproxymax.sh"
set +e

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

# Stubs
check_root() { :; }
log_info() { :; }
log_warn() { :; }
log_success() { :; }
log_error() { :; }

# Mock system calls for free / sysctl so run_heal doesn't fail on non-root or unprivileged environments
free() {
    echo "Mem: 1000 500 500 0 0 500"
}
sysctl() { :; }

DOCKER_RM_LOG="$TEST_ROOT/docker_rm.log"
START_PROXY_LOG="$TEST_ROOT/start_proxy.log"
INSPECT_LOG="$TEST_ROOT/inspect_count.log"

get_inspect_count() {
    [ -f "$INSPECT_LOG" ] && wc -l < "$INSPECT_LOG" | tr -d ' ' || echo 0
}

docker() {
    local cmd="$1"
    shift
    case "$cmd" in
        inspect)
            echo "call" >> "$INSPECT_LOG"
            local cnt; cnt=$(get_inspect_count)
            if [ -n "$MOCK_INSPECT_FAIL_ONCE" ] && [ "$cnt" -eq 1 ]; then
                # Simulate a transient inspect failure on first call
                return 1
            fi
            if [ -n "$MOCK_INSPECT_STATE" ]; then
                echo "$MOCK_INSPECT_STATE"
                return 0
            fi
            echo "true"
            return 0
            ;;
        rm)
            echo "$*" >> "$DOCKER_RM_LOG"
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

start_proxy_container() {
    echo "started" >> "$START_PROXY_LOG"
    return 0
}

echo "run_heal safe liveness & recovery tests (Issue #152)"

# ── 1. Transient inspect hiccup does NOT destroy the container ────────────────
: > "$INSPECT_LOG"
MOCK_INSPECT_FAIL_ONCE=1
MOCK_INSPECT_STATE="true"
: > "$DOCKER_RM_LOG"
: > "$START_PROXY_LOG"

run_heal >/dev/null 2>&1

assert_eq "transient inspect hiccup does not trigger docker rm" "0" \
    "$([ -f "$DOCKER_RM_LOG" ] && wc -l < "$DOCKER_RM_LOG" | tr -d ' ' || echo 0)"
assert_eq "transient inspect hiccup does not trigger recovery start" "0" \
    "$([ -f "$START_PROXY_LOG" ] && wc -l < "$START_PROXY_LOG" | tr -d ' ' || echo 0)"

# ── 2. Dead container triggers start_proxy_container WITHOUT calling docker rm in run_heal ──
: > "$INSPECT_LOG"
unset MOCK_INSPECT_FAIL_ONCE
MOCK_INSPECT_STATE="false"
: > "$DOCKER_RM_LOG"
: > "$START_PROXY_LOG"

run_heal >/dev/null 2>&1

assert_eq "run_heal delegates to start_proxy_container on genuine downtime" "1" \
    "$([ -f "$START_PROXY_LOG" ] && wc -l < "$START_PROXY_LOG" | tr -d ' ' || echo 0)"
assert_eq "run_heal does not call docker rm -f itself" "0" \
    "$([ -f "$DOCKER_RM_LOG" ] && wc -l < "$DOCKER_RM_LOG" | tr -d ' ' || echo 0)"

# ── 3. is_proxy_running retries on transient inspect failure ─────────────────
: > "$INSPECT_LOG"
MOCK_INSPECT_FAIL_ONCE=1
MOCK_INSPECT_STATE="true"
is_proxy_running
rc=$?
assert_eq "is_proxy_running recovers from transient inspect failure" "0" "$rc"
assert_eq "is_proxy_running performed retry" "2" "$(get_inspect_count)"

# ── 4. is_proxy_running returns non-zero when genuinely stopped ───────────────
: > "$INSPECT_LOG"
unset MOCK_INSPECT_FAIL_ONCE
MOCK_INSPECT_STATE="false"
is_proxy_running
rc=$?
assert_eq "is_proxy_running returns non-zero when stopped" "1" "$rc"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
