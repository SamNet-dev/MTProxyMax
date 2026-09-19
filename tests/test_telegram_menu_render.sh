#!/bin/bash
# Tests for inline-keyboard rendering: shape, payload bounds, and pagination.
#
# The Bot API validates reply_markup as a whole, so one bad button loses the
# entire keyboard — and one malformed JSON string loses the whole message.
# These tests check every view a role can reach, across all roles.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"
OFFSET_FILE="$INSTALL_DIR/relay_stats/tg_offset"
ADMINS_FILE="$INSTALL_DIR/admins.conf"
AUDIT_LOG="$INSTALL_DIR/audit.log"
SECRETS_FILE="$INSTALL_DIR/secrets.conf"

# 13 users: enough to force three pages at a page size of six.
: > "$SECRETS_FILE"
for _i in $(seq 1 13); do
    _state="true"; [ $(( _i % 3 )) -eq 0 ] && _state="false"
    printf 'user%02d|%s|1700000000|%s|0|0|0|0||\n' "$_i" "$(printf '%032d' "$_i")" "$_state" >> "$SECRETS_FILE"
done

# One well-formed template, plus one whose name can never be a button payload —
# the second is what proves the list says so instead of dropping it silently.
TEMPLATES_FILE="$INSTALL_DIR/templates.conf"
printf 'vip|100|5|53687091200|2027-01-01|top tier\n' > "$TEMPLATES_FILE"
printf 'not a button|10|2|1073741824|0|x\n' >> "$TEMPLATES_FILE"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
assert_ok() {
    local name="$1" cond="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$cond" -eq 0 ] 2>/dev/null; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s\n' "$name"; fi
}
assert_eq() {
    local name="$1" want="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" = "$want" ]; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"; fi
}

telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
for _fn in _tg_security_log _cb_label_ok _cb_enc _cb_dec _esc _iso_to_epoch; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
awk '/^# >>> TG_MENU_BEGIN$/,/^# <<< TG_MENU_END$/' "$DAEMON" >> "$FNS"
assert_eq "menu render extraction is valid bash" 0 \
    "$(bash -n "$FNS" 2>/dev/null; echo $?)"

ROLE_TO_RETURN="superadmin"
_check_tg_role() { echo "$ROLE_TO_RETURN"; }
EDIT="$TEST_TMPDIR/edit.txt"
tg_edit() { printf '%s\n%s' "$3" "$4" > "$EDIT"; }
tg_edit_markup() { printf '%s' "$3" > "$EDIT"; }
tg_answer_cb() { :; }
tg_send_to() { :; }
tg_send() { :; }
# The server-console views read live state; the render test only cares about
# their SHAPE, so these answer with fixed values rather than reaching for
# docker or the metrics endpoint.
get_uptime() { echo "98201"; }
get_active_connections() { echo "3"; }
get_cached_ip() { echo "203.0.113.9"; }
is_proxy_running() { return 0; }
get_container_uptime() { echo "98201"; }
load_tg_settings() { :; }
is_running() { return 1; }
get_cached_ip() { echo "203.0.113.9"; }
_tg_metrics_raw() { printf ''; }
source "$FNS"
_CB_CHAT=111; _CB_MID=77

# Render one view and echo "<text>\n<markup>".
render() {
    _UI_ROLE="$1"; _CB_ROLE="$1"
    _CB_NS=""; _CB_ACT=""; _CB_TGT=""; _CB_PAGE=""
    case "$2" in
        hub)      _cb_render_hub ;;
        help)     _cb_render_help ;;
        list)     _cb_render_user_list "${3:-0}" ;;
        detail)   _cb_render_user_detail "${3:-user01}" "${4:-0}" ;;
        confirm)  _cb_render_confirm "${3:-disable}" "${4:-user01}" 0 ;;
        traffic)  _cb_render_traffic 24h ;;
        engine)   _cb_render_engine ;;
        settings) _cb_render_settings ;;
        manage)   _cb_render_user_manage "${3:-user01}" "${4:-0}" ;;
        limits_q) _cb_render_limits q "${3:-user01}" "${4:-0}" ;;
        limits_c) _cb_render_limits c "${3:-user01}" "${4:-0}" ;;
        limits_i) _cb_render_limits i "${3:-user01}" "${4:-0}" ;;
        limits_x) _cb_render_limits x "${3:-user01}" "${4:-0}" ;;
        limits_r) _cb_render_limits r "${3:-user01}" "${4:-0}" ;;
        tpl_list)   _cb_render_tpl_list ;;
        tpl_edit)   _cb_render_tpl_edit "${3:-vip}" 0 ;;
        tpl_field)  _cb_render_tpl_field "${3:-vip}" "${4:-q}" ;;
        tpl_apply)  _cb_render_tpl_apply_picker "${3:-vip}" 0 ;;
        tpl_picker) _cb_render_tpl_picker "${3:-user01}" 0 ;;
        tools)     _cb_render_tools ;;
        digest)    _cb_render_digest ;;
        upstreams) _cb_render_upstreams ;;
        fleet)     _cb_render_fleet ;;
        vouchers)  _cb_render_vouchers ;;
        update)    _cb_render_update "Installed version: test" ;;
    esac
    cat "$EDIT"
}
markup_of() { printf '%s' "$1" | tail -1; }
cbs_of() { printf '%s' "$1" | grep -o '"callback_data":"[^"]*"' | sed 's/.*:"//;s/"$//'; }

echo "Telegram menu render tests"

VIEWS="hub help list detail confirm traffic engine settings manage \
limits_q limits_c limits_i limits_x limits_r \
tpl_list tpl_edit tpl_field tpl_apply tpl_picker \
tools digest upstreams fleet vouchers update"

# ── Every view for every role is structurally sound ──────────────────────────
for _role in superadmin reseller operator; do
    for _v in $VIEWS; do
        _out=$(render "$_role" "$_v")
        _mk=$(markup_of "$_out")

        # The markup must be a well-formed inline_keyboard object.
        case "$_mk" in
            '{"inline_keyboard":['*']}') _shape=0 ;;
            *) _shape=1 ;;
        esac
        assert_ok "role=$_role view=$_v markup has inline_keyboard shape" "$_shape"

        # Balanced brackets — an unbalanced one is a 400 and loses the message.
        _open=$(printf '%s' "$_mk" | tr -cd '[' | wc -c | tr -d ' ')
        _close=$(printf '%s' "$_mk" | tr -cd ']' | wc -c | tr -d ' ')
        assert_eq "role=$_role view=$_v brackets balance" "$_open" "$_close"

        # Every payload must fit 64 bytes and decode.
        _bad=0
        while IFS= read -r _p; do
            [ -z "$_p" ] && continue
            [ "${#_p}" -gt 64 ] && _bad=1
            _cb_dec "$_p" || _bad=1
        done < <(cbs_of "$_out")
        assert_ok "role=$_role view=$_v payloads are valid and <=64 bytes" "$_bad"

        # No row may exceed Telegram's 8-button limit.
        _wide=0
        while IFS= read -r _row; do
            _n=$(printf '%s' "$_row" | grep -o '"text"' | wc -l | tr -d ' ')
            [ "$_n" -gt 8 ] && _wide=1
        done < <(printf '%s' "$_mk" | sed 's/\[/\n[/g')
        assert_ok "role=$_role view=$_v no row exceeds 8 buttons" "$_wide"

        # The body must fit one message (the chunker is tested separately).
        _body=$(printf '%s' "$_out" | head -n -1)
        assert_ok "role=$_role view=$_v body fits one message" \
            "$([ "${#_body}" -le 4096 ] && echo 0 || echo 1)"
    done
done

# ── A role never sees a button it cannot use ─────────────────────────────────
_out=$(render reseller hub)
assert_eq "reseller hub offers no action payloads" 0 "$(cbs_of "$_out" | grep -cE '^[ac]:')"
assert_eq "reseller hub offers no user list" 0 "$(cbs_of "$_out" | grep -c '^u:')"

_out=$(render operator hub)
assert_eq "unrecognised role hub offers no action payloads" 0 "$(cbs_of "$_out" | grep -cE '^[ac]:')"

_out=$(render superadmin hub)
assert_ok "superadmin hub does offer the user list" \
    "$([ "$(cbs_of "$_out" | grep -c '^u:l:')" -ge 1 ] && echo 0 || echo 1)"

# ── A reseller's detail card must not carry destructive actions ──────────────
# _cb_dispatch would refuse them anyway, but advertising them is misleading.
_out=$(render reseller detail user01)
assert_eq "reseller detail card hides destructive buttons" 0 \
    "$(cbs_of "$_out" | grep -cE '^[ac]:(disable|remove|rotate)')"

_out=$(render superadmin detail user01)
assert_ok "superadmin detail card does offer actions" \
    "$([ "$(cbs_of "$_out" | grep -cE '^a:')" -ge 1 ] && echo 0 || echo 1)"

# ── Pagination ───────────────────────────────────────────────────────────────
_p0=$(cbs_of "$(render superadmin list 0)")
assert_eq "page 0 shows a full page of users" 6 "$(printf '%s\n' "$_p0" | grep -c '^u:s:')"
assert_eq "page 0 has no Prev button" 0 "$(printf '%s\n' "$_p0" | grep -c '^u:l:$')"

_p2=$(cbs_of "$(render superadmin list 2)")
assert_eq "last page shows the remaining users" 1 "$(printf '%s\n' "$_p2" | grep -c '^u:s:')"

# An out-of-range page must clamp rather than render an empty keyboard.
_p9=$(cbs_of "$(render superadmin list 99)")
assert_ok "an out-of-range page still renders users" \
    "$([ "$(printf '%s\n' "$_p9" | grep -c '^u:s:')" -ge 1 ] && echo 0 || echo 1)"

# A garbage page value must not produce garbage output.
_px=$(render superadmin list "abc")
assert_ok "a non-numeric page still renders a keyboard" \
    "$(printf '%s' "$_px" | tail -1 | grep -q 'inline_keyboard' && echo 0 || echo 1)"

# Back from a detail card returns to the page it came from.
_cbs=$(cbs_of "$(render superadmin detail user07 1)")
assert_ok "detail card carries its origin page into Back" \
    "$(printf '%s\n' "$_cbs" | grep -q '^u:l:1$' && echo 0 || echo 1)"

# ── A disabled secret offers Enable, not Disable ─────────────────────────────
# user03 is disabled in the fixture.
_cbs=$(cbs_of "$(render superadmin detail user03)")
assert_ok "a disabled secret offers Enable" \
    "$(printf '%s\n' "$_cbs" | grep -q '^a:enable:user03$' && echo 0 || echo 1)"
assert_eq "a disabled secret does not offer Disable" 0 \
    "$(printf '%s\n' "$_cbs" | grep -c '^a:disable:user03$')"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
