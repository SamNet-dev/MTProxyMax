#!/bin/bash
# Regression tests for Issue #135:
# Ensure secondary instances allocate disjoint metrics and stats port pairs
# and handle range exhaustion cleanly.

set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e

TESTS_RUN=0
TESTS_FAILED=0
LAST_ERROR=""

log_error() {
    LAST_ERROR="$*"
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

assert_exit() {
    local name="$1" want_code="$2" got_code="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got_code" -eq "$want_code" ]; then
        printf '  PASS  %s (exit %d)\n' "$name" "$got_code"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (got exit %d, want exit %d)\n' "$name" "$got_code" "$want_code"
    fi
}

echo "Instance metrics port allocation tests (Issue #135)"

# Test 1: Fresh install with default primary metrics port (9090).
# Primary binds metrics=9090, stats=9091.
# First instance MUST NOT be allocated 9091 (collides with primary stats).
# It must receive 9092 (pair 9092 & 9093).
PROXY_METRICS_PORT=9090
INSTANCE_METRICS_PORTS=()
res=$(_next_free_metrics_port)
code=$?
assert_exit "default primary finds free port" 0 "$code"
assert_eq "first instance gets 9092 (not 9091 which is primary stats)" "9092" "$res"

# Test 2: Second instance allocation after first instance took 9092.
# Primary uses 9090 & 9091.
# Instance 1 uses 9092 (metrics) & 9093 (stats).
# Next port must NOT be 9093 (inst 1 stats). It must be 9094.
INSTANCE_METRICS_PORTS=("9092")
res=$(_next_free_metrics_port)
code=$?
assert_exit "second instance finds free port" 0 "$code"
assert_eq "second instance gets 9094 (skips 9093 inst 1 stats)" "9094" "$res"

# Test 3: Third instance allocation after 9092 and 9094 are taken.
# Next port must be 9096 (skipping 9095 inst 2 stats).
INSTANCE_METRICS_PORTS=("9092" "9094")
res=$(_next_free_metrics_port)
code=$?
assert_exit "third instance finds free port" 0 "$code"
assert_eq "third instance gets 9096 (pair 9096 & 9097)" "9096" "$res"

# Test 4: Custom primary metrics port where 9091 is free.
# Primary uses 9094 & 9095.
# First instance should safely receive 9091 (pair 9091 & 9092).
PROXY_METRICS_PORT=9094
INSTANCE_METRICS_PORTS=()
res=$(_next_free_metrics_port)
code=$?
assert_exit "custom primary finds free port" 0 "$code"
assert_eq "first instance gets 9091 when primary is 9094" "9091" "$res"

# Test 5: Candidate stats port collision with primary metrics port.
# Primary uses 9094 & 9095.
# Instance 1 uses 9091 (pair 9091 & 9092).
# Candidate 9093 would have stats port 9094, which collides with primary metrics (9094)!
# Therefore, 9093 must be skipped. 9094 & 9095 are primary. Next free must be 9096.
PROXY_METRICS_PORT=9094
INSTANCE_METRICS_PORTS=("9091")
res=$(_next_free_metrics_port)
code=$?
assert_exit "collision with candidate stats port avoided" 0 "$code"
assert_eq "second instance skips 9093 to avoid stats port collision with primary" "9096" "$res"

# Test 6: Non-consecutive existing instance port in instances.conf.
# Primary uses 9090 & 9091.
# Existing instance has mp=9093 (pair 9093 & 9094).
# Candidate 9092 has stats port 9093, which collides with mp=9093!
# 9093 collides with mp=9093, 9094 collides with ms=9094.
# Next free must be 9095.
PROXY_METRICS_PORT=9090
INSTANCE_METRICS_PORTS=("9093")
res=$(_next_free_metrics_port)
code=$?
assert_exit "skips candidate whose stats port collides with existing instance" 0 "$code"
assert_eq "skips 9092 when existing instance is on 9093" "9095" "$res"

# Test 7: Port range exhaustion.
# Fill all available pairs from 9092 through 9198.
PROXY_METRICS_PORT=9090
INSTANCE_METRICS_PORTS=()
for ((p=9092; p<9200; p+=2)); do
    INSTANCE_METRICS_PORTS+=("$p")
done
res=$(_next_free_metrics_port)
code=$?
assert_exit "exhausted range returns exit code 1" 1 "$code"
assert_eq "exhausted range produces no output" "" "$res"

# Test 8: instance_add aborts cleanly on metrics port exhaustion.
# Ensure instance is not added and error is logged.
LAST_ERROR=""
INSTANCE_PORTS=()
INSTANCE_ENABLED=()
INSTANCE_LABELS=()
PROXY_PORT=443
instance_add 8443 "overflow-test"
code=$?
assert_exit "instance_add fails on exhausted metrics ports" 1 "$code"
assert_eq "instances array left empty" 0 "${#INSTANCE_PORTS[@]}"
[[ "$LAST_ERROR" == *"No free metrics ports available"* ]]
assert_eq "error logged on exhaustion" 0 "$?"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
