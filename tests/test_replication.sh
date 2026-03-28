#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  MTProxyMax — Replication Unit Tests
#  Tests Section 14b (save/load/add/remove) and Section 5 REPLICATION_* keys
#  in save_settings / load_settings round-trip.
#
#  Requirements: bash 4.2+, mktemp, mv, chmod  (no Docker, SSH, systemd)
#  Run: bash tests/test_replication.sh
#
# ─────────────────────────────────────────────────────────────────────────────
# Do NOT use set -e here: tests intentionally call functions that return non-zero
# exit codes and must capture $? before the next statement.
set -o pipefail

# ── Bash version guard ───────────────────────────────────────────────────────
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] || \
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
    echo "SKIP: bash 4.2+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

# ── Temp directory setup ─────────────────────────────────────────────────────
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Override every path the production functions touch
INSTALL_DIR="$TEST_TMPDIR/install"
REPLICATION_FILE="$TEST_TMPDIR/install/replication.conf"
SETTINGS_FILE="$TEST_TMPDIR/install/settings.conf"

mkdir -p "$INSTALL_DIR"

# ── Counter state ─────────────────────────────────────────────────────────────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

pass() {
    local name="$1"
    TESTS_RUN=$(( TESTS_RUN + 1 ))
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    printf "  PASS  %s\n" "$name"
}

fail() {
    local name="$1" detail="${2:-}"
    TESTS_RUN=$(( TESTS_RUN + 1 ))
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILED_NAMES+=("$name")
    printf "  FAIL  %s\n" "$name"
    [ -n "$detail" ] && printf "        %s\n" "$detail"
}

assert_eq() {
    local name="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        pass "$name"
    else
        fail "$name" "got='$got'  want='$want'"
    fi
}

assert_true() {
    local name="$1"; shift
    if "$@" 2>/dev/null; then
        pass "$name"
    else
        fail "$name" "expression returned false: $*"
    fi
}

assert_false() {
    local name="$1"; shift
    if ! "$@" 2>/dev/null; then
        pass "$name"
    else
        fail "$name" "expression returned true (expected false): $*"
    fi
}

# Returns 0 if $2 appears in $1
contains() { [[ "$1" == *"$2"* ]]; }

# ─────────────────────────────────────────────────────────────────────────────
# MINIMAL STUBS — exact copies of only the code we need from mtproxymax.sh
# so we never need to source the full 8200-line script.
# ─────────────────────────────────────────────────────────────────────────────

VERSION="1.0.3"

# Temp-file helper (mirrors Section 1 _mktemp, but isolated to TEST_TMPDIR)
declare -a _TEMP_FILES=()
_cleanup_test_temps() {
    local f
    for f in "${_TEMP_FILES[@]+"${_TEMP_FILES[@]}"}"; do
        rm -f "$f" 2>/dev/null
    done
}

_mktemp() {
    local dir="${1:-${INSTALL_DIR}}"
    local tmp
    tmp=$(mktemp "${dir}/.mtproxymax.XXXXXX") || return 1
    chmod 600 "$tmp"
    _TEMP_FILES+=("$tmp")
    echo "$tmp"
}

# Logging stubs — capture output for assertions, suppress visual decoration
_LAST_ERROR=""
_LAST_SUCCESS=""
log_error()   { _LAST_ERROR="$1";   printf "  [ERR] %s\n" "$1" >&2; }
log_success() { _LAST_SUCCESS="$1"; }
log_info()    { :; }
log_warn()    { :; }

# ── Replication arrays (Section 14b) ─────────────────────────────────────────
declare -a REPL_HOSTS=()
declare -a REPL_PORTS=()
declare -a REPL_LABELS=()
declare -a REPL_ENABLED=()
declare -a REPL_LAST_SYNC=()
declare -a REPL_STATUS=()

# save_replication — exact copy of Section 14b
save_replication() {
    mkdir -p "$INSTALL_DIR"
    local tmp
    tmp=$(_mktemp) || { log_error "Cannot create temp file"; return 1; }

    {
        echo "# MTProxyMax Replication Slaves — v${VERSION}"
        echo "# Format: HOST|PORT|LABEL|ENABLED|LAST_SYNC|STATUS"
        echo "# DO NOT EDIT MANUALLY — use 'mtproxymax replication' commands"
        local i
        for i in "${!REPL_HOSTS[@]}"; do
            echo "${REPL_HOSTS[$i]}|${REPL_PORTS[$i]}|${REPL_LABELS[$i]}|${REPL_ENABLED[$i]}|${REPL_LAST_SYNC[$i]}|${REPL_STATUS[$i]}"
        done
    } > "$tmp"

    chmod 600 "$tmp"
    mv "$tmp" "$REPLICATION_FILE"
}

# load_replication — exact copy of Section 14b
load_replication() {
    REPL_HOSTS=()
    REPL_PORTS=()
    REPL_LABELS=()
    REPL_ENABLED=()
    REPL_LAST_SYNC=()
    REPL_STATUS=()

    [ -f "$REPLICATION_FILE" ] || return 0

    while IFS='|' read -r _rl_h _rl_p _rl_l _rl_e _rl_ls _rl_st; do
        [[ "$_rl_h" =~ ^[[:space:]]*# ]] && continue
        [[ "$_rl_h" =~ ^[[:space:]]*$ ]] && continue
        [[ "$_rl_h" =~ ^[a-zA-Z0-9._-]+$ ]] || continue
        [[ "$_rl_p" =~ ^[0-9]+$ ]] && [ "$_rl_p" -ge 1 ] && [ "$_rl_p" -le 65535 ] || _rl_p=22
        [ "$_rl_e" = "false" ] || _rl_e="true"
        [[ "$_rl_ls" =~ ^[0-9]+$ ]] || _rl_ls=0
        [[ "$_rl_st" =~ ^(ok|error|unknown)$ ]] || _rl_st="unknown"

        REPL_HOSTS+=("$_rl_h")
        REPL_PORTS+=("$_rl_p")
        REPL_LABELS+=("${_rl_l:-$_rl_h}")
        REPL_ENABLED+=("$_rl_e")
        REPL_LAST_SYNC+=("$_rl_ls")
        REPL_STATUS+=("$_rl_st")
    done < "$REPLICATION_FILE"
}

# replication_add — exact copy of Section 14b
replication_add() {
    local host="${1:-}" port="${2:-22}" label="${3:-}"

    if [ -z "$host" ]; then
        log_error "Usage: replication add <host> [port] [label]"
        return 1
    fi

    if [[ ! "$host" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid host format. Use IP or FQDN (letters, digits, dots, hyphens only)"
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Port must be 1-65535"
        return 1
    fi

    load_replication
    local i
    for i in "${!REPL_HOSTS[@]}"; do
        if [ "${REPL_HOSTS[$i]}" = "$host" ]; then
            log_error "Slave '${host}' already registered"
            return 1
        fi
    done

    [ -z "$label" ] && label="$host"

    REPL_HOSTS+=("$host")
    REPL_PORTS+=("$port")
    REPL_LABELS+=("$label")
    REPL_ENABLED+=("true")
    REPL_LAST_SYNC+=("0")
    REPL_STATUS+=("unknown")

    save_replication
    log_success "Slave '${label}' (${host}:${port}) added"
}

# replication_remove — exact copy of Section 14b
replication_remove() {
    local target="${1:-}"

    if [ -z "$target" ]; then
        log_error "Usage: replication remove <host_or_label>"
        return 1
    fi

    load_replication

    local idx=-1 i
    for i in "${!REPL_HOSTS[@]}"; do
        if [ "${REPL_HOSTS[$i]}" = "$target" ] || [ "${REPL_LABELS[$i]}" = "$target" ]; then
            idx=$i; break
        fi
    done

    if [ $idx -eq -1 ]; then
        log_error "Slave '${target}' not found"
        return 1
    fi

    local label="${REPL_LABELS[$idx]}"
    local new_hosts=() new_ports=() new_labels=() new_enabled=() new_last_sync=() new_status=()
    for i in "${!REPL_HOSTS[@]}"; do
        [ "$i" -eq "$idx" ] && continue
        new_hosts+=("${REPL_HOSTS[$i]}")
        new_ports+=("${REPL_PORTS[$i]}")
        new_labels+=("${REPL_LABELS[$i]}")
        new_enabled+=("${REPL_ENABLED[$i]}")
        new_last_sync+=("${REPL_LAST_SYNC[$i]}")
        new_status+=("${REPL_STATUS[$i]}")
    done

    REPL_HOSTS=("${new_hosts[@]+"${new_hosts[@]}"}")
    REPL_PORTS=("${new_ports[@]+"${new_ports[@]}"}")
    REPL_LABELS=("${new_labels[@]+"${new_labels[@]}"}")
    REPL_ENABLED=("${new_enabled[@]+"${new_enabled[@]}"}")
    REPL_LAST_SYNC=("${new_last_sync[@]+"${new_last_sync[@]}"}")
    REPL_STATUS=("${new_status[@]+"${new_status[@]}"}")

    save_replication
    log_success "Slave '${label}' removed"
}

# ── Settings stubs (Section 5) — only the REPLICATION_* vars we care about ───

REPLICATION_ENABLED="false"
REPLICATION_ROLE="standalone"
REPLICATION_SYNC_INTERVAL=60
REPLICATION_SSH_PORT=22
REPLICATION_SSH_USER="root"
REPLICATION_DELETE_EXTRA="true"
REPLICATION_SSH_KEY_PATH="/opt/mtproxymax/.ssh/id_ed25519"
REPLICATION_EXCLUDE="relay_stats,backups,connection.log,.ssh,mtproxymax-telegram.sh,mtproxymax-sync.sh"
REPLICATION_RESTART_ON_CHANGE="true"
REPLICATION_LOG="/var/log/mtproxymax-sync.log"

# Remaining settings vars required by save_settings heredoc
PROXY_PORT=443
PROXY_METRICS_PORT=9090
PROXY_DOMAIN="cloudflare.com"
PROXY_CONCURRENCY=8192
PROXY_CPUS=""
PROXY_MEMORY=""
CUSTOM_IP=""
FAKE_CERT_LEN=2048
PROXY_PROTOCOL="false"
PROXY_PROTOCOL_TRUSTED_CIDRS=""
AD_TAG=""
GEOBLOCK_MODE="blacklist"
BLOCKLIST_COUNTRIES=""
MASKING_ENABLED="true"
MASKING_HOST=""
MASKING_PORT=443
UNKNOWN_SNI_ACTION="mask"
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_INTERVAL=6
TELEGRAM_ALERTS_ENABLED="true"
TELEGRAM_SERVER_LABEL="MTProxyMax"
AUTO_UPDATE_ENABLED="true"

# save_settings — exact copy of Section 5 (minus the flock/atomic detail which
# is already handled by _mktemp + mv in the original)
save_settings() {
    mkdir -p "$INSTALL_DIR"

    local tmp
    tmp=$(_mktemp) || { log_error "Cannot create temp file"; return 1; }

    cat > "$tmp" << SETTINGS_EOF
# MTProxyMax Settings — v${VERSION}
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# DO NOT EDIT MANUALLY — use 'mtproxymax' to change settings

# Proxy Configuration
PROXY_PORT='${PROXY_PORT}'
PROXY_METRICS_PORT='${PROXY_METRICS_PORT}'
PROXY_DOMAIN='${PROXY_DOMAIN}'
PROXY_CONCURRENCY='${PROXY_CONCURRENCY}'
PROXY_CPUS='${PROXY_CPUS}'
PROXY_MEMORY='${PROXY_MEMORY}'
CUSTOM_IP='${CUSTOM_IP}'
FAKE_CERT_LEN='${FAKE_CERT_LEN}'
PROXY_PROTOCOL='${PROXY_PROTOCOL}'
PROXY_PROTOCOL_TRUSTED_CIDRS='${PROXY_PROTOCOL_TRUSTED_CIDRS}'

# Ad-Tag (from @MTProxyBot)
AD_TAG='${AD_TAG}'

# Geo-Blocking
GEOBLOCK_MODE='${GEOBLOCK_MODE}'
BLOCKLIST_COUNTRIES='${BLOCKLIST_COUNTRIES}'

# Traffic Masking
MASKING_ENABLED='${MASKING_ENABLED}'
MASKING_HOST='${MASKING_HOST}'
MASKING_PORT='${MASKING_PORT}'
UNKNOWN_SNI_ACTION='${UNKNOWN_SNI_ACTION}'

# Telegram Integration
TELEGRAM_ENABLED='${TELEGRAM_ENABLED}'
TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'
TELEGRAM_CHAT_ID='${TELEGRAM_CHAT_ID}'
TELEGRAM_INTERVAL='${TELEGRAM_INTERVAL}'
TELEGRAM_ALERTS_ENABLED='${TELEGRAM_ALERTS_ENABLED}'
TELEGRAM_SERVER_LABEL='${TELEGRAM_SERVER_LABEL}'

# Auto-Update
AUTO_UPDATE_ENABLED='${AUTO_UPDATE_ENABLED}'

# Replication / HA
REPLICATION_ENABLED='${REPLICATION_ENABLED}'
REPLICATION_ROLE='${REPLICATION_ROLE}'
REPLICATION_SYNC_INTERVAL='${REPLICATION_SYNC_INTERVAL}'
REPLICATION_SSH_PORT='${REPLICATION_SSH_PORT}'
REPLICATION_SSH_USER='${REPLICATION_SSH_USER}'
REPLICATION_DELETE_EXTRA='${REPLICATION_DELETE_EXTRA}'
REPLICATION_SSH_KEY_PATH='${REPLICATION_SSH_KEY_PATH}'
REPLICATION_EXCLUDE='${REPLICATION_EXCLUDE}'
REPLICATION_RESTART_ON_CHANGE='${REPLICATION_RESTART_ON_CHANGE}'
REPLICATION_LOG='${REPLICATION_LOG}'
SETTINGS_EOF

    chmod 600 "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
}

# load_settings — exact copy of Section 5
load_settings() {
    [ -f "$SETTINGS_FILE" ] || return 0

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\'([^\']*)\'$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\"([^\"]*)\"$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=([^[:space:]]*)$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        else
            continue
        fi

        case "$key" in
            PROXY_PORT|PROXY_METRICS_PORT|PROXY_DOMAIN|PROXY_CONCURRENCY|\
            PROXY_CPUS|PROXY_MEMORY|CUSTOM_IP|FAKE_CERT_LEN|PROXY_PROTOCOL|PROXY_PROTOCOL_TRUSTED_CIDRS|AD_TAG|GEOBLOCK_MODE|BLOCKLIST_COUNTRIES|\
            MASKING_ENABLED|MASKING_HOST|MASKING_PORT|UNKNOWN_SNI_ACTION|\
            TELEGRAM_ENABLED|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|\
            TELEGRAM_INTERVAL|TELEGRAM_ALERTS_ENABLED|TELEGRAM_SERVER_LABEL|\
            AUTO_UPDATE_ENABLED|\
            REPLICATION_ENABLED|REPLICATION_ROLE|REPLICATION_SYNC_INTERVAL|\
            REPLICATION_SSH_PORT|REPLICATION_SSH_USER|REPLICATION_DELETE_EXTRA|REPLICATION_SSH_KEY_PATH|REPLICATION_EXCLUDE|\
            REPLICATION_RESTART_ON_CHANGE|REPLICATION_LOG)
                printf -v "$key" '%s' "$val"
                ;;
        esac
    done < "$SETTINGS_FILE"

    # Post-load validation — exact copy from Section 5
    [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_PORT" -ge 1 ] && [ "$PROXY_PORT" -le 65535 ] || PROXY_PORT=443
    [[ "$PROXY_METRICS_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_METRICS_PORT" -ge 1 ] && [ "$PROXY_METRICS_PORT" -le 65535 ] || PROXY_METRICS_PORT=9090
    [[ "$MASKING_PORT" =~ ^[0-9]+$ ]] && [ "$MASKING_PORT" -ge 1 ] && [ "$MASKING_PORT" -le 65535 ] || MASKING_PORT=443
    [[ "$UNKNOWN_SNI_ACTION" == "drop" ]] || UNKNOWN_SNI_ACTION="mask"
    [[ "$FAKE_CERT_LEN" =~ ^[0-9]+$ ]] && [ "$FAKE_CERT_LEN" -ge 512 ] || FAKE_CERT_LEN=2048
    [[ "$PROXY_CONCURRENCY" =~ ^[0-9]+$ ]] || PROXY_CONCURRENCY=8192
    [[ "$PROXY_PROTOCOL" == "true" ]] || PROXY_PROTOCOL="false"
    [[ "$GEOBLOCK_MODE" == "whitelist" ]] || GEOBLOCK_MODE="blacklist"
    [[ "$TELEGRAM_INTERVAL" =~ ^[0-9]+$ ]] || TELEGRAM_INTERVAL=6
    [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]] || TELEGRAM_CHAT_ID=""
    # Replication validation
    [[ "$REPLICATION_ROLE" =~ ^(standalone|master|slave)$ ]] || REPLICATION_ROLE="standalone"
    [[ "$REPLICATION_SYNC_INTERVAL" =~ ^[0-9]+$ ]] && [ "$REPLICATION_SYNC_INTERVAL" -ge 10 ] || REPLICATION_SYNC_INTERVAL=60
    [[ "$REPLICATION_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$REPLICATION_SSH_PORT" -ge 1 ] && [ "$REPLICATION_SSH_PORT" -le 65535 ] || REPLICATION_SSH_PORT=22
    [[ "$REPLICATION_SSH_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || REPLICATION_SSH_USER="root"
    [[ "$REPLICATION_DELETE_EXTRA" == "false" ]] || REPLICATION_DELETE_EXTRA="true"
    [[ "$REPLICATION_ENABLED" == "true" ]] || REPLICATION_ENABLED="false"
    [[ "$REPLICATION_RESTART_ON_CHANGE" == "false" ]] || REPLICATION_RESTART_ON_CHANGE="true"
}

# Helper: wipe only the in-memory arrays (leave the file on disk untouched).
# Use this after save_replication when you want to test that load_replication
# correctly re-populates the arrays from the file.
_clear_repl_arrays() {
    REPL_HOSTS=()
    REPL_PORTS=()
    REPL_LABELS=()
    REPL_ENABLED=()
    REPL_LAST_SYNC=()
    REPL_STATUS=()
}

# Helper: wipe both the in-memory arrays AND the on-disk file.
# Use this at the start of each test that needs a clean slate.
_reset_replication() {
    _clear_repl_arrays
    rm -f "$REPLICATION_FILE"
}

# Helper: reset settings vars to their canonical defaults (leave file on disk).
# Use this after save_settings when you want to test that load_settings
# correctly re-populates the vars from the file.
_clear_settings_vars() {
    REPLICATION_ENABLED="false"
    REPLICATION_ROLE="standalone"
    REPLICATION_SYNC_INTERVAL=60
    REPLICATION_SSH_PORT=22
    REPLICATION_SSH_USER="root"
    REPLICATION_DELETE_EXTRA="true"
    REPLICATION_SSH_KEY_PATH="/opt/mtproxymax/.ssh/id_ed25519"
    REPLICATION_EXCLUDE="relay_stats,backups"
    REPLICATION_RESTART_ON_CHANGE="true"
    REPLICATION_LOG="/var/log/mtproxymax-sync.log"
}

# Helper: reset settings vars AND remove settings.conf.
# Use this at the start of each settings test that needs a clean slate.
_reset_settings_vars() {
    _clear_settings_vars
    rm -f "$SETTINGS_FILE"
}

# ═════════════════════════════════════════════════════════════════════════════
#  TEST SUITES
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Suite 1 — save_replication / load_replication round-trip
# ─────────────────────────────────────────────────────────────────────────────
printf "\n--- Suite 1: save_replication / load_replication round-trip ---\n"

# 1.1  Empty save produces a parseable (empty) file
_reset_replication
save_replication
assert_true "1.1  empty save creates replication.conf" test -f "$REPLICATION_FILE"
load_replication
assert_eq   "1.1  empty load gives zero hosts" "${#REPL_HOSTS[@]}" "0"

# 1.2  Single entry survives a save→load round-trip
# Populate arrays directly, save to file, wipe arrays (leave file), then reload.
_reset_replication
REPL_HOSTS=("192.168.1.10")
REPL_PORTS=("22")
REPL_LABELS=("slave-1")
REPL_ENABLED=("true")
REPL_LAST_SYNC=("1711450000")
REPL_STATUS=("ok")
save_replication
_clear_repl_arrays    # keep file on disk; reset in-memory state only
load_replication
assert_eq "1.2  host preserved"      "${REPL_HOSTS[0]}"      "192.168.1.10"
assert_eq "1.2  port preserved"      "${REPL_PORTS[0]}"      "22"
assert_eq "1.2  label preserved"     "${REPL_LABELS[0]}"     "slave-1"
assert_eq "1.2  enabled preserved"   "${REPL_ENABLED[0]}"    "true"
assert_eq "1.2  last_sync preserved" "${REPL_LAST_SYNC[0]}"  "1711450000"
assert_eq "1.2  status preserved"    "${REPL_STATUS[0]}"     "ok"

# 1.3  Multiple entries — all survive in order
_reset_replication
REPL_HOSTS=("10.0.0.1" "10.0.0.2" "backup.example.com")
REPL_PORTS=("22" "2222" "22")
REPL_LABELS=("alpha" "beta" "gamma")
REPL_ENABLED=("true" "false" "true")
REPL_LAST_SYNC=("0" "9999" "12345")
REPL_STATUS=("unknown" "error" "ok")
save_replication
_clear_repl_arrays    # keep file on disk; reset in-memory state only
load_replication
assert_eq "1.3  count"          "${#REPL_HOSTS[@]}"    "3"
assert_eq "1.3  host[1]"        "${REPL_HOSTS[1]}"     "10.0.0.2"
assert_eq "1.3  port[1]"        "${REPL_PORTS[1]}"     "2222"
assert_eq "1.3  label[2]"       "${REPL_LABELS[2]}"    "gamma"
assert_eq "1.3  status[1]"      "${REPL_STATUS[1]}"    "error"
assert_eq "1.3  last_sync[2]"   "${REPL_LAST_SYNC[2]}" "12345"

# 1.4  Comments and blank lines in the file are skipped on load
_reset_replication
printf "# comment line\n\n192.168.5.5|22|node5|true|0|ok\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.4  only real entry loaded" "${#REPL_HOSTS[@]}" "1"
assert_eq "1.4  host is correct"        "${REPL_HOSTS[0]}"  "192.168.5.5"

# 1.5  load_replication normalises a bad port (outside 1-65535) to 22
_reset_replication
printf "10.0.0.9|99999|badinput|true|0|ok\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.5  bad port normalised to 22" "${REPL_PORTS[0]}" "22"

# 1.6  load_replication normalises an unknown status to "unknown"
_reset_replication
printf "10.0.0.9|22|node|true|0|GARBAGE\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.6  bad status normalised" "${REPL_STATUS[0]}" "unknown"

# 1.7  load_replication treats any enabled value != "false" as "true"
_reset_replication
printf "10.0.0.9|22|node|RANDOM|0|ok\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.7  non-false enabled treated as true" "${REPL_ENABLED[0]}" "true"

# 1.8  load_replication uses host as label when label column is empty
_reset_replication
printf "10.0.0.9|22||true|0|ok\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.8  empty label falls back to host" "${REPL_LABELS[0]}" "10.0.0.9"

# 1.9  Entries with invalid host characters are silently skipped
_reset_replication
printf "bad host!|22|x|true|0|ok\n10.0.0.1|22|valid|true|0|ok\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.9  invalid host skipped" "${#REPL_HOSTS[@]}"  "1"
assert_eq "1.9  valid host loaded"    "${REPL_HOSTS[0]}"   "10.0.0.1"

# 1.10  load_replication normalises a non-numeric last_sync to 0
_reset_replication
printf "10.0.0.1|22|node|true|NOTANUMBER|ok\n" > "$REPLICATION_FILE"
load_replication
assert_eq "1.10 bad last_sync normalised to 0" "${REPL_LAST_SYNC[0]}" "0"

# ─────────────────────────────────────────────────────────────────────────────
# Suite 2 — replication_add validation
# ─────────────────────────────────────────────────────────────────────────────
printf "\n--- Suite 2: replication_add ---\n"

# 2.1  Missing host returns error
_reset_replication
replication_add "" 22 "label" 2>/dev/null
assert_eq "2.1  missing host returns 1" "$?" "1"
assert_true "2.1  error message set" contains "$_LAST_ERROR" "Usage"

# 2.2  Invalid host with spaces returns error
_reset_replication
replication_add "invalid host" 22 "label" 2>/dev/null
assert_eq "2.2  host with space returns 1" "$?" "1"
assert_true "2.2  error mentions format" contains "$_LAST_ERROR" "Invalid host"

# 2.3  Invalid host with shell special chars returns error
_reset_replication
replication_add "host;rm -rf" 22 "label" 2>/dev/null
assert_eq "2.3  host with special chars returns 1" "$?" "1"

# 2.4  Port 0 is rejected
_reset_replication
replication_add "10.0.0.1" 0 "label" 2>/dev/null
assert_eq "2.4  port 0 rejected" "$?" "1"
assert_true "2.4  error mentions port" contains "$_LAST_ERROR" "Port"

# 2.5  Port 65536 is rejected
_reset_replication
replication_add "10.0.0.1" 65536 "label" 2>/dev/null
assert_eq "2.5  port 65536 rejected" "$?" "1"

# 2.6  Port 65535 is accepted (boundary)
_reset_replication
replication_add "10.0.0.1" 65535 "boundary-label"
assert_eq "2.6  port 65535 accepted" "$?" "0"
load_replication
assert_eq "2.6  host written"  "${REPL_HOSTS[0]}"  "10.0.0.1"
assert_eq "2.6  port written"  "${REPL_PORTS[0]}"  "65535"
assert_eq "2.6  label written" "${REPL_LABELS[0]}" "boundary-label"

# 2.7  Port 1 is accepted (boundary)
_reset_replication
replication_add "10.0.0.2" 1 "port-one"
assert_eq "2.7  port 1 accepted" "$?" "0"

# 2.8  Non-numeric port is rejected
_reset_replication
replication_add "10.0.0.1" "ssh" "label" 2>/dev/null
assert_eq "2.8  non-numeric port rejected" "$?" "1"

# 2.9  FQDN hostname is accepted
_reset_replication
replication_add "slave.example.com" 22 "fqdn-slave"
assert_eq "2.9  FQDN accepted" "$?" "0"
load_replication
assert_eq "2.9  FQDN host stored" "${REPL_HOSTS[0]}" "slave.example.com"

# 2.10  Hostname with hyphens is accepted
_reset_replication
replication_add "my-slave-01" 22 ""
assert_eq "2.10 hyphen hostname accepted" "$?" "0"

# 2.11  Label defaults to host when omitted
_reset_replication
replication_add "10.5.5.5" 22 ""
load_replication
assert_eq "2.11 label defaults to host" "${REPL_LABELS[0]}" "10.5.5.5"

# 2.12  Default port is 22 when second arg is omitted
_reset_replication
replication_add "10.5.5.6"
load_replication
assert_eq "2.12 default port is 22" "${REPL_PORTS[0]}" "22"

# 2.13  New entry gets enabled=true and status=unknown
_reset_replication
replication_add "10.5.5.7" 22 "newnode"
load_replication
assert_eq "2.13 new entry enabled=true"     "${REPL_ENABLED[0]}"   "true"
assert_eq "2.13 new entry status=unknown"   "${REPL_STATUS[0]}"    "unknown"
assert_eq "2.13 new entry last_sync=0"      "${REPL_LAST_SYNC[0]}" "0"

# 2.14  Duplicate host is rejected.
_reset_replication
replication_add "10.0.0.1" 22 "first"
replication_add "10.0.0.1" 22 "second" 2>/dev/null
assert_eq "2.14 duplicate rejected" "$?" "1"
assert_true "2.14 error mentions already registered" contains "$_LAST_ERROR" "already registered"
# Only one entry should exist
load_replication
assert_eq "2.14 only one entry in file" "${#REPL_HOSTS[@]}" "1"

# 2.15  Adding a second different host increases count to 2.
_reset_replication
replication_add "10.0.0.1" 22 "alpha"
replication_add "10.0.0.2" 22 "beta"
load_replication
assert_eq "2.15 two entries" "${#REPL_HOSTS[@]}" "2"

# 2.16  IPv6-like addresses are rejected (contain colons — not in allowed set)
_reset_replication
replication_add "2001:db8::1" 22 "v6" 2>/dev/null
assert_eq "2.16 IPv6 address rejected" "$?" "1"

# ─────────────────────────────────────────────────────────────────────────────
# Suite 3 — replication_remove
# ─────────────────────────────────────────────────────────────────────────────
printf "\n--- Suite 3: replication_remove ---\n"

# 3.1  Missing target returns error
_reset_replication
replication_add "10.0.0.1" 22 "node1"
replication_remove "" 2>/dev/null
assert_eq "3.1  missing target returns 1" "$?" "1"
assert_true "3.1  error mentions Usage" contains "$_LAST_ERROR" "Usage"

# 3.2  Not-found target returns error
_reset_replication
replication_add "10.0.0.1" 22 "node1"
replication_remove "nonexistent" 2>/dev/null
assert_eq "3.2  not-found returns 1" "$?" "1"
assert_true "3.2  error mentions not found" contains "$_LAST_ERROR" "not found"

# 3.3  Remove by host address.
_reset_replication
replication_add "10.0.0.1" 22 "node1"
replication_add "10.0.0.2" 22 "node2"
replication_remove "10.0.0.1"
assert_eq "3.3  remove by host succeeds" "$?" "0"
load_replication
assert_eq "3.3  one entry remains"    "${#REPL_HOSTS[@]}" "1"
assert_eq "3.3  remaining host"       "${REPL_HOSTS[0]}"  "10.0.0.2"

# 3.4  Remove by label.
_reset_replication
replication_add "10.0.0.1" 22 "alpha"
replication_add "10.0.0.2" 22 "beta"
replication_remove "alpha"
assert_eq "3.4  remove by label succeeds" "$?" "0"
load_replication
assert_eq "3.4  one entry remains"        "${#REPL_HOSTS[@]}" "1"
assert_eq "3.4  remaining label is beta"  "${REPL_LABELS[0]}" "beta"

# 3.5  Remove the only entry leaves empty file
_reset_replication
replication_add "10.0.0.1" 22 "sole"
replication_remove "sole"
assert_eq "3.5  remove only entry succeeds" "$?" "0"
load_replication
assert_eq "3.5  no entries remain" "${#REPL_HOSTS[@]}" "0"

# 3.6  Remove middle entry of three — order of survivors preserved.
_reset_replication
replication_add "10.0.0.1" 22 "alpha"
replication_add "10.0.0.2" 22 "beta"
replication_add "10.0.0.3" 22 "gamma"
replication_remove "beta"
load_replication
assert_eq "3.6  two entries remain"          "${#REPL_HOSTS[@]}" "2"
assert_eq "3.6  first survivor is alpha"     "${REPL_LABELS[0]}" "alpha"
assert_eq "3.6  second survivor is gamma"    "${REPL_LABELS[1]}" "gamma"

# 3.7  Cannot remove same entry twice
_reset_replication
replication_add "10.0.0.1" 22 "node1"
replication_remove "node1"
replication_remove "node1" 2>/dev/null
assert_eq "3.7  second remove returns 1" "$?" "1"

# 3.8  Remove by label when label differs from host
_reset_replication
replication_add "192.168.99.99" 2222 "my-custom-label"
replication_remove "my-custom-label"
assert_eq "3.8  remove by custom label" "$?" "0"
load_replication
assert_eq "3.8  empty after remove" "${#REPL_HOSTS[@]}" "0"

# ─────────────────────────────────────────────────────────────────────────────
# Suite 4 — REPLICATION_* keys in save_settings / load_settings round-trip
# ─────────────────────────────────────────────────────────────────────────────
printf "\n--- Suite 4: REPLICATION_* keys in save_settings / load_settings ---\n"

# 4.1  Basic round-trip of all REPLICATION_* vars
_reset_settings_vars
REPLICATION_ENABLED="true"
REPLICATION_ROLE="master"
REPLICATION_SYNC_INTERVAL=120
REPLICATION_SSH_PORT=2222
REPLICATION_SSH_USER="syncuser"
REPLICATION_DELETE_EXTRA="false"
REPLICATION_SSH_KEY_PATH="/home/user/.ssh/id_ed25519"
REPLICATION_EXCLUDE="backups,connection.log"
REPLICATION_RESTART_ON_CHANGE="false"
REPLICATION_LOG="/tmp/sync.log"
save_settings

# Wipe vars only (leave file on disk) then reload to verify round-trip
_clear_settings_vars
load_settings

assert_eq "4.1  REPLICATION_ENABLED"          "$REPLICATION_ENABLED"          "true"
assert_eq "4.1  REPLICATION_ROLE"             "$REPLICATION_ROLE"             "master"
assert_eq "4.1  REPLICATION_SYNC_INTERVAL"    "$REPLICATION_SYNC_INTERVAL"    "120"
assert_eq "4.1  REPLICATION_SSH_PORT"         "$REPLICATION_SSH_PORT"         "2222"
assert_eq "4.1  REPLICATION_SSH_KEY_PATH"     "$REPLICATION_SSH_KEY_PATH"     "/home/user/.ssh/id_ed25519"
assert_eq "4.1  REPLICATION_EXCLUDE"          "$REPLICATION_EXCLUDE"          "backups,connection.log"
assert_eq "4.1  REPLICATION_SSH_USER"          "$REPLICATION_SSH_USER"          "syncuser"
assert_eq "4.1  REPLICATION_DELETE_EXTRA"     "$REPLICATION_DELETE_EXTRA"     "false"
assert_eq "4.1  REPLICATION_RESTART_ON_CHANGE" "$REPLICATION_RESTART_ON_CHANGE" "false"
assert_eq "4.1  REPLICATION_LOG"              "$REPLICATION_LOG"              "/tmp/sync.log"

# 4.2  slave role round-trips correctly
_reset_settings_vars
REPLICATION_ROLE="slave"
save_settings
_clear_settings_vars
load_settings
assert_eq "4.2  REPLICATION_ROLE=slave preserved" "$REPLICATION_ROLE" "slave"

# 4.3  standalone role round-trips correctly
_reset_settings_vars
REPLICATION_ROLE="standalone"
save_settings
_clear_settings_vars
load_settings
assert_eq "4.3  REPLICATION_ROLE=standalone preserved" "$REPLICATION_ROLE" "standalone"

# 4.4  Post-load validation: invalid REPLICATION_ROLE becomes standalone
_reset_settings_vars
REPLICATION_ROLE="supermaster"   # not in allowed set
save_settings
_clear_settings_vars
load_settings
assert_eq "4.4  bad role normalised to standalone" "$REPLICATION_ROLE" "standalone"

# 4.5  Post-load validation: REPLICATION_ENABLED != "true" becomes "false"
_reset_settings_vars
REPLICATION_ENABLED="yes"
save_settings
_clear_settings_vars
load_settings
assert_eq "4.5  REPLICATION_ENABLED='yes' normalised to false" "$REPLICATION_ENABLED" "false"

# 4.6  Post-load validation: REPLICATION_SYNC_INTERVAL < 10 reset to 60
_reset_settings_vars
REPLICATION_SYNC_INTERVAL=5
save_settings
_clear_settings_vars
load_settings
assert_eq "4.6  sync interval < 10 reset to 60" "$REPLICATION_SYNC_INTERVAL" "60"

# 4.7  Post-load validation: REPLICATION_SYNC_INTERVAL = 10 is accepted (boundary)
_reset_settings_vars
REPLICATION_SYNC_INTERVAL=10
save_settings
_clear_settings_vars
load_settings
assert_eq "4.7  sync interval = 10 accepted" "$REPLICATION_SYNC_INTERVAL" "10"

# 4.8  Post-load validation: non-numeric REPLICATION_SYNC_INTERVAL reset to 60
_reset_settings_vars
REPLICATION_SYNC_INTERVAL="weekly"
save_settings
_clear_settings_vars
load_settings
assert_eq "4.8  non-numeric interval reset to 60" "$REPLICATION_SYNC_INTERVAL" "60"

# 4.9  Post-load validation: bad SSH port (0) reset to 22
_reset_settings_vars
REPLICATION_SSH_PORT=0
save_settings
_clear_settings_vars
load_settings
assert_eq "4.9  SSH port 0 reset to 22" "$REPLICATION_SSH_PORT" "22"

# 4.10  Post-load validation: SSH port 65535 accepted
_reset_settings_vars
REPLICATION_SSH_PORT=65535
save_settings
_clear_settings_vars
load_settings
assert_eq "4.10 SSH port 65535 accepted" "$REPLICATION_SSH_PORT" "65535"

# 4.11  Post-load validation: REPLICATION_RESTART_ON_CHANGE
#        The rule: anything != "false" becomes "true"
_reset_settings_vars
REPLICATION_RESTART_ON_CHANGE="false"
save_settings
_clear_settings_vars
load_settings
assert_eq "4.11 RESTART_ON_CHANGE=false preserved" "$REPLICATION_RESTART_ON_CHANGE" "false"

# 4.12  REPLICATION_RESTART_ON_CHANGE any non-"false" value → "true"
_reset_settings_vars
REPLICATION_RESTART_ON_CHANGE="maybe"
save_settings
_clear_settings_vars
load_settings
assert_eq "4.12 RESTART_ON_CHANGE='maybe' normalised to true" "$REPLICATION_RESTART_ON_CHANGE" "true"

# 4.13  load_settings is a no-op when SETTINGS_FILE is absent
_reset_settings_vars
rm -f "$SETTINGS_FILE"
REPLICATION_ENABLED="true"    # set a non-default value
load_settings                  # should not reset anything when file is absent
assert_eq "4.13 load without file is no-op" "$REPLICATION_ENABLED" "true"

# 4.14  Keys not in the whitelist are ignored (security: no arbitrary variable injection)
_reset_settings_vars
{
    echo "REPLICATION_ENABLED='true'"
    echo "EVIL_VAR='rm -rf /'"        # must be ignored
    echo "REPLICATION_ROLE='master'"
} > "$SETTINGS_FILE"
EVIL_VAR=""
load_settings
assert_eq "4.14 REPLICATION_ENABLED loaded"    "$REPLICATION_ENABLED" "true"
assert_eq "4.14 REPLICATION_ROLE loaded"       "$REPLICATION_ROLE"    "master"
assert_eq "4.14 EVIL_VAR not injected"         "$EVIL_VAR"            ""

# ─────────────────────────────────────────────────────────────────────────────
# Suite 5 — replication.conf file integrity
# ─────────────────────────────────────────────────────────────────────────────
printf "\n--- Suite 5: replication.conf file integrity ---\n"

# 5.1  replication.conf has mode 600 after save
# NOTE: Skipped on Windows/NTFS where chmod 600 is a no-op and stat returns 644.
_reset_replication
save_replication
if [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || [[ "$(uname -s 2>/dev/null)" == MSYS* ]] || [[ "$(uname -s 2>/dev/null)" == CYGWIN* ]]; then
    pass "5.1  permissions check (Windows — chmod 600 is no-op, skipped)"
else
    perms=$(stat -c "%a" "$REPLICATION_FILE" 2>/dev/null || stat -f "%OLp" "$REPLICATION_FILE" 2>/dev/null || echo "skip")
    if [ "$perms" = "skip" ]; then
        pass "5.1  permissions check (stat not available — skipped)"
    else
        assert_eq "5.1  replication.conf has mode 600" "$perms" "600"
    fi
fi

# 5.2  settings.conf has mode 600 after save
# NOTE: Skipped on Windows/NTFS where chmod 600 is a no-op and stat returns 644.
_reset_settings_vars
save_settings
if [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || [[ "$(uname -s 2>/dev/null)" == MSYS* ]] || [[ "$(uname -s 2>/dev/null)" == CYGWIN* ]]; then
    pass "5.2  permissions check (Windows — chmod 600 is no-op, skipped)"
else
    perms=$(stat -c "%a" "$SETTINGS_FILE" 2>/dev/null || stat -f "%OLp" "$SETTINGS_FILE" 2>/dev/null || echo "skip")
    if [ "$perms" = "skip" ]; then
        pass "5.2  permissions check (stat not available — skipped)"
    else
        assert_eq "5.2  settings.conf has mode 600" "$perms" "600"
    fi
fi

# 5.3  replication.conf contains the standard header comment
_reset_replication
REPL_HOSTS=("10.1.1.1"); REPL_PORTS=("22"); REPL_LABELS=("x")
REPL_ENABLED=("true"); REPL_LAST_SYNC=("0"); REPL_STATUS=("ok")
save_replication
assert_true "5.3  header comment present" grep -q "MTProxyMax Replication Slaves" "$REPLICATION_FILE"

# 5.4  replication.conf contains the format comment
assert_true "5.4  format comment present" grep -q "HOST|PORT|LABEL" "$REPLICATION_FILE"

# 5.5  Data row has correct pipe-delimited format
content=$(grep -v "^#" "$REPLICATION_FILE" | grep -v "^$")
IFS='|' read -r c_host c_port c_label c_enabled c_sync c_status <<< "$content"
assert_eq "5.5  data row host"    "$c_host"    "10.1.1.1"
assert_eq "5.5  data row port"    "$c_port"    "22"
assert_eq "5.5  data row label"   "$c_label"   "x"
assert_eq "5.5  data row enabled" "$c_enabled" "true"
assert_eq "5.5  data row sync"    "$c_sync"    "0"
assert_eq "5.5  data row status"  "$c_status"  "ok"

# ─────────────────────────────────────────────────────────────────────────────
# Suite 6 — Edge cases and regression anchors
# ─────────────────────────────────────────────────────────────────────────────
printf "\n--- Suite 6: Edge cases ---\n"

# 6.1  Host that is purely numeric (valid IP octet style) is accepted by the regex
_reset_replication
replication_add "192.168.0.1" 22 "ip-style"
assert_eq "6.1  numeric dotted host accepted" "$?" "0"

# 6.2  Underscore in hostname IS allowed — the regex [a-zA-Z0-9._-] includes it
#       (dot and underscore are both listed explicitly in the character class).
_reset_replication
replication_add "under_score" 22 "label"
assert_eq "6.2  underscore in host accepted" "$?" "0"

# 6.3  Empty-string port silently defaults to 22 via ${2:-22} parameter expansion.
#       An empty arg ("") is treated as unset/null, so port becomes "22" and the
#       call succeeds.
_reset_replication
replication_add "10.9.9.9" "" "label"
assert_eq "6.3  empty port defaults to 22 and succeeds" "$?" "0"

# 6.4  replication_add with port as a string of spaces is rejected
_reset_replication
replication_add "10.9.9.9" "   " "label" 2>/dev/null
assert_eq "6.4  spaces-only port rejected" "$?" "1"

# 6.5  Remove targets are matched by exact host, not substring.
_reset_replication
replication_add "10.0.0.10"  22 "ten"
replication_add "10.0.0.100" 22 "hundred"
replication_remove "10.0.0.10"
load_replication
assert_eq "6.5  only exact match removed" "${#REPL_HOSTS[@]}"  "1"
assert_eq "6.5  100 entry survives"       "${REPL_HOSTS[0]}"   "10.0.0.100"

# 6.6  save_replication is idempotent — saving twice with same data, reloading
#       gives the same single copy of each entry (not duplicates)
_reset_replication
replication_add "10.0.0.1" 22 "alpha"
save_replication   # second explicit save
load_replication
assert_eq "6.6  idempotent save — no duplicates" "${#REPL_HOSTS[@]}" "1"

# 6.7  REPLICATION_SYNC_INTERVAL=9 is below minimum — reset to 60
_reset_settings_vars
REPLICATION_SYNC_INTERVAL=9
save_settings
_clear_settings_vars
load_settings
assert_eq "6.7  interval 9 (below min) reset to 60" "$REPLICATION_SYNC_INTERVAL" "60"

# 6.8  REPLICATION_SSH_PORT=65536 is too large — reset to 22
_reset_settings_vars
REPLICATION_SSH_PORT=65536
save_settings
_clear_settings_vars
load_settings
assert_eq "6.8  SSH port 65536 reset to 22" "$REPLICATION_SSH_PORT" "22"

# ─────────────────────────────────────────────────────────────────────────────
# Final report
# ─────────────────────────────────────────────────────────────────────────────
printf "\n"
printf "═%.0s" {1..60}
printf "\n"
printf " Test Results\n"
printf "═%.0s" {1..60}
printf "\n"
printf "  Total:  %d\n" "$TESTS_RUN"
printf "  Passed: %d\n" "$TESTS_PASSED"
printf "  Failed: %d\n" "$TESTS_FAILED"
printf "═%.0s" {1..60}
printf "\n"

if [ "$TESTS_FAILED" -gt 0 ]; then
    printf "\nFailed tests:\n"
    for name in "${FAILED_NAMES[@]}"; do
        printf "  - %s\n" "$name"
    done
    printf "\n"
    exit 1
else
    printf "\nAll tests passed.\n\n"
    exit 0
fi
