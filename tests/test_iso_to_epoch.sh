#!/bin/bash
# Regression tests for _iso_to_epoch(), which parses the ISO 8601 timestamps this project
# stores for secret expiry.
#
# The stored format is "%Y-%m-%dT%H:%M:%SZ" — no fractional seconds. Two independent
# defects made the function return a wrong value for exactly that format:
#
#   1. Z duplication (affects GNU/Linux, i.e. Debian and Ubuntu).
#        local ts_clean="${ts%%.*}"
#        [[ "$ts" == *Z ]] && ts_clean="${ts_clean}Z"
#      For a value with no fractional part, `${ts%%.*}` is a no-op, so the Z is still
#      present and a second one is appended: "2026-03-03T10:00:00ZZ". GNU date rejects
#      that, `date -D` does not exist on GNU, and the function falls through to `echo 0`.
#      A return of 0 is read by callers as "no expiry", so `secret_check_expiry` skips
#      the secret entirely and an expired key stays enabled.
#
#   2. Local-time parsing (affects Alpine/busybox).
#      The busybox branch strips the Z and then parses with no TZ, so a UTC value is
#      reinterpreted as local time — busybox ignores the designator outright under `-D`.
#      The error equals the offset that timestamp's own date carries, so on a DST zone it
#      is an hour in winter and two in summer.
#
# Both are covered below: part A forces the busybox branch with a stub, part B uses the
# real date. Neither part alone would catch both defects.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

REAL_DATE=$(command -v date)
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_iso_XXXXXX')

# A date that models busybox's actual option surface:
#   - plain `-d <value ending in Z>`  -> rejected outright
#   - `-D FMT -d <value>`             -> accepted, and any trailing Z is IGNORED, so the
#                                        value is parsed in the ambient TZ
# Parsing itself is delegated to the real date, so the ambient TZ decides the answer.
FAKEBIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/date" <<DATE_EOF
#!/bin/bash
_args=("\$@")
_i=0
_darg=""
_outfmt=""
_have_D=0
_Dfmt=""
while [ "\$_i" -lt "\${#_args[@]}" ]; do
    case "\${_args[\$_i]}" in
    -d)
        _i=\$((_i + 1))
        _darg="\${_args[\$_i]:-}"
        ;;
    -D)
        _have_D=1
        _i=\$((_i + 1))
        _Dfmt="\${_args[\$_i]:-}"
        ;;
    +*)
        _outfmt="\${_args[\$_i]}"
        ;;
    esac
    _i=\$((_i + 1))
done
if [ -n "\$_darg" ]; then
    if [ "\$_have_D" = "1" ]; then
        # The Z is ignored under -D, so drop it before parsing. Which delegation works
        # depends on what the real date is: GNU parses the bare value, busybox needs -D.
        _out=\$("$REAL_DATE" -d "\${_darg%Z}" "\$_outfmt" 2>/dev/null) &&
            { printf '%s\n' "\$_out"; exit 0; }
        exec "$REAL_DATE" -D "\$_Dfmt" -d "\${_darg%Z}" "\$_outfmt"
    fi
    case "\$_darg" in
    *Z)
        echo "date: invalid date '\$_darg'" >&2
        exit 1
        ;;
    esac
    exec "$REAL_DATE" -d "\$_darg" "\$_outfmt"
fi
exec "$REAL_DATE" "\$@"
DATE_EOF
chmod +x "$FAKEBIN/date"

# POSIX TZ string, so no tzdata is needed: XXX-2 is two hours EAST of Greenwich.
export TZ="XXX-2"

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

TRUE_EPOCH=1772532000   # 2026-03-03T10:00:00Z, verified with `date -u -d`

echo "ISO-8601 epoch parsing tests"

# ---- Part A: the busybox branch, forced via the stub -------------------------------
PATH="$FAKEBIN:$PATH"
assert_eq "stub date is the one on PATH" "$FAKEBIN/date" "$(command -v date)"

# The stored format: no fractional seconds. Broken on every platform.
assert_eq "A: stored-format timestamp parses correctly" \
    "$TRUE_EPOCH" "$(_iso_to_epoch '2026-03-03T10:00:00Z')"
# With sub-second precision, which busybox truncates.
assert_eq "A: sub-second precision does not shift the result" \
    "$TRUE_EPOCH" "$(_iso_to_epoch '2026-03-03T10:00:00.123456789Z')"

# ---- Part B: the real date on this host --------------------------------------------
PATH="${PATH#"$FAKEBIN:"}"
real_date_now=$(command -v date)
assert_eq "real date restored for part B" "yes" \
    "$([ "$real_date_now" != "$FAKEBIN/date" ] && echo yes || echo no)"

# On GNU this is where the doubled Z surfaced; on busybox it is a UTC container, so the
# timezone defect does not apply here and the parse must still be exact.
assert_eq "B: stored-format timestamp parses correctly" \
    "$TRUE_EPOCH" "$(_iso_to_epoch '2026-03-03T10:00:00Z')"
assert_eq "B: sub-second precision does not shift the result" \
    "$TRUE_EPOCH" "$(_iso_to_epoch '2026-03-03T10:00:00.123456789Z')"

# ---- both defects at once, on a value that must not parse ---------------------------
assert_eq "an unparseable value still reports 0" "0" "$(_iso_to_epoch 'not-a-timestamp')"
assert_eq "an empty value still reports 0" "0" "$(_iso_to_epoch '')"

# The generated daemon carries its own copy inside a heredoc, so it cannot be exercised by
# sourcing; guard it at the source level. Both copies must force UTC for the busybox branch.
assert_eq "both copies force UTC on the busybox branch" "2" \
    "$(grep -c "TZ=UTC date -D '%Y-%m-%dT%H:%M:%S'" "$REPO_ROOT/mtproxymax.sh")"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
