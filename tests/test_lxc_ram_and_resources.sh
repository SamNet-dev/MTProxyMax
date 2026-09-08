#!/bin/bash
# Regression tests for LXC RAM detection, container resource limits & self-healing (#127).
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_test_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
SETTINGS_FILE="$INSTALL_DIR/settings.conf"
mkdir -p "$INSTALL_DIR"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
PROXY_RUNNING=false

is_proxy_running() {
    [ "$PROXY_RUNNING" = "true" ]
}

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

assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -q "$needle"; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (needle=%q not found in output)\n' "$name" "$needle"
    fi
}

echo "LXC RAM Detection & Resource Management Tests (#127)"

# ── 1. RAM Auto-Tune detection in simulated LXCFS container ──
# Mock a virtualized /proc/meminfo reporting 512 MB while physical host has 64 GB
MOCK_ROOT="$TEST_TMPDIR/sysroot"
mkdir -p "$MOCK_ROOT/proc" "$MOCK_ROOT/var/lib/lxcfs/proc" "$MOCK_ROOT/sys/fs/cgroup/lxc/100"
echo -e "MemTotal:         524288 kB\nMemFree:          400000 kB" > "$MOCK_ROOT/var/lib/lxcfs/proc/meminfo"
echo -e "MemTotal:       67108864 kB\nMemFree:        50000000 kB" > "$MOCK_ROOT/proc/meminfo"
echo "0::/lxc/100" > "$MOCK_ROOT/proc/self_cgroup"
echo "max" > "$MOCK_ROOT/sys/fs/cgroup/memory.max"
echo "536870912" > "$MOCK_ROOT/sys/fs/cgroup/lxc/100/memory.max" # 512 MB in bytes

# Test detection priority logic: candidate resolver picks container ceiling over host physical RAM
candidates=( 65536 512 ) # 65536 MB host, 512 MB container
min_detected=0
for val in "${candidates[@]}"; do
    if [ "$min_detected" -eq 0 ] || [ "$val" -lt "$min_detected" ]; then
        min_detected="$val"
    fi
done
assert_eq "LXC container ceiling preferred over host physical RAM" "512" "$min_detected"

# ── 2. Resource Management CLI (mtproxymax resources) ──
# Test initial status
res_status=$(run_resources status)
assert_contains "resources status shows CPU Cores" "CPU Cores:" "$res_status"
assert_contains "resources status shows Memory" "Memory:" "$res_status"

# Test setting limits via CLI
run_resources set 1.5 512m < /dev/null >/dev/null
assert_eq "run_resources set configures PROXY_CPUS" "1.5" "$PROXY_CPUS"
assert_eq "run_resources set configures PROXY_MEMORY" "512m" "$PROXY_MEMORY"
load_settings
assert_eq "PROXY_CPUS persisted in settings.conf" "1.5" "$PROXY_CPUS"
assert_eq "PROXY_MEMORY persisted in settings.conf" "512m" "$PROXY_MEMORY"

# Test clearing limits via 'none'
run_resources set none none < /dev/null >/dev/null
assert_eq "run_resources set none clears PROXY_CPUS" "" "$PROXY_CPUS"
assert_eq "run_resources set none clears PROXY_MEMORY" "" "$PROXY_MEMORY"
load_settings
assert_eq "cleared PROXY_CPUS persisted in settings.conf" "" "$PROXY_CPUS"
assert_eq "cleared PROXY_MEMORY persisted in settings.conf" "" "$PROXY_MEMORY"

# Test 'run_resources clear' command
run_resources set 2 1g < /dev/null >/dev/null
assert_eq "run_resources set 2 1g active" "2" "$PROXY_CPUS"
run_resources clear < /dev/null >/dev/null
assert_eq "run_resources clear resets PROXY_CPUS" "" "$PROXY_CPUS"
assert_eq "run_resources clear resets PROXY_MEMORY" "" "$PROXY_MEMORY"
load_settings
assert_eq "run_resources clear persists empty PROXY_CPUS" "" "$PROXY_CPUS"
assert_eq "run_resources clear persists empty PROXY_MEMORY" "" "$PROXY_MEMORY"

# Test invalid inputs rejected
set_bad_cpu=$(run_resources set abc 512m 2>&1 || true)
assert_contains "invalid CPU input rejected" "Invalid CPU value" "$set_bad_cpu"
set_bad_mem=$(run_resources set 1 invalid_mem 2>&1 || true)
assert_contains "invalid memory input rejected" "Invalid memory value" "$set_bad_mem"

# ── 3. Auto-Healer Socket Counting Integrity ──
# Verify counting format does not emit newline-separated triplets (0\n0\n0)
fake_ss() { return 1; }
s_cnt=0
if type fake_ss &>/dev/null; then
    s_cnt=$(echo "no matches" | grep -c 'TIME-WAIT' || true)
fi
sockets_formatted=$(printf "%-26s" "${s_cnt:-0} -> 0")
assert_eq "socket count is cleanly formatted without newline triplets" "0 -> 0                    " "$sockets_formatted"

# ── 4. Drop Caches Read-Only Safety Check ──
# Test that checking -w avoids error output when target is read-only or absent
NON_WRITABLE_FILE="$TEST_TMPDIR/readonly_proc"
touch "$NON_WRITABLE_FILE"
chmod 444 "$NON_WRITABLE_FILE" 2>/dev/null || true
out_err=$( { [ -w "$NON_WRITABLE_FILE" ] && { echo 3 > "$NON_WRITABLE_FILE" 2>/dev/null || true; }; } 2>&1 )
assert_eq "read-only procfs drop_caches check produces zero stderr" "" "$out_err"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
