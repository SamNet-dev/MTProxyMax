#!/bin/bash
# Regression tests for the `producer | grep -q pattern` idiom under `set -eo pipefail`.
#
# The script runs with `set -eo pipefail` (mtproxymax.sh:10). `grep -q` exits as soon as it
# matches, which closes the read end of the pipe while the producer may still be writing;
# the producer then dies of SIGPIPE and `pipefail` makes the pipeline report 141 (128+13)
# instead of grep's 0. The intended "did it match?" answer is silently replaced by "the
# pipeline failed", and inverting with `!` turns that into the opposite answer.
#
# Measured, and the reason this needs a class-wide fix rather than a hand-picked one: the
# fault depends on how much data the producer still has to write. With `echo` producing a
# short string the write completes before grep can exit and the status is consistently 0;
# with a ~1.2 MB string it is consistently 141. "Is this producer small enough?" is not
# answerable from the source, so every occurrence is treated as unsafe.
#
# `grep -c pattern >/dev/null` reads all of its input, so the producer never receives
# SIGPIPE, and the exit status keeps its usual meaning (0 = matched, 1 = no match).
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_sigpipe_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR"

# A netstat that emits far more than one pipe-buffer's worth of output, with the match on
# the very first line — the shape that makes `grep -q` exit early and the producer die.
FAKEBIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/netstat" <<'NETSTAT_EOF'
#!/bin/bash
echo "tcp 0 0 127.0.0.1:443 0.0.0.0:* LISTEN"
awk 'BEGIN { for (i = 0; i < 120000; i++) print "tcp 0 0 10.0.0.9:" (40000 + i) " 0.0.0.0:* TIME_WAIT" }'
NETSTAT_EOF
chmod +x "$FAKEBIN/netstat"
PATH="$FAKEBIN:$PATH"
export PATH

MTPROXYMAX_SOURCE_ONLY=true source "$REPO_ROOT/mtproxymax.sh"
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

echo "SIGPIPE pipeline tests"

# The class fix. Every occurrence of the idiom has to go, because which producers are
# "small enough" is a property of runtime data, not of the source.
assert_eq "no '| grep -q' pipeline remains in the script" "0" \
    "$(grep -cE '\|[[:space:]]*grep[[:space:]]+-q' "$REPO_ROOT/mtproxymax.sh")"

# Demonstrate the fault itself, so the guard above is not just a style rule.
assert_eq "a pipeline over a large producer reports SIGPIPE, not the match" "141" \
    "$(netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE '[:.]443$'; echo $?)"
assert_eq "the same pipeline with grep -c reports the match" "0" \
    "$(netstat -tln 2>/dev/null | awk '{print $4}' | grep -cE '[:.]443$' >/dev/null; echo $?)"

# Behavioural consequence: is_port_available answers "is this port free?". Port 443 IS
# listening in the fixture, so the only correct answer is "no".
#
# Before the fix the SIGPIPE above made the pipeline report failure, `!` inverted it, and
# this returned 0 — meaning the port-conflict guard in run_proxy_container (:9283) would
# wave a container start through on an already-occupied port.
assert_eq "a listening port is reported as NOT available" "1" \
    "$(is_port_available 443 >/dev/null 2>&1; echo $?)"
# 1234 is deliberately outside the range the fixture's netstat emits (40000+), so this
# asserts "no match" rather than accidentally matching a generated line.
assert_eq "a free port is still reported as available" "0" \
    "$(is_port_available 1234 >/dev/null 2>&1; echo $?)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
