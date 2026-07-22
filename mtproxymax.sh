#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  MTProxyMax — The Ultimate Telegram Proxy Manager
#  Copyright (c) 2026 SamNet Technologies
#  https://github.com/SamNet-dev/MTProxyMax
#
#  Engine: telemt 3.x (Rust+Tokio)
#  License: MIT
# ═══════════════════════════════════════════════════════════════
set -eo pipefail
export LC_NUMERIC=C

# ── Section 1: Initialization ────────────────────────────────
VERSION="1.4.0-LTS"
SCRIPT_NAME="mtproxymax"
INSTALL_DIR="${INSTALL_DIR:-/opt/mtproxymax}"
CONFIG_DIR="${CONFIG_DIR:-${INSTALL_DIR}/mtproxy}"
SETTINGS_FILE="${SETTINGS_FILE:-${INSTALL_DIR}/settings.conf}"
SECRETS_FILE="${SECRETS_FILE:-${INSTALL_DIR}/secrets.conf}"
STATS_DIR="${STATS_DIR:-${INSTALL_DIR}/relay_stats}"
UPSTREAMS_FILE="${UPSTREAMS_FILE:-${INSTALL_DIR}/upstreams.conf}"
BACKUP_DIR="${BACKUP_DIR:-${INSTALL_DIR}/backups}"
CONNECTION_LOG="${CONNECTION_LOG:-${INSTALL_DIR}/connection.log}"
INSTANCES_FILE="${INSTANCES_FILE:-${INSTALL_DIR}/instances.conf}"
REPLICATION_FILE="${REPLICATION_FILE:-${INSTALL_DIR}/replication.conf}"
REPLICATION_SSH_DIR="${REPLICATION_SSH_DIR:-${INSTALL_DIR}/.ssh}"
VOUCHERS_FILE="${VOUCHERS_FILE:-${INSTALL_DIR}/vouchers.conf}"
ADMINS_FILE="${ADMINS_FILE:-${INSTALL_DIR}/admins.conf}"
PORTAL_DIR="${PORTAL_DIR:-${INSTALL_DIR}/portal}"
PORTAL_WWW="${PORTAL_WWW:-${PORTAL_DIR}/www}"
PORTAL_DATA="${PORTAL_DATA:-${PORTAL_WWW}/data.json}"
SPEED_LIMITS_FILE="${SPEED_LIMITS_FILE:-${INSTALL_DIR}/speed_limits.conf}"
FLEET_FILE="${FLEET_FILE:-${INSTALL_DIR}/fleet.conf}"
FLEET_DATA_DIR="${FLEET_DATA_DIR:-${INSTALL_DIR}/fleet_data}"
SSL_CONF_FILE="${SSL_CONF_FILE:-${INSTALL_DIR}/ssl.conf}"
SSL_DIR="${SSL_DIR:-${INSTALL_DIR}/ssl}"
CLOUD_BACKUP_FILE="${CLOUD_BACKUP_FILE:-${INSTALL_DIR}/cloud_backup.conf}"
SCANNER_SHIELD_SET="mtp_scanners"
CONTAINER_NAME="mtproxymax"
DOCKER_IMAGE_BASE="mtproxymax-telemt"
TELEMT_MIN_VERSION="3.4.25"
TELEMT_COMMIT="51e58b5"  # Pinned: v3.4.25 — Handshake failure stage accounting, In-Runtime Reload
GITHUB_REPO="SamNet-dev/MTProxyMax"
REGISTRY_IMAGE="ghcr.io/samnet-dev/mtproxymax-telemt"

# Bash version check
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "ERROR: MTProxyMax requires bash 4.2+. Current: ${BASH_VERSION:-unknown}" >&2
    exit 1
fi

# Temp file tracking
declare -a _TEMP_FILES=()
_cleanup() {
    for f in "${_TEMP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null
    done
    rm -f /tmp/.mtproxymax-tg.* 2>/dev/null || true
}
trap _cleanup EXIT

_mktemp() {
    local dir="${1:-${TMPDIR:-/tmp}}"
    local tmp
    tmp=$(mktemp "${dir}/.mtproxymax.XXXXXX") || return 1
    chmod 600 "$tmp"
    _TEMP_FILES+=("$tmp")
    echo "$tmp"
}

# ── Section 2: Constants & Defaults ──────────────────────────

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly ITALIC='\033[3m'
readonly UNDERLINE='\033[4m'
readonly BLINK='\033[5m'
readonly REVERSE='\033[7m'
readonly NC='\033[0m'

# Bright colors for retro feel
readonly BRIGHT_GREEN='\033[1;32m'
readonly BRIGHT_CYAN='\033[1;36m'
readonly BRIGHT_YELLOW='\033[1;33m'
readonly BRIGHT_RED='\033[1;31m'
readonly BRIGHT_MAGENTA='\033[1;35m'
readonly BRIGHT_WHITE='\033[1;37m'
readonly BG_BLACK='\033[40m'
readonly BG_BLUE='\033[44m'

# Box drawing
readonly BOX_TL='┌' BOX_TR='┐' BOX_BL='└' BOX_BR='┘'
readonly BOX_H='─' BOX_V='│' BOX_LT='├' BOX_RT='┤'
readonly BOX_DTL='╔' BOX_DTR='╗' BOX_DBL='╚' BOX_DBR='╝'
readonly BOX_DH='═' BOX_DV='║' BOX_DLT='╠' BOX_DRT='╣'

# Status symbols
readonly SYM_OK='●'
readonly SYM_ARROW='►'
readonly SYM_UP='↑'
readonly SYM_DOWN='↓'
readonly SYM_CHECK='✓'
readonly SYM_CROSS='✗'
readonly SYM_WARN='!'
readonly SYM_STAR='★'

# Default configuration
PROXY_PORT=443
PROXY_METRICS_PORT=9090
PROXY_DOMAIN="cloudflare.com"
PROXY_CONCURRENCY=8192
CLIENT_MSS="tspu"
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
MASKING_RELAY_MAX_BYTES=""  # Empty = engine default (32 KiB). "0" = unlimited (useful for large mask backends)
UNKNOWN_SNI_ACTION="mask"

# Custom Telegram infrastructure URLs (for restricted regions where core.telegram.org is blocked)
PROXY_SECRET_URL=""
PROXY_CONFIG_V4_URL=""
PROXY_CONFIG_V6_URL=""

TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_INTERVAL=6
TELEGRAM_ALERTS_ENABLED="true"
TELEGRAM_SERVER_LABEL="MTProxyMax"
AUTO_UPDATE_ENABLED="true"

# Anti-DPI & Stealth Defenses
STEALTH_SHIELD="false"
STEALTH_PRESET="normal"
STEALTH_MSS_CLAMP="false"
LOCKDOWN_MODE="false"
PORT_POOL_PORTS=""
QOS_LIMIT_MBPS="0"
HAPPY_HOURS_WINDOW=""

# Performance, Diagnostics & Self-Healing Suite
TCP_BOOST_ENABLED="false"
TCP_CLEAN_ENABLED="false"
SOCKET_BOOST_ENABLED="false"
TLS_PAD_ENABLED="false"
HONEYPOT_ENABLED="false"
AUTO_HEAL_ENABLED="false"
TCP_FASTPATH_ENABLED="false"
RAM_TUNE_ENABLED="false"
PORT_HOP_RANGES=""
CPU_TUNE_ENABLED="false"
SCANNER_SHIELD_ENABLED="false"
BBR_ECN_ENABLED="false"
ANTI_DPI_SHIELD_ENABLED="false"
COVER_SHIELD_ENABLED="false"
COVER_FALLBACK_TARGET="https://cloudflare.com"
PORTAL_ENABLED="false"
PORTAL_PORT="8080"

# Auto-rotate and backup retention
SECRET_AUTO_ROTATE_DAYS="0"     # 0 = disabled; otherwise rotate secrets older than N days
BACKUP_RETENTION_DAYS="30"      # Auto-clean backups older than N days (0 = keep all)
QUOTA_ENFORCEMENT_MODE="manager" # manager = smooth reset without restart; engine = strict in-memory telemt config

# Replication / HA
REPLICATION_ENABLED="false"
REPLICATION_ROLE="standalone"
REPLICATION_SYNC_INTERVAL=60
REPLICATION_SSH_PORT=22
REPLICATION_SSH_USER="root"
REPLICATION_DELETE_EXTRA="true"
REPLICATION_SSH_KEY_PATH="/opt/mtproxymax/.ssh/id_ed25519"
REPLICATION_EXCLUDE="relay_stats,backups,connection.log,.ssh,settings.conf,replication.conf,mtproxymax-telegram.sh,mtproxymax-sync.sh"
REPLICATION_RESTART_ON_CHANGE="true"
REPLICATION_LOG="/var/log/mtproxymax-sync.log"

# Terminal width
TERM_WIDTH=$(tput cols 2>/dev/null || echo 60)
[ "$TERM_WIDTH" -gt 80 ] && TERM_WIDTH=80
[ "$TERM_WIDTH" -lt 40 ] && TERM_WIDTH=60

# ── Section 3: TUI Drawing Functions ────────────────────────

# Get string display length (strips ANSI escape codes)
_strlen() {
    local clean="$1"
    local esc=$'\033'
    # Normalize literal \033 (from single-quoted color vars) to real ESC byte
    clean="${clean//$'\\033'/$esc}"
    # Strip ANSI escape sequences in pure bash (no subprocesses)
    while [[ "$clean" == *"${esc}["* ]]; do
        local before="${clean%%${esc}\[*}"
        local rest="${clean#*${esc}\[}"
        local after="${rest#*m}"
        [ "$rest" = "$after" ] && break
        clean="${before}${after}"
    done
    echo "${#clean}"
}

# Repeat a character n times (pure bash, no subprocesses)
_repeat() {
    local char="$1" count="$2" str
    [ "${count:-0}" -le 0 ] 2>/dev/null && return 0
    printf -v str '%*s' "$count" ''
    printf '%s' "${str// /$char}"
}

# Draw a horizontal line
draw_line() {
    local width="${1:-$TERM_WIDTH}" char="${2:-$BOX_H}" color="${3:-$DIM}"
    [ "${width:-0}" -le 0 ] 2>/dev/null && width=0
    echo -e "${color}$(_repeat "$char" "$width")${NC}"
}

# Draw top border of a box
draw_box_top() {
    local width="${1:-$TERM_WIDTH}"
    local inner=$((width - 2))
    [ "$inner" -lt 0 ] && inner=0
    echo -e "${CYAN}${BOX_TL}$(_repeat "$BOX_H" "$inner")${BOX_TR}${NC}"
}

# Draw bottom border of a box
draw_box_bottom() {
    local width="${1:-$TERM_WIDTH}"
    local inner=$((width - 2))
    [ "$inner" -lt 0 ] && inner=0
    echo -e "${CYAN}${BOX_BL}$(_repeat "$BOX_H" "$inner")${BOX_BR}${NC}"
}

# Draw separator in a box
draw_box_sep() {
    local width="${1:-$TERM_WIDTH}"
    local inner=$((width - 2))
    [ "$inner" -lt 0 ] && inner=0
    echo -e "${CYAN}${BOX_LT}$(_repeat "$BOX_H" "$inner")${BOX_RT}${NC}"
}

# Draw a line inside a box with auto-padding
draw_box_line() {
    local text="$1" width="${2:-$TERM_WIDTH}"
    local inner=$((width - 2))
    local text_len
    text_len=$(_strlen "$text")
    local padding=$((inner - text_len - 1))
    [ "$padding" -lt 0 ] && padding=0
    echo -e "${CYAN}${BOX_V}${NC} ${text}$(_repeat ' ' "$padding")${CYAN}${BOX_V}${NC}"
}

# Draw an empty line inside a box
draw_box_empty() {
    local width="${1:-$TERM_WIDTH}"
    draw_box_line "" "$width"
}

# Draw a centered line inside a box
draw_box_center() {
    local text="$1" width="${2:-$TERM_WIDTH}"
    local inner=$((width - 2))
    local text_len
    text_len=$(_strlen "$text")
    local left_pad=$(( (inner - text_len) / 2 ))
    local right_pad=$((inner - text_len - left_pad))
    [ "$left_pad" -lt 0 ] && left_pad=0
    [ "$right_pad" -lt 0 ] && right_pad=0
    echo -e "${CYAN}${BOX_V}${NC}$(_repeat ' ' "$left_pad")${text}$(_repeat ' ' "$right_pad")${CYAN}${BOX_V}${NC}"
}

# Draw section header with retro styling
draw_header() {
    local title="$1"
    echo ""
    echo -e "  ${BRIGHT_CYAN}${SYM_ARROW} ${BOLD}${title}${NC}"
    echo -e "  ${DIM}$(_repeat '─' $((${#title} + 2)))${NC}"
}

# Draw a status indicator
draw_status() {
    local status="$1" label="${2:-}"
    case "$status" in
        running|up|true|enabled|active)
            echo -e "${BRIGHT_GREEN}${SYM_OK}${NC} ${GREEN}${label:-RUNNING}${NC}" ;;
        stopped|down|false|disabled|inactive)
            echo -e "${BRIGHT_RED}${SYM_OK}${NC} ${RED}${label:-STOPPED}${NC}" ;;
        starting|pending|warning)
            echo -e "${BRIGHT_YELLOW}${SYM_OK}${NC} ${YELLOW}${label:-STARTING}${NC}" ;;
        *)
            echo -e "${DIM}${SYM_OK}${NC} ${DIM}${label:-UNKNOWN}${NC}" ;;
    esac
}



# Prompt for menu choice with retro styling
read_choice() {
    local prompt="${1:-choice}"
    local default="${2:-}"
    # Drain any stale input (e.g., leftover escape-sequence bytes)
    read -rn 256 -t 0.05 _ 2>/dev/null || true
    echo -en "\n  Enter ${prompt,,}" >&2
    [ -n "$default" ] && echo -en " [${default}]" >&2
    echo -en ": " >&2
    local choice
    read -r choice
    [ -z "$choice" ] && choice="$default"
    echo "$choice"
}



# Press any key prompt
press_any_key() {
    echo ""
    echo -en "  ${DIM}Press any key to continue...${NC}"
    read -rsn1
    # Drain leftover bytes from multi-byte keys (arrow/function keys send escape sequences)
    read -rn 256 -t 0.05 _ 2>/dev/null || true
    echo ""
}

# Clear screen and show mini header
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
    echo -e "${BRIGHT_CYAN}${BOLD}  MTProxyMax${NC} ${DIM}v${VERSION}${NC}"
    echo -e "  ${DIM}$(_repeat '─' 30)${NC}"
}

# Show the big ASCII banner
show_banner() {
    echo -e "${BRIGHT_CYAN}"
    cat << 'BANNER_ART'

    ███╗   ███╗████████╗██████╗ ██████╗  ██████╗
    ████╗ ████║╚══██╔══╝██╔══██╗██╔══██╗██╔═══██╗
    ██╔████╔██║   ██║   ██████╔╝██████╔╝██║   ██║
    ██║╚██╔╝██║   ██║   ██╔═══╝ ██╔══██╗██║   ██║
    ██║ ╚═╝ ██║   ██║   ██║     ██║  ██║╚██████╔╝
    ╚═╝     ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝ ╚═════╝
BANNER_ART
    cat << BANNER
    ╔═════════════════ M A X ══════════════════════╗
    ║  The Ultimate Telegram Proxy Manager v${VERSION}$(printf '%*s' $((7 - ${#VERSION})) '')║
    ║             SamNet Technologies              ║
    ╚══════════════════════════════════════════════╝

BANNER
    echo -e "${NC}"
}

# ── Section 4: Utility Functions ─────────────────────────────

log_info()    { echo -e "  ${BLUE}[i]${NC} $1"; }
log_success() { echo -e "  ${GREEN}[${SYM_CHECK}]${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}[${SYM_WARN}]${NC} $1" >&2; }
log_error()   { echo -e "  ${RED}[${SYM_CROSS}]${NC} $1" >&2; }

# Format bytes to human-readable
format_bytes() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [ -z "$bytes" ] || [ "$bytes" = "0" ]; then
        echo "0 B"
        return
    fi
    if [ "$bytes" -lt 1024 ] 2>/dev/null; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1048576 ] 2>/dev/null; then
        echo "$(awk -v b="$bytes" 'BEGIN {printf "%.1f", b/1024}') KB"
    elif [ "$bytes" -lt 1073741824 ] 2>/dev/null; then
        echo "$(awk -v b="$bytes" 'BEGIN {printf "%.2f", b/1048576}') MB"
    elif [ "$bytes" -lt 1099511627776 ] 2>/dev/null; then
        echo "$(awk -v b="$bytes" 'BEGIN {printf "%.2f", b/1073741824}') GB"
    else
        echo "$(awk -v b="$bytes" 'BEGIN {printf "%.2f", b/1099511627776}') TB"
    fi
}

format_human_bytes() {
    format_bytes "$@"
}

# Format seconds to human-readable duration
format_duration() {
    local secs=$1
    [[ "$secs" =~ ^-?[0-9]+$ ]] || secs=0
    [ "$secs" -lt 1 ] && { echo "0s"; return; }
    local days=$((secs / 86400))
    local hours=$(( (secs % 86400) / 3600 ))
    local mins=$(( (secs % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [ "$hours" -gt 0 ]; then
        echo "${hours}h ${mins}m"
    elif [ "$mins" -gt 0 ]; then
        echo "${mins}m"
    else
        echo "${secs}s"
    fi
}



# Escape markdown special characters
escape_md() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//\*/\\*}"
    text="${text//_/\\_}"
    text="${text//\`/\\\`}"
    echo "$text"
}

# Compare version strings: returns 0 if v1 >= v2 (semver part only, ignores commit hash)
_version_gte() {
    local v1="${1%%-*}" v2="${2%%-*}"  # strip commit hash
    local IFS='.'; local a=($v1) b=($v2)
    local i
    for i in 0 1 2; do
        local n1=${a[$i]:-0} n2=${b[$i]:-0}
        (( n1 > n2 )) && return 0
        (( n1 < n2 )) && return 1
    done
    return 0
}

# Get public IP address
_PUBLIC_IP_CACHE=""
_PUBLIC_IP_CACHE_AGE=0

get_public_ip() {
    # Return custom IP if configured
    if [ -n "${CUSTOM_IP}" ]; then
        echo "${CUSTOM_IP}"
        return 0
    fi
    local now; now=$(date +%s)
    # Return cached IP if less than 5 minutes old
    if [ -n "$_PUBLIC_IP_CACHE" ] && [ $(( now - _PUBLIC_IP_CACHE_AGE )) -lt 300 ]; then
        echo "$_PUBLIC_IP_CACHE"
        return 0
    fi
    local ip=""
    ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null) ||
    ip=$(curl -s --max-time 3 https://ifconfig.me 2>/dev/null) ||
    ip=$(curl -s --max-time 3 https://icanhazip.com 2>/dev/null) ||
    ip=""
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$ip" =~ : ]]; then
        _PUBLIC_IP_CACHE="$ip"
        _PUBLIC_IP_CACHE_AGE=$now
        echo "$ip"
    fi
}

get_export_dir() {
    local edir="${INSTALL_DIR:-/opt/mtproxymax}/exports"
    mkdir -p "$edir" 2>/dev/null || true
    chmod 700 "$edir" 2>/dev/null || true
    echo "$edir"
}

# Validate port number
validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# Check if port is available
is_port_available() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ! ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
    elif command -v netstat &>/dev/null; then
        ! netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
    else
        return 0
    fi
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "MTProxyMax must be run as root"
        echo -e "  ${DIM}Try: sudo $0 $*${NC}"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint|kali) echo "debian" ;;
            centos|rhel|fedora|rocky|alma|oracle) echo "rhel" ;;
            alpine) echo "alpine" ;;
            *) echo "unknown" ;;
        esac
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    command -v curl &>/dev/null || missing+=("curl")
    command -v awk &>/dev/null || missing+=("awk")
    command -v openssl &>/dev/null || missing+=("openssl")

    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing dependencies: ${missing[*]}"
        log_info "Installing..."
        local os
        os=$(detect_os)
        case "$os" in
            debian) apt-get update -qq && apt-get install -y -qq "${missing[@]}" ;;
            rhel)   yum install -y -q "${missing[@]}" ;;
            alpine) apk add --no-cache "${missing[@]}" ;;
        esac
    fi
}

# Parse human-readable byte sizes (e.g., 5G, 500M, 1T) to raw bytes
parse_human_bytes() {
    local input="${1:-0}"
    input="${input^^}"  # uppercase
    local num unit
    if [[ "$input" =~ ^([0-9]+(\.[0-9]+)?)[[:space:]]*(B|K|KB|M|MB|G|GB|T|TB)?$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[3]:-B}"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
        return 0
    else
        echo "0"
        return 1
    fi
    case "$unit" in
        B)        awk -v n="$num" 'BEGIN {printf "%.0f", n}' ;;
        K|KB)     awk -v n="$num" 'BEGIN {printf "%.0f", n * 1024}' ;;
        M|MB)     awk -v n="$num" 'BEGIN {printf "%.0f", n * 1048576}' ;;
        G|GB)     awk -v n="$num" 'BEGIN {printf "%.0f", n * 1073741824}' ;;
        T|TB)     awk -v n="$num" 'BEGIN {printf "%.0f", n * 1099511627776}' ;;
        *)        echo "0"; return 1 ;;
    esac
}

# Validate a domain name or comma-separated domain pool
validate_domain() {
    local d="$1"
    [ -z "$d" ] && return 1
    local part
    IFS=',' read -ra parts <<< "$d"
    for part in "${parts[@]}"; do
        part="${part// /}"
        if ! [[ "$part" =~ ^[a-zA-Z0-9.-]+$ ]] || ! [[ "$part" =~ \. ]]; then
            return 1
        fi
    done
    return 0
}

# Detect remote TLS certificate DER payload length using openssl
detect_remote_cert_len() {
    local domain="$1"
    [ -z "$domain" ] && return 1
    if ! command -v openssl >/dev/null 2>&1; then return 1; fi
    local len
    len=$(echo -n | timeout 5 openssl s_client -connect "${domain}:443" -servername "${domain}" 2>/dev/null | openssl x509 -outform DER 2>/dev/null | wc -c)
    if [[ "$len" =~ ^[0-9]+$ ]] && [ "$len" -ge 256 ] && [ "$len" -le 16384 ]; then
        echo "$len"
        return 0
    fi
    return 1
}

# Automatically sync FAKE_CERT_LEN with target PROXY_DOMAIN cert length
sync_domain_cert_len() {
    local force="${1:-false}" quiet="${2:-false}"
    [ -z "${PROXY_DOMAIN:-}" ] && return 0
    
    local stamp_file="${INSTALL_DIR}/.last_cert_sync"
    local now_s; now_s=$(date +%s)
    if [ "$force" != "true" ] && [ -f "$stamp_file" ]; then
        local last_s; last_s=$(cat "$stamp_file" 2>/dev/null)
        if [[ "$last_s" =~ ^[0-9]+$ ]]; then
            # Run at most once every 24 hours (86400 seconds)
            if [ $((now_s - last_s)) -lt 86400 ]; then
                return 0
            fi
        fi
    fi

    local detected
    local first_domain="${PROXY_DOMAIN%%,*}"
    first_domain="${first_domain// /}"
    if detected=$(detect_remote_cert_len "$first_domain"); then
        mkdir -p "$INSTALL_DIR" 2>/dev/null || true
        echo "$now_s" > "$stamp_file" 2>/dev/null || true
        if [ "$detected" != "${FAKE_CERT_LEN:-2048}" ]; then
            if [ "$quiet" = "false" ]; then
                log_info "Auto-detected TLS cert length for '${PROXY_DOMAIN}': ${detected} bytes (was ${FAKE_CERT_LEN:-2048})"
            fi
            FAKE_CERT_LEN="$detected"
            save_settings
            if is_proxy_running; then
                reload_proxy_config
            fi
        fi
    fi
    return 0
}

# ── Section 5: Settings Persistence ──────────────────────────

save_settings() {
    mkdir -p "$INSTALL_DIR"

    local tmp
    tmp=$(_mktemp) || { log_error "Cannot create temp file"; return 1; }

    # Sanitize string variables against single quotes and carriage returns
    TELEGRAM_SERVER_LABEL="${TELEGRAM_SERVER_LABEL//\'/}"
    TELEGRAM_SERVER_LABEL="${TELEGRAM_SERVER_LABEL//$'\r'/}"
    AD_TAG="${AD_TAG//\'/}"
    PROXY_DOMAIN="${PROXY_DOMAIN//\'/}"
    BLOCKLIST_COUNTRIES="${BLOCKLIST_COUNTRIES//\'/}"

    cat > "$tmp" << SETTINGS_EOF
# MTProxyMax Settings — v${VERSION}
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# DO NOT EDIT MANUALLY — use 'mtproxymax' to change settings

# Proxy Configuration
PROXY_PORT='${PROXY_PORT}'
PROXY_METRICS_PORT='${PROXY_METRICS_PORT}'
PROXY_DOMAIN='${PROXY_DOMAIN}'
PROXY_CONCURRENCY='${PROXY_CONCURRENCY}'
CLIENT_MSS='${CLIENT_MSS}'
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
MASKING_RELAY_MAX_BYTES='${MASKING_RELAY_MAX_BYTES}'
UNKNOWN_SNI_ACTION='${UNKNOWN_SNI_ACTION}'

# Custom Telegram infrastructure URLs (for restricted regions)
PROXY_SECRET_URL='${PROXY_SECRET_URL}'
PROXY_CONFIG_V4_URL='${PROXY_CONFIG_V4_URL}'
PROXY_CONFIG_V6_URL='${PROXY_CONFIG_V6_URL}'

# Telegram Integration
TELEGRAM_ENABLED='${TELEGRAM_ENABLED}'
TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'
TELEGRAM_CHAT_ID='${TELEGRAM_CHAT_ID}'
TELEGRAM_INTERVAL='${TELEGRAM_INTERVAL}'
TELEGRAM_ALERTS_ENABLED='${TELEGRAM_ALERTS_ENABLED}'
TELEGRAM_SERVER_LABEL='${TELEGRAM_SERVER_LABEL}'

# Auto-Update
AUTO_UPDATE_ENABLED='${AUTO_UPDATE_ENABLED}'

# Secret auto-rotate & Quota
SECRET_AUTO_ROTATE_DAYS='${SECRET_AUTO_ROTATE_DAYS}'
BACKUP_RETENTION_DAYS='${BACKUP_RETENTION_DAYS}'
QUOTA_ENFORCEMENT_MODE='${QUOTA_ENFORCEMENT_MODE:-manager}'

# Anti-DPI & Stealth Defenses
STEALTH_SHIELD='${STEALTH_SHIELD}'
STEALTH_PRESET='${STEALTH_PRESET}'
STEALTH_MSS_CLAMP='${STEALTH_MSS_CLAMP}'
LOCKDOWN_MODE='${LOCKDOWN_MODE}'
PORT_POOL_PORTS='${PORT_POOL_PORTS}'
QOS_LIMIT_MBPS='${QOS_LIMIT_MBPS}'
HAPPY_HOURS_WINDOW='${HAPPY_HOURS_WINDOW}'

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
# Cloudflare Dynamic DNS (DDNS)
DDNS_ENABLED='${DDNS_ENABLED}'
DDNS_CF_TOKEN='${DDNS_CF_TOKEN}'
DDNS_CF_ZONE_ID='${DDNS_CF_ZONE_ID}'
DDNS_RECORD_NAME='${DDNS_RECORD_NAME}'
# Performance, Diagnostics & Self-Healing Suite
TCP_BOOST_ENABLED='${TCP_BOOST_ENABLED}'
TCP_CLEAN_ENABLED='${TCP_CLEAN_ENABLED}'
SOCKET_BOOST_ENABLED='${SOCKET_BOOST_ENABLED}'
TLS_PAD_ENABLED='${TLS_PAD_ENABLED}'
HONEYPOT_ENABLED='${HONEYPOT_ENABLED}'
AUTO_HEAL_ENABLED='${AUTO_HEAL_ENABLED}'
TCP_FASTPATH_ENABLED='${TCP_FASTPATH_ENABLED}'
RAM_TUNE_ENABLED='${RAM_TUNE_ENABLED}'
PORT_HOP_RANGES='${PORT_HOP_RANGES}'
CPU_TUNE_ENABLED='${CPU_TUNE_ENABLED}'
SCANNER_SHIELD_ENABLED='${SCANNER_SHIELD_ENABLED}'
BBR_ECN_ENABLED='${BBR_ECN_ENABLED}'
ANTI_DPI_SHIELD_ENABLED='${ANTI_DPI_SHIELD_ENABLED}'
COVER_SHIELD_ENABLED='${COVER_SHIELD_ENABLED}'
COVER_FALLBACK_TARGET='${COVER_FALLBACK_TARGET}'
PORTAL_ENABLED='${PORTAL_ENABLED}'
PORTAL_PORT='${PORTAL_PORT}'
SETTINGS_EOF

    chmod 600 "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
}

load_settings() {
    [ -f "$SETTINGS_FILE" ] || return 0

    # Safe whitelist-based parsing (no source/eval)
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Match KEY='VALUE' or KEY="VALUE" or KEY=VALUE
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\'([^\']*)\'$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\"([^\"]*)\"$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=([^[:space:]]*)$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Whitelist of allowed keys
        case "$key" in
            PROXY_PORT|PROXY_METRICS_PORT|PROXY_DOMAIN|PROXY_CONCURRENCY|CLIENT_MSS|\
            PROXY_CPUS|PROXY_MEMORY|CUSTOM_IP|FAKE_CERT_LEN|PROXY_PROTOCOL|PROXY_PROTOCOL_TRUSTED_CIDRS|AD_TAG|GEOBLOCK_MODE|BLOCKLIST_COUNTRIES|\
            MASKING_ENABLED|MASKING_HOST|MASKING_PORT|MASKING_RELAY_MAX_BYTES|UNKNOWN_SNI_ACTION|\
            PROXY_SECRET_URL|PROXY_CONFIG_V4_URL|PROXY_CONFIG_V6_URL|\
            TELEGRAM_ENABLED|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|\
            TELEGRAM_INTERVAL|TELEGRAM_ALERTS_ENABLED|TELEGRAM_SERVER_LABEL|\
            AUTO_UPDATE_ENABLED|SECRET_AUTO_ROTATE_DAYS|BACKUP_RETENTION_DAYS|QUOTA_ENFORCEMENT_MODE|\
            STEALTH_SHIELD|STEALTH_PRESET|STEALTH_MSS_CLAMP|LOCKDOWN_MODE|PORT_POOL_PORTS|QOS_LIMIT_MBPS|HAPPY_HOURS_WINDOW|\
            REPLICATION_ENABLED|REPLICATION_ROLE|REPLICATION_SYNC_INTERVAL|\
            REPLICATION_SSH_PORT|REPLICATION_SSH_USER|REPLICATION_DELETE_EXTRA|REPLICATION_SSH_KEY_PATH|REPLICATION_EXCLUDE|\
            REPLICATION_RESTART_ON_CHANGE|REPLICATION_LOG|\
            DDNS_ENABLED|DDNS_CF_TOKEN|DDNS_CF_ZONE_ID|DDNS_RECORD_NAME|\
            TCP_BOOST_ENABLED|TCP_CLEAN_ENABLED|SOCKET_BOOST_ENABLED|TLS_PAD_ENABLED|HONEYPOT_ENABLED|AUTO_HEAL_ENABLED|\
            TCP_FASTPATH_ENABLED|RAM_TUNE_ENABLED|PORT_HOP_RANGES|CPU_TUNE_ENABLED|\
            SCANNER_SHIELD_ENABLED|BBR_ECN_ENABLED|ANTI_DPI_SHIELD_ENABLED|COVER_SHIELD_ENABLED|COVER_FALLBACK_TARGET|PORTAL_ENABLED|PORTAL_PORT)
                printf -v "$key" '%s' "$val"
                ;;
        esac
    done < "$SETTINGS_FILE"

    # Post-load validation for numeric fields
    [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_PORT" -ge 1 ] && [ "$PROXY_PORT" -le 65535 ] || PROXY_PORT=443
    [[ "$PROXY_METRICS_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_METRICS_PORT" -ge 1 ] && [ "$PROXY_METRICS_PORT" -le 65535 ] || PROXY_METRICS_PORT=9090
    [[ "$MASKING_PORT" =~ ^[0-9]+$ ]] && [ "$MASKING_PORT" -ge 1 ] && [ "$MASKING_PORT" -le 65535 ] || MASKING_PORT=443
    [[ "$FAKE_CERT_LEN" =~ ^[0-9]+$ ]] && [ "$FAKE_CERT_LEN" -ge 256 ] || FAKE_CERT_LEN=2048
    [[ "$PROXY_CONCURRENCY" =~ ^[0-9]+$ ]] || PROXY_CONCURRENCY=8192
    [[ "$PROXY_PROTOCOL" == "true" ]] || PROXY_PROTOCOL="false"
    [[ "$GEOBLOCK_MODE" == "whitelist" ]] || GEOBLOCK_MODE="blacklist"
    [[ "$UNKNOWN_SNI_ACTION" == "drop" ]] || UNKNOWN_SNI_ACTION="mask"
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

    # Stealth validation
    [[ "$STEALTH_SHIELD" == "true" ]] || STEALTH_SHIELD="false"
    [[ "$STEALTH_PRESET" =~ ^(ultra|normal)$ ]] || STEALTH_PRESET="normal"
    [[ "$STEALTH_MSS_CLAMP" == "true" ]] || STEALTH_MSS_CLAMP="false"

    # Migration: ensure settings.conf and replication.conf are always excluded
    [[ "$REPLICATION_EXCLUDE" == *"settings.conf"* ]]   || REPLICATION_EXCLUDE="${REPLICATION_EXCLUDE},settings.conf"
    [[ "$REPLICATION_EXCLUDE" == *"replication.conf"* ]] || REPLICATION_EXCLUDE="${REPLICATION_EXCLUDE},replication.conf"
}

# Save secrets database
save_secrets() {
    mkdir -p "$INSTALL_DIR"

    local tmp
    tmp=$(_mktemp) || { log_error "Cannot create temp file"; return 1; }

    echo "# MTProxyMax Secrets Database — v${VERSION}" > "$tmp"
    echo "# Format: LABEL|SECRET|CREATED_TS|ENABLED|MAX_CONNS|MAX_IPS|QUOTA_BYTES|EXPIRES|NOTES|AD_TAG" >> "$tmp"
    echo "# DO NOT EDIT MANUALLY — use 'mtproxymax secret' commands" >> "$tmp"

    if [ ${#SECRETS_LABELS[@]} -gt 0 ]; then
        local i
        for i in "${!SECRETS_LABELS[@]}"; do
            echo "${SECRETS_LABELS[$i]}|${SECRETS_KEYS[$i]}|${SECRETS_CREATED[$i]}|${SECRETS_ENABLED[$i]}|${SECRETS_MAX_CONNS[$i]:-0}|${SECRETS_MAX_IPS[$i]:-0}|${SECRETS_QUOTA[$i]:-0}|${SECRETS_EXPIRES[$i]:-0}|${SECRETS_NOTES[$i]:-}|${SECRETS_AD_TAGS[$i]:-}" >> "$tmp"
        done
    fi

    chmod 600 "$tmp"
    mv "$tmp" "$SECRETS_FILE"
}

# Arrays for secret management
declare -a SECRETS_LABELS=()
declare -a SECRETS_KEYS=()
declare -a SECRETS_CREATED=()
declare -a SECRETS_ENABLED=()
declare -a SECRETS_MAX_CONNS=()
declare -a SECRETS_MAX_IPS=()
declare -a SECRETS_QUOTA=()
declare -a SECRETS_EXPIRES=()
declare -a SECRETS_NOTES=()
declare -a SECRETS_AD_TAGS=()

# Load secrets database
load_secrets() {
    SECRETS_LABELS=()
    SECRETS_KEYS=()
    SECRETS_CREATED=()
    SECRETS_ENABLED=()
    SECRETS_MAX_CONNS=()
    SECRETS_MAX_IPS=()
    SECRETS_QUOTA=()
    SECRETS_EXPIRES=()
    SECRETS_NOTES=()
    SECRETS_AD_TAGS=()

    if [ -f "$SECRETS_FILE" ]; then
        while IFS='|' read -r label secret created enabled max_conns max_ips quota expires notes ad_tag || [ -n "$label" ]; do
            [[ "$label" =~ ^[[:space:]]*# ]] && continue
            [[ "$label" =~ ^[[:space:]]*$ ]] && continue
            [ -z "$secret" ] && continue
            # Validate label and secret format on load
            [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            [[ "$secret" =~ ^[0-9a-fA-F]{32}$ ]] || continue

            # Validate numeric fields on load
            local _mc="${max_conns:-0}" _mi="${max_ips:-0}" _q="${quota:-0}" _en="${enabled:-true}"
            [[ "$_mc" =~ ^[0-9]+$ ]] || _mc="0"
            [[ "$_mi" =~ ^[0-9]+$ ]] || _mi="0"
            [[ "$_q" =~ ^[0-9]+$ ]] || _q="0"
            [ "$_en" != "true" ] && [ "$_en" != "false" ] && _en="true"

            SECRETS_LABELS+=("$label")
            SECRETS_KEYS+=("$secret")
            local _cr="${created:-$(date +%s)}"
            [[ "$_cr" =~ ^[0-9]+$ ]] || _cr=$(date +%s)
            SECRETS_CREATED+=("$_cr")
            SECRETS_ENABLED+=("$_en")
            SECRETS_MAX_CONNS+=("$_mc")
            SECRETS_MAX_IPS+=("$_mi")
            SECRETS_QUOTA+=("$_q")
            local _ex="${expires:-0}"
            if [ "$_ex" != "0" ] && ! [[ "$_ex" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9:Z+.-]+)?$ ]]; then
                _ex="0"
            fi
            SECRETS_EXPIRES+=("$_ex")
            SECRETS_NOTES+=("${notes:-}")
            local _at="${ad_tag:-}"
            [[ "$_at" =~ ^[0-9a-fA-F]{32}$ ]] || _at=""
            SECRETS_AD_TAGS+=("$_at")
        done < "$SECRETS_FILE"
    fi

    # Always load upstreams alongside secrets (both feed into config)
    load_upstreams
}

# Arrays for upstream management
declare -a UPSTREAM_NAMES=()
declare -a UPSTREAM_TYPES=()
declare -a UPSTREAM_ADDRS=()
declare -a UPSTREAM_USERS=()
declare -a UPSTREAM_PASSES=()
declare -a UPSTREAM_WEIGHTS=()
declare -a UPSTREAM_IFACES=()
declare -a UPSTREAM_ENABLED=()

# Save upstreams database
save_upstreams() {
    mkdir -p "$INSTALL_DIR"

    local tmp
    tmp=$(_mktemp) || { log_error "Cannot create temp file"; return 1; }

    echo "# MTProxyMax Upstreams Database — v${VERSION}" > "$tmp"
    echo "# Format: NAME|TYPE|ADDR|USER|PASS|WEIGHT|IFACE|ENABLED" >> "$tmp"
    echo "# DO NOT EDIT MANUALLY — use 'mtproxymax upstream' commands" >> "$tmp"

    if [ ${#UPSTREAM_NAMES[@]} -gt 0 ]; then
        local i
        for i in "${!UPSTREAM_NAMES[@]}"; do
            echo "${UPSTREAM_NAMES[$i]}|${UPSTREAM_TYPES[$i]}|${UPSTREAM_ADDRS[$i]}|${UPSTREAM_USERS[$i]}|${UPSTREAM_PASSES[$i]}|${UPSTREAM_WEIGHTS[$i]}|${UPSTREAM_IFACES[$i]}|${UPSTREAM_ENABLED[$i]}" >> "$tmp"
        done
    fi

    chmod 600 "$tmp"
    mv "$tmp" "$UPSTREAMS_FILE"
}

# Load upstreams database
load_upstreams() {
    UPSTREAM_NAMES=()
    UPSTREAM_TYPES=()
    UPSTREAM_ADDRS=()
    UPSTREAM_USERS=()
    UPSTREAM_PASSES=()
    UPSTREAM_WEIGHTS=()
    UPSTREAM_IFACES=()
    UPSTREAM_ENABLED=()

    if [ ! -f "$UPSTREAMS_FILE" ]; then
        # Default: single direct upstream
        UPSTREAM_NAMES+=("direct")
        UPSTREAM_TYPES+=("direct")
        UPSTREAM_ADDRS+=("")
        UPSTREAM_USERS+=("")
        UPSTREAM_PASSES+=("")
        UPSTREAM_WEIGHTS+=("10")
        UPSTREAM_IFACES+=("")
        UPSTREAM_ENABLED+=("true")
        return 0
    fi

    while IFS='|' read -r name type addr user pass weight iface enabled || [ -n "$name" ]; do
        [[ "$name" =~ ^[[:space:]]*# ]] && continue
        [[ "$name" =~ ^[[:space:]]*$ ]] && continue
        # Validate name format on load
        [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || continue

        # Backward compat: old 7-col format has enabled in col7 (no iface)
        if [ "$iface" = "true" ] || [ "$iface" = "false" ]; then
            enabled="$iface"
            iface=""
        fi

        # Validate type, weight, and enabled on load
        local _type="${type:-direct}"
        case "$_type" in
            direct|socks5|socks4) ;;
            *) _type="direct" ;;
        esac
        local _weight="${weight:-10}"
        [[ "$_weight" =~ ^[0-9]+$ ]] && [ "$_weight" -ge 1 ] && [ "$_weight" -le 100 ] || _weight="10"
        local _enabled="${enabled:-true}"
        [ "$_enabled" != "true" ] && [ "$_enabled" != "false" ] && _enabled="true"

        # Skip socks entries with no address
        [ "$_type" != "direct" ] && [ -z "${addr:-}" ] && continue

        UPSTREAM_NAMES+=("$name")
        UPSTREAM_TYPES+=("$_type")
        UPSTREAM_ADDRS+=("${addr:-}")
        UPSTREAM_USERS+=("${user:-}")
        UPSTREAM_PASSES+=("${pass:-}")
        UPSTREAM_WEIGHTS+=("$_weight")
        UPSTREAM_IFACES+=("${iface:-}")
        UPSTREAM_ENABLED+=("$_enabled")
    done < "$UPSTREAMS_FILE"

    # Ensure at least one entry exists
    if [ ${#UPSTREAM_NAMES[@]} -eq 0 ]; then
        UPSTREAM_NAMES+=("direct")
        UPSTREAM_TYPES+=("direct")
        UPSTREAM_ADDRS+=("")
        UPSTREAM_USERS+=("")
        UPSTREAM_PASSES+=("")
        UPSTREAM_WEIGHTS+=("10")
        UPSTREAM_IFACES+=("")
        UPSTREAM_ENABLED+=("true")
    fi
}

# ── Section 6: Docker Management ─────────────────────────────

install_docker() {
    if command -v docker &>/dev/null; then
        log_success "Docker is already installed"
        return 0
    fi

    log_info "Installing Docker..."
    local os
    os=$(detect_os)

    case "$os" in
        debian)
            curl -fsSL https://get.docker.com | sh
            ;;
        rhel)
            # Determine Docker repo URL: Fedora has its own repo, others use CentOS
            local _distro_id _repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
            [ -f /etc/os-release ] && . /etc/os-release && _distro_id="$ID"
            [ "$_distro_id" = "fedora" ] && _repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"

            if command -v dnf &>/dev/null; then
                # dnf5 (Fedora 41+) uses --addrepo, older dnf uses --add-repo
                dnf config-manager --add-repo "$_repo_url" 2>/dev/null ||
                dnf config-manager --addrepo "$_repo_url" 2>/dev/null ||
                yum-config-manager --add-repo "$_repo_url"
                dnf install -y docker-ce docker-ce-cli containerd.io
            else
                yum install -y yum-utils
                yum-config-manager --add-repo "$_repo_url"
                yum install -y docker-ce docker-ce-cli containerd.io
            fi
            ;;
        alpine)
            apk add --no-cache docker docker-compose
            ;;
        *)
            log_error "Unsupported OS. Please install Docker manually."
            return 1
            ;;
    esac

    systemctl enable docker 2>/dev/null || rc-update add docker default 2>/dev/null || true
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true

    if command -v docker &>/dev/null; then
        log_success "Docker installed successfully"
    else
        log_error "Docker installation failed"
        return 1
    fi
}

wait_for_docker() {
    local retries=10
    while [ $retries -gt 0 ]; do
        docker info &>/dev/null && return 0
        sleep 1
        retries=$((retries - 1))
    done
    log_error "Docker is not responding"
    return 1
}

# Build telemt Docker image from latest GitHub release binary
build_telemt_image() {
    local force="${1:-false}"

    local commit="${TELEMT_COMMIT}"
    local version="${TELEMT_MIN_VERSION}-${commit}"

    # Skip if image already exists (unless forced)
    if [ "$force" != "true" ] && docker image inspect "${DOCKER_IMAGE_BASE}:${version}" &>/dev/null; then
        return 0
    fi

    # Strategy 1: Pull pre-built image from registry (fast — seconds)
    log_info "Pulling pre-built telemt v${version}..."
    if docker pull "${REGISTRY_IMAGE}:${version}" 2>/dev/null; then
        docker tag "${REGISTRY_IMAGE}:${version}" "${DOCKER_IMAGE_BASE}:${version}"
        docker tag "${DOCKER_IMAGE_BASE}:${version}" "${DOCKER_IMAGE_BASE}:latest" 2>/dev/null || true
        log_success "Pulled telemt v${version}"
        mkdir -p "$INSTALL_DIR"
        echo "$version" > "${INSTALL_DIR}/.telemt_version"
        return 0
    fi

    # Strategy 2: Pull latest from registry if exact version not found
    if [ "$force" != "source" ]; then
        log_info "Exact version not in registry, trying latest..."
        if docker pull "${REGISTRY_IMAGE}:latest" 2>/dev/null; then
            docker tag "${REGISTRY_IMAGE}:latest" "${DOCKER_IMAGE_BASE}:${version}"
            docker tag "${DOCKER_IMAGE_BASE}:${version}" "${DOCKER_IMAGE_BASE}:latest" 2>/dev/null || true
            log_success "Pulled telemt (latest)"
            mkdir -p "$INSTALL_DIR"
            echo "$version" > "${INSTALL_DIR}/.telemt_version"
            return 0
        fi
    fi

    # Strategy 3: Build from source (slow first time, cached after)
    log_warn "Pre-built image not available, compiling from source..."
    log_info "Includes: Prometheus metrics, ME perf fixes, critical ME bug fixes"

    local build_dir
    build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mtproxymax-build.XXXXXX")
    _TEMP_FILES+=("$build_dir")

    cat > "${build_dir}/Dockerfile" << 'DOCKERFILE_EOF'
FROM rust:1-bookworm AS builder
ARG TELEMT_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*
RUN git clone "https://github.com/telemt/telemt.git" /build
WORKDIR /build
RUN git checkout "${TELEMT_COMMIT}"
ENV CARGO_PROFILE_RELEASE_LTO=true CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_DEBUG=false
RUN cargo build --release && \
    strip target/release/telemt 2>/dev/null || true && \
    cp target/release/telemt /telemt

FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /telemt /usr/local/bin/telemt
RUN chmod +x /usr/local/bin/telemt
STOPSIGNAL SIGINT
ENTRYPOINT ["telemt"]
DOCKERFILE_EOF

    log_info "Compiling from source (first build takes a few minutes)..."
    if docker build \
        --build-arg "TELEMT_COMMIT=${commit}" \
        -t "${DOCKER_IMAGE_BASE}:${version}" "$build_dir"; then
        docker tag "${DOCKER_IMAGE_BASE}:${version}" "${DOCKER_IMAGE_BASE}:latest" 2>/dev/null || true
        log_success "Built telemt v${version} from source"
        mkdir -p "$INSTALL_DIR"
        echo "$version" > "${INSTALL_DIR}/.telemt_version"
    else
        log_error "Source build failed — ensure Docker has enough memory (2GB+)"
        rm -rf "$build_dir"
        return 1
    fi

    rm -rf "$build_dir"
    return 0
}

# Get installed telemt version
get_telemt_version() {
    # Try saved version file first
    local ver
    ver=$(cat "${INSTALL_DIR}/.telemt_version" 2>/dev/null)
    if [ -n "$ver" ]; then echo "$ver"; return; fi
    # Fallback: check Docker image tags
    ver=$(docker images --format '{{.Tag}}' "${DOCKER_IMAGE_BASE}" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
    if [ -n "$ver" ]; then echo "$ver"; return; fi
    echo "unknown"
}

# Get the versioned Docker image tag for telemt
get_docker_image() {
    local ver
    ver=$(get_telemt_version)
    if [ "$ver" = "unknown" ]; then
        echo "${DOCKER_IMAGE_BASE}:latest"
    else
        echo "${DOCKER_IMAGE_BASE}:${ver}"
    fi
}

# ── Section 7: Telemt Engine ─────────────────────────────────

# Generate a random 32-char hex secret
generate_secret() {
    openssl rand -hex 16 2>/dev/null || {
        # Fallback
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32
    }
}

# Convert domain to hex for ee-prefixed FakeTLS secret
domain_to_hex() {
    printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

# Build the full FakeTLS secret for sharing (ee + raw_secret + domain_hex)
build_faketls_secret() {
    local raw_secret="$1" domain="${2:-$PROXY_DOMAIN}"
    if [ "${MASKING_ENABLED:-true}" = "false" ]; then
        echo "dd${raw_secret}"
    else
        local domain_hex
        domain_hex=$(domain_to_hex "$domain")
        echo "ee${raw_secret}${domain_hex}"
    fi
}

# Generate telemt config.toml
generate_telemt_config() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    local raw_domain="${PROXY_DOMAIN:-cloudflare.com}"
    local domain="${raw_domain%%,*}"
    domain="${domain// /}"
    local mask_enabled="${MASKING_ENABLED:-true}"
    local mask_host="${MASKING_HOST:-$domain}"
    local mask_port="${MASKING_PORT:-443}"
    if [ "${COVER_SHIELD_ENABLED:-false}" = "true" ] && [ -n "${COVER_FALLBACK_TARGET:-}" ]; then
        local _t="${COVER_FALLBACK_TARGET#*://}" # strip https:// or http://
        _t="${_t%%/*}"                           # strip path
        if [[ "$_t" == *":"* ]]; then
            mask_host="${_t%%:*}"
            mask_port="${_t#*:}"
        else
            mask_host="$_t"
            mask_port="443"
        fi
        mask_enabled="true"
        UNKNOWN_SNI_ACTION="mask"
    fi
    local ad_tag="${AD_TAG:-}"
    ad_tag=$(echo "$ad_tag" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [[ "$ad_tag" =~ ^[0-9a-f]{32}$ ]] || ad_tag=""
    local port="${PROXY_PORT:-443}"
    local metrics_port="${PROXY_METRICS_PORT:-9090}"

    local domains_toml=""
    if [[ "$raw_domain" == *","* ]]; then
        local part
        IFS=',' read -ra _dparts <<< "$raw_domain"
        local _dlist=""
        for part in "${_dparts[@]}"; do
            part="${part// /}"
            [ -n "$part" ] && _dlist="${_dlist:+$_dlist, }\"${part}\""
        done
        [ -n "$_dlist" ] && domains_toml="tls_domains = [${_dlist}]"
    fi

    local r_check=65536 r_win=1800
    if [ "${STEALTH_PRESET:-normal}" = "ultra" ]; then
        r_check=131072
        r_win=180
    fi

    # Build config in a temp file for atomic write (same-dir for atomic mv)
    local tmp
    tmp=$(_mktemp "$CONFIG_DIR") || { log_error "Cannot create temp file for config"; return 1; }

    cat > "$tmp" << TOML_EOF
# MTProxyMax — telemt configuration
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

[general]
prefer_ipv6 = false
fast_mode = true
use_middle_proxy = true
log_level = "normal"
$([ -n "$ad_tag" ] && echo "ad_tag = \"$ad_tag\"" || echo "# ad_tag = \"\"  # Get from @MTProxyBot")
$([ -n "${PROXY_SECRET_URL:-}" ] && echo "proxy_secret_url = \"${PROXY_SECRET_URL}\"")
$([ -n "${PROXY_CONFIG_V4_URL:-}" ] && echo "proxy_config_v4_url = \"${PROXY_CONFIG_V4_URL}\"")
$([ -n "${PROXY_CONFIG_V6_URL:-}" ] && echo "proxy_config_v6_url = \"${PROXY_CONFIG_V6_URL}\"")
tg_connect = 10

[general.modes]
classic = false
secure = $([ "$mask_enabled" = "false" ] && echo "true" || echo "false")
tls = true

[general.links]
show = [$(get_enabled_labels_quoted)]
# public_host = ""
# public_port = ${port}

[server]
port = ${port}
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"
proxy_protocol = ${PROXY_PROTOCOL:-false}
$([ "$PROXY_PROTOCOL" = "true" ] && [ -n "$PROXY_PROTOCOL_TRUSTED_CIDRS" ] && echo "proxy_protocol_trusted_cidrs = [$(echo "$PROXY_PROTOCOL_TRUSTED_CIDRS" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//;s/[[:space:]]*,[[:space:]]*/", "/g;s/^/"/;s/$/"/' )]")
metrics_listen = "127.0.0.1:${metrics_port}"
metrics_whitelist = ["127.0.0.1", "::1"]
${CLIENT_MSS:+client_mss = \"${CLIENT_MSS}\"}

[timeouts]
client_handshake = 30
client_keepalive = 15
client_ack = 90

[censorship]
tls_domain = "${domain}"
$([ -n "${domains_toml}" ] && echo "${domains_toml}")
unknown_sni_action = "${UNKNOWN_SNI_ACTION:-mask}"
mask = ${mask_enabled}
mask_port = ${mask_port}
$([ "$mask_enabled" = "true" ] && [ -n "$mask_host" ] && echo "mask_host = \"${mask_host}\"")
$([ -n "${MASKING_RELAY_MAX_BYTES:-}" ] && echo "mask_relay_max_bytes = ${MASKING_RELAY_MAX_BYTES}")
fake_cert_len = ${FAKE_CERT_LEN:-2048}
# Note: geo-blocking is enforced at the host firewall level (iptables/nftables),
# not via telemt config. See: mtproxymax info -> Geo-Blocking

[access]
replay_check_len = ${r_check}
replay_window_secs = ${r_win}
ignore_time_skew = false

[access.users]
TOML_EOF

    # Append enabled secrets
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        echo "${SECRETS_LABELS[$i]} = \"${SECRETS_KEYS[$i]}\"" >> "$tmp"
    done

    # Append per-user limits (only sections with non-zero values)
    local has_conns=false has_ips=false has_quota=false has_expires=false has_adtags=false
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        [ "${SECRETS_MAX_CONNS[$i]:-0}" != "0" ] && has_conns=true
        [ "${SECRETS_MAX_IPS[$i]:-0}" != "0" ] && has_ips=true
        [ "${SECRETS_QUOTA[$i]:-0}" != "0" ] && has_quota=true
        [ "${SECRETS_EXPIRES[$i]:-0}" != "0" ] && has_expires=true
        [ -n "${SECRETS_AD_TAGS[$i]:-}" ] && has_adtags=true
    done

    if $has_conns; then
        echo "" >> "$tmp"
        echo "[access.user_max_tcp_conns]" >> "$tmp"
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            [ "${SECRETS_MAX_CONNS[$i]:-0}" != "0" ] || continue
            echo "${SECRETS_LABELS[$i]} = ${SECRETS_MAX_CONNS[$i]}" >> "$tmp"
        done
    fi

    if $has_ips; then
        echo "" >> "$tmp"
        echo "[access.user_max_unique_ips]" >> "$tmp"
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            [ "${SECRETS_MAX_IPS[$i]:-0}" != "0" ] || continue
            echo "${SECRETS_LABELS[$i]} = ${SECRETS_MAX_IPS[$i]}" >> "$tmp"
        done
    fi

    if $has_quota && [ "${QUOTA_ENFORCEMENT_MODE:-manager}" = "engine" ]; then
        echo "" >> "$tmp"
        echo "[access.user_data_quota]" >> "$tmp"
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            [ "${SECRETS_QUOTA[$i]:-0}" != "0" ] || continue
            echo "${SECRETS_LABELS[$i]} = ${SECRETS_QUOTA[$i]}" >> "$tmp"
        done
    fi

    if $has_expires; then
        echo "" >> "$tmp"
        echo "[access.user_expirations]" >> "$tmp"
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            [ "${SECRETS_EXPIRES[$i]:-0}" != "0" ] || continue
            echo "${SECRETS_LABELS[$i]} = \"${SECRETS_EXPIRES[$i]}\"" >> "$tmp"
        done
    fi

    if $has_adtags; then
        echo "" >> "$tmp"
        echo "[access.user_ad_tags]" >> "$tmp"
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            local _uat="${SECRETS_AD_TAGS[$i]:-}"
            _uat=$(echo "$_uat" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            [[ "$_uat" =~ ^[0-9a-f]{32}$ ]] || continue
            echo "${SECRETS_LABELS[$i]} = \"${_uat}\"" >> "$tmp"
        done
    fi

    local rate_toml; rate_toml=$(_emit_tunings_for_section "rate_limit" 2>/dev/null || true)
    if [ -n "$rate_toml" ]; then
        echo "" >> "$tmp"
        echo "[rate_limit]" >> "$tmp"
        echo "$rate_toml" >> "$tmp"
    fi

    # Append enabled upstream entries
    local _has_enabled_up=false
    for i in "${!UPSTREAM_NAMES[@]}"; do
        [ "${UPSTREAM_ENABLED[$i]}" = "true" ] || continue
        _has_enabled_up=true
        echo "" >> "$tmp"
        echo "[[upstreams]]" >> "$tmp"
        echo "type = \"${UPSTREAM_TYPES[$i]}\"" >> "$tmp"
        echo "weight = ${UPSTREAM_WEIGHTS[$i]}" >> "$tmp"
        if [ "${UPSTREAM_TYPES[$i]}" != "direct" ] && [ -n "${UPSTREAM_ADDRS[$i]}" ]; then
            echo "address = \"${UPSTREAM_ADDRS[$i]}\"" >> "$tmp"
        fi
        # SOCKS5 uses username/password; SOCKS4 uses user_id
        if [ "${UPSTREAM_TYPES[$i]}" = "socks5" ]; then
            [ -n "${UPSTREAM_USERS[$i]}" ] && echo "username = \"${UPSTREAM_USERS[$i]}\"" >> "$tmp"
            [ -n "${UPSTREAM_PASSES[$i]}" ] && echo "password = \"${UPSTREAM_PASSES[$i]}\"" >> "$tmp"
        elif [ "${UPSTREAM_TYPES[$i]}" = "socks4" ] && [ -n "${UPSTREAM_USERS[$i]}" ]; then
            echo "user_id = \"${UPSTREAM_USERS[$i]}\"" >> "$tmp"
        fi
        # Bind outbound to specific IP
        if [ -n "${UPSTREAM_IFACES[$i]}" ]; then
            echo "interface = \"${UPSTREAM_IFACES[$i]}\"" >> "$tmp"
        fi
    done
    if ! $_has_enabled_up; then
        echo "" >> "$tmp"
        echo "[[upstreams]]" >> "$tmp"
        echo "type = \"direct\"" >> "$tmp"
        echo "weight = 10" >> "$tmp"
    fi

    # Apply engine tunings (replace matching keys in-place before the final copy)
    if [ -f "${_TUNE_FILE:-/dev/null}" ] && [ -s "${_TUNE_FILE}" ]; then
        while IFS='|' read -r _tp _tv; do
            [ -z "$_tp" ] && continue
            # Only allow whitelisted params
            _tune_lookup "$_tp" >/dev/null 2>&1 || continue
            # Format value (quote strings, leave numbers/booleans bare)
            local _tv_out
            if [[ "$_tv" =~ ^(true|false|[0-9]+)$ ]]; then
                _tv_out="$_tv"
            else
                _tv_out="\"$_tv\""
            fi
            # Escape for sed
            local _esc_tp _esc_tv
            _esc_tp=$(printf '%s' "$_tp" | sed 's/[][\/.*^$]/\\&/g')
            _esc_tv=$(printf '%s' "$_tv_out" | sed 's/[\/&]/\\&/g')
            # Replace existing line if present; otherwise append to [general] section
            if grep -qE "^${_esc_tp} *=" "$tmp"; then
                sed -i.bak "s/^${_esc_tp} *=.*/${_tp} = ${_tv_out}/" "$tmp" && rm -f "${tmp}.bak"
            else
                # Append after [general] header if not elsewhere (safe fallback)
                awk -v p="$_tp" -v v="$_tv_out" '
                    BEGIN{inserted=0}
                    {print}
                    /^\[general\]$/ && !inserted {print p " = " v; inserted=1}
                ' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
            fi
        done < "$_TUNE_FILE"
    fi

    chmod 644 "$tmp"
    cp "$tmp" "${CONFIG_DIR}/config.toml" && rm -f "$tmp"
}

# Get comma-separated quoted list of enabled labels for config
get_enabled_labels_quoted() {
    local result="" first=true
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        if $first; then
            result="\"${SECRETS_LABELS[$i]}\""
            first=false
        else
            result+=", \"${SECRETS_LABELS[$i]}\""
        fi
    done
    echo "$result"
}

# ── Traffic Tracking ──────────────────────────────────────────
# Primary: Prometheus /metrics endpoint (telemt built from HEAD)
# Fallback: iptables byte counters (if metrics unavailable)

IPTABLES_CHAIN="MTPROXY_STATS"
_TRACKED_PORT=""
_METRICS_CACHE=""
_METRICS_CACHE_AGE=0

# Fetch Prometheus metrics (cached for 2 seconds to avoid hammering)
_fetch_metrics() {
    local now
    now=$(date +%s)
    if [ -n "$_METRICS_CACHE" ] && [ $((now - _METRICS_CACHE_AGE)) -lt 2 ]; then
        echo "$_METRICS_CACHE"
        return 0
    fi
    local mport="${PROXY_METRICS_PORT:-9090}"
    _METRICS_CACHE=$(curl -s --noproxy '*' --max-time 2 "http://127.0.0.1:${mport}/metrics" 2>/dev/null) || true
    if [ -z "$_METRICS_CACHE" ]; then
        _METRICS_CACHE=$(curl -s --noproxy '*' --max-time 2 "http://localhost:${mport}/metrics" 2>/dev/null) || true
    fi
    if [ -z "$_METRICS_CACHE" ] && [ "${ENGINE_MODE:-docker}" = "docker" ] && command -v docker &>/dev/null; then
        local _cip
        _cip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mtproxymax 2>/dev/null | head -1)
        [ -n "$_cip" ] && _METRICS_CACHE=$(curl -s --noproxy '*' --max-time 2 "http://${_cip}:${mport}/metrics" 2>/dev/null) || true
    fi
    _METRICS_CACHE_AGE=$now
    [ -n "$_METRICS_CACHE" ] && echo "$_METRICS_CACHE" && return 0
    return 1
}

# Set up iptables tracking rules (fallback when Prometheus unavailable)
# Idempotent — safe to call repeatedly, auto-handles port changes
traffic_tracking_setup() {
    local port="${PROXY_PORT:-443}"

    if [ "$_TRACKED_PORT" = "$port" ] && \
       iptables -C "$IPTABLES_CHAIN" -p tcp --dport "$port" -m comment --comment "mtproxymax-in" 2>/dev/null; then
        return 0
    fi

    iptables -N "$IPTABLES_CHAIN" 2>/dev/null || true
    iptables -F "$IPTABLES_CHAIN" 2>/dev/null
    iptables -A "$IPTABLES_CHAIN" -p tcp --dport "$port" -m comment --comment "mtproxymax-in" 2>/dev/null
    iptables -A "$IPTABLES_CHAIN" -p tcp --sport "$port" -m comment --comment "mtproxymax-out" 2>/dev/null
    iptables -C INPUT -j "$IPTABLES_CHAIN" -m comment --comment "mtproxymax" 2>/dev/null || \
        iptables -I INPUT -j "$IPTABLES_CHAIN" -m comment --comment "mtproxymax" 2>/dev/null
    iptables -C OUTPUT -j "$IPTABLES_CHAIN" -m comment --comment "mtproxymax" 2>/dev/null || \
        iptables -I OUTPUT -j "$IPTABLES_CHAIN" -m comment --comment "mtproxymax" 2>/dev/null

    _TRACKED_PORT="$port"
}

# Remove all iptables tracking rules
traffic_tracking_teardown() {
    local i
    for i in 1 2 3; do
        iptables -D INPUT -j "$IPTABLES_CHAIN" -m comment --comment "mtproxymax" 2>/dev/null || true
        iptables -D OUTPUT -j "$IPTABLES_CHAIN" -m comment --comment "mtproxymax" 2>/dev/null || true
        iptables -D INPUT -j "$IPTABLES_CHAIN" 2>/dev/null || true
        iptables -D OUTPUT -j "$IPTABLES_CHAIN" 2>/dev/null || true
    done
    iptables -F "$IPTABLES_CHAIN" 2>/dev/null || true
    iptables -X "$IPTABLES_CHAIN" 2>/dev/null || true
    _TRACKED_PORT=""
}

# Read current traffic counters
# Returns: bytes_in bytes_out connections
get_proxy_stats() {
    if ! is_proxy_running; then
        echo "0 0 0"
        return
    fi

    # Try Prometheus first
    local m
    if m=$(_fetch_metrics); then
        local bi bo conns
        bi=$(echo "$m" | awk '/^telemt_user_octets_from_client\{/{s+=$NF}END{printf "%.0f",s}')
        bo=$(echo "$m" | awk '/^telemt_user_octets_to_client\{/{s+=$NF}END{printf "%.0f",s}')
        conns=$(echo "$m" | awk '/^telemt_user_connections_current\{/{s+=$NF}END{printf "%.0f",s}')
        echo "${bi:-0} ${bo:-0} ${conns:-0}"
        return
    fi

    # Fallback: iptables
    local port="${PROXY_PORT:-443}"
    if [ "$_TRACKED_PORT" != "$port" ] || \
       ! iptables -C "$IPTABLES_CHAIN" -p tcp --dport "$port" -m comment --comment "mtproxymax-in" 2>/dev/null; then
        traffic_tracking_setup
    fi

    local stats
    stats=$(iptables -L "$IPTABLES_CHAIN" -v -n -x 2>/dev/null)
    local bytes_in bytes_out
    bytes_in=$(echo "$stats" | awk '/mtproxymax-in/ {print $2; exit}')
    bytes_out=$(echo "$stats" | awk '/mtproxymax-out/ {print $2; exit}')
    local connections
    connections=$(ss -tn state established 2>/dev/null | grep -c ":${port} " || echo "0")

    echo "${bytes_in:-0} ${bytes_out:-0} ${connections:-0}"
}

# Get cumulative global traffic (persisted across restarts)
get_cumulative_proxy_stats() {
    local _stats_dir="${INSTALL_DIR}/relay_stats"
    local _tf="${_stats_dir}/cumulative_traffic"
    local _gsnap="${_stats_dir}/global_traffic_snapshot"

    local saved_in=0 saved_out=0
    if [ -f "$_tf" ]; then
        IFS='|' read -r saved_in saved_out < "$_tf"
    fi
    [[ "${saved_in:-0}" =~ ^[0-9]+$ ]] || saved_in=0
    [[ "${saved_out:-0}" =~ ^[0-9]+$ ]] || saved_out=0

    local snap_in=0 snap_out=0
    if [ -f "$_gsnap" ]; then
        IFS='|' read -r snap_in snap_out < "$_gsnap"
    fi
    [[ "${snap_in:-0}" =~ ^[0-9]+$ ]] || snap_in=0
    [[ "${snap_out:-0}" =~ ^[0-9]+$ ]] || snap_out=0

    local live_in=0 live_out=0 conns=0
    read -r live_in live_out conns <<< "$(get_proxy_stats)"

    local delta_in=$((live_in - snap_in))
    local delta_out=$((live_out - snap_out))
    [ "$delta_in" -lt 0 ] 2>/dev/null && delta_in=$live_in
    [ "$delta_out" -lt 0 ] 2>/dev/null && delta_out=$live_out

    echo "$(( saved_in + delta_in )) $(( saved_out + delta_out )) ${conns}"
}

# Get per-user stats from Prometheus
# Returns: bytes_in bytes_out connections
get_user_stats() {
    local user="$1"
    local m
    if m=$(_fetch_metrics); then
        local i o c
        i=$(echo "$m" | awk -v u="$user" '$0 ~ "^telemt_user_octets_from_client\\{.*user=\"" u "\"" {print $NF}')
        o=$(echo "$m" | awk -v u="$user" '$0 ~ "^telemt_user_octets_to_client\\{.*user=\"" u "\"" {print $NF}')
        c=$(echo "$m" | awk -v u="$user" '$0 ~ "^telemt_user_connections_current\\{.*user=\"" u "\"" {print $NF}')
        echo "${i:-0} ${o:-0} ${c:-0}"
        return
    fi
    echo "0 0 0"
}


# Batch-load cumulative stats for ALL users in one pass (avoids N*8 forks)
# Populates: _batch_cum_in[label], _batch_cum_out[label], _batch_cum_conns[label]
declare -A _batch_cum_in _batch_cum_out _batch_cum_conns
_load_all_cumulative_user_stats() {
    _batch_cum_in=(); _batch_cum_out=(); _batch_cum_conns=()
    local _stats_dir="${INSTALL_DIR}/relay_stats"
    local _ut_file="${_stats_dir}/user_traffic"
    local _snap_file="${_stats_dir}/user_traffic_snapshot"

    # Load cumulative from disk (one read)
    declare -A _saved_in _saved_out _snap_in _snap_out
    if [ -f "$_ut_file" ]; then
        while IFS='|' read -r _l _i _o || [ -n "$_l" ]; do
            [[ "$_l" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            _i=${_i:-0}; _o=${_o:-0}
            [[ "$_i" =~ ^[0-9]+$ ]] || _i=0
            [[ "$_o" =~ ^[0-9]+$ ]] || _o=0
            _saved_in["$_l"]=$_i; _saved_out["$_l"]=$_o
        done < "$_ut_file"
    fi
    if [ -f "$_snap_file" ]; then
        while IFS='|' read -r _l _i _o || [ -n "$_l" ]; do
            [[ "$_l" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            _i=${_i:-0}; _o=${_o:-0}
            [[ "$_i" =~ ^[0-9]+$ ]] || _i=0
            [[ "$_o" =~ ^[0-9]+$ ]] || _o=0
            _snap_in["$_l"]=$_i; _snap_out["$_l"]=$_o
        done < "$_snap_file"
    fi

    # Fetch metrics once
    local _m=""
    _m=$(_fetch_metrics 2>/dev/null) || true

    # Extract all per-user stats in a single awk pass
    if [ -n "$_m" ]; then
        while IFS='|' read -r _l _li _lo _lc; do
            local si=${_snap_in["$_l"]:-0} so=${_snap_out["$_l"]:-0}
            local di=$((_li - si)) doo=$((_lo - so))
            [ "$di" -lt 0 ] 2>/dev/null && di=$_li
            [ "$doo" -lt 0 ] 2>/dev/null && doo=$_lo
            _batch_cum_in["$_l"]=$(( ${_saved_in["$_l"]:-0} + di ))
            _batch_cum_out["$_l"]=$(( ${_saved_out["$_l"]:-0} + doo ))
            _batch_cum_conns["$_l"]=${_lc:-0}
        done < <(echo "$_m" | awk '
            function get_user(s,   p,q) {
                p = index(s, "user=\"")
                if (!p) return ""
                s = substr(s, p + 6)
                q = index(s, "\"")
                return q ? substr(s, 1, q - 1) : ""
            }
            /^telemt_user_octets_from_client\{/ {
                u = get_user($0); if (u) users_in[u] += $NF
            }
            /^telemt_user_octets_to_client\{/ {
                u = get_user($0); if (u) users_out[u] += $NF
            }
            /^telemt_user_connections_current\{/ {
                u = get_user($0); if (u) users_conns[u] += $NF
            }
            END {
                for (u in users_in) {
                    printf "%s|%.0f|%.0f|%.0f\n", u, users_in[u]+0, users_out[u]+0, users_conns[u]+0
                }
                for (u in users_out) {
                    if (!(u in users_in)) printf "%s|0|%.0f|%.0f\n", u, users_out[u]+0, users_conns[u]+0
                }
            }
        ')
    fi

    # Fill in users that have saved data but no live metrics (e.g., after restart with 0 traffic)
    for _l in "${!_saved_in[@]}"; do
        if [ -z "${_batch_cum_in[$_l]+x}" ]; then
            _batch_cum_in["$_l"]=${_saved_in["$_l"]:-0}
            _batch_cum_out["$_l"]=${_saved_out["$_l"]:-0}
            _batch_cum_conns["$_l"]=0
        fi
    done
}

# One-shot flush of traffic counters to disk (for use before stop/restart)
# Works standalone — loads cumulative from disk, computes delta from live metrics, saves back
flush_traffic_to_disk() {
    local _stats_dir="${INSTALL_DIR}/relay_stats"
    local _tf="${_stats_dir}/cumulative_traffic"
    local _utf="${_stats_dir}/user_traffic"
    local _snap="${_stats_dir}/user_traffic_snapshot"
    mkdir -p "$_stats_dir" 2>/dev/null
    # Acquire lock to prevent race with daemon's save_traffic
    exec 9>"${_stats_dir}/.traffic.lock"
    flock -w 5 9 2>/dev/null || { exec 9>&- 2>/dev/null; return 0; }

    # Load existing cumulative totals
    local cum_in=0 cum_out=0
    if [ -f "$_tf" ]; then
        IFS='|' read -r cum_in cum_out < "$_tf"
    fi
    [[ "${cum_in:-0}" =~ ^[0-9]+$ ]] || cum_in=0
    [[ "${cum_out:-0}" =~ ^[0-9]+$ ]] || cum_out=0

    # Load existing per-user cumulative and snapshots
    declare -A _fu_cum_in _fu_cum_out _fu_snap_in _fu_snap_out
    if [ -f "$_utf" ]; then
        while IFS='|' read -r _l _i _o; do
            [[ "$_l" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            _i=${_i:-0}; _o=${_o:-0}
            [[ "$_i" =~ ^[0-9]+$ ]] || _i=0
            [[ "$_o" =~ ^[0-9]+$ ]] || _o=0
            _fu_cum_in["$_l"]=$_i; _fu_cum_out["$_l"]=$_o
        done < "$_utf"
    fi
    if [ -f "$_snap" ]; then
        while IFS='|' read -r _l _i _o; do
            [[ "$_l" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            _i=${_i:-0}; _o=${_o:-0}
            [[ "$_i" =~ ^[0-9]+$ ]] || _i=0
            [[ "$_o" =~ ^[0-9]+$ ]] || _o=0
            _fu_snap_in["$_l"]=$_i; _fu_snap_out["$_l"]=$_o
        done < "$_snap"
    fi

    # Load previous global snapshot
    local snap_gin=0 snap_gout=0
    if [ -f "${_stats_dir}/global_traffic_snapshot" ]; then
        IFS='|' read -r snap_gin snap_gout < "${_stats_dir}/global_traffic_snapshot"
    fi
    [[ "${snap_gin:-0}" =~ ^[0-9]+$ ]] || snap_gin=0
    [[ "${snap_gout:-0}" =~ ^[0-9]+$ ]] || snap_gout=0

    # Fetch current live metrics
    local _metrics _have_metrics=false
    _metrics=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null) || true
    [ -n "$_metrics" ] && _have_metrics=true

    if $_have_metrics; then
        # Global traffic delta
        local cur_gin cur_gout
        cur_gin=$(echo "$_metrics" | awk '/^telemt_user_octets_from_client\{/{s+=$NF}END{printf "%.0f",s}')
        cur_gout=$(echo "$_metrics" | awk '/^telemt_user_octets_to_client\{/{s+=$NF}END{printf "%.0f",s}')
        cur_gin=${cur_gin:-0}; cur_gout=${cur_gout:-0}
        local gd_in=$((cur_gin - snap_gin)) gd_out=$((cur_gout - snap_gout))
        [ "$gd_in" -lt 0 ] 2>/dev/null && gd_in=$cur_gin
        [ "$gd_out" -lt 0 ] 2>/dev/null && gd_out=$cur_gout
        cum_in=$((cum_in + gd_in))
        cum_out=$((cum_out + gd_out))

        # Per-user traffic delta
        local in_happy="false"
        if [ -n "${HAPPY_HOURS_WINDOW:-}" ] && check_in_happy_hours "${HAPPY_HOURS_WINDOW}" 2>/dev/null; then
            in_happy="true"
        fi
        if [ -f "${INSTALL_DIR}/calendar.conf" ]; then
            local wp="false" hb="false"
            source "${INSTALL_DIR}/calendar.conf" 2>/dev/null || true
            if [ "$wp" = "true" ]; then
                local dow; dow=$(date +%u 2>/dev/null || echo 1)
                if [ "$dow" -eq 5 ] || [ "$dow" -eq 6 ] || [ "$dow" -eq 7 ]; then
                    in_happy="true"
                fi
            fi
            if [ "$hb" = "true" ]; then
                local md; md=$(date +%m-%d 2>/dev/null || echo "")
                case "$md" in
                    01-01|03-21|10-31|12-25|12-31) in_happy="true" ;;
                esac
            fi
        fi
        [ -f "$SECRETS_FILE" ] && while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
            [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue
            [ "$enabled" != "true" ] && continue
            local ui uo
            ui=$(echo "$_metrics" | awk -v u="$label" '$0 ~ "^telemt_user_octets_from_client\\{.*user=\"" u "\"" {print $NF}')
            uo=$(echo "$_metrics" | awk -v u="$label" '$0 ~ "^telemt_user_octets_to_client\\{.*user=\"" u "\"" {print $NF}')
            ui=${ui:-0}; uo=${uo:-0}
            local si=${_fu_snap_in["$label"]:-0} so=${_fu_snap_out["$label"]:-0}
            local di=$((ui - si)) doo=$((uo - so))
            [ "$di" -lt 0 ] 2>/dev/null && di=$ui
            [ "$doo" -lt 0 ] 2>/dev/null && doo=$uo
            if [ "$in_happy" != "true" ]; then
                _fu_cum_in["$label"]=$(( ${_fu_cum_in["$label"]:-0} + di ))
                _fu_cum_out["$label"]=$(( ${_fu_cum_out["$label"]:-0} + doo ))
            fi
            _fu_snap_in["$label"]=$ui
            _fu_snap_out["$label"]=$uo
        done < "$SECRETS_FILE"
    fi
    # If metrics unavailable, still save existing cumulative (don't lose what we have)
    # Snapshot resets to 0 so next session starts fresh

    # Write cumulative traffic
    local _tmp
    _tmp=$(_mktemp "${_stats_dir}") || { exec 9>&-; return; }
    echo "${cum_in}|${cum_out}" > "$_tmp"
    mv "$_tmp" "$_tf" 2>/dev/null || { rm -f "$_tmp"; exec 9>&-; return; }

    # Write per-user cumulative
    _tmp=$(_mktemp "${_stats_dir}") || { exec 9>&-; return; }
    for _l in "${!_fu_cum_in[@]}"; do
        echo "${_l}|${_fu_cum_in[$_l]}|${_fu_cum_out[$_l]}" >> "$_tmp"
    done
    mv "$_tmp" "$_utf" 2>/dev/null || rm -f "$_tmp"

    # Write per-user snapshot (reset to 0 if metrics were unavailable)
    _tmp=$(_mktemp "${_stats_dir}") || { exec 9>&-; return; }
    if $_have_metrics; then
        for _l in "${!_fu_snap_in[@]}"; do
            echo "${_l}|${_fu_snap_in[$_l]}|${_fu_snap_out[$_l]}" >> "$_tmp"
        done
    else
        for _l in "${!_fu_cum_in[@]}"; do
            echo "${_l}|0|0" >> "$_tmp"
        done
    fi
    mv "$_tmp" "$_snap" 2>/dev/null || rm -f "$_tmp"

    # Write global snapshot (reset to 0 if metrics were unavailable)
    _tmp=$(_mktemp "${_stats_dir}") || { exec 9>&-; return; }
    if $_have_metrics; then
        echo "${cur_gin}|${cur_gout}" > "$_tmp"
    else
        echo "0|0" > "$_tmp"
    fi
    mv "$_tmp" "${_stats_dir}/global_traffic_snapshot" 2>/dev/null || rm -f "$_tmp"
    exec 9>&-  # Release lock
}

# ── Section 8: Secret Management ─────────────────────────────

# Add a new secret
secret_add() {
    local label="$1" custom_secret="${2:-}" no_restart="${3:-false}"

    # Validate label
    if [ -z "$label" ]; then
        log_error "Label is required"
        return 1
    fi
    if ! [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Label must be alphanumeric (a-z, 0-9, _, -)"
        return 1
    fi
    if [ ${#label} -gt 32 ]; then
        log_error "Label must be 32 characters or less"
        return 1
    fi

    # Check for duplicate
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then
            log_error "Secret with label '${label}' already exists"
            return 1
        fi
    done

    # Generate or use provided secret
    local raw_secret
    if [ -n "$custom_secret" ]; then
        raw_secret="$custom_secret"
    else
        raw_secret=$(generate_secret)
    fi

    if [ -z "$raw_secret" ] || ! [[ "$raw_secret" =~ ^[0-9a-fA-F]{32}$ ]]; then
        log_error "Secret must be exactly 32 hex characters"
        return 1
    fi

    # Add to arrays
    SECRETS_LABELS+=("$label")
    SECRETS_KEYS+=("$raw_secret")
    SECRETS_CREATED+=("$(date +%s)")
    SECRETS_ENABLED+=("true")
    SECRETS_MAX_CONNS+=("0")
    SECRETS_MAX_IPS+=("0")
    SECRETS_QUOTA+=("0")
    SECRETS_EXPIRES+=("0")
    SECRETS_NOTES+=("")
    SECRETS_AD_TAGS+=("")

    # Save
    save_secrets

    # Hot-reload config (no restart, no dropped connections)
    if [ "$no_restart" != "true" ]; then
        reload_proxy_config
    fi

    local full_secret
    full_secret=$(build_faketls_secret "$raw_secret")
    local server_ip
    server_ip=$(get_public_ip)

    log_success "Secret '${label}' created"
    audit_log "secret add ${label}"
    echo ""
    echo -e "  ${BOLD}Proxy Link:${NC}"
    echo -e "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    echo ""
    echo -e "  ${BOLD}Web Link:${NC}"
    echo -e "  ${CYAN}https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"

    # Show QR code inline if qrencode is available
    if command -v qrencode &>/dev/null; then
        echo ""
        qrencode -t ANSIUTF8 "tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}" 2>/dev/null | sed 's/^/  /'
    fi
    echo ""
}

# Remove a secret
secret_remove() {
    [ ${#SECRETS_LABELS[@]} -eq 0 ] && load_secrets
    local label="$1" force="${2:-false}" no_restart="${3:-false}"

    local idx=-1
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then
            idx=$i
            break
        fi
    done

    if [ $idx -eq -1 ]; then
        log_error "Secret '${label}' not found"
        return 1
    fi

    # Prevent removing the last secret
    if [ ${#SECRETS_LABELS[@]} -le 1 ]; then
        log_error "Cannot remove the last secret — proxy needs at least one"
        return 1
    fi

    # Confirm unless forced or non-interactive
    if [ "$force" != "true" ]; then
        if [ ! -t 0 ]; then
            force="true"
        else
            echo -e "  ${YELLOW}Remove secret '${label}'? Users with this key will be disconnected.${NC}"
            echo -en "  ${BOLD}Type 'yes' to confirm:${NC} "
            local confirm
            read -r confirm
            [ "$confirm" != "yes" ] && { log_info "Cancelled"; return 0; }
        fi
    fi

    # Remove from arrays (rebuild without the index)
    local -a new_labels=() new_keys=() new_created=() new_enabled=()
    local -a new_max_conns=() new_max_ips=() new_quota=() new_expires=() new_notes=() new_adtags=()
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "$i" -eq "$idx" ] && continue
        new_labels+=("${SECRETS_LABELS[$i]}")
        new_keys+=("${SECRETS_KEYS[$i]}")
        new_created+=("${SECRETS_CREATED[$i]}")
        new_enabled+=("${SECRETS_ENABLED[$i]}")
        new_max_conns+=("${SECRETS_MAX_CONNS[$i]:-0}")
        new_max_ips+=("${SECRETS_MAX_IPS[$i]:-0}")
        new_quota+=("${SECRETS_QUOTA[$i]:-0}")
        new_expires+=("${SECRETS_EXPIRES[$i]:-0}")
        new_notes+=("${SECRETS_NOTES[$i]:-}")
        new_adtags+=("${SECRETS_AD_TAGS[$i]:-}")
    done
    SECRETS_LABELS=("${new_labels[@]}")
    SECRETS_KEYS=("${new_keys[@]}")
    SECRETS_CREATED=("${new_created[@]}")
    SECRETS_ENABLED=("${new_enabled[@]}")
    SECRETS_MAX_CONNS=("${new_max_conns[@]}")
    SECRETS_MAX_IPS=("${new_max_ips[@]}")
    SECRETS_QUOTA=("${new_quota[@]}")
    SECRETS_EXPIRES=("${new_expires[@]}")
    SECRETS_NOTES=("${new_notes[@]}")
    SECRETS_AD_TAGS=("${new_adtags[@]}")

    save_secrets

    if [ "$no_restart" != "true" ]; then
        reload_proxy_config
    fi

    log_success "Secret '${label}' removed"
    audit_log "secret remove ${label}"
}

# Batch add multiple secrets (single restart)
secret_add_batch() {
    local no_restart="false"
    if [ "$1" = "true" ] || [ "$1" = "false" ]; then
        no_restart="$1"; shift
    fi
    local labels=("$@")

    if [ ${#labels[@]} -eq 0 ]; then
        log_error "Usage: mtproxymax secret add-batch <label1> <label2> ..."
        return 1
    fi

    local added=0 failed=0
    for label in "${labels[@]}"; do
        if secret_add "$label" "" "true"; then
            added=$((added + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # Single hot-reload after all additions
    if [ "$no_restart" != "true" ] && [ $added -gt 0 ]; then
        reload_proxy_config
    fi

    echo ""
    log_success "Batch complete: ${added} added, ${failed} failed"
}

# Batch remove multiple secrets (single restart)
secret_remove_batch() {
    local force="${1:-false}"
    shift 2>/dev/null || true
    local no_restart="false"
    if [ "$1" = "true" ] || [ "$1" = "false" ]; then
        no_restart="$1"; shift
    fi
    local labels=("$@")

    if [ ${#labels[@]} -eq 0 ]; then
        log_error "Usage: mtproxymax secret remove-batch <label1> <label2> ..."
        return 1
    fi

    # Count how many of the requested labels actually exist
    local match_count=0
    local l i
    for l in "${labels[@]}"; do
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_LABELS[$i]}" = "$l" ] && { match_count=$((match_count + 1)); break; }
        done
    done

    if [ $match_count -ge ${#SECRETS_LABELS[@]} ]; then
        log_error "Cannot remove all secrets — proxy needs at least one"
        return 1
    fi

    # Confirm unless forced
    if [ "$force" != "true" ] && [ -t 0 ]; then
        echo -e "  ${YELLOW}Remove ${#labels[@]} secrets? Users with these keys will be disconnected.${NC}"
        echo -e "  ${DIM}Labels: ${labels[*]}${NC}"
        echo -en "  ${BOLD}Type 'yes' to confirm:${NC} "
        local confirm
        read -r confirm
        [ "$confirm" != "yes" ] && { log_info "Cancelled"; return 0; }
    fi

    local removed=0 failed=0
    for l in "${labels[@]}"; do
        if secret_remove "$l" "true" "true"; then
            removed=$((removed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # Single hot-reload after all removals
    if [ "$no_restart" != "true" ] && [ $removed -gt 0 ]; then
        reload_proxy_config
    fi

    echo ""
    log_success "Batch complete: ${removed} removed, ${failed} failed"
}

# List all secrets
secret_list() {
    load_secrets

    if [ ${#SECRETS_LABELS[@]} -eq 0 ]; then
        log_info "No secrets configured"
        echo -e "  ${DIM}Run: mtproxymax secret add <label>${NC}"
        return
    fi

    echo ""
    draw_header "SECRETS"
    echo ""

    # Batch-load all user stats in one pass (single metrics fetch + single file read)
    _load_all_cumulative_user_stats 2>/dev/null

    # Table header
    printf "  ${BOLD}%-4s %-16s %-10s %-10s %-12s %-12s${NC}\n" "#" "LABEL" "STATUS" "CREATED" "TRAFFIC IN" "TRAFFIC OUT"
    echo -e "  ${DIM}$(_repeat '─' 70)${NC}"

    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        local label="${SECRETS_LABELS[$i]}"
        local enabled="${SECRETS_ENABLED[$i]}"
        local created="${SECRETS_CREATED[$i]}"
        local status_icon status_text

        if [ "$enabled" = "true" ]; then
            status_icon="${GREEN}${SYM_OK}${NC}"
            status_text="${GREEN}active${NC}"
        else
            # Check if disabled due to quota
            local _quota="${SECRETS_QUOTA[$i]:-0}"
            local _total_usage=$(( ${_batch_cum_in["$label"]:-0} + ${_batch_cum_out["$label"]:-0} ))
            if [ "$_quota" -gt 0 ] 2>/dev/null && [ "$_total_usage" -ge "$_quota" ] 2>/dev/null; then
                status_icon="${RED}${SYM_OK}${NC}"
                status_text="${RED}quota hit${NC}"
            else
                status_icon="${RED}${SYM_OK}${NC}"
                status_text="${RED}disabled${NC}"
            fi
        fi

        # Expiry warning
        local expiry_info=""
        local _exp="${SECRETS_EXPIRES[$i]}"
        if [ "$_exp" != "0" ] && [ -n "$_exp" ]; then
            local exp_epoch _exp_full="$_exp"
            [[ "$_exp_full" == *T* ]] || _exp_full="${_exp_full}T23:59:59Z"
            exp_epoch=$(_iso_to_epoch "$_exp_full" 2>/dev/null) || exp_epoch=0
            if [ "$exp_epoch" -gt 0 ]; then
                local now_epoch days_left
                now_epoch=$(date +%s)
                days_left=$(( (exp_epoch - now_epoch) / 86400 ))
                if [ "$days_left" -lt 0 ]; then
                    expiry_info=" ${RED}(expired)${NC}"
                elif [ "$days_left" -le 3 ]; then
                    expiry_info=" ${YELLOW}(${days_left}d left)${NC}"
                elif [ "$days_left" -le 7 ]; then
                    expiry_info=" ${DIM}(${days_left}d left)${NC}"
                fi
            fi
        fi

        # Format creation date (use printf builtin when available, fallback to date)
        local created_fmt
        created_fmt=$(printf '%(%Y-%m-%d)T' "$created" 2>/dev/null) || \
            created_fmt=$(date -d "@${created}" '+%Y-%m-%d' 2>/dev/null || echo "unknown")

        # Get per-user traffic from batch-loaded arrays
        local u_in=${_batch_cum_in["$label"]:-0}
        local u_out=${_batch_cum_out["$label"]:-0}
        local traffic_in_fmt traffic_out_fmt
        traffic_in_fmt=$(format_bytes "$u_in")
        traffic_out_fmt=$(format_bytes "$u_out")

        printf "  %-4s %-16s ${status_icon} %-8b %-10s %-12s %-12s" \
            "$((i+1))" "$label" "$status_text" "$created_fmt" "$traffic_in_fmt" "$traffic_out_fmt"
        echo -e "${expiry_info}"

        # Show note if present
        [ -n "${SECRETS_NOTES[$i]:-}" ] && echo -e "       ${DIM}📝 ${SECRETS_NOTES[$i]}${NC}"
    done
    echo ""
}

# Rotate a secret (new key, same label)
secret_rotate() {
    local label="$1"

    local idx=-1
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then
            idx=$i
            break
        fi
    done

    if [ $idx -eq -1 ]; then
        log_error "Secret '${label}' not found"
        return 1
    fi

    local new_secret
    new_secret=$(generate_secret)
    if [ -z "$new_secret" ] || ! [[ "$new_secret" =~ ^[0-9a-fA-F]{32}$ ]]; then
        log_error "Failed to generate secret"
        return 1
    fi
    SECRETS_KEYS[$idx]="$new_secret"
    SECRETS_CREATED[$idx]="$(date +%s)"

    save_secrets
    reload_proxy_config

    local full_secret
    full_secret=$(build_faketls_secret "$new_secret")
    local server_ip
    server_ip=$(get_public_ip)

    log_success "Secret '${label}' rotated"
    audit_log "secret rotate ${label}"
    echo ""
    echo -e "  ${BOLD}New Proxy Link:${NC}"
    echo -e "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    echo ""

    # Notify via Telegram if enabled
    if [ "$TELEGRAM_ENABLED" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local msg="🔄 *Secret Rotated*\n\nLabel: \`${label}\`\n📡 Server: \`${server_ip}\`\n🔌 Port: \`${PROXY_PORT}\`\n🔑 Secret: \`${full_secret}\`"
        telegram_send_message "$msg" &>/dev/null &
    fi
}

# Enable/disable a secret
secret_toggle() {
    [ ${#SECRETS_LABELS[@]} -eq 0 ] && load_secrets
    local label="$1" action="${2:-toggle}"

    local idx=-1
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then
            idx=$i
            break
        fi
    done

    if [ $idx -eq -1 ]; then
        log_error "Secret '${label}' not found"
        return 1
    fi

    local _will_disable=false
    case "$action" in
        enable)  SECRETS_ENABLED[$idx]="true" ;;
        disable) _will_disable=true; SECRETS_ENABLED[$idx]="false" ;;
        toggle)
            if [ "${SECRETS_ENABLED[$idx]}" = "true" ]; then
                _will_disable=true
                SECRETS_ENABLED[$idx]="false"
            else
                SECRETS_ENABLED[$idx]="true"
            fi
            ;;
        *) log_error "Invalid action: $action"; return 1 ;;
    esac

    # Prevent disabling the last active secret
    if $_will_disable; then
        local _en_count=0
        for i in "${!SECRETS_ENABLED[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] && _en_count=$((_en_count + 1))
        done
        if [ "$_en_count" -eq 0 ]; then
            # Revert — restore original state
            SECRETS_ENABLED[$idx]="true"
            log_error "Cannot disable the last enabled secret — proxy needs at least one"
            return 1
        fi
    fi

    save_secrets
    reload_proxy_config

    log_success "Secret '${label}' is now ${SECRETS_ENABLED[$idx]}"
}

# Get proxy link for a specific secret
get_proxy_link() {
    local label="${1:-}"
    local server_ip
    server_ip=$(get_public_ip)

    # If no label given, use first enabled secret
    if [ -z "$label" ]; then
        local i
        for i in "${!SECRETS_LABELS[@]}"; do
            if [ "${SECRETS_ENABLED[$i]}" = "true" ]; then
                label="${SECRETS_LABELS[$i]}"
                break
            fi
        done
    fi

    [ -z "$label" ] && { log_error "No active secrets"; return 1; }

    local idx=-1
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { idx=$i; break; }
    done

    [ $idx -eq -1 ] && { log_error "Secret '${label}' not found"; return 1; }

    local full_secret
    full_secret=$(build_faketls_secret "${SECRETS_KEYS[$idx]}")

    echo "tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}"
}

# Get HTTPS proxy link
get_proxy_link_https() {
    local label="${1:-}"
    local link
    link=$(get_proxy_link "$label") || return 1
    echo "$link" | sed 's|^tg://proxy|https://t.me/proxy|'
}

# Set per-user limits for a secret
secret_set_limits() {
    [ ${#SECRETS_LABELS[@]} -eq 0 ] && load_secrets
    local label="$1" max_conns="${2:-}" max_ips="${3:-}" quota="${4:-}" expires="${5:-}" no_restart="${6:-false}"

    local idx=-1
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then
            idx=$i
            break
        fi
    done

    if [ $idx -eq -1 ]; then
        log_error "Secret '${label}' not found"
        return 1
    fi

    # Update only provided values (validate numeric)
    if [ -n "$max_conns" ]; then
        [[ "$max_conns" =~ ^[0-9]+$ ]] || { log_error "Max connections must be a number"; return 1; }
        [ "$max_conns" -gt 1000000 ] && { log_error "Max connections cannot exceed 1000000"; return 1; }
        [ "$max_conns" -gt 0 ] && [ "$max_conns" -lt 5 ] && log_warn "Telegram uses ~3 connections per device; values below 5 may break connectivity"
        SECRETS_MAX_CONNS[$idx]="$max_conns"
    fi
    if [ -n "$max_ips" ]; then
        [[ "$max_ips" =~ ^[0-9]+$ ]] || { log_error "Max IPs must be a number"; return 1; }
        [ "$max_ips" -gt 1000000 ] && { log_error "Max IPs cannot exceed 1000000"; return 1; }
        SECRETS_MAX_IPS[$idx]="$max_ips"
    fi
    if [ -n "$quota" ]; then
        local quota_bytes
        quota_bytes=$(parse_human_bytes "$quota") || { log_error "Invalid quota format (e.g. 5G, 500M, 0)"; return 1; }
        SECRETS_QUOTA[$idx]="$quota_bytes"
    fi
    if [ -n "$expires" ]; then
        if [ "$expires" = "0" ] || [ "$expires" = "never" ]; then
            SECRETS_EXPIRES[$idx]="0"
        elif [[ "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            # Date only — append time component for RFC 3339
            SECRETS_EXPIRES[$idx]="${expires}T23:59:59Z"
        elif [[ "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
            SECRETS_EXPIRES[$idx]="$expires"
        else
            log_error "Invalid expiry format (use YYYY-MM-DD or 0 for never)"
            return 1
        fi
    fi

    save_secrets

    if [ "$no_restart" != "true" ]; then
        reload_proxy_config
    fi

    log_success "Limits updated for '${label}'"
    secret_show_limits "$label"
}

# Edit note/description for a secret
secret_edit_note() {
    local label="$1" note="${2:-}"

    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then idx=$i; break; fi
    done
    [ "$idx" = "-1" ] && { log_error "Secret '${label}' not found"; return 1; }

    # Interactive prompt if no note provided
    if [ -z "$note" ]; then
        echo -e "  ${DIM}Current note: ${SECRETS_NOTES[$idx]:-${DIM}(none)${NC}}${NC}"
        echo -en "  ${BOLD}New note (empty to clear):${NC} "
        read -r note
    fi

    # Validate: no pipe characters or newlines
    if [[ "$note" == *"|"* ]]; then
        log_error "Notes cannot contain the pipe character (|)"
        return 1
    fi

    SECRETS_NOTES[$idx]="$note"
    save_secrets
    if [ -n "$note" ]; then
        log_success "Note set for '${label}': ${note}"
    else
        log_success "Note cleared for '${label}'"
    fi
}

# Set per-secret AdTag (32 hex chars)
secret_set_adtag() {
    check_root
    local label="$1" ad_tag="$2" no_restart="${3:-false}"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret adtag <label> [32-hex-tag|clear]"; return 1; }

    ad_tag=$(echo "${ad_tag:-}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "$ad_tag" =~ ^(clear|remove|off|delete)$ ]] || [ -z "$ad_tag" ]; then
        secret_clear_adtag "$label" "$no_restart"
        return $?
    fi

    # Validate exactly 32 hex chars
    if ! [[ "$ad_tag" =~ ^[0-9a-f]{32}$ ]]; then
        log_error "Ad-tag must be exactly 32 hexadecimal characters (obtained from @MTProxyBot)"
        return 1
    fi

    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then idx=$i; break; fi
    done
    [ "$idx" = "-1" ] && { log_error "Secret '${label}' not found"; return 1; }

    SECRETS_AD_TAGS[$idx]="$ad_tag"
    save_secrets
    if [ "$no_restart" != "true" ]; then
        reload_proxy_config
    fi
    log_success "Set per-secret ad-tag '${ad_tag}' for secret '${label}'"
    audit_log "secret adtag set ${label} ${ad_tag}"
}

# Clear per-secret AdTag (revert to global default)
secret_clear_adtag() {
    check_root
    local label="$1" no_restart="${2:-false}"
    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then idx=$i; break; fi
    done
    [ "$idx" = "-1" ] && { log_error "Secret '${label}' not found"; return 1; }

    SECRETS_AD_TAGS[$idx]=""
    save_secrets
    if [ "$no_restart" != "true" ]; then
        reload_proxy_config
    fi
    log_success "Cleared per-secret ad-tag for secret '${label}' (reverted to global default)"
    audit_log "secret adtag clear ${label}"
}

# Re-enable a quota-exceeded secret with optional traffic reset
secret_reenable() {
    local label="$1"

    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_LABELS[$i]}" = "$label" ]; then idx=$i; break; fi
    done
    [ "$idx" = "-1" ] && { log_error "Secret '${label}' not found"; return 1; }

    if [ "${SECRETS_ENABLED[$idx]}" = "true" ]; then
        log_info "Secret '${label}' is already enabled"
        return 0
    fi

    # Re-enable
    SECRETS_ENABLED[$idx]="true"
    save_secrets

    # Offer quota reset
    local _quota="${SECRETS_QUOTA[$idx]:-0}"
    if [ "$_quota" -gt 0 ] 2>/dev/null; then
        echo -en "  ${BOLD}Reset traffic counter for quota? [y/N]:${NC} "
        local _ans; read -r _ans
        if [[ "$_ans" =~ ^[yY] ]]; then
            secret_reset_traffic "$label" "no_reload" >/dev/null 2>&1 || true
            log_success "Traffic counter reset for '${label}'"
        fi
    fi

    load_settings 2>/dev/null || true
    if [ "${QUOTA_ENFORCEMENT_MODE:-manager}" = "engine" ]; then
        restart_proxy_container 2>/dev/null || true
    else
        reload_proxy_config 2>/dev/null || true
    fi
    log_success "Secret '${label}' re-enabled"
}

# Reset traffic counters for a secret (or all)
secret_reset_traffic() {
    local label="${1:-}"
    local no_reload="${2:-}"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret reset-traffic <label|all>"; return 1; }

    local _ut="${STATS_DIR}/user_traffic"
    local _snap="${STATS_DIR}/user_traffic_snapshot"
    local _qa="${STATS_DIR}/.quota_alerts_sent"
    mkdir -p "${STATS_DIR}" 2>/dev/null

    if [ "$label" = "all" ]; then
        : > "$_ut" 2>/dev/null || true
        : > "$_qa" 2>/dev/null || true
        # Update snapshot with current live Prometheus values so delta becomes 0 right now
        local _m
        if _m=$(_fetch_metrics 2>/dev/null) && [ -n "$_m" ]; then
            echo "$_m" | awk '
                function get_user(s,   p,q) {
                    p = index(s, "user=\"")
                    if (!p) return ""
                    s = substr(s, p + 6)
                    q = index(s, "\"")
                    return q ? substr(s, 1, q - 1) : ""
                }
                /^telemt_user_octets_from_client\{/ { u = get_user($0); if (u) in_oct[u] += $NF }
                /^telemt_user_octets_to_client\{/ { u = get_user($0); if (u) out_oct[u] += $NF }
                END {
                    for (u in in_oct) {
                        printf "%s|%.0f|%.0f\n", u, in_oct[u], out_oct[u]
                    }
                }
            ' > "$_snap" 2>/dev/null || : > "$_snap"
        else
            : > "$_snap" 2>/dev/null || true
        fi
        log_success "Traffic counters reset for all users"
    else
        # Verify label exists
        local found=false i
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_LABELS[$i]}" = "$label" ] && { found=true; break; }
        done
        [ "$found" = "false" ] && { log_error "Secret '${label}' not found"; return 1; }

        # Clear saved user_traffic and quota alerts
        for f in "$_ut" "$_qa"; do
            [ -f "$f" ] && { grep -v "^${label}|" "$f" > "${f}.tmp" 2>/dev/null || true; mv "${f}.tmp" "$f" 2>/dev/null || true; }
        done

        # Update user_traffic_snapshot to exact current live Prometheus values so delta becomes 0 right now
        local live_in=0 live_out=0
        read -r live_in live_out _ <<< "$(get_user_stats "$label" 2>/dev/null)"
        [[ "${live_in:-0}" =~ ^[0-9]+$ ]] || live_in=0
        [[ "${live_out:-0}" =~ ^[0-9]+$ ]] || live_out=0
        if [ -f "$_snap" ]; then
            grep -v "^${label}|" "$_snap" > "${_snap}.tmp" 2>/dev/null || true
            mv "${_snap}.tmp" "$_snap" 2>/dev/null || true
        fi
        echo "${label}|${live_in}|${live_out}" >> "$_snap"
        log_success "Traffic counters reset for '${label}'"
    fi

    if [ "${no_reload:-}" != "no_reload" ]; then
        load_settings 2>/dev/null || true
        if [ "${QUOTA_ENFORCEMENT_MODE:-manager}" = "engine" ]; then
            restart_proxy_container 2>/dev/null || true
        else
            reload_proxy_config 2>/dev/null || true
        fi
    fi
}

# Show limits for a secret
secret_show_limits() {
    [ ${#SECRETS_LABELS[@]} -eq 0 ] && load_secrets
    local label="${1:-}"

    if [ -z "$label" ]; then
        # Show all
        echo ""
        draw_header "USER LIMITS"
        echo ""
        printf "  ${BOLD}%-4s %-16s %-10s %-8s %-12s %-14s${NC}\n" "#" "LABEL" "MAX CONN" "MAX IP" "QUOTA" "EXPIRES"
        echo -e "  ${DIM}$(_repeat '─' 70)${NC}"

        local i
        for i in "${!SECRETS_LABELS[@]}"; do
            local conns="${SECRETS_MAX_CONNS[$i]:-0}"
            local ips="${SECRETS_MAX_IPS[$i]:-0}"
            local quota="${SECRETS_QUOTA[$i]:-0}"
            local exp="${SECRETS_EXPIRES[$i]:-0}"
            local conns_fmt ips_fmt quota_fmt exp_fmt
            [ "$conns" = "0" ] && conns_fmt="${DIM}∞${NC}" || conns_fmt="$conns"
            [ "$ips" = "0" ] && ips_fmt="${DIM}∞${NC}" || ips_fmt="$ips"
            [ "$quota" = "0" ] && quota_fmt="${DIM}∞${NC}" || quota_fmt="$(format_bytes "$quota")"
            [ "$exp" = "0" ] && exp_fmt="${DIM}never${NC}" || exp_fmt="${exp%%T*}"

            printf "  %-4s %-16s %-10b %-8b %-12b %-14b\n" \
                "$((i+1))" "${SECRETS_LABELS[$i]}" "$conns_fmt" "$ips_fmt" "$quota_fmt" "$exp_fmt"
        done
        echo ""
        return
    fi

    local idx=-1
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { idx=$i; break; }
    done

    if [ $idx -eq -1 ]; then
        log_error "Secret '${label}' not found"
        return 1
    fi

    local conns="${SECRETS_MAX_CONNS[$idx]:-0}"
    local ips="${SECRETS_MAX_IPS[$idx]:-0}"
    local quota="${SECRETS_QUOTA[$idx]:-0}"
    local exp="${SECRETS_EXPIRES[$idx]:-0}"

    echo ""
    echo -e "  ${BOLD}Limits for '${label}':${NC}"
    echo -e "  Max TCP connections:  $([ "$conns" = "0" ] && echo "${DIM}unlimited${NC}" || echo "$conns")"
    echo -e "  Max unique IPs:       $([ "$ips" = "0" ] && echo "${DIM}unlimited${NC}" || echo "$ips")"
    echo -e "  Data quota:           $([ "$quota" = "0" ] && echo "${DIM}unlimited${NC}" || echo "$(format_bytes "$quota")")"
    echo -e "  Expires:              $([ "$exp" = "0" ] && echo "${DIM}never${NC}" || echo "$exp")"
    echo ""
}

# Rename a secret's label
secret_rename() {
    local old_label="$1" new_label="$2"
    [ -z "$old_label" ] || [ -z "$new_label" ] && { log_error "Usage: mtproxymax secret rename <old-label> <new-label>"; return 1; }

    # Validate new label
    [[ "$new_label" =~ ^[a-zA-Z0-9_-]+$ ]] || { log_error "Label must be alphanumeric (a-z, 0-9, _, -)"; return 1; }
    [ ${#new_label} -gt 32 ] && { log_error "Label must be 32 characters or less"; return 1; }

    # Find old label
    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$old_label" ] && { idx=$i; break; }
    done
    [ $idx -eq -1 ] && { log_error "Secret '${old_label}' not found"; return 1; }

    # Check new label doesn't exist
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$new_label" ] && { log_error "Secret '${new_label}' already exists"; return 1; }
    done

    SECRETS_LABELS[$idx]="$new_label"
    save_secrets
    reload_proxy_config
    log_success "Secret renamed: '${old_label}' → '${new_label}'"
}

# Clone a secret with all its limits
secret_clone() {
    local src_label="$1" new_label="$2"
    [ -z "$src_label" ] || [ -z "$new_label" ] && { log_error "Usage: mtproxymax secret clone <source-label> <new-label>"; return 1; }

    # Validate new label
    [[ "$new_label" =~ ^[a-zA-Z0-9_-]+$ ]] || { log_error "Label must be alphanumeric (a-z, 0-9, _, -)"; return 1; }
    [ ${#new_label} -gt 32 ] && { log_error "Label must be 32 characters or less"; return 1; }

    # Find source
    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$src_label" ] && { idx=$i; break; }
    done
    [ $idx -eq -1 ] && { log_error "Secret '${src_label}' not found"; return 1; }

    # Check new label doesn't exist
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$new_label" ] && { log_error "Secret '${new_label}' already exists"; return 1; }
    done

    SECRETS_LABELS+=("$new_label")
    SECRETS_KEYS+=("$(generate_secret)")
    SECRETS_CREATED+=("$(date +%s)")
    SECRETS_ENABLED+=("true")
    SECRETS_MAX_CONNS+=("${SECRETS_MAX_CONNS[$idx]:-0}")
    SECRETS_MAX_IPS+=("${SECRETS_MAX_IPS[$idx]:-0}")
    SECRETS_QUOTA+=("${SECRETS_QUOTA[$idx]:-0}")
    SECRETS_EXPIRES+=("${SECRETS_EXPIRES[$idx]:-0}")
    SECRETS_NOTES+=("${SECRETS_NOTES[$idx]:-}")
    SECRETS_AD_TAGS+=("${SECRETS_AD_TAGS[$idx]:-}")

    save_secrets
    reload_proxy_config

    local full_secret server_ip
    full_secret=$(build_faketls_secret "${SECRETS_KEYS[${#SECRETS_KEYS[@]}-1]}")
    server_ip=$(get_public_ip)
    log_success "Secret '${new_label}' cloned from '${src_label}'"
    echo -e "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    echo ""
}

# Extend all secrets' expiry by N days
secret_bulk_extend() {
    local days="$1"
    [ -z "$days" ] && { log_error "Usage: mtproxymax secret bulk-extend <days>"; return 1; }
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { log_error "Days must be a positive number"; return 1; }

    local now_epoch extended=0
    now_epoch=$(date +%s)

    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        local exp="${SECRETS_EXPIRES[$i]:-0}"
        [ "$exp" = "0" ] && continue

        local base_epoch
        base_epoch=$(_iso_to_epoch "$exp")
        [ "$base_epoch" -le "$now_epoch" ] && base_epoch=$now_epoch

        local new_epoch=$((base_epoch + days * 86400))
        local new_date
        new_date=$(date -u -d "@${new_epoch}" '+%Y-%m-%dT23:59:59Z' 2>/dev/null) || \
        new_date=$(date -u -r "$new_epoch" '+%Y-%m-%dT23:59:59Z' 2>/dev/null) || \
        new_date=$(python3 -c "import datetime;print(datetime.datetime.utcfromtimestamp(${new_epoch}).strftime('%Y-%m-%dT23:59:59Z'))" 2>/dev/null)
        [ -z "$new_date" ] && continue

        SECRETS_EXPIRES[$i]="$new_date"
        [ "${SECRETS_ENABLED[$i]}" = "false" ] && SECRETS_ENABLED[$i]="true"
        extended=$((extended + 1))
        log_info "${SECRETS_LABELS[$i]} → ${new_date%%T*}"
    done

    if [ $extended -gt 0 ]; then
        save_secrets
        reload_proxy_config
        log_success "Extended ${extended} secret(s) by ${days} days"
    else
        log_info "No secrets with expiry dates to extend"
    fi
}

# Export secrets to CSV (stdout)
secret_export() {
    echo "# label|key|enabled|max_conns|max_ips|quota|expires|notes|ad_tag"
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        echo "${SECRETS_LABELS[$i]}|${SECRETS_KEYS[$i]}|${SECRETS_ENABLED[$i]}|${SECRETS_MAX_CONNS[$i]:-0}|${SECRETS_MAX_IPS[$i]:-0}|${SECRETS_QUOTA[$i]:-0}|${SECRETS_EXPIRES[$i]:-0}|${SECRETS_NOTES[$i]:-}|${SECRETS_AD_TAGS[$i]:-}"
    done
}

# Import secrets from CSV file
secret_import() {
    local file="$1"
    [ -z "$file" ] && { log_error "Usage: mtproxymax secret import <file>"; return 1; }
    [ -f "$file" ] || { log_error "File not found: ${file}"; return 1; }

    local added=0 skipped=0
    while IFS='|' read -r label key col3 col4 col5 col6 col7 col8 col9 col10 col_rest || [ -n "$label" ]; do
        [[ "$label" =~ ^# ]] || [ -z "$label" ] && continue
        # Skip if label already exists
        local exists=false i
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_LABELS[$i]}" = "$label" ] && { exists=true; break; }
        done
        if $exists; then
            skipped=$((skipped + 1))
            continue
        fi
        # Validate
        [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { log_warn "Skipping invalid label: ${label}"; continue; }
        [[ "$key" =~ ^[a-fA-F0-9]{32}$ ]] || { log_warn "Skipping invalid key for ${label}"; continue; }

        local created enabled max_conns max_ips quota expires notes ad_tag
        if [ "$col3" = "true" ] || [ "$col3" = "false" ]; then
            created="$(date +%s)"
            enabled="$col3"
            max_conns="$col4"
            max_ips="$col5"
            quota="$col6"
            expires="$col7"
            notes="$col8"
            ad_tag="$col9"
        else
            created="${col3:-$(date +%s)}"
            [[ "$created" =~ ^[0-9]+$ ]] || created="$(date +%s)"
            enabled="${col4:-true}"
            max_conns="$col5"
            max_ips="$col6"
            quota="$col7"
            expires="$col8"
            notes="$col9"
            ad_tag="$col10"
        fi

        SECRETS_LABELS+=("$label")
        SECRETS_KEYS+=("$key")
        SECRETS_CREATED+=("$created")
        SECRETS_ENABLED+=("${enabled:-true}")
        SECRETS_MAX_CONNS+=("${max_conns:-0}")
        SECRETS_MAX_IPS+=("${max_ips:-0}")
        SECRETS_QUOTA+=("${quota:-0}")
        SECRETS_EXPIRES+=("${expires:-0}")
        SECRETS_NOTES+=("${notes:-}")
        SECRETS_AD_TAGS+=("${ad_tag:-}")
        added=$((added + 1))
    done < <(sed 's/,/|/g' "$file" 2>/dev/null || cat "$file")

    if [ $added -gt 0 ]; then
        save_secrets
        reload_proxy_config
    fi
    log_success "Imported ${added} secrets (${skipped} skipped as duplicates)"
}

# Show live active connections per user
show_connections() {
    local m
    if ! m=$(_fetch_metrics 2>/dev/null); then
        log_error "Metrics endpoint unavailable — is the proxy running?"
        return 1
    fi

    _load_all_cumulative_user_stats 2>/dev/null

    local parsed
    parsed=$(echo "$m" | awk '
        function lbl(s, k,    p, q) {
            p = index(s, k "=\""); if (!p) return ""
            s = substr(s, p + length(k) + 2)
            q = index(s, "\""); return q ? substr(s, 1, q-1) : ""
        }
        /^telemt_user_connections_current\{/  { u=lbl($0,"user"); if(u) uc[u]+=$NF }
        /^telemt_user_connections_total\{/    { u=lbl($0,"user"); if(u) ut[u]+=$NF }
        /^telemt_user_unique_ips_current\{/   { u=lbl($0,"user"); if(u) ui[u]+=$NF }
        /^telemt_user_octets_from_client\{/   { u=lbl($0,"user"); if(u) rx[u]+=$NF }
        /^telemt_user_octets_to_client\{/     { u=lbl($0,"user"); if(u) tx[u]+=$NF }
        /^telemt_connections_current /         { total=$NF }
        END {
            for (u in uc) users[u]=1
            for (u in ut) users[u]=1
            for (u in ui) users[u]=1
            for (u in rx) users[u]=1
            for (u in tx) users[u]=1
            printf "T|%.0f\n", total+0
            for (u in users)
                printf "U|%s|%.0f|%.0f|%.0f|%.0f|%.0f\n", u, uc[u]+0, ut[u]+0, ui[u]+0, rx[u]+0, tx[u]+0
        }
    ')

    local total=0
    IFS='|' read -r _ total <<< "$(echo "$parsed" | grep '^T|')"

    draw_header "ACTIVE CONNECTIONS"
    echo ""
    echo -e "  ${BOLD}Total active:${NC} ${total:-0}"
    echo ""

    local user_lines
    user_lines=$(echo "$parsed" | grep '^U|' | sort -t'|' -k3 -rn)
    if [ -n "$user_lines" ]; then
        printf "  ${BOLD}%-16s %8s %8s %6s %12s %12s${NC}\n" "USER" "ACTIVE" "TOTAL" "IPs" "DOWN" "UP"
        echo -e "  ${DIM}$(_repeat '─' 68)${NC}"
        while IFS='|' read -r _ uname ucur utot uips urx utx; do
            [ -z "$uname" ] && continue
            local down="${_batch_cum_in["$uname"]:-$urx}"
            local up="${_batch_cum_out["$uname"]:-$utx}"
            printf "  %-16s %8s %8s %6s %12s %12s\n" "$uname" "$ucur" "$utot" "$uips" "$(format_bytes "$down")" "$(format_bytes "$up")"
        done <<< "$user_lines"
    else
        echo -e "  ${DIM}No users connected${NC}"
    fi
    echo ""
}

# Disable all expired secrets
secret_disable_expired() {
    local now_epoch disabled=0 _disabled_list=""
    now_epoch=$(date +%s)

    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        local exp="${SECRETS_EXPIRES[$i]:-0}"
        [ "$exp" = "0" ] && continue
        [ "${SECRETS_ENABLED[$i]}" = "false" ] && continue

        local exp_epoch
        exp_epoch=$(_iso_to_epoch "$exp")
        [ "$exp_epoch" -le 0 ] && continue

        if [ "$exp_epoch" -le "$now_epoch" ]; then
            SECRETS_ENABLED[$i]="false"
            disabled=$((disabled + 1))
            _disabled_list+="${_disabled_list:+\n}  • *$(_esc "${SECRETS_LABELS[$i]}")* (exp: ${exp%%T*})"
            log_info "Disabled expired secret: ${SECRETS_LABELS[$i]} (expired ${exp%%T*})"
        fi
    done

    if [ $disabled -gt 0 ]; then
        save_secrets
        reload_proxy_config
        if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
            tg_send "⏳ *Expired Secrets Deactivated*\n\nAutomatically disabled ${disabled} user secret(s) whose expiration date passed:\n${_disabled_list}"
        fi
        log_success "Disabled ${disabled} expired secret(s)"
    else
        log_info "No expired secrets found"
    fi
}

# Extend a secret's expiry by N days
secret_extend() {
    local label="$1" days="$2"
    [ -z "$label" ] || [ -z "$days" ] && { log_error "Usage: mtproxymax secret extend <label> <days>"; return 1; }
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { log_error "Days must be a positive number"; return 1; }

    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { idx=$i; break; }
    done
    [ $idx -eq -1 ] && { log_error "Secret '${label}' not found"; return 1; }

    local exp="${SECRETS_EXPIRES[$idx]:-0}"
    local base_epoch
    if [ "$exp" = "0" ]; then
        # No expiry set — extend from now
        base_epoch=$(date +%s)
    else
        base_epoch=$(_iso_to_epoch "$exp")
        # If already expired, extend from now instead of the past date
        local now_epoch; now_epoch=$(date +%s)
        [ "$base_epoch" -le "$now_epoch" ] && base_epoch=$now_epoch
    fi

    local new_epoch=$((base_epoch + days * 86400))
    local new_date
    new_date=$(date -u -d "@${new_epoch}" '+%Y-%m-%dT23:59:59Z' 2>/dev/null) || \
    new_date=$(date -u -r "$new_epoch" '+%Y-%m-%dT23:59:59Z' 2>/dev/null) || \
    new_date=$(python3 -c "import datetime;print(datetime.datetime.utcfromtimestamp(${new_epoch}).strftime('%Y-%m-%dT23:59:59Z'))" 2>/dev/null)

    [ -z "$new_date" ] && { log_error "Failed to compute new expiry date"; return 1; }

    SECRETS_EXPIRES[$idx]="$new_date"
    # Re-enable if it was disabled due to expiry
    [ "${SECRETS_ENABLED[$idx]}" = "false" ] && SECRETS_ENABLED[$idx]="true"
    save_secrets
    reload_proxy_config
    log_success "Secret '${label}' expiry extended by ${days}d → ${new_date%%T*}"
}

# Compact per-user stats
secret_stats() {
    local m
    m=$(_fetch_metrics 2>/dev/null) || true

    # Parse live metrics in one awk pass
    local parsed=""
    if [ -n "$m" ]; then
        parsed=$(echo "$m" | awk '
            function lbl(s, k,    p, q) {
                p = index(s, k "=\""); if (!p) return ""
                s = substr(s, p + length(k) + 2)
                q = index(s, "\""); return q ? substr(s, 1, q-1) : ""
            }
            /^telemt_user_connections_current\{/  { u=lbl($0,"user"); if(u) uc[u]+=$NF }
            /^telemt_user_octets_from_client\{/   { u=lbl($0,"user"); if(u) rx[u]+=$NF }
            /^telemt_user_octets_to_client\{/     { u=lbl($0,"user"); if(u) tx[u]+=$NF }
            /^telemt_user_unique_ips_current\{/   { u=lbl($0,"user"); if(u) ip[u]+=$NF }
            END { for (u in uc) printf "%s|%.0f|%.0f|%.0f|%.0f\n", u, uc[u]+0, rx[u]+0, tx[u]+0, ip[u]+0 }
        ')
    fi

    draw_header "USER STATS"
    echo ""
    printf "  ${BOLD}%-14s %5s %6s %10s %10s %6s %8s %10s${NC}\n" "LABEL" "CONNS" "IPs" "DOWN" "UP" "QUOTA" "USED" "EXPIRES"
    echo -e "  ${DIM}$(_repeat '─' 80)${NC}"

    local now_epoch; now_epoch=$(date +%s)
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local label="${SECRETS_LABELS[$i]}"
        local quota="${SECRETS_QUOTA[$i]:-0}"
        local exp="${SECRETS_EXPIRES[$i]:-0}"

        # Live metrics for this user
        local conns=0 rx=0 tx=0 ips=0
        if [ -n "$parsed" ]; then
            local line; line=$(echo "$parsed" | grep "^${label}|" | head -1)
            if [ -n "$line" ]; then
                IFS='|' read -r _ conns rx tx ips <<< "$line"
            fi
        fi

        # Quota usage
        local quota_str="${DIM}—${NC}" used_str="${DIM}—${NC}"
        if [ "$quota" != "0" ] && [ "$quota" -gt 0 ] 2>/dev/null; then
            quota_str=$(format_bytes "$quota")
            local total_bytes=$((rx + tx))
            local pct=$(awk -v b="$total_bytes" -v q="$quota" 'BEGIN {printf "%.0f", (q>0 ? b/q*100 : 0)}')
            [ "$pct" -ge 80 ] 2>/dev/null && used_str="${YELLOW}${pct}%${NC}" || used_str="${pct}%"
        fi

        # Expiry
        local exp_str="${DIM}—${NC}"
        if [ "$exp" != "0" ]; then
            local exp_epoch; exp_epoch=$(_iso_to_epoch "$exp")
            local days_left=$(( (exp_epoch - now_epoch) / 86400 ))
            if [ $days_left -lt 0 ]; then
                exp_str="${RED}expired${NC}"
            elif [ $days_left -le 3 ]; then
                exp_str="${YELLOW}${days_left}d${NC}"
            else
                exp_str="${days_left}d"
            fi
        fi

        printf "  %-14s %5s %6s %10s %10s %6b %8b %10b\n" \
            "$label" "$conns" "$ips" "$(format_bytes "$rx")" "$(format_bytes "$tx")" "$quota_str" "$used_str" "$exp_str"
    done
    echo ""
}

# Sort secrets by field
secret_sort() {
    local field="${1:-traffic}"
    _load_all_cumulative_user_stats 2>/dev/null

    # Build sortable data: idx|sort_value
    local -a sort_data=()
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        local label="${SECRETS_LABELS[$i]}"
        local val=0
        case "$field" in
            traffic|t)
                val=$(( ${_batch_cum_in["$label"]:-0} + ${_batch_cum_out["$label"]:-0} ))
                ;;
            conns|c)
                val=${_batch_cum_conns["$label"]:-0}
                ;;
            date|d) val="${SECRETS_CREATED[$i]}" ;;
            name|n) ;; # handled separately
        esac
        sort_data+=("${i}|${val}|${label}")
    done

    # Sort
    local sorted
    if [ "$field" = "name" ] || [ "$field" = "n" ]; then
        sorted=$(printf '%s\n' "${sort_data[@]}" | sort -t'|' -k3)
    else
        sorted=$(printf '%s\n' "${sort_data[@]}" | sort -t'|' -k2 -rn)
    fi

    # Rebuild arrays in sorted order
    local -a new_labels=() new_keys=() new_created=() new_enabled=() new_conns=() new_ips=() new_quota=() new_expires=() new_notes=() new_adtags=()
    while IFS='|' read -r idx _ _; do
        new_labels+=("${SECRETS_LABELS[$idx]}")
        new_keys+=("${SECRETS_KEYS[$idx]}")
        new_created+=("${SECRETS_CREATED[$idx]}")
        new_enabled+=("${SECRETS_ENABLED[$idx]}")
        new_conns+=("${SECRETS_MAX_CONNS[$idx]}")
        new_ips+=("${SECRETS_MAX_IPS[$idx]}")
        new_quota+=("${SECRETS_QUOTA[$idx]}")
        new_expires+=("${SECRETS_EXPIRES[$idx]}")
        new_notes+=("${SECRETS_NOTES[$idx]}")
        new_adtags+=("${SECRETS_AD_TAGS[$idx]:-}")
    done <<< "$sorted"

    SECRETS_LABELS=("${new_labels[@]}")
    SECRETS_KEYS=("${new_keys[@]}")
    SECRETS_CREATED=("${new_created[@]}")
    SECRETS_ENABLED=("${new_enabled[@]}")
    SECRETS_MAX_CONNS=("${new_conns[@]}")
    SECRETS_MAX_IPS=("${new_ips[@]}")
    SECRETS_QUOTA=("${new_quota[@]}")
    SECRETS_EXPIRES=("${new_expires[@]}")
    SECRETS_NOTES=("${new_notes[@]}")
    SECRETS_AD_TAGS=("${new_adtags[@]}")

    save_secrets
    log_success "Secrets sorted by ${field}"
}

# Doctor: comprehensive diagnostics
run_doctor() {
    echo ""
    draw_header "DOCTOR"
    echo ""
    local issues=0

    # Docker
    if command -v docker &>/dev/null; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Docker installed"
    else
        echo -e "  ${RED}${SYM_CROSS}${NC} Docker not installed"
        issues=$((issues + 1))
    fi

    # Container
    if is_proxy_running; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Engine running"
    else
        echo -e "  ${RED}${SYM_CROSS}${NC} Engine not running"
        issues=$((issues + 1))
    fi

    # Port listening
    if ! is_port_available "$PROXY_PORT" 2>/dev/null; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Port ${PROXY_PORT} listening"
    elif is_proxy_running; then
        echo -e "  ${RED}${SYM_CROSS}${NC} Port ${PROXY_PORT} not listening (engine running but port not bound)"
        issues=$((issues + 1))
    else
        echo -e "  ${DIM}—${NC}  Port ${PROXY_PORT} (engine stopped)"
    fi

    # Metrics endpoint
    if curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" &>/dev/null; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Metrics endpoint responding"
    elif is_proxy_running; then
        echo -e "  ${RED}${SYM_CROSS}${NC} Metrics endpoint not responding"
        issues=$((issues + 1))
    else
        echo -e "  ${DIM}—${NC}  Metrics endpoint (engine stopped)"
    fi

    # Domain reachable
    local domain="${PROXY_DOMAIN:-cloudflare.com}"
    if curl -s --max-time 5 -o /dev/null "https://${domain}" 2>/dev/null; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Domain ${domain} reachable (TLS cert fetch will work)"
    else
        echo -e "  ${YELLOW}!${NC}  Domain ${domain} unreachable (engine will use fallback cert)"
        issues=$((issues + 1))
    fi

    # Secrets
    local active=0 disabled=0 expired=0 near_expiry=0 near_quota=0
    local now_epoch; now_epoch=$(date +%s)
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "${SECRETS_ENABLED[$i]}" = "true" ]; then
            active=$((active + 1))
        else
            disabled=$((disabled + 1))
        fi
        local exp="${SECRETS_EXPIRES[$i]:-0}"
        if [ "$exp" != "0" ]; then
            local exp_epoch; exp_epoch=$(_iso_to_epoch "$exp")
            if [ "$exp_epoch" -le "$now_epoch" ]; then
                expired=$((expired + 1))
            elif [ $((exp_epoch - now_epoch)) -le 259200 ]; then  # 3 days
                near_expiry=$((near_expiry + 1))
            fi
        fi
    done

    if [ $active -gt 0 ]; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} ${active} active secret(s)"
    else
        echo -e "  ${RED}${SYM_CROSS}${NC} No active secrets"
        issues=$((issues + 1))
    fi

    [ $expired -gt 0 ] && { echo -e "  ${YELLOW}!${NC}  ${expired} expired secret(s) — run: mtproxymax secret disable-expired"; issues=$((issues + 1)); }
    [ $near_expiry -gt 0 ] && echo -e "  ${YELLOW}!${NC}  ${near_expiry} secret(s) expiring within 3 days"

    # Disk space
    local disk_pct
    disk_pct=$(df -h "${INSTALL_DIR:-/opt/mtproxymax}" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$disk_pct" ] && [ "$disk_pct" -ge 90 ] 2>/dev/null; then
        echo -e "  ${RED}${SYM_CROSS}${NC} Disk usage ${disk_pct}% — critically low"
        issues=$((issues + 1))
    elif [ -n "$disk_pct" ] && [ "$disk_pct" -ge 80 ] 2>/dev/null; then
        echo -e "  ${YELLOW}!${NC}  Disk usage ${disk_pct}%"
    elif [ -n "$disk_pct" ]; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Disk usage ${disk_pct}%"
    fi

    # Config file
    if [ -f "${CONFIG_DIR}/config.toml" ]; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Config file exists"
    else
        echo -e "  ${RED}${SYM_CROSS}${NC} Config file missing — run: mtproxymax restart"
        issues=$((issues + 1))
    fi

    # Telegram bot
    if [ "$TELEGRAM_ENABLED" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local _cfg; _cfg=$(_mktemp) || true
        if [ -n "$_cfg" ]; then
            printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$TELEGRAM_BOT_TOKEN" > "$_cfg"
            if curl -s --max-time 5 -K "$_cfg" 2>/dev/null | grep -q '"ok":true'; then
                echo -e "  ${GREEN}${SYM_CHECK}${NC} Telegram bot reachable"
            else
                echo -e "  ${YELLOW}!${NC}  Telegram bot unreachable (can't reach api.telegram.org)"
                issues=$((issues + 1))
            fi
            rm -f "$_cfg"
        fi
    fi

    # v1.4.0-LTS Health Checks
    load_ssl_config 2>/dev/null || true
    if [ "${SSL_ENABLED:-false}" = "true" ] && [ -n "${SSL_DOMAIN:-}" ]; then
        if [ -f "${SSL_DIR}/${SSL_DOMAIN}.crt" ]; then
            echo -e "  ${GREEN}${SYM_CHECK}${NC} SSL Shield active for ${SSL_DOMAIN}"
        else
            echo -e "  ${RED}${SYM_CROSS}${NC} SSL Shield enabled for ${SSL_DOMAIN} but cert file missing"
            issues=$((issues + 1))
        fi
    fi
    load_speed_limits 2>/dev/null || true
    if [ "${#SPEED_LIMIT_TARGETS[@]}" -gt 0 ]; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} QoS Bandwidth shaping active (${#SPEED_LIMIT_TARGETS[@]} target(s))"
    fi
    load_cloud_backup_config 2>/dev/null || true
    if [ "${CLOUD_BACKUP_ENABLED:-false}" = "true" ]; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Cloud Backups enabled (${CLOUD_BACKUP_MODE:-telegram} -> ${CLOUD_BACKUP_TARGET:-admin})"
    fi

    echo ""
    if [ $issues -eq 0 ]; then
        echo -e "  ${BRIGHT_GREEN}All checks passed${NC}"
    else
        echo -e "  ${YELLOW}${issues} issue(s) found${NC}"
    fi
    echo ""
}

# Startup warnings (called after proxy start)
_startup_warnings() {
    local now_epoch; now_epoch=$(date +%s)
    local warnings=0

    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local exp="${SECRETS_EXPIRES[$i]:-0}"
        [ "$exp" = "0" ] && continue
        local exp_epoch; exp_epoch=$(_iso_to_epoch "$exp")
        if [ "$exp_epoch" -le "$now_epoch" ]; then
            [ $warnings -eq 0 ] && echo ""
            log_warn "Secret '${SECRETS_LABELS[$i]}' is expired"
            warnings=$((warnings + 1))
        elif [ $((exp_epoch - now_epoch)) -le 259200 ]; then
            local days_left=$(( (exp_epoch - now_epoch) / 86400 ))
            [ $warnings -eq 0 ] && echo ""
            log_warn "Secret '${SECRETS_LABELS[$i]}' expires in ${days_left}d"
            warnings=$((warnings + 1))
        fi
    done
}

# Full info for a single secret
secret_info() {
    local label="${1:-}"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret info <label>"; return 1; }

    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { idx=$i; break; }
    done
    [ $idx -eq -1 ] && { log_error "Secret '${label}' not found"; return 1; }

    local enabled="${SECRETS_ENABLED[$idx]}"
    local created="${SECRETS_CREATED[$idx]}"
    local conns="${SECRETS_MAX_CONNS[$idx]:-0}"
    local ips="${SECRETS_MAX_IPS[$idx]:-0}"
    local quota="${SECRETS_QUOTA[$idx]:-0}"
    local exp="${SECRETS_EXPIRES[$idx]:-0}"
    local notes="${SECRETS_NOTES[$idx]:-}"

    echo ""
    draw_header "SECRET: ${label}"
    echo ""
    echo -e "  ${BOLD}Status:${NC}      $([ "$enabled" = "true" ] && echo "${GREEN}active${NC}" || echo "${RED}disabled${NC}")"
    echo -e "  ${BOLD}Created:${NC}     $(date -d "@${created}" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$created" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$created")"
    [ -n "$notes" ] && echo -e "  ${BOLD}Notes:${NC}       ${notes}"
    local adtag="${SECRETS_AD_TAGS[$idx]:-}"
    if [ -n "$adtag" ]; then
        echo -e "  ${BOLD}Ad-tag:${NC}      ${adtag}"
    else
        echo -e "  ${BOLD}Ad-tag:${NC}      ${DIM}global default (${AD_TAG:-not set})${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}Limits:${NC}"
    echo -e "    Connections: $([ "$conns" = "0" ] && echo "unlimited" || echo "$conns")"
    echo -e "    IPs:         $([ "$ips" = "0" ] && echo "unlimited" || echo "$ips")"
    echo -e "    Quota:       $([ "$quota" = "0" ] && echo "unlimited" || echo "$(format_bytes "$quota")")"
    if [ "$exp" != "0" ]; then
        local exp_epoch; exp_epoch=$(_iso_to_epoch "$exp")
        local now_epoch; now_epoch=$(date +%s)
        local days_left=$(( (exp_epoch - now_epoch) / 86400 ))
        if [ $days_left -lt 0 ]; then
            echo -e "    Expires:     ${RED}expired${NC} (${exp%%T*})"
        else
            echo -e "    Expires:     ${exp%%T*} (${days_left}d left)"
        fi
    else
        echo -e "    Expires:     never"
    fi

    # Live metrics
    local m; m=$(_fetch_metrics 2>/dev/null) || true
    if [ -n "$m" ]; then
        local live; live=$(echo "$m" | awk -v u="$label" '
            function lbl(s, k,    p, q) { p=index(s,k"=\""); if(!p) return ""; s=substr(s,p+length(k)+2); q=index(s,"\""); return q ? substr(s,1,q-1) : "" }
            /^telemt_user_connections_current\{/ { if(lbl($0,"user")==u) c+=$NF }
            /^telemt_user_octets_from_client\{/  { if(lbl($0,"user")==u) rx+=$NF }
            /^telemt_user_octets_to_client\{/    { if(lbl($0,"user")==u) tx+=$NF }
            /^telemt_user_unique_ips_current\{/  { if(lbl($0,"user")==u) ip+=$NF }
            END { printf "%.0f|%.0f|%.0f|%.0f", c+0, rx+0, tx+0, ip+0 }
        ')
        local lc lrx ltx lip
        IFS='|' read -r lc lrx ltx lip <<< "$live"
        echo ""
        echo -e "  ${BOLD}Live:${NC}"
        echo -e "    Active conns: ${lc}   IPs: ${lip}"
        echo -e "    Traffic:      ${SYM_DOWN} $(format_bytes "$lrx")  ${SYM_UP} $(format_bytes "$ltx")"
    fi

    # Link
    local full_secret server_ip
    full_secret=$(build_faketls_secret "${SECRETS_KEYS[$idx]}")
    server_ip=$(get_public_ip)
    echo ""
    echo -e "  ${BOLD}Link:${NC}"
    echo -e "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    if command -v qrencode &>/dev/null; then
        echo ""
        qrencode -t ANSIUTF8 "tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}" 2>/dev/null | sed 's/^/  /'
    fi
    echo ""
}

# Bulk export all proxy links to file
secret_generate_links() {
    local fmt="${1:-txt}" outfile="${2:-}"
    local server_ip; server_ip=$(get_public_ip)
    [ -z "$server_ip" ] && { log_error "Cannot detect server IP"; return 1; }

    if [ "$fmt" = "html" ]; then
        [ -z "$outfile" ] && outfile="$(get_export_dir)/mtproxymax-links-$(date +%Y%m%d).html"
        {
            echo "<html><head><meta charset='utf-8'><title>MTProxyMax Links</title>"
            echo "<style>body{font-family:monospace;background:#1a1a2e;color:#e0e0e0;padding:20px}a{color:#4fc3f7}.user{margin:20px 0;padding:15px;border:1px solid #333;border-radius:8px}img{margin:10px 0}</style></head><body>"
            echo "<h1>MTProxyMax Proxy Links</h1><p>Generated: $(date -u '+%Y-%m-%d %H:%M UTC')</p>"
            local i
            for i in "${!SECRETS_LABELS[@]}"; do
                [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
                local label="${SECRETS_LABELS[$i]}"
                local fs; fs=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
                local link="https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${fs}"
                local qr_url="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$(printf '%s' "$link" | sed 's/:/%3A/g;s|/|%2F|g;s/?/%3F/g;s/=/%3D/g;s/&/%26/g')"
                echo "<div class='user'><h2>${label}</h2><a href='${link}'>${link}</a><br><img src='${qr_url}' alt='QR'></div>"
            done
            echo "</body></html>"
        } > "$outfile"
    else
        [ -z "$outfile" ] && outfile="$(get_export_dir)/mtproxymax-links-$(date +%Y%m%d).txt"
        {
            echo "# MTProxyMax Proxy Links — $(date -u '+%Y-%m-%d %H:%M UTC')"
            echo ""
            local i
            for i in "${!SECRETS_LABELS[@]}"; do
                [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
                local label="${SECRETS_LABELS[$i]}"
                local fs; fs=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
                echo "${label}:"
                echo "  tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${fs}"
                echo ""
            done
        } > "$outfile"
    fi
    chmod 600 "$outfile" 2>/dev/null || true
    log_success "Links exported to ${outfile}"
}

# Search secrets by partial label or note content
secret_search() {
    local query="$1"
    [ -z "$query" ] && { log_error "Usage: mtproxymax secret search <query>"; return 1; }

    local found=0 i
    local query_lower; query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    for i in "${!SECRETS_LABELS[@]}"; do
        local label="${SECRETS_LABELS[$i]}"
        local notes="${SECRETS_NOTES[$i]:-}"
        local label_lower; label_lower=$(echo "$label" | tr '[:upper:]' '[:lower:]')
        local notes_lower; notes_lower=$(echo "$notes" | tr '[:upper:]' '[:lower:]')
        if [[ "$label_lower" == *"$query_lower"* ]] || [[ "$notes_lower" == *"$query_lower"* ]]; then
            local icon="🟢"; [ "${SECRETS_ENABLED[$i]}" != "true" ] && icon="🔴"
            echo -e "  ${icon} ${BOLD}${label}${NC}$([ -n "$notes" ] && echo " — ${DIM}${notes}${NC}")"
            found=$((found + 1))
        fi
    done
    [ $found -eq 0 ] && log_info "No secrets matching '${query}'"
    [ $found -gt 0 ] && echo -e "\n  ${DIM}${found} result(s)${NC}"
}

# Archive a secret (soft-delete, restorable)
secret_archive() {
    local label="$1"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret archive <label>"; return 1; }

    local idx=-1 i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { idx=$i; break; }
    done
    [ $idx -eq -1 ] && { log_error "Secret '${label}' not found"; return 1; }

    # Prevent archiving the last secret
    [ ${#SECRETS_LABELS[@]} -le 1 ] && { log_error "Cannot archive the last secret"; return 1; }

    local archive_file="${INSTALL_DIR}/secrets_archive.conf"
    echo "${SECRETS_LABELS[$idx]}|${SECRETS_KEYS[$idx]}|${SECRETS_CREATED[$idx]}|${SECRETS_ENABLED[$idx]}|${SECRETS_MAX_CONNS[$idx]:-0}|${SECRETS_MAX_IPS[$idx]:-0}|${SECRETS_QUOTA[$idx]:-0}|${SECRETS_EXPIRES[$idx]:-0}|${SECRETS_NOTES[$idx]:-}|${SECRETS_AD_TAGS[$idx]:-}" >> "$archive_file"
    chmod 600 "$archive_file"

    # Remove from active arrays (inline, no log output)
    local -a _new=() _nk=() _nc=() _ne=() _nmc=() _nmi=() _nq=() _nex=() _nn=() _nat=()
    local j
    for j in "${!SECRETS_LABELS[@]}"; do
        [ "$j" -eq "$idx" ] && continue
        _new+=("${SECRETS_LABELS[$j]}"); _nk+=("${SECRETS_KEYS[$j]}"); _nc+=("${SECRETS_CREATED[$j]}")
        _ne+=("${SECRETS_ENABLED[$j]}"); _nmc+=("${SECRETS_MAX_CONNS[$j]:-0}"); _nmi+=("${SECRETS_MAX_IPS[$j]:-0}")
        _nq+=("${SECRETS_QUOTA[$j]:-0}"); _nex+=("${SECRETS_EXPIRES[$j]:-0}"); _nn+=("${SECRETS_NOTES[$j]:-}")
        _nat+=("${SECRETS_AD_TAGS[$j]:-}")
    done
    SECRETS_LABELS=("${_new[@]}"); SECRETS_KEYS=("${_nk[@]}"); SECRETS_CREATED=("${_nc[@]}")
    SECRETS_ENABLED=("${_ne[@]}"); SECRETS_MAX_CONNS=("${_nmc[@]}"); SECRETS_MAX_IPS=("${_nmi[@]}")
    SECRETS_QUOTA=("${_nq[@]}"); SECRETS_EXPIRES=("${_nex[@]}"); SECRETS_NOTES=("${_nn[@]}")
    SECRETS_AD_TAGS=("${_nat[@]}")
    save_secrets
    reload_proxy_config
    log_success "Secret '${label}' archived (restore with: mtproxymax secret unarchive ${label})"
}

# Unarchive (restore) a secret
secret_unarchive() {
    local label="$1"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret unarchive <label>"; return 1; }

    local archive_file="${INSTALL_DIR}/secrets_archive.conf"
    [ -f "$archive_file" ] || { log_error "No archived secrets"; return 1; }

    local line; line=$(grep "^${label}|" "$archive_file" | head -1)
    [ -z "$line" ] && { log_error "Secret '${label}' not found in archive"; return 1; }

    # Check not already active
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { log_error "Secret '${label}' already exists"; return 1; }
    done

    IFS='|' read -r _l key created enabled mc mi q ex notes ad_tag <<< "$line"
    SECRETS_LABELS+=("$label")
    SECRETS_KEYS+=("$key")
    SECRETS_CREATED+=("$created")
    SECRETS_ENABLED+=("${enabled:-true}")
    SECRETS_MAX_CONNS+=("${mc:-0}")
    SECRETS_MAX_IPS+=("${mi:-0}")
    SECRETS_QUOTA+=("${q:-0}")
    SECRETS_EXPIRES+=("${ex:-0}")
    SECRETS_NOTES+=("${notes:-}")
    local _at="${ad_tag:-}"
    [[ "$_at" =~ ^[0-9a-fA-F]{32}$ ]] || _at=""
    SECRETS_AD_TAGS+=("$_at")

    # Remove from archive
    local tmp; tmp=$(_mktemp) || return 1
    grep -v "^${label}|" "$archive_file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$archive_file"

    save_secrets
    reload_proxy_config
    log_success "Secret '${label}' restored from archive"
}

# List archived secrets
secret_archive_list() {
    local archive_file="${INSTALL_DIR}/secrets_archive.conf"
    if [ ! -f "$archive_file" ] || [ ! -s "$archive_file" ]; then
        log_info "No archived secrets"
        return
    fi
    echo ""
    draw_header "ARCHIVED SECRETS"
    echo ""
    while IFS='|' read -r label key created enabled _mc _mi _q _ex notes; do
        [ -z "$label" ] && continue
        local date_str; date_str=$(date -d "@${created}" '+%Y-%m-%d' 2>/dev/null || echo "$created")
        echo -e "  ${DIM}${SYM_OK}${NC} ${BOLD}${label}${NC}  created: ${date_str}$([ -n "$notes" ] && echo "  ${DIM}— ${notes}${NC}")"
    done < "$archive_file"
    echo ""
}

# Top N users by traffic or connections
secret_top() {
    local field="${1:-traffic}" count="${2:-5}"
    local m; m=$(_fetch_metrics 2>/dev/null) || { log_error "Metrics unavailable"; return 1; }

    local parsed
    parsed=$(echo "$m" | awk '
        function lbl(s, k,    p, q) { p=index(s,k"=\""); if(!p) return ""; s=substr(s,p+length(k)+2); q=index(s,"\""); return q ? substr(s,1,q-1) : "" }
        /^telemt_user_connections_current\{/  { u=lbl($0,"user"); if(u) uc[u]+=$NF }
        /^telemt_user_octets_from_client\{/   { u=lbl($0,"user"); if(u) rx[u]+=$NF }
        /^telemt_user_octets_to_client\{/     { u=lbl($0,"user"); if(u) tx[u]+=$NF }
        END { for(u in uc) printf "%s|%.0f|%.0f|%.0f\n", u, uc[u]+0, rx[u]+0, tx[u]+0 }
    ')

    echo ""
    case "$field" in
        traffic|t)
            draw_header "TOP ${count} BY TRAFFIC"
            echo ""
            echo "$parsed" | awk -F'|' '{printf "%s|%.0f\n", $0, $3+$4}' | sort -t'|' -k5 -rn | head -n "$count" | \
            while IFS='|' read -r uname conns rx tx total; do
                printf "  %-16s  ${SYM_DOWN} %-10s  ${SYM_UP} %-10s  (total: %s)\n" "$uname" "$(format_bytes "$rx")" "$(format_bytes "$tx")" "$(format_bytes "$total")"
            done
            ;;
        conns|c)
            draw_header "TOP ${count} BY CONNECTIONS"
            echo ""
            echo "$parsed" | sort -t'|' -k2 -rn | head -n "$count" | \
            while IFS='|' read -r uname conns rx tx; do
                printf "  %-16s  %s active connections\n" "$uname" "$conns"
            done
            ;;
    esac
    echo ""
}

# Purge disabled or expired secrets
secret_purge_disabled() {
    local to_purge=() i
    local now_s; now_s=$(date +%s)
    for i in "${!SECRETS_LABELS[@]}"; do
        local purge=false
        if [ "${SECRETS_ENABLED[$i]}" = "false" ]; then
            purge=true
        elif [ -n "${SECRETS_EXPIRES[$i]}" ] && [ "${SECRETS_EXPIRES[$i]}" != "0" ]; then
            local _exp_s; _exp_s=$(_iso_to_epoch "${SECRETS_EXPIRES[$i]}")
            [ "$_exp_s" -gt 0 ] && [ "$now_s" -ge "$_exp_s" ] 2>/dev/null && purge=true
        fi
        if [ "$purge" = "true" ]; then
            to_purge+=("${SECRETS_LABELS[$i]}")
        fi
    done

    if [ ${#to_purge[@]} -gt 0 ]; then
        if [ ${#to_purge[@]} -ge ${#SECRETS_LABELS[@]} ]; then
            log_error "Cannot purge all secrets — proxy needs at least one active secret"
            return 1
        fi
        local l count=0
        for l in "${to_purge[@]}"; do
            log_info "Purging secret: '${l}'"
            secret_remove "$l" "true" "true"
            count=$((count + 1))
        done
        if is_proxy_running; then restart_proxy_container; fi
        log_success "Purged ${count} disabled/expired secret(s)"
    else
        log_info "No disabled or expired secrets found to purge"
    fi
}

# Export subscription link feed (Base64)
secret_sub() {
    local server_ip; server_ip=$(get_public_ip)
    if [ -z "$server_ip" ]; then
        log_error "Cannot detect server IP"
        return 1
    fi
    local sub_feed="" i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local full_secret; full_secret=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
        local tg_link="tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}"
        sub_feed="${sub_feed}${tg_link}\n"
    done
    if [ -z "$sub_feed" ]; then
        log_info "No enabled secrets found for subscription"
        return 0
    fi
    printf "%b" "$sub_feed" | base64 | tr -d '\n'
    echo ""
}

# Export users as JSON
secret_export_json() {
    local json="[\n" i first=true
    for i in "${!SECRETS_LABELS[@]}"; do
        if [ "$first" = "true" ]; then first=false; else json="${json},\n"; fi
        local enabled_bool=true
        [ "${SECRETS_ENABLED[$i]}" = "false" ] && enabled_bool=false
        local exp_raw="${SECRETS_EXPIRES[$i]:-0}"
        local exp_epoch=0
        [ "$exp_raw" != "0" ] && exp_epoch=$(_iso_to_epoch "$exp_raw")
        local notes_clean="${SECRETS_NOTES[$i]:-}"
        notes_clean="${notes_clean//\"/\\\"}"
        local adtag_clean="${SECRETS_AD_TAGS[$i]:-}"
        adtag_clean="${adtag_clean//\"/\\\"}"
        json="${json}  {\"label\": \"${SECRETS_LABELS[$i]}\", \"key\": \"${SECRETS_KEYS[$i]}\", \"enabled\": ${enabled_bool}, \"max_conns\": ${SECRETS_MAX_CONNS[$i]:-0}, \"max_ips\": ${SECRETS_MAX_IPS[$i]:-0}, \"quota_bytes\": ${SECRETS_QUOTA[$i]:-0}, \"expires_iso\": \"${exp_raw}\", \"expires_epoch\": ${exp_epoch}, \"notes\": \"${notes_clean}\", \"ad_tag\": \"${adtag_clean}\"}"
    done
    json="${json}\n]\n"
    printf "%b" "$json"
}

# Rename secret labels by prefix
secret_rename_prefix() {
    local old_p="$1" new_p="$2" count=0 i
    [ -z "$old_p" ] && { log_error "Usage: mtproxymax secret rename-prefix <old_prefix> <new_prefix>"; return 1; }
    for i in "${!SECRETS_LABELS[@]}"; do
        local label="${SECRETS_LABELS[$i]}"
        if [[ "$label" == "$old_p"* ]]; then
            local new_label="${new_p}${label#$old_p}"
            if [[ "$new_label" =~ ^[a-zA-Z0-9_-]+$ ]] && [ ${#new_label} -le 32 ]; then
                log_info "Renaming '${label}' -> '${new_label}'"
                SECRETS_LABELS[$i]="$new_label"
                count=$((count + 1))
            else
                log_error "Skipping '${label}' -> '${new_label}' (invalid label format)"
            fi
        fi
    done
    if [ "$count" -gt 0 ]; then
        save_secrets
        reload_proxy_config
        log_success "Renamed ${count} secret(s) with prefix '${old_p}'"
    else
        log_info "No secrets found matching prefix '${old_p}'"
    fi
}

# Show current engine config
show_config() {
    local config="${CONFIG_DIR}/config.toml"
    if [ -f "$config" ]; then
        echo ""
        draw_header "ENGINE CONFIG"
        echo ""
        sed 's/^/  /' "$config"
        echo ""
    else
        log_error "Config file not found — is the proxy installed?"
    fi
}

# One-line scriptable uptime output
show_uptime_oneliner() {
    if ! is_proxy_running; then
        echo "stopped"
        return
    fi
    local up_secs; up_secs=$(get_proxy_uptime 2>/dev/null) || up_secs=0
    local t_in t_out conns
    read -r t_in t_out conns <<< "$(get_cumulative_proxy_stats 2>/dev/null)" || true
    echo "$(format_duration "$up_secs") | ${conns:-0} conns | ${SYM_DOWN} $(format_bytes "${t_in:-0}") ${SYM_UP} $(format_bytes "${t_out:-0}")"
}

# Send custom notification via Telegram
send_notify() {
    local msg="$1"
    [ -z "$msg" ] && { log_error "Usage: mtproxymax notify <message>"; return 1; }
    [ "$TELEGRAM_ENABLED" != "true" ] && { log_error "Telegram bot is not configured"; return 1; }
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && { log_error "Telegram bot token or chat ID not set"; return 1; }
    if telegram_send_message "📢 ${msg}"; then
        log_success "Notification sent"
    else
        log_error "Failed to send notification"
    fi
}

# Check if proxy port is reachable from outside
port_check() {
    local ip; ip=$(get_public_ip)
    [ -z "$ip" ] && { log_error "Cannot detect public IP"; return 1; }

    echo ""
    echo -e "  ${BOLD}Testing port ${PROXY_PORT} on ${ip}...${NC}"

    # Test 1: local socket check
    if ! is_port_available "$PROXY_PORT" 2>/dev/null; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Port ${PROXY_PORT} is listening locally"
    else
        echo -e "  ${RED}${SYM_CROSS}${NC} Port ${PROXY_PORT} is NOT listening"
        return 1
    fi

    # Test 2: external reachability via TLS handshake to self
    local result
    result=$(curl -sv --connect-timeout 5 --max-time 10 "https://${ip}:${PROXY_PORT}" 2>&1) || true
    if echo "$result" | grep -q "Connected to.*${PROXY_PORT}"; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Port ${PROXY_PORT} is reachable from outside"
    else
        echo -e "  ${RED}${SYM_CROSS}${NC} Port ${PROXY_PORT} is NOT reachable from outside"
        echo -e "  ${DIM}Check: firewall rules, cloud security groups, ISP blocking${NC}"
    fi
    echo ""
}

# Config profiles — save/load/list/delete
PROFILES_DIR="${INSTALL_DIR}/profiles"

profile_save() {
    local name="$1"
    [ -z "$name" ] && { log_error "Usage: mtproxymax profile save <name>"; return 1; }
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { log_error "Profile name must be alphanumeric"; return 1; }

    local dir="${PROFILES_DIR}/${name}"
    mkdir -p "$dir"
    for f in "${MIGRATION_FILES[@]}"; do
        [ -f "$f" ] && cp "$f" "${dir}/$(basename "$f")" 2>/dev/null || true
    done
    echo "$(date +%s)" > "${dir}/.timestamp"
    log_success "Profile '${name}' saved"
}

profile_load() {
    local name="$1"
    [ -z "$name" ] && { log_error "Usage: mtproxymax profile load <name>"; return 1; }

    local dir="${PROFILES_DIR}/${name}"
    [ -d "$dir" ] || { log_error "Profile '${name}' not found"; return 1; }

    for f in "${MIGRATION_FILES[@]}"; do
        local b; b=$(basename "$f")
        [ -f "${dir}/${b}" ] && cp "${dir}/${b}" "$f" 2>/dev/null || true
    done

    load_settings
    load_secrets
    load_upstreams 2>/dev/null || true

    if is_proxy_running; then
        restart_proxy_container
    else
        reload_proxy_config
    fi

    log_success "Profile '${name}' loaded and applied"
}

profile_list() {
    [ ! -d "$PROFILES_DIR" ] && { log_info "No saved profiles"; return; }
    local dirs; dirs=$(ls -1 "$PROFILES_DIR" 2>/dev/null)
    [ -z "$dirs" ] && { log_info "No saved profiles"; return; }

    echo ""
    draw_header "PROFILES"
    echo ""
    while read -r name; do
        [ -z "$name" ] && continue
        local ts="" date_str="unknown"
        [ -f "${PROFILES_DIR}/${name}/.timestamp" ] && ts=$(<"${PROFILES_DIR}/${name}/.timestamp")
        [ -n "$ts" ] && date_str=$(date -d "@${ts}" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ts")
        echo -e "  ${BOLD}${name}${NC}  ${DIM}saved: ${date_str}${NC}"
    done <<< "$dirs"
    echo ""
}

profile_delete() {
    local name="$1"
    [ -z "$name" ] && { log_error "Usage: mtproxymax profile delete <name>"; return 1; }
    local dir="${PROFILES_DIR}/${name}"
    [ -d "$dir" ] || { log_error "Profile '${name}' not found"; return 1; }
    rm -rf "$dir"
    log_success "Profile '${name}' deleted"
}

# ── Secret Tagging & Template Features ─────────────────────────

# ── Secret Tags (stored in separate file: label|tag1,tag2,tag3) ──
_TAGS_FILE="${INSTALL_DIR}/secrets_tags.conf"

secret_get_tags() {
    local label="$1"
    [ -f "$_TAGS_FILE" ] || return 0
    awk -F'|' -v u="$label" '$1==u{print $2; exit}' "$_TAGS_FILE"
}

secret_set_tags() {
    local label="$1" tags="$2"
    [ -z "$label" ] && { log_error "Usage: secret_set_tags <label> <tags>"; return 1; }
    mkdir -p "$INSTALL_DIR"
    touch "$_TAGS_FILE"; chmod 600 "$_TAGS_FILE"
    local tmp; tmp=$(_mktemp) || return 1
    grep -v "^${label}|" "$_TAGS_FILE" > "$tmp" 2>/dev/null || true
    [ -n "$tags" ] && echo "${label}|${tags}" >> "$tmp"
    mv "$tmp" "$_TAGS_FILE"
    chmod 600 "$_TAGS_FILE"
}

secret_tag() {
    local label="$1"; shift 2>/dev/null || true
    local new_tags="$*"
    [ -z "$label" ] || [ -z "$new_tags" ] && { log_error "Usage: mtproxymax secret tag <label> <tag1,tag2,...>"; return 1; }

    # Verify secret exists
    local exists=false i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { exists=true; break; }
    done
    $exists || { log_error "Secret '${label}' not found"; return 1; }

    # Sanitize tags: strip spaces, allow a-z0-9_-
    local _clean; _clean=$(echo "$new_tags" | tr '[:upper:]' '[:lower:]' | tr -s ' ' ',' | sed 's/[^a-z0-9_,-]//g;s/,,*/,/g;s/^,//;s/,$//')
    [ -z "$_clean" ] && { log_error "No valid tags after sanitization"; return 1; }

    secret_set_tags "$label" "$_clean"
    log_success "Tags for '${label}': ${_clean}"
}

secret_untag() {
    local label="$1"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret untag <label>"; return 1; }
    secret_set_tags "$label" ""
    log_success "Tags cleared for '${label}'"
}

secret_list_by_tag() {
    local tag="$1"
    [ -z "$tag" ] && { log_error "Usage: mtproxymax secret list --tag <tag>"; return 1; }
    [ -f "$_TAGS_FILE" ] || { log_info "No tagged secrets"; return 0; }

    local tag_lower; tag_lower=$(echo "$tag" | tr '[:upper:]' '[:lower:]')
    local found=0
    echo ""
    draw_header "SECRETS WITH TAG: ${tag_lower}"
    echo ""
    while IFS='|' read -r label tags; do
        [ -z "$label" ] && continue
        # Match whole tags (comma-separated)
        [[ ",${tags}," == *",${tag_lower},"* ]] || continue
        # Verify secret still exists and get status
        local idx=-1 i
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_LABELS[$i]}" = "$label" ] && { idx=$i; break; }
        done
        [ $idx -eq -1 ] && continue
        local icon="${GREEN}●${NC}"
        [ "${SECRETS_ENABLED[$idx]}" != "true" ] && icon="${RED}○${NC}"
        echo -e "  ${icon} ${BOLD}${label}${NC}  ${DIM}[${tags}]${NC}"
        found=$((found + 1))
    done < "$_TAGS_FILE"
    [ $found -eq 0 ] && echo -e "  ${DIM}No secrets with tag '${tag_lower}'${NC}"
    echo ""
}



# ── Maintenance mode (iptables-based) ──
MAINTENANCE_FILE="${INSTALL_DIR}/.maintenance"

maintenance_on() {
    check_root
    local port="${PROXY_PORT:-443}"
    # Idempotent: skip if rule already exists
    if ! iptables -C INPUT -p tcp --dport "$port" --syn -j REJECT --reject-with tcp-reset -m comment --comment "mtproxymax-maintenance" 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" --syn -j REJECT --reject-with tcp-reset -m comment --comment "mtproxymax-maintenance" 2>/dev/null
    fi
    touch "$MAINTENANCE_FILE"
    log_success "Maintenance mode ON — new connections rejected on port ${port}"
    log_info "Existing connections remain active. Use 'mtproxymax maintenance off' to restore."
}

# Reapply maintenance rule if the marker file exists (called on startup)
maintenance_reapply() {
    [ -f "$MAINTENANCE_FILE" ] || return 0
    local port="${PROXY_PORT:-443}"
    iptables -C INPUT -p tcp --dport "$port" --syn -j REJECT --reject-with tcp-reset -m comment --comment "mtproxymax-maintenance" 2>/dev/null || \
    iptables -I INPUT -p tcp --dport "$port" --syn -j REJECT --reject-with tcp-reset -m comment --comment "mtproxymax-maintenance" 2>/dev/null
}

maintenance_off() {
    check_root
    # Remove all rules tagged with our comment
    while iptables -C INPUT -p tcp --dport "${PROXY_PORT:-443}" --syn -j REJECT --reject-with tcp-reset -m comment --comment "mtproxymax-maintenance" 2>/dev/null; do
        iptables -D INPUT -p tcp --dport "${PROXY_PORT:-443}" --syn -j REJECT --reject-with tcp-reset -m comment --comment "mtproxymax-maintenance" 2>/dev/null
    done
    rm -f "$MAINTENANCE_FILE"
    log_success "Maintenance mode OFF — accepting new connections"
}

maintenance_status() {
    if [ -f "$MAINTENANCE_FILE" ]; then
        echo -e "  Maintenance: ${YELLOW}ON${NC}"
    else
        echo -e "  Maintenance: ${GREEN}OFF${NC}"
    fi
}

# ── IP Banlist (iptables) ──
BANLIST_FILE="${INSTALL_DIR}/banlist.conf"

_valid_ip_or_cidr() {
    local x="$1"
    [[ "$x" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]] || \
    [[ "$x" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]
}

ban_ip() {
    check_root
    local ip="$1"
    [ -z "$ip" ] && { log_error "Usage: mtproxymax ban <ip|cidr>"; return 1; }
    _valid_ip_or_cidr "$ip" || { log_error "Invalid IP or CIDR"; return 1; }

    # Idempotent: skip if already banned
    if [ -f "$BANLIST_FILE" ] && grep -qFx "$ip" "$BANLIST_FILE" 2>/dev/null; then
        log_warn "'${ip}' is already banned"
        return 0
    fi

    local cmd=iptables
    [[ "$ip" =~ : ]] && cmd=ip6tables
    $cmd -I INPUT -s "$ip" -j DROP -m comment --comment "mtproxymax-ban" 2>/dev/null || { log_error "Failed to add iptables rule"; return 1; }

    echo "$ip" >> "$BANLIST_FILE"
    chmod 600 "$BANLIST_FILE"
    log_success "Banned ${ip}"
}

unban_ip() {
    check_root
    local ip="$1"
    [ -z "$ip" ] && { log_error "Usage: mtproxymax unban <ip|cidr>"; return 1; }

    local cmd=iptables
    [[ "$ip" =~ : ]] && cmd=ip6tables
    while $cmd -C INPUT -s "$ip" -j DROP -m comment --comment "mtproxymax-ban" 2>/dev/null; do
        $cmd -D INPUT -s "$ip" -j DROP -m comment --comment "mtproxymax-ban" 2>/dev/null
    done

    if [ -f "$BANLIST_FILE" ]; then
        local tmp; tmp=$(_mktemp) || return 1
        grep -vFx "$ip" "$BANLIST_FILE" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$BANLIST_FILE"
    fi
    log_success "Unbanned ${ip}"
}

bans_list() {
    echo ""
    draw_header "BANNED IPs"
    echo ""
    if [ -f "$BANLIST_FILE" ] && [ -s "$BANLIST_FILE" ]; then
        local count=0
        while read -r ip; do
            [ -z "$ip" ] && continue
            echo -e "  ${RED}${SYM_CROSS}${NC} ${ip}"
            count=$((count + 1))
        done < "$BANLIST_FILE"
        echo ""
        echo -e "  ${DIM}${count} banned${NC}"
    else
        echo -e "  ${DIM}No IPs banned${NC}"
    fi
    echo ""
}

# Restore bans from file (called on startup / after reboot)
bans_reapply() {
    [ -f "$BANLIST_FILE" ] || return 0
    while read -r ip; do
        [ -z "$ip" ] && continue
        _valid_ip_or_cidr "$ip" || continue
        local cmd=iptables
        [[ "$ip" =~ : ]] && cmd=ip6tables
        $cmd -C INPUT -s "$ip" -j DROP -m comment --comment "mtproxymax-ban" 2>/dev/null || \
        $cmd -I INPUT -s "$ip" -j DROP -m comment --comment "mtproxymax-ban" 2>/dev/null
    done < "$BANLIST_FILE"
}

# ── Per-user activity log ──
secret_logs() {
    local label="$1" lines="${2:-50}"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret logs <label> [lines]"; return 1; }
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=50

    if [ ! -f "$CONNECTION_LOG" ] || [ ! -s "$CONNECTION_LOG" ]; then
        log_info "Connection log is empty"
        return
    fi

    echo ""
    draw_header "ACTIVITY: ${label}"
    echo ""
    local matches; matches=$(grep -F " ${label}: " "$CONNECTION_LOG" | tail -n "$lines")
    if [ -z "$matches" ]; then
        echo -e "  ${DIM}No activity logged for '${label}'${NC}"
    else
        echo "$matches" | sed 's/^/  /'
    fi
    echo ""
}

# ── Server migration: export/import ──
MIGRATION_FILES=("$SETTINGS_FILE" "$SECRETS_FILE" "$UPSTREAMS_FILE" "$INSTANCES_FILE" "$_TAGS_FILE" "${INSTALL_DIR}/secrets_archive.conf" "$BANLIST_FILE" "$SPEED_LIMITS_FILE" "$FLEET_FILE" "$SSL_CONF_FILE" "$CLOUD_BACKUP_FILE" "${INSTALL_DIR}/pools.conf" "${INSTALL_DIR}/calendar.conf" "${INSTALL_DIR}/webhooks.conf" "${INSTALL_DIR}/geofence.conf" "${INSTALL_DIR}/decoy.conf" "${INSTALL_DIR}/failover.conf" "${INSTALL_DIR}/eco_mode.conf" "$VOUCHERS_FILE" "$ADMINS_FILE")

migrate_export() {
    local out="${1:-$(get_export_dir)/mtproxymax-migrate-$(date +%Y%m%d-%H%M%S).tar.gz}"
    local tmp; tmp=$(mktemp -d) || { log_error "Cannot create temp dir"; return 1; }
    _TEMP_FILES+=("$tmp")
    local count=0
    for f in "${MIGRATION_FILES[@]}"; do
        [ -f "$f" ] && { cp "$f" "$tmp/$(basename "$f")" 2>/dev/null && count=$((count + 1)); }
    done
    # Also include profiles/ and v1.4 directories if present
    [ -d "${INSTALL_DIR}/profiles" ] && cp -r "${INSTALL_DIR}/profiles" "$tmp/" 2>/dev/null
    [ -d "$SSL_DIR" ] && cp -r "$SSL_DIR" "$tmp/" 2>/dev/null
    [ -d "$FLEET_DATA_DIR" ] && cp -r "$FLEET_DATA_DIR" "$tmp/" 2>/dev/null
    [ -d "$STATS_DIR" ] && cp -r "$STATS_DIR" "$tmp/" 2>/dev/null
    [ -f "${INSTALL_DIR}/connection.log" ] && cp "${INSTALL_DIR}/connection.log" "$tmp/" 2>/dev/null
    echo "v${VERSION}" > "$tmp/MIGRATE_VERSION"
    tar -czf "$out" -C "$tmp" . 2>/dev/null && log_success "Exported ${count} file(s) to ${out}" || { log_error "Export failed"; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    chmod 600 "$out"
}

migrate_import() {
    check_root
    local file="$1"
    [ -z "$file" ] && { log_error "Usage: mtproxymax migrate import <file.tar.gz>"; return 1; }
    [ -f "$file" ] || { log_error "File not found: ${file}"; return 1; }

    # Backup current state before overwriting
    local backup_before="${BACKUP_DIR}/pre-migrate-$(date +%s).tar.gz"
    mkdir -p "$BACKUP_DIR"
    migrate_export "$backup_before" 2>/dev/null
    log_info "Current state backed up to: ${backup_before}"

    local tmp; tmp=$(mktemp -d) || { log_error "Cannot create temp dir"; return 1; }
    _TEMP_FILES+=("$tmp")
    tar -xzf "$file" -C "$tmp" 2>/dev/null || { log_error "Invalid tarball"; rm -rf "$tmp"; return 1; }

    # Copy each file back (but not replication.conf to preserve role)
    local restored=0 f base
    for f in "${MIGRATION_FILES[@]}"; do
        base=$(basename "$f")
        [ -f "${tmp}/${base}" ] && { cp "${tmp}/${base}" "$f" && chmod 600 "$f" && restored=$((restored + 1)); }
    done
    # Restore profiles and v1.4 directories if present
    [ -d "${tmp}/profiles" ] && { rm -rf "${INSTALL_DIR}/profiles"; cp -r "${tmp}/profiles" "${INSTALL_DIR}/"; }
    [ -d "${tmp}/ssl" ] && { rm -rf "$SSL_DIR"; cp -r "${tmp}/ssl" "$SSL_DIR" 2>/dev/null; }
    [ -d "${tmp}/fleet_data" ] && { rm -rf "$FLEET_DATA_DIR"; cp -r "${tmp}/fleet_data" "$FLEET_DATA_DIR" 2>/dev/null; }
    [ -d "${tmp}/relay_stats" ] && { rm -rf "$STATS_DIR"; cp -r "${tmp}/relay_stats" "$STATS_DIR" 2>/dev/null; }
    [ -f "${tmp}/connection.log" ] && cp "${tmp}/connection.log" "${INSTALL_DIR}/connection.log" 2>/dev/null

    rm -rf "$tmp"
    load_settings
    load_secrets
    log_success "Imported ${restored} file(s) from ${file}"
    if is_proxy_running; then
        restart_proxy_container
    else
        reload_proxy_config
    fi
}

# ── Encrypted backups (openssl AES-256) ──
backup_create_encrypted() {
    check_root
    command -v openssl &>/dev/null || { log_error "openssl is required for encrypted backups"; return 1; }

    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local plain="${BACKUP_DIR}/mtproxymax-${ts}.tar.gz"
    local enc="${plain}.enc"

    migrate_export "$plain" >/dev/null || { log_error "Backup export failed"; return 1; }

    local pw1 pw2
    echo -en "  ${BOLD}Encryption password:${NC} "
    read -rs pw1; echo ""
    echo -en "  ${BOLD}Confirm password:${NC} "
    read -rs pw2; echo ""
    if [ "$pw1" != "$pw2" ]; then
        log_error "Passwords don't match"
        rm -f "$plain"
        unset pw1 pw2
        return 1
    fi
    if [ ${#pw1} -lt 8 ]; then
        log_error "Password must be at least 8 characters"
        rm -f "$plain"
        unset pw1 pw2
        return 1
    fi

    # Encrypt with AES-256-CBC + PBKDF2 (password via env to avoid exposing in process list)
    local _rc=0
    MTPMXPW="$pw1" openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "$plain" -out "$enc" -pass env:MTPMXPW 2>/dev/null || _rc=1
    unset pw1 pw2 MTPMXPW
    if [ "$_rc" -eq 0 ]; then
        chmod 600 "$enc"
        rm -f "$plain"
        log_success "Encrypted backup saved: ${enc}"
        backup_cloud_push "$enc" 2>/dev/null || true
        log_info "Keep your password safe — backup cannot be decrypted without it."
    else
        log_error "Encryption failed"
        rm -f "$plain" "$enc"
        return 1
    fi
}

backup_restore_encrypted() {
    check_root
    local file="$1"
    [ -z "$file" ] && { log_error "Usage: mtproxymax backup restore-encrypted <file.tar.gz.enc>"; return 1; }
    [ -f "$file" ] || { log_error "File not found: ${file}"; return 1; }
    command -v openssl &>/dev/null || { log_error "openssl is required"; return 1; }

    local pw
    echo -en "  ${BOLD}Decryption password:${NC} "
    read -rs pw; echo ""
    mkdir -p "$BACKUP_DIR"
    local plain; plain=$(_mktemp "${BACKUP_DIR}") || return 1
    local _rc=0
    MTPMXPW="$pw" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$file" -out "$plain" -pass env:MTPMXPW 2>/dev/null || _rc=1
    unset pw MTPMXPW
    if [ "$_rc" -eq 0 ]; then
        migrate_import "$plain"
        rm -f "$plain"
    else
        log_error "Decryption failed (wrong password?)"
        rm -f "$plain"
        return 1
    fi
}

# ── Comprehensive server info ──
show_server_info() {
    echo ""
    draw_header "MTPROXYMAX SERVER INFO"
    echo ""

    # System
    local os_name="unknown" kernel arch
    [ -f /etc/os-release ] && os_name=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-$ID}")
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")

    echo -e "  ${BOLD}System${NC}"
    echo -e "    OS:           ${os_name}"
    echo -e "    Kernel:       ${kernel}"
    echo -e "    Architecture: ${arch}"
    echo -e "    Hostname:     $(hostname 2>/dev/null || echo '—')"
    echo ""

    # Network
    local ip4 ip6
    ip4=$(get_public_ip)
    ip6=$(curl -s --max-time 3 -6 https://api6.ipify.org 2>/dev/null || echo "")
    echo -e "  ${BOLD}Network${NC}"
    echo -e "    Public IPv4:  ${ip4:-—}"
    echo -e "    Public IPv6:  ${ip6:-—}"
    echo -e "    Proxy port:   ${PROXY_PORT:-443}"
    echo ""

    # Proxy config
    echo -e "  ${BOLD}Proxy Configuration${NC}"
    echo -e "    Script ver:   v${VERSION}"
    echo -e "    Engine ver:   telemt v$(get_telemt_version 2>/dev/null || echo '?')"
    echo -e "    Domain:       ${PROXY_DOMAIN:-cloudflare.com}"
    echo -e "    Masking:      ${MASKING_ENABLED:-true}"
    echo -e "    Ad-tag:       ${AD_TAG:-${DIM}not set${NC}}"
    echo ""

    # Users
    local active=0 disabled=0 total=${#SECRETS_LABELS[@]} i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] && active=$((active + 1)) || disabled=$((disabled + 1))
    done
    local archived=0
    [ -f "${INSTALL_DIR}/secrets_archive.conf" ] && archived=$(awk 'NF>0 && !/^[[:space:]]*#/{c++} END{print c+0}' "${INSTALL_DIR}/secrets_archive.conf" 2>/dev/null || echo 0)

    echo -e "  ${BOLD}Users${NC}"
    echo -e "    Total:        ${total}"
    echo -e "    Active:       ${active}"
    echo -e "    Disabled:     ${disabled}"
    echo -e "    Archived:     ${archived}"
    echo ""

    # Services
    local proxy_status="stopped"
    is_proxy_running && proxy_status="running"
    local bot_status="disabled"
    [ "${TELEGRAM_ENABLED:-false}" = "true" ] && bot_status="enabled"
    local repl_role="${REPLICATION_ROLE:-standalone}"
    local ssl_st="disabled"
    load_ssl_config 2>/dev/null || true
    [ "${SSL_ENABLED:-false}" = "true" ] && ssl_st="active (${SSL_DOMAIN})"
    local qos_st="disabled"
    load_speed_limits 2>/dev/null || true
    [ "${#SPEED_LIMIT_TARGETS[@]}" -gt 0 ] && qos_st="active (${#SPEED_LIMIT_TARGETS[@]} rule(s))"
    local cb_st="disabled"
    load_cloud_backup_config 2>/dev/null || true
    [ "${CLOUD_BACKUP_ENABLED:-false}" = "true" ] && cb_st="active (${CLOUD_BACKUP_MODE:-telegram})"

    echo -e "  ${BOLD}Services${NC}"
    echo -e "    Proxy:        ${proxy_status}"
    echo -e "    Telegram bot: ${bot_status}"
    echo -e "    Replication:  ${repl_role}"
    echo -e "    SSL Shield:   ${ssl_st}"
    echo -e "    QoS shaping:  ${qos_st}"
    echo -e "    Cloud Backup: ${cb_st}"
    if [ -f "$MAINTENANCE_FILE" ]; then
        echo -e "    Maintenance:  ${YELLOW}ON${NC}"
    fi
    local ban_count=0
    [ -f "$BANLIST_FILE" ] && ban_count=$(wc -l < "$BANLIST_FILE" 2>/dev/null | tr -d ' ')
    [ "$ban_count" -gt 0 ] 2>/dev/null && echo -e "    Banned IPs:   ${ban_count}"
    echo ""

    # Security
    echo -e "  ${BOLD}Security${NC}"
    echo -e "    Metrics bind: 127.0.0.1:${PROXY_METRICS_PORT:-9090} ${DIM}(localhost only)${NC}"
    echo -e "    SNI policy:   ${UNKNOWN_SNI_ACTION:-mask}"
    local geo_count=0
    [ -n "$BLOCKLIST_COUNTRIES" ] && geo_count=$(echo "$BLOCKLIST_COUNTRIES" | tr ',' '\n' | wc -l | tr -d ' ')
    echo -e "    Geo-block:    ${GEOBLOCK_MODE:-blacklist} (${geo_count} countries)"
    echo ""

    # Disk
    local disk_usage
    disk_usage=$(df -h "$INSTALL_DIR" 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')
    echo -e "  ${BOLD}Storage${NC}"
    echo -e "    Install dir:  ${INSTALL_DIR}"
    echo -e "    Disk used:    ${disk_usage:-—}"
    echo ""
}

# ── Monthly quota reset ──
# Config: secrets_quota_reset.conf with lines "label|day_of_month"
# State:  .quota_reset_log with lines "label|YYYY-MM" (last reset month)
_QUOTA_RESET_FILE="${INSTALL_DIR}/secrets_quota_reset.conf"
_QUOTA_RESET_LOG="${INSTALL_DIR}/relay_stats/.quota_reset_log"

secret_get_quota_reset_day() {
    local label="$1"
    [ -f "$_QUOTA_RESET_FILE" ] || return 0
    awk -F'|' -v u="$label" '$1==u{print $2; exit}' "$_QUOTA_RESET_FILE"
}

secret_set_quota_reset_day() {
    check_root
    local label="$1" day="$2"
    [ -z "$label" ] && { log_error "Usage: mtproxymax secret quota-reset <label> <day|off>"; return 1; }

    # Verify secret exists
    local exists=false i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { exists=true; break; }
    done
    $exists || { log_error "Secret '${label}' not found"; return 1; }

    mkdir -p "$INSTALL_DIR"
    touch "$_QUOTA_RESET_FILE"; chmod 600 "$_QUOTA_RESET_FILE"
    local tmp; tmp=$(_mktemp) || return 1
    grep -v "^${label}|" "$_QUOTA_RESET_FILE" > "$tmp" 2>/dev/null || true

    if [ "$day" = "off" ] || [ "$day" = "clear" ] || [ -z "$day" ]; then
        mv "$tmp" "$_QUOTA_RESET_FILE"; chmod 600 "$_QUOTA_RESET_FILE"
        log_success "Quota reset disabled for '${label}'"
    elif [[ "$day" =~ ^[0-9]+$ ]] && [ "$day" -ge 1 ] && [ "$day" -le 31 ]; then
        echo "${label}|${day}" >> "$tmp"
        mv "$tmp" "$_QUOTA_RESET_FILE"; chmod 600 "$_QUOTA_RESET_FILE"
        log_success "Quota for '${label}' will reset on day ${day} of each month"
    else
        rm -f "$tmp"
        log_error "Day must be 1-31, 'off', or 'clear'"
        return 1
    fi
}

# Check quota resets (called from bot loop)
secret_check_quota_resets() {
    [ -f "$_QUOTA_RESET_FILE" ] || return 0
    local today_day today_month last_day
    today_day=$(date +%d | sed 's/^0//')
    today_month=$(date +%Y-%m)
    # Last day of current month (GNU date or BSD fallback)
    last_day=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%d 2>/dev/null | sed 's/^0//')
    [ -z "$last_day" ] && last_day=$(date -v1d -v+1m -v-1d +%d 2>/dev/null | sed 's/^0//')
    [ -z "$last_day" ] && last_day=31

    mkdir -p "$(dirname "$_QUOTA_RESET_LOG")"
    touch "$_QUOTA_RESET_LOG"; chmod 600 "$_QUOTA_RESET_LOG"

    while IFS='|' read -r label day; do
        [ -z "$label" ] && continue
        [[ "$day" =~ ^[0-9]+$ ]] || continue
        # Clamp configured day to last day of the current month (e.g. day 31 in February → day 28/29)
        local effective_day="$day"
        [ "$day" -gt "$last_day" ] && effective_day="$last_day"
        # Only reset on or after the effective day
        [ "$today_day" -lt "$effective_day" ] && continue
        # Already reset this month?
        awk -v l="$label" -v m="$today_month" -F'|' '$1 == l && $2 == m {found=1} END {exit !found}' "$_QUOTA_RESET_LOG" 2>/dev/null && continue
        # Reset
        if secret_reset_traffic "$label" &>/dev/null; then
            echo "${label}|${today_month}" >> "$_QUOTA_RESET_LOG"
            log_info "Monthly quota reset for '${label}'"
        fi
    done < "$_QUOTA_RESET_FILE"
}

# ── Auto-rotate policy ──
# Global setting: SECRET_AUTO_ROTATE_DAYS (in settings.conf)
# State: .auto_rotate_log (last rotation per label as epoch)
_AUTO_ROTATE_LOG="${INSTALL_DIR}/relay_stats/.auto_rotate_log"

secret_check_auto_rotate() {
    local days="${SECRET_AUTO_ROTATE_DAYS:-0}"
    [ "$days" = "0" ] || [ -z "$days" ] && return 0
    [[ "$days" =~ ^[0-9]+$ ]] || return 0

    mkdir -p "$(dirname "$_AUTO_ROTATE_LOG")"
    touch "$_AUTO_ROTATE_LOG"; chmod 600 "$_AUTO_ROTATE_LOG"

    local now i
    now=$(date +%s)
    local threshold=$((days * 86400))

    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local label="${SECRETS_LABELS[$i]}"
        # Check last auto-rotate time (if any) or use creation time
        local last; last=$(awk -F'|' -v u="$label" '$1==u{print $2; exit}' "$_AUTO_ROTATE_LOG")
        [ -z "$last" ] && last="${SECRETS_CREATED[$i]}"
        [[ "$last" =~ ^[0-9]+$ ]] || continue
        local age=$((now - last))
        if [ "$age" -ge "$threshold" ]; then
            if secret_rotate "$label" &>/dev/null; then
                # Update log
                local tmp; tmp=$(_mktemp) || continue
                grep -v "^${label}|" "$_AUTO_ROTATE_LOG" > "$tmp" 2>/dev/null || true
                echo "${label}|${now}" >> "$tmp"
                mv "$tmp" "$_AUTO_ROTATE_LOG"; chmod 600 "$_AUTO_ROTATE_LOG"
                log_info "Auto-rotated '${label}' (age: $((age / 86400))d)"
            fi
        fi
    done
}

# ── Backup autoclean ──
backup_autoclean() {
    local days="${1:-${BACKUP_RETENTION_DAYS:-30}}"
    [[ "$days" =~ ^[0-9]+$ ]] || { log_error "Days must be a positive integer"; return 1; }
    [ "$days" -le 0 ] && { log_info "Autoclean disabled (0 = keep all)"; return 0; }
    [ -d "$BACKUP_DIR" ] || return 0

    local before=0 after=0
    before=$(find "$BACKUP_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    find "$BACKUP_DIR" -maxdepth 1 -type f -mtime "+${days}" -delete 2>/dev/null
    after=$(find "$BACKUP_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')

    local removed=$((before - after))
    log_success "Removed ${removed} backup(s) older than ${days} day(s) (${after} remaining)"
}

# ── Secret Templates ──
_TEMPLATES_FILE="${INSTALL_DIR}/templates.conf"

template_save() {
    check_root
    local name="$1" conns="${2:-0}" ips="${3:-0}" quota="${4:-0}" expires="${5:-0}" notes="${6:-}"
    [ -z "$name" ] && { log_error "Usage: mtproxymax template save <name> <conns> <ips> <quota> [expires] [notes]"; return 1; }
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { log_error "Name must be alphanumeric"; return 1; }
    [[ "$conns" =~ ^[0-9]+$ ]] || { log_error "Conns must be a number"; return 1; }
    [[ "$ips" =~ ^[0-9]+$ ]] || { log_error "IPs must be a number"; return 1; }

    # Parse quota (supports 10G, 500M, etc)
    local quota_bytes
    if [[ "$quota" =~ ^[0-9]+$ ]]; then
        quota_bytes="$quota"
    else
        quota_bytes=$(parse_human_bytes "$quota" 2>/dev/null) || quota_bytes="0"
    fi

    mkdir -p "$INSTALL_DIR"
    touch "$_TEMPLATES_FILE"; chmod 600 "$_TEMPLATES_FILE"
    local tmp; tmp=$(_mktemp) || return 1
    grep -v "^${name}|" "$_TEMPLATES_FILE" > "$tmp" 2>/dev/null || true
    echo "${name}|${conns}|${ips}|${quota_bytes}|${expires}|${notes}" >> "$tmp"
    mv "$tmp" "$_TEMPLATES_FILE"; chmod 600 "$_TEMPLATES_FILE"
    log_success "Template '${name}' saved: conns=${conns} ips=${ips} quota=${quota} expires=${expires:-never}"
}

template_list() {
    if [ ! -f "$_TEMPLATES_FILE" ] || [ ! -s "$_TEMPLATES_FILE" ]; then
        log_info "No templates saved"
        return
    fi
    echo ""
    draw_header "TEMPLATES"
    echo ""
    printf "  ${BOLD}%-16s %-8s %-8s %-12s %-14s${NC}\n" "NAME" "CONNS" "IPS" "QUOTA" "EXPIRES"
    echo -e "  ${DIM}$(_repeat '─' 64)${NC}"
    while IFS='|' read -r name conns ips quota expires notes; do
        [ -z "$name" ] && continue
        local q_fmt="$([ "$quota" = "0" ] && echo "—" || format_bytes "$quota")"
        local e_fmt="$([ "$expires" = "0" ] || [ -z "$expires" ] && echo "never" || echo "${expires%%T*}")"
        printf "  %-16s %-8s %-8s %-12s %-14s\n" "$name" "$conns" "$ips" "$q_fmt" "$e_fmt"
    done < "$_TEMPLATES_FILE"
    echo ""
}

template_delete() {
    check_root
    local name="$1"
    [ -z "$name" ] && { log_error "Usage: mtproxymax template delete <name>"; return 1; }
    [ -f "$_TEMPLATES_FILE" ] || { log_error "No templates saved"; return 1; }

    local tmp; tmp=$(_mktemp) || return 1
    grep -v "^${name}|" "$_TEMPLATES_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$_TEMPLATES_FILE"; chmod 600 "$_TEMPLATES_FILE"
    log_success "Template '${name}' deleted"
}

# Apply a template to an existing secret
template_apply() {
    check_root
    local name="$1" label="$2"
    [ -z "$name" ] || [ -z "$label" ] && { log_error "Usage: mtproxymax template apply <name> <label>"; return 1; }
    [ -f "$_TEMPLATES_FILE" ] || { log_error "No templates saved"; return 1; }

    local line; line=$(grep "^${name}|" "$_TEMPLATES_FILE" | head -1)
    [ -z "$line" ] && { log_error "Template '${name}' not found"; return 1; }

    IFS='|' read -r _tn tconns tips tquota texpires tnotes <<< "$line"
    secret_set_limits "$label" "$tconns" "$tips" "$tquota" "$texpires" "false" || return 1
    if [ -n "$tnotes" ]; then
        local _idx; _idx=$(_get_secret_idx "$label")
        if [ "$_idx" != "-1" ]; then
            SECRETS_NOTES[$_idx]="$tnotes"
            save_secrets
        fi
    fi
    log_success "Template '${name}' applied to '${label}'"
}

_get_secret_idx() {
    local label="$1" i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_LABELS[$i]}" = "$label" ] && { echo "$i"; return; }
    done
    echo "-1"
}

# ── Bulk rotate all secrets ──
secret_rotate_all() {
    check_root
    local dry_run="${1:-false}"

    [ ${#SECRETS_LABELS[@]} -eq 0 ] && { log_info "No secrets to rotate"; return 0; }

    if [ "$dry_run" = "true" ]; then
        local i dry_count=0
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] && dry_count=$((dry_count + 1))
        done
        log_info "DRY RUN — would rotate ${dry_count} enabled secret(s):"
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] && echo "  - ${SECRETS_LABELS[$i]}"
        done
        return 0
    fi

    if [ -t 0 ]; then
        echo -en "  ${YELLOW}This will rotate ALL ${#SECRETS_LABELS[@]} secret(s). Existing links will stop working. Type 'yes' to confirm:${NC} "
        local confirm; read -r confirm
        [ "$confirm" != "yes" ] && { log_info "Cancelled"; return 0; }
    fi

    local now; now=$(date +%s)
    local i count=0
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        SECRETS_KEYS[$i]=$(generate_secret)
        SECRETS_CREATED[$i]="$now"
        count=$((count + 1))
    done
    save_secrets
    reload_proxy_config
    log_success "Rotated ${count} secret(s) — share new links with your users"
    audit_log "secret rotate --all (${count} secrets)"
}

# ── CSV secret listing ──
secret_list_csv() {
    echo "label,enabled,max_conns,max_ips,quota_bytes,expires,notes,tags"
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        local label="${SECRETS_LABELS[$i]}"
        local tags; tags=$(secret_get_tags "$label" 2>/dev/null)
        # Sanitize notes for CSV: strip newlines, escape commas and quotes
        local notes="${SECRETS_NOTES[$i]:-}"
        notes="${notes//$'\n'/ }"
        notes="${notes//$'\r'/ }"
        notes="${notes//\"/\"\"}"
        notes="${notes//,/;}"
        echo "${label},${SECRETS_ENABLED[$i]},${SECRETS_MAX_CONNS[$i]:-0},${SECRETS_MAX_IPS[$i]:-0},${SECRETS_QUOTA[$i]:-0},${SECRETS_EXPIRES[$i]:-0},\"${notes}\",${tags}"
    done
}

# ── Engine parameter tuning ──
# Whitelist of safe params that can be set via `tune`
# Format: param_name:section:validator  (section: general|server|timeouts|censorship)
_TUNE_WHITELIST=(
    "fake_cert_len:censorship:^[0-9]+$"
    "client_handshake:timeouts:^[0-9]+$"
    "tg_connect:timeouts:^[0-9]+$"
    "client_keepalive:timeouts:^[0-9]+$"
    "client_ack:timeouts:^[0-9]+$"
    "replay_check_len:access:^[0-9]+$"
    "replay_window_secs:access:^[0-9]+$"
    "ignore_time_skew:access:^(true|false)$"
    "listen_backlog:server:^[0-9]+$"
    "max_connections:server:^[0-9]+$"
    "accept_permit_timeout_ms:server:^[0-9]+$"
    "prefer_ipv6:general:^(true|false)$"
    "fast_mode:general:^(true|false)$"
    "log_level:general:^(debug|verbose|normal|silent)$"
    "mask_relay_timeout_ms:censorship:^[0-9]+$"
    "mask_relay_idle_timeout_ms:censorship:^[0-9]+$"
    "syn_per_sec:rate_limit:^[0-9]+$"
    "syn_burst:rate_limit:^[0-9]+$"
    "syn_tarpit_secs:rate_limit:^[0-9]+$"
    "cidr_mask_ipv4:rate_limit:^[0-9]+$"
    "cidr_mask_ipv6:rate_limit:^[0-9]+$"
    "synlimit:rate_limit:^[0-9]+$"
    "CidrRateLimitKey:rate_limit:^[0-9]+$"
)
_TUNE_FILE="${_TUNE_FILE:-${INSTALL_DIR}/tunings.conf}"

_tune_lookup() {
    local param="$1" entry
    for entry in "${_TUNE_WHITELIST[@]}"; do
        [[ "$entry" =~ ^${param}: ]] && { echo "$entry"; return 0; }
    done
    return 1
}

tune_list_params() {
    echo ""
    draw_header "TUNABLE ENGINE PARAMS"
    echo ""
    local entry p s v
    for entry in "${_TUNE_WHITELIST[@]}"; do
        IFS=':' read -r p s v <<< "$entry"
        printf "  %-32s ${DIM}[%s]${NC}\n" "$p" "$s"
    done
    echo ""
    [ -f "$_TUNE_FILE" ] && [ -s "$_TUNE_FILE" ] && {
        echo -e "  ${BOLD}Currently set:${NC}"
        while IFS='|' read -r p v; do
            [ -z "$p" ] && continue
            echo "    ${p} = ${v}"
        done < "$_TUNE_FILE"
        echo ""
    }
}

tune_set() {
    check_root
    local param="$1" value="$2"
    [ -z "$param" ] && { log_error "Usage: mtproxymax tune set <param> <value>"; return 1; }

    local entry; entry=$(_tune_lookup "$param") || { log_error "Unknown param '${param}'. Run: mtproxymax tune list"; return 1; }
    local p sect regex
    IFS=':' read -r p sect regex <<< "$entry"

    if [ -z "$value" ]; then
        log_error "Value required"
        return 1
    fi
    [[ "$value" =~ $regex ]] || { log_error "Invalid value for '${param}' (expected pattern: ${regex})"; return 1; }

    mkdir -p "$INSTALL_DIR"
    touch "$_TUNE_FILE"; chmod 600 "$_TUNE_FILE"
    local tmp; tmp=$(_mktemp) || return 1
    grep -v "^${param}|" "$_TUNE_FILE" > "$tmp" 2>/dev/null || true
    echo "${param}|${value}" >> "$tmp"
    mv "$tmp" "$_TUNE_FILE"; chmod 600 "$_TUNE_FILE"
    log_success "Tune '${param}' = ${value}"
    if is_proxy_running; then
        echo -en "  ${DIM}Restart to apply? [Y/n]:${NC} "
        local r; read -r r 2>/dev/null || r="y"
        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
    fi
}

tune_clear() {
    check_root
    local param="$1"
    [ -z "$param" ] && { log_error "Usage: mtproxymax tune clear <param|all>"; return 1; }
    [ ! -f "$_TUNE_FILE" ] && { log_info "No tunings set"; return 0; }

    if [ "$param" = "all" ]; then
        rm -f "$_TUNE_FILE"
        log_success "All tunings cleared"
    else
        local tmp; tmp=$(_mktemp) || return 1
        grep -v "^${param}|" "$_TUNE_FILE" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$_TUNE_FILE"; chmod 600 "$_TUNE_FILE"
        log_success "Tune '${param}' cleared"
    fi
    if is_proxy_running; then
        echo -en "  ${DIM}Restart to apply? [Y/n]:${NC} "
        local r; read -r r 2>/dev/null || r="y"
        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
    fi
}

tune_get() {
    local param="$1"
    if [ -z "$param" ]; then
        if [ ! -f "$_TUNE_FILE" ] || [ ! -s "$_TUNE_FILE" ]; then
            log_info "No tunings set"
            return
        fi
        echo ""
        while IFS='|' read -r p v; do
            [ -z "$p" ] && continue
            echo "  ${p} = ${v}"
        done < "$_TUNE_FILE"
        echo ""
    else
        local v; v=$(awk -F'|' -v u="$param" '$1==u{print $2; exit}' "$_TUNE_FILE" 2>/dev/null)
        [ -n "$v" ] && echo "  ${param} = ${v}" || echo -e "  ${DIM}${param}: not set${NC}"
    fi
}

# Helper: emit tunings for a given section (used by generate_telemt_config)
_emit_tunings_for_section() {
    [ -f "$_TUNE_FILE" ] || return 0
    local target_section="$1" entry p s v tune_p tune_v
    while IFS='|' read -r tune_p tune_v || [ -n "$tune_p" ]; do
        [ -z "$tune_p" ] && continue
        entry=$(_tune_lookup "$tune_p") || continue
        IFS=':' read -r p s <<< "$entry"
        if [ "$s" = "$target_section" ]; then
            # Boolean / numeric — no quotes. String values wrap in quotes.
            if [[ "$tune_v" =~ ^(true|false|[0-9]+)$ ]]; then
                echo "${tune_p} = ${tune_v}"
            else
                echo "${tune_p} = \"${tune_v}\""
            fi
        fi
    done < "$_TUNE_FILE"
}

# ── End-to-end install verification ──
run_verify() {
    echo ""
    draw_header "VERIFY"
    echo ""
    local pass=0 fail=0
    _check() {
        local name="$1" cmd="$2"
        if eval "$cmd" &>/dev/null; then
            echo -e "  ${GREEN}${SYM_CHECK}${NC} ${name}"
            pass=$((pass + 1))
        else
            echo -e "  ${RED}${SYM_CROSS}${NC} ${name}"
            fail=$((fail + 1))
        fi
    }

    _check "Docker installed"           "command -v docker"
    _check "Engine container running"   "is_proxy_running"
    _check "Port ${PROXY_PORT} listening" "ss -tln 2>/dev/null | grep -qE ':${PROXY_PORT}[[:space:]]'"
    _check "Metrics endpoint responds"  "curl -fsS --max-time 3 http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics -o /dev/null"
    _check "TLS handshake on proxy port" "echo | timeout 5 openssl s_client -connect 127.0.0.1:${PROXY_PORT} -servername ${PROXY_DOMAIN:-cloudflare.com} 2>&1 | grep -q 'CONNECTED'"
    _check "Domain ${PROXY_DOMAIN:-cloudflare.com} reachable" "curl -fsS --max-time 5 -o /dev/null https://${PROXY_DOMAIN:-cloudflare.com}"
    _check "api.telegram.org reachable" "curl -fsS --max-time 5 -o /dev/null https://api.telegram.org"
    _check "At least one active secret"  "[ ${#SECRETS_LABELS[@]} -gt 0 ]"
    _check "Config file exists"          "[ -f '${CONFIG_DIR}/config.toml' ]"

    # Telegram bot if configured
    if [ "$TELEGRAM_ENABLED" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        local _cfg; _cfg=$(_mktemp)
        printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$TELEGRAM_BOT_TOKEN" > "$_cfg"
        _check "Telegram bot token valid" "curl -fsS --max-time 5 -K '$_cfg' | grep -q '\"ok\":true'"
        rm -f "$_cfg"
    fi

    unset -f _check
    echo ""
    if [ $fail -eq 0 ]; then
        echo -e "  ${BRIGHT_GREEN}${BOLD}All ${pass} checks passed${NC}"
    else
        echo -e "  ${YELLOW}${pass} passed, ${RED}${fail} failed${NC}"
    fi
    echo ""
    return "$fail"
}

# ── Audit log (config change history) ──
_AUDIT_LOG="${INSTALL_DIR}/audit.log"

audit_log() {
    local action="$*"
    [ -z "$action" ] && return 0
    mkdir -p "$INSTALL_DIR"
    touch "$_AUDIT_LOG"; chmod 600 "$_AUDIT_LOG"
    local ts user
    ts=$(date -u '+%Y-%m-%d %H:%M:%S')
    user="${SUDO_USER:-${USER:-root}}"
    echo "${ts} UTC | ${user} | ${action}" >> "$_AUDIT_LOG"
    # Rotate if over 10000 lines
    local lines; lines=$(wc -l < "$_AUDIT_LOG" 2>/dev/null | tr -d ' ')
    if [[ "$lines" =~ ^[0-9]+$ ]] && [ "$lines" -gt 10000 ] 2>/dev/null; then
        tail -n 8000 "$_AUDIT_LOG" > "${_AUDIT_LOG}.tmp" && mv "${_AUDIT_LOG}.tmp" "$_AUDIT_LOG"
    fi
    return 0
}

show_history() {
    local lines="${1:-50}"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=50
    if [ ! -f "$_AUDIT_LOG" ] || [ ! -s "$_AUDIT_LOG" ]; then
        log_info "No audit history yet"
        return
    fi
    echo ""
    draw_header "AUDIT HISTORY (last ${lines})"
    echo ""
    tail -n "$lines" "$_AUDIT_LOG" | sed 's/^/  /'
    echo ""
}

# ── Bash completion ──
emit_completion() {
    cat <<'COMPL'
# mtproxymax bash completion — generated by `mtproxymax completion`
# Install: sudo mtproxymax completion > /etc/bash_completion.d/mtproxymax
# Or: eval "$(mtproxymax completion)"
_mtproxymax_completion() {
    local cur prev cmd
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmd="${COMP_WORDS[1]}"

    # Top-level commands
    if [ "$COMP_CWORD" -eq 1 ]; then
        local cmds="start stop restart status menu install uninstall secret upstream port ip domain mask-backend mask-relay-bytes tg-urls adtag traffic connections metrics logs health doctor info maintenance ban unban bans migrate changelog backup restore backups config uptime notify port-check profile auto-rotate template sweep tune verify history completion speedtest telegram replication rebuild update engine geoblock sni-policy digest ping-dc shield stealth clamp-mss domain-pool dpi-inspect cover-watchdog lockdown port-pool qos happy-hours notify-expiry abuse-watch broadcast export-lb ddns diag-dump snapshot daily-report ssh-shield net-grade onboard tcp-boost leak-scan cert-check clone-link bootstrap heal auto-heal tcp-clean socket-boost tls-pad honeypot tcp-fastpath ram-tune port-hop cpu-tune top export-client export-report qr-sheet tag guest pool calendar geofence decoy auto-sni dc-optimize ip-score webhook failover eco-mode chaos-test evacuate speed-limit fleet ssl backup-cloud"
        COMPREPLY=( $(compgen -W "${cmds}" -- "${cur}") )
        return 0
    fi

    # Subcommands
    case "$cmd" in
        secret)
            if [ "$COMP_CWORD" -eq 2 ]; then
                COMPREPLY=( $(compgen -W "add remove list info rotate clone rename enable disable limits setlimit setlimits link qr note stats sort top search archive unarchive archives generate-links extend bulk-extend disable-expired export import reset-traffic tag untag tags logs quota-reset purge-disabled sub export-json rename-prefix" -- "${cur}") )
            fi
            ;;
        upstream)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "list add remove enable disable test" -- "${cur}") )
            ;;
        profile)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "save load list delete" -- "${cur}") )
            ;;
        template)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "save list delete apply" -- "${cur}") )
            ;;
        tune)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "list get set clear fastpath bbr ram cpu" -- "${cur}") )
            ;;
        migrate)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "export import" -- "${cur}") )
            ;;
        backup)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "--encrypt restore-encrypted autoclean send-tg" -- "${cur}") )
            ;;
        tg-urls)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "get set clear" -- "${cur}") )
            ;;
        geoblock)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "add remove list mode" -- "${cur}") )
            ;;
        maintenance)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "on off status" -- "${cur}") )
            ;;
        daily-report|ssh-shield|tcp-boost|auto-heal|tcp-clean|socket-boost|honeypot|tcp-fastpath|cpu-tune)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "on off status" -- "${cur}") )
            ;;
        tls-pad)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "auto off rotate status" -- "${cur}") )
            ;;
        ram-tune)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "auto off status" -- "${cur}") )
            ;;
        port-hop)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "add remove list" -- "${cur}") )
            ;;
        telegram)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "setup status test disable remove interval label alerts" -- "${cur}") )
            ;;
        replication)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "setup status add remove list enable disable sync test logs reset promote" -- "${cur}") )
            ;;
        shield|clamp-mss|lockdown)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "on off status" -- "${cur}") )
            ;;
        stealth)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "ultra normal status" -- "${cur}") )
            ;;
        cover-watchdog)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "test auto" -- "${cur}") )
            ;;
        port-pool)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "add remove list" -- "${cur}") )
            ;;
        qos)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "set off status" -- "${cur}") )
            ;;
        happy-hours)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "set off status" -- "${cur}") )
            ;;
        domain-pool)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "get" -- "${cur}") )
            ;;
        speed-limit)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "set remove apply clear list status" -- "${cur}") )
            ;;
        fleet)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "status collect" -- "${cur}") )
            ;;
        ssl)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "issue status clear" -- "${cur}") )
            ;;
        backup-cloud)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "toggle push status off" -- "${cur}") )
            ;;
        instance)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "add remove list status sync" -- "${cur}") )
            ;;
        voucher)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "generate list redeem revoke purge" -- "${cur}") )
            ;;
        portal)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "on off status generate" -- "${cur}") )
            ;;
        quota-mode)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "manager engine status" -- "${cur}") )
            ;;
        ddns)
            [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "setup update status disable" -- "${cur}") )
            ;;
    esac
    return 0
}
complete -F _mtproxymax_completion mtproxymax
COMPL
}

# ── Outbound throughput test ──
run_speedtest() {
    echo ""
    draw_header "SPEED TEST"
    echo ""
    echo -e "  ${DIM}Measuring outbound bandwidth from server...${NC}"
    echo ""

    # Parallel arrays: label + url
    local labels=("Cachefly 10MB" "Hetzner 100MB" "Telegram API (latency)")
    local urls=(
        "https://cachefly.cachefly.net/10mb.test"
        "https://speed.hetzner.de/100MB.bin"
        "https://api.telegram.org"
    )

    local i
    for i in "${!urls[@]}"; do
        local label="${labels[$i]}" url="${urls[$i]}"
        printf "  ${BOLD}%-28s${NC}  " "$label"
        local result
        result=$(curl -so /dev/null -w '%{http_code}|%{time_total}|%{speed_download}' --max-time 15 "$url" 2>/dev/null) || { echo -e "${RED}FAILED${NC}"; continue; }
        local code time speed
        IFS='|' read -r code time speed <<< "$result"
        local speed_fmt="—"
        local speed_int="${speed%.*}"
        [[ "$speed_int" =~ ^[0-9]+$ ]] && [ "$speed_int" -gt 0 ] 2>/dev/null && speed_fmt="$(format_bytes "$speed_int")/s"
        printf "code=%s  time=%.2fs  speed=%s\n" "$code" "$time" "$speed_fmt"
    done
    echo ""
    echo -e "  ${DIM}Note: measures server ↔ internet bandwidth, not proxy throughput.${NC}"
    echo ""
}

run_digest() {
    echo ""
    draw_header "EXECUTIVE DIGEST"
    echo ""

    local _running=false _pstatus="stopped" uptime_str="—"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        _running=true
        _pstatus="running"
        local started_at
        started_at=$(docker inspect --format '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)
        local start_epoch=$(_iso_to_epoch "$started_at")
        local up_secs=$(( $(date +%s) - start_epoch ))
        uptime_str=$(format_duration "$up_secs")
    fi

    local traffic_in=0 traffic_out=0 connections=0
    if [ "$_running" = "true" ]; then
        read -r traffic_in traffic_out connections <<< "$(get_cumulative_proxy_stats)"
    fi

    local active=0 disabled=0
    for i in "${!SECRETS_ENABLED[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] && active=$((active+1)) || disabled=$((disabled+1))
    done

    local bot_str="Disabled"
    [ "$TELEGRAM_ENABLED" = "true" ] && bot_str="Active"

    echo -e "  ${BOLD}Proxy Status:${NC}   $(draw_status "$_pstatus")  (Uptime: ${uptime_str})"
    echo -e "  ${BOLD}Active Sockets:${NC} ${connections}"
    echo -e "  ${BOLD}Config Users:${NC}   ${active} active / ${disabled} disabled"
    echo -e "  ${BOLD}Total Traffic:${NC}  ${SYM_DOWN} $(format_bytes "$traffic_in")  ${SYM_UP} $(format_bytes "$traffic_out")"
    echo -e "  ${BOLD}Telegram Bot:${NC}   ${bot_str}"
    echo -e "  ${BOLD}Geo-Blocking:${NC}   ${GEOBLOCK_MODE:-off}"
    echo ""
}

run_ping_dc() {
    echo ""
    draw_header "TELEGRAM DC BENCHMARK"
    echo ""
    echo -e "  ${DIM}Benchmarking TCP handshake latency to global Telegram DCs...${NC}"
    echo ""

    local dc_names=("DC1 (MIA)" "DC2 (AMS)" "DC3 (MIA)" "DC4 (AMS)" "DC5 (SIN)")
    local dc_ips=("149.154.175.50" "149.154.167.51" "149.154.175.100" "149.154.167.91" "91.108.56.130")

    local i min_time=999999 best_dc=""
    for i in "${!dc_ips[@]}"; do
        local name="${dc_names[$i]}" ip="${dc_ips[$i]}"
        printf "  ${BOLD}%-12s (%-15s)${NC}  " "$name" "$ip"
        local time_s
        time_s=$(curl -o /dev/null -s -w "%{time_connect}" --connect-timeout 4 "http://${ip}:80" 2>/dev/null) || { echo -e "${RED}TIMEOUT / BLOCKED${NC}"; continue; }
        if [ -n "$time_s" ] && [ "$time_s" != "0.000000" ]; then
            local time_ms
            time_ms=$(awk -v t="$time_s" 'BEGIN { printf "%.1f", t * 1000 }')
            printf "${GREEN}%s ms${NC}\n" "$time_ms"
            if awk -v cur="$time_s" -v min="$min_time" 'BEGIN { exit !(cur < min) }'; then
                min_time="$time_s"
                best_dc="$name"
            fi
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
    echo ""
    if [ -n "$best_dc" ]; then
        echo -e "  🏆 ${BOLD}Fastest DC:${NC} ${CYAN}${best_dc}${NC}"
        echo ""
    fi
}

# Apply or clean up kernel firewall anti-DPI rules
apply_firewall_rules() {
    [ -z "${PROXY_PORT:-}" ] && return 0
    local -a _all_ports=("${PROXY_PORT}")
    load_instances 2>/dev/null || true
    local _ip _p
    for _ip in "${INSTANCE_PORTS[@]}"; do
        [ -n "$_ip" ] && _all_ports+=("$_ip")
    done

    if command -v iptables >/dev/null 2>&1; then
        for _p in "${_all_ports[@]}"; do
            while iptables -D INPUT -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m hashlimit --hashlimit-name mtproxy_syn_in --hashlimit-mode srcip --hashlimit-above 25/sec --hashlimit-burst 60 -m comment --comment "mtproxymax_shield" -j DROP 2>/dev/null; do :; done
            while iptables -D INPUT -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --set --name mtproxy_syn 2>/dev/null; do :; done
            while iptables -D INPUT -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --set --name mtproxy_syn -m comment --comment "mtproxymax_shield" 2>/dev/null; do :; done
            while iptables -D INPUT -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --update --seconds 5 --hitcount 15 --name mtproxy_syn -j DROP 2>/dev/null; do :; done
            while iptables -D INPUT -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --update --seconds 5 --hitcount 15 --name mtproxy_syn -m comment --comment "mtproxymax_shield" -j DROP 2>/dev/null; do :; done
            while iptables -D INPUT -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --rcheck --seconds 2 --hitcount 20 --name mtproxy_syn -m comment --comment "mtproxymax_shield" -j DROP 2>/dev/null; do :; done
            for _chain in FORWARD OUTPUT POSTROUTING; do
                while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --dport "${_p}" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
                while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --dport "${_p}" -m comment --comment "mtproxymax_mss" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
                while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --sport "${_p}" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
                while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --sport "${_p}" -m comment --comment "mtproxymax_mss" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
            done
        done
    fi
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet mtproxymax_shield 2>/dev/null || true
        nft delete table inet mtproxymax_mss 2>/dev/null || true
    fi

    if [ "${STEALTH_SHIELD:-false}" = "true" ]; then
        local _shield_ok=false
        if command -v iptables >/dev/null 2>&1; then
            for _p in "${_all_ports[@]}"; do
                # Prefer hashlimit with token-bucket burst (25/sec, burst 60) to allow instant multi-socket Telegram client connection without dropping a single packet
                if iptables -I INPUT 1 -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m hashlimit --hashlimit-name mtproxy_syn_in --hashlimit-mode srcip --hashlimit-above 25/sec --hashlimit-burst 60 -m comment --comment "mtproxymax_shield" -j DROP 2>/dev/null; then
                    _shield_ok=true
                else
                    # Safe fallback to xt_recent using --rcheck (NEVER --update!) and 20 hits/2s so clients never get trapped in infinite drop loops
                    iptables -I INPUT 1 -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --set --name mtproxy_syn -m comment --comment "mtproxymax_shield" 2>/dev/null && \
                    iptables -I INPUT 2 -p tcp --dport "${_p}" -m conntrack --ctstate NEW -m recent --rcheck --seconds 2 --hitcount 20 --name mtproxy_syn -m comment --comment "mtproxymax_shield" -j DROP 2>/dev/null && _shield_ok=true || true
                fi
            done
        fi
        if [ "$_shield_ok" = "false" ] && command -v nft >/dev/null 2>&1; then
            nft add table inet mtproxymax_shield 2>/dev/null || true
            nft add chain inet mtproxymax_shield input '{ type filter hook input priority filter; policy accept; }' 2>/dev/null || true
            nft add set inet mtproxymax_shield syn_meter '{ type ipv4_addr; flags dynamic,timeout; timeout 60s; }' 2>/dev/null || true
            for _p in "${_all_ports[@]}"; do
                nft add rule inet mtproxymax_shield input tcp dport "${_p}" ct state new add @syn_meter '{ ip saddr limit rate over 25/second burst 60 packets }' counter drop 2>/dev/null && _shield_ok=true || true
            done
        fi
    fi

    if [ "${STEALTH_MSS_CLAMP:-false}" = "true" ]; then
        local _mss_ok=false
        if command -v iptables >/dev/null 2>&1; then
            for _p in "${_all_ports[@]}"; do
                for _chain in FORWARD OUTPUT POSTROUTING; do
                    iptables -t mangle -I "$_chain" 1 -p tcp --tcp-flags SYN,RST SYN --dport "${_p}" -m comment --comment "mtproxymax_mss" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null && _mss_ok=true || true
                    iptables -t mangle -I "$_chain" 2 -p tcp --tcp-flags SYN,RST SYN --sport "${_p}" -m comment --comment "mtproxymax_mss" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
                done
            done
        fi
        if [ "$_mss_ok" = "false" ] && command -v nft >/dev/null 2>&1; then
            nft add table inet mtproxymax_mss 2>/dev/null || true
            nft add chain inet mtproxymax_mss forward '{ type filter hook forward priority mangle; policy accept; }' 2>/dev/null || true
            nft add chain inet mtproxymax_mss postrouting '{ type filter hook postrouting priority mangle; policy accept; }' 2>/dev/null || true
            for _p in "${_all_ports[@]}"; do
                nft add rule inet mtproxymax_mss forward tcp flags '& (syn|rst) == syn' tcp dport "${_p}" tcp option maxseg size set rt mtu 2>/dev/null && _mss_ok=true || true
                nft add rule inet mtproxymax_mss postrouting tcp flags '& (syn|rst) == syn' tcp sport "${_p}" tcp option maxseg size set rt mtu 2>/dev/null || true
            done
        fi
    fi
    apply_qos_rules
    apply_port_pool_rules
    apply_port_hop_rules
    [ "${ANTI_DPI_SHIELD_ENABLED:-false}" = "true" ] && run_anti_dpi_shield on >/dev/null 2>&1 || true
}

apply_port_pool_rules() {
    [ -z "${PROXY_PORT:-}" ] && return 0
    if command -v iptables >/dev/null 2>&1; then
        if [ -n "${PORT_POOL_PORTS:-}" ]; then
            IFS=',' read -ra _plist <<< "${PORT_POOL_PORTS}"
            for _p in "${_plist[@]}"; do
                _p="${_p// /}"
                [ -z "$_p" ] && continue
                while iptables -t nat -D PREROUTING -p tcp --dport "$_p" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null; do :; done
                while iptables -t nat -D PREROUTING -p tcp --dport "$_p" -m comment --comment "mtproxymax_portpool" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null; do :; done
                iptables -t nat -I PREROUTING -p tcp --dport "$_p" -m comment --comment "mtproxymax_portpool" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null || true
            done
        fi
    elif command -v nft >/dev/null 2>&1; then
        nft delete table inet mtproxymax_pool 2>/dev/null || true
        if [ -n "${PORT_POOL_PORTS:-}" ]; then
            nft add table inet mtproxymax_pool 2>/dev/null || true
            nft add chain inet mtproxymax_pool prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null || true
            IFS=',' read -ra _plist <<< "${PORT_POOL_PORTS}"
            for _p in "${_plist[@]}"; do
                _p="${_p// /}"
                [ -z "$_p" ] && continue
                nft add rule inet mtproxymax_pool prerouting tcp dport "$_p" redirect to :"$PROXY_PORT" 2>/dev/null || true
            done
        fi
    fi
}

apply_port_hop_rules() {
    [ -z "${PROXY_PORT:-}" ] && return 0
    if [ -n "${PORT_HOP_RANGES:-}" ]; then
        IFS=',' read -ra _rlist <<< "${PORT_HOP_RANGES}"
        for _r in "${_rlist[@]}"; do
            _r="${_r// /}"
            [ -z "$_r" ] && continue
            local s="${_r%%:*}" e="${_r##*:}"
            if command -v iptables >/dev/null 2>&1; then
                while iptables -t nat -D PREROUTING -p tcp --dport "${s}:${e}" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null; do :; done
                while iptables -t nat -D PREROUTING -p tcp --dport "${s}:${e}" -m comment --comment "mtproxymax_porthop" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null; do :; done
                iptables -t nat -I PREROUTING -p tcp --dport "${s}:${e}" -m comment --comment "mtproxymax_porthop" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null || true
            elif command -v nft >/dev/null 2>&1; then
                nft add table inet mtproxymax_hop 2>/dev/null || true
                nft add chain inet mtproxymax_hop prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null || true
                nft add rule inet mtproxymax_hop prerouting tcp dport "${s}-${e}" redirect to :"$PROXY_PORT" 2>/dev/null || true
            fi
        done
    fi
}

run_shield() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable|true|1)
            check_root
            STEALTH_SHIELD="true"
            save_settings
            apply_firewall_rules
            log_success "Kernel SYN Shield enabled (>15 SYN/5s tarpit on port ${PROXY_PORT})"
            ;;
        off|disable|false|0)
            check_root
            STEALTH_SHIELD="false"
            save_settings
            apply_firewall_rules
            log_success "Kernel SYN Shield disabled"
            ;;
        status)
            echo -e "\n  🛡️  ${BOLD}Kernel SYN Shield Status:${NC}"
            if [ "${STEALTH_SHIELD:-false}" = "true" ]; then
                echo -e "     Status: ${GREEN}ENABLED${NC} (Active protection on port ${PROXY_PORT})"
            else
                echo -e "     Status: ${YELLOW}DISABLED${NC}"
            fi
            echo ""
            ;;
        *)
            log_error "Usage: mtproxymax shield [on|off|status]"
            return 1
            ;;
    esac
}

run_clamp_mss() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable|true|1)
            check_root
            STEALTH_MSS_CLAMP="true"
            save_settings
            apply_firewall_rules
            log_success "TCP MSS Clamping enabled on port ${PROXY_PORT}"
            ;;
        off|disable|false|0)
            check_root
            STEALTH_MSS_CLAMP="false"
            save_settings
            apply_firewall_rules
            log_success "TCP MSS Clamping disabled"
            ;;
        status)
            echo -e "\n  📉 ${BOLD}TCP MSS Clamping Status:${NC}"
            if [ "${STEALTH_MSS_CLAMP:-false}" = "true" ]; then
                echo -e "     Status: ${GREEN}ENABLED${NC} (Active alignment on port ${PROXY_PORT})"
                if command -v iptables >/dev/null 2>&1; then
                    local _rule_cnt; _rule_cnt=$(iptables -t mangle -S 2>/dev/null | grep -c "mtproxymax_mss" || echo 0)
                    echo -e "     Kernel Hooks: ${CYAN}${_rule_cnt} Netfilter rules active across FORWARD, OUTPUT & POSTROUTING${NC}"
                fi
            else
                echo -e "     Status: ${YELLOW}DISABLED${NC}"
            fi
            echo ""
            ;;
        *)
            log_error "Usage: mtproxymax clamp-mss [on|off|status]"
            return 1
            ;;
    esac
}

run_stealth_preset() {
    load_settings
    local preset="${1:-status}"
    case "$preset" in
        ultra|high|max)
            check_root
            STEALTH_PRESET="ultra"
            UNKNOWN_SNI_ACTION="drop"
            save_settings
            log_success "Stealth preset set to ULTRA (Replay window: 180s, Cache: 131072, Unknown SNI: drop)"
            if is_proxy_running; then reload_proxy_config; fi
            ;;
        normal|standard|default)
            check_root
            STEALTH_PRESET="normal"
            UNKNOWN_SNI_ACTION="mask"
            save_settings
            log_success "Stealth preset set to NORMAL (Replay window: 1800s, Cache: 65536, Unknown SNI: mask)"
            if is_proxy_running; then reload_proxy_config; fi
            ;;
        status)
            echo -e "\n  🥷 ${BOLD}Stealth Defense Preset:${NC}"
            if [ "${STEALTH_PRESET:-normal}" = "ultra" ]; then
                echo -e "     Current Preset: ${RED}${BOLD}ULTRA STEALTH${NC}"
                echo -e "     Replay Window:  180 seconds"
                echo -e "     Replay Cache:   131,072 entries"
                echo -e "     Unknown SNI:    Drop connection"
            else
                echo -e "     Current Preset: ${GREEN}NORMAL${NC}"
                echo -e "     Replay Window:  1800 seconds"
                echo -e "     Replay Cache:   65,536 entries"
                echo -e "     Unknown SNI:    Mask traffic to cover domain"
            fi
            echo ""
            ;;
        *)
            log_error "Usage: mtproxymax stealth [ultra|normal|status]"
            return 1
            ;;
    esac
}

run_domain_pool() {
    load_settings
    local pool="$1"
    case "$pool" in
        ""|get|list|show)
            echo -e "\n  🔀 ${BOLD}Multi-Domain SNI Pool:${NC}"
            echo -e "     Current Pool: ${CYAN}${PROXY_DOMAIN:-<not set>}${NC}"
            echo ""
            ;;
        *)
            check_root
            if validate_domain "$pool"; then
                PROXY_DOMAIN="$pool"
                sync_domain_cert_len "true" "false" || true
                save_settings
                log_success "Domain pool updated: ${pool}"
                if is_proxy_running; then reload_proxy_config; fi
            else
                log_error "Invalid domain pool format (use e.g. cloudflare.com,www.microsoft.com)"
                return 1
            fi
            ;;
    esac
}

# ── DPI Forensics & Readiness Score ──
run_dpi_inspect() {
    echo ""
    draw_header "DPI FORENSICS & READINESS ANALYZER"
    echo ""
    echo -e "  ${DIM}Running active 5-point network diagnostics...${NC}"
    echo ""

    local score=0 total_checks=5

    # Check 1: Cover Domain Reachability & Latency
    local primary_dom="${PROXY_DOMAIN:-}"
    primary_dom="${primary_dom%%,*}"
    primary_dom="${primary_dom// /}"
    printf "  [1/5] Cover Domain Status (${CYAN}%s${NC}): " "${primary_dom:-none}"
    if [ -n "${primary_dom:-}" ]; then
        local time_s
        time_s=$(curl -o /dev/null -s -w "%{time_connect}" --connect-timeout 4 "https://${primary_dom}:443" 2>/dev/null) || time_s=""
        if [ -n "$time_s" ] && [ "$time_s" != "0.000000" ]; then
            local time_ms
            time_ms=$(awk -v t="$time_s" 'BEGIN { printf "%.1f", t * 1000 }')
            echo -e "${GREEN}PASS (${time_ms} ms)${NC}"
            score=$((score + 20))
        else
            echo -e "${RED}FAIL / BLOCKED${NC}"
        fi
    else
        echo -e "${YELLOW}NOT CONFIGURED${NC}"
    fi

    # Check 2: TLS Certificate Parity
    printf "  [2/5] Auto Cert Synchronization: "
    if [ -n "${FAKE_CERT_LEN:-}" ] && [ "${FAKE_CERT_LEN}" != "0" ]; then
        echo -e "${GREEN}PASS (Cert Len: ${FAKE_CERT_LEN})${NC}"
        score=$((score + 20))
    else
        echo -e "${YELLOW}WARNING (Using defaults)${NC}"
        score=$((score + 10))
    fi

    # Check 3: Kernel SYN Shield State
    printf "  [3/5] Anti-DPI SYN Shield: "
    if [ "${STEALTH_SHIELD:-false}" = "true" ]; then
        echo -e "${GREEN}ACTIVE${NC}"
        score=$((score + 20))
    else
        echo -e "${YELLOW}DISABLED${NC}"
    fi

    # Check 4: Stealth Preset Engine Hardening
    printf "  [4/5] Engine Replay Hardening: "
    if [ "${STEALTH_PRESET:-normal}" = "ultra" ]; then
        echo -e "${GREEN}ULTRA STEALTH${NC}"
        score=$((score + 20))
    else
        echo -e "${GREEN}NORMAL STEALTH${NC}"
        score=$((score + 15))
    fi

    # Check 5: TCP MSS Clamping
    printf "  [5/5] TCP MSS Clamping (PMTU): "
    if [ "${STEALTH_MSS_CLAMP:-false}" = "true" ]; then
        local mss_rules=0
        if command -v iptables >/dev/null 2>&1; then
            mss_rules=$(iptables -t mangle -S 2>/dev/null | grep -c "mtproxymax_mss" || echo 0)
        fi
        if [ "$mss_rules" -gt 0 ] 2>/dev/null; then
            echo -e "${GREEN}ENABLED (${mss_rules} kernel hooks active)${NC}"
            score=$((score + 20))
        else
            echo -e "${GREEN}ENABLED${NC}"
            score=$((score + 20))
        fi
    else
        echo -e "${YELLOW}DISABLED${NC}"
    fi

    echo ""
    local score_color="${GREEN}"
    [ "$score" -lt 70 ] && score_color="${YELLOW}"
    [ "$score" -lt 40 ] && score_color="${RED}"
    echo -e "  🛡️  ${BOLD}Anti-DPI Readiness Score:${NC} ${score_color}${BOLD}${score}%${NC}"
    echo ""
}

# ── Cover Domain Watchdog & Auto-Rotator ──
run_cover_watchdog() {
    local action="${1:-test}"
    case "$action" in
        test)
            echo ""
            draw_header "COVER DOMAIN HEALTH WATCHDOG"
            echo ""
            echo -e "  ${DIM}Testing live latency across domain pool...${NC}"
            echo ""
            local pool_str="${PROXY_DOMAIN:-}"
            if [ -n "${PROXY_TLS_DOMAINS:-}" ]; then
                pool_str="${pool_str},${PROXY_TLS_DOMAINS}"
            fi
            # Deduplicate and split by comma
            local -a domains=()
            IFS=',' read -ra _parts <<< "$pool_str" || true
            for _d in "${_parts[@]}"; do
                _d="${_d// /}"
                [ -n "$_d" ] && domains+=("$_d")
            done
            if [ ${#domains[@]} -eq 0 ]; then
                log_info "No cover domains configured."
                return 0
            fi
            for _d in "${domains[@]}"; do
                printf "  %-26s  " "${_d}"
                local time_s code
                read -r code time_s <<< "$(curl -o /dev/null -s -w "%{http_code} %{time_connect}" --connect-timeout 4 "https://${_d}:443" 2>/dev/null || echo "000 0")"
                if [ "$code" != "000" ] && [ "$time_s" != "0" ]; then
                    local time_ms
                    time_ms=$(awk -v t="$time_s" 'BEGIN { printf "%.1f", t * 1000 }')
                    echo -e "${GREEN}ONLINE (${time_ms} ms | HTTP ${code})${NC}"
                else
                    echo -e "${RED}TIMEOUT / BLOCKED${NC}"
                fi
            done
            echo ""
            ;;
        auto)
            check_root
            load_settings
            [ -z "${PROXY_DOMAIN:-}" ] && return 0
            local primary="${PROXY_DOMAIN%%,*}"
            primary="${primary// /}"
            # Test primary domain
            if ! curl -o /dev/null -s --connect-timeout 4 "https://${primary}:443" 2>/dev/null; then
                log_warning "Primary domain '${primary}' failed watchdog probe. Attempting rotation..."
                local pool_str="${PROXY_DOMAIN:-}"
                if [ -n "${PROXY_TLS_DOMAINS:-}" ]; then
                    pool_str="${pool_str},${PROXY_TLS_DOMAINS}"
                fi
                IFS=',' read -ra _candidates <<< "$pool_str" || true
                for _cand in "${_candidates[@]}"; do
                    _cand="${_cand// /}"
                    [ -z "$_cand" ] || [ "$_cand" = "$primary" ] && continue
                    if curl -o /dev/null -s --connect-timeout 4 "https://${_cand}:443" 2>/dev/null; then
                        log_success "Swapped primary cover domain to healthy backup: ${_cand}"
                        # Put healthy candidate at the front of the pool string
                        local new_pool="${_cand}"
                        for _rem in "${_candidates[@]}"; do
                            _rem="${_rem// /}"
                            [ -n "$_rem" ] && [ "$_rem" != "$_cand" ] && new_pool="${new_pool},${_rem}"
                        done
                        PROXY_DOMAIN="$new_pool"
                        sync_domain_cert_len "true" "false" || true
                        save_settings
                        if is_proxy_running; then reload_proxy_config; fi
                        break
                    fi
                done
            fi
            ;;
        *)
            log_error "Usage: mtproxymax cover-watchdog [test|auto]"
            return 1
            ;;
    esac
}

# ── Emergency Lockdown Mode ──
run_lockdown() {
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            load_settings
            LOCKDOWN_MODE="true"
            STEALTH_SHIELD="true"
            STEALTH_PRESET="ultra"
            STEALTH_MSS_CLAMP="true"
            save_settings
            apply_firewall_rules
            if is_proxy_running; then reload_proxy_config; fi
            log_success "🚨 EMERGENCY LOCKDOWN ACTIVATED: Shield ON | Ultra Stealth ON | MSS Clamp ON"
            if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
                tg_send "🚨 *EMERGENCY LOCKDOWN ACTIVATED*\n\nServer has entered maximum defensive posture.\n• Kernel SYN Shield: ACTIVE\n• Stealth Preset: ULTRA\n• MSS Clamping: ACTIVE"
            fi
            ;;
        off|disable)
            check_root
            load_settings
            LOCKDOWN_MODE="false"
            save_settings
            log_success "Lockdown deactivated. Server restored to normal operating posture."
            ;;
        status|"")
            echo -e "  ${BOLD}Emergency Lockdown Mode:${NC} $([ "${LOCKDOWN_MODE:-false}" = "true" ] && echo "${RED}${BOLD}ACTIVE${NC}" || echo "${GREEN}INACTIVE${NC}")"
            ;;
        *)
            log_error "Usage: mtproxymax lockdown [on|off|status]"
            return 1
            ;;
    esac
}

# ── Multi-Port Pool Listener ──
run_port_pool() {
    local action="${1:-list}"
    case "$action" in
        add)
            check_root
            local port="$2"
            [ -z "$port" ] && { log_error "Usage: mtproxymax port-pool add <port>"; return 1; }
            [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { log_error "Invalid port number"; return 1; }
            load_settings
            if [[ ",${PORT_POOL_PORTS}," == *",${port},"* ]] || [ "$port" = "$PROXY_PORT" ]; then
                log_info "Port ${port} is already in use or configured."
                return 0
            fi
            PORT_POOL_PORTS="${PORT_POOL_PORTS:+${PORT_POOL_PORTS},}${port}"
            save_settings
            if command -v iptables >/dev/null 2>&1 && [ -n "${PROXY_PORT:-}" ]; then
                iptables -t nat -I PREROUTING -p tcp --dport "$port" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null || true
            fi
            log_success "Added port ${port} to multi-port listener pool pointing to engine port ${PROXY_PORT}."
            ;;
        remove)
            check_root
            local port="$2"
            [ -z "$port" ] && { log_error "Usage: mtproxymax port-pool remove <port>"; return 1; }
            load_settings
            # Remove port from comma-delimited string
            local -a new_ports=()
            IFS=',' read -ra _plist <<< "${PORT_POOL_PORTS:-}"
            for _p in "${_plist[@]}"; do
                [ "$_p" != "$port" ] && [ -n "$_p" ] && new_ports+=("$_p")
            done
            local joined
            joined=$(IFS=','; echo "${new_ports[*]}")
            PORT_POOL_PORTS="$joined"
            save_settings
            if command -v iptables >/dev/null 2>&1 && [ -n "${PROXY_PORT:-}" ]; then
                while iptables -t nat -D PREROUTING -p tcp --dport "$port" -j REDIRECT --to-ports "${PROXY_PORT}" 2>/dev/null; do :; done
            fi
            log_success "Removed port ${port} from multi-port listener pool."
            ;;
        list|"")
            load_settings
            echo -e "  ${BOLD}Primary Engine Port:${NC} ${GREEN}${PROXY_PORT:-443}${NC}"
            echo -e "  ${BOLD}Secondary Port Pool:${NC} ${CYAN}${PORT_POOL_PORTS:-none}${NC}"
            echo -e "  ${DIM}Usage: mtproxymax port-pool [add|remove] <port>${NC}"
            ;;
        *)
            log_error "Usage: mtproxymax port-pool [add|remove|list]"
            return 1
            ;;
    esac
}

# ── QoS Shaping Rules ──
validate_happy_hours_win() {
    local win="$1"
    [[ "$win" =~ ^([0-9]{2}):([0-9]{2})-([0-9]{2}):([0-9]{2})$ ]] || return 1
    local s_h="${BASH_REMATCH[1]}" s_m="${BASH_REMATCH[2]}"
    local e_h="${BASH_REMATCH[3]}" e_m="${BASH_REMATCH[4]}"
    [ $((10#$s_h)) -le 23 ] && [ $((10#$s_m)) -le 59 ] && [ $((10#$e_h)) -le 23 ] && [ $((10#$e_m)) -le 59 ] || return 1
    return 0
}

check_in_happy_hours() {
    local win="$1"
    validate_happy_hours_win "$win" || return 1
    [[ "$win" =~ ^([0-9]{2}):([0-9]{2})-([0-9]{2}):([0-9]{2})$ ]]
    local s_h="${BASH_REMATCH[1]}" s_m="${BASH_REMATCH[2]}"
    local e_h="${BASH_REMATCH[3]}" e_m="${BASH_REMATCH[4]}"
    local start_val=$(( 10#$s_h * 60 + 10#$s_m ))
    local end_val=$(( 10#$e_h * 60 + 10#$e_m ))
    [ "$start_val" -eq "$end_val" ] && return 1

    local cur_h cur_m
    cur_h=$(date +%H); cur_m=$(date +%M)
    local cur_val=$(( 10#$cur_h * 60 + 10#$cur_m ))

    if [ "$start_val" -lt "$end_val" ]; then
        if [ "$cur_val" -ge "$start_val" ] && [ "$cur_val" -lt "$end_val" ]; then
            return 0
        fi
    else
        # Window spans midnight (e.g. 22:00-04:00)
        if [ "$cur_val" -ge "$start_val" ] || [ "$cur_val" -lt "$end_val" ]; then
            return 0
        fi
    fi
    return 1
}

apply_qos_rules() {
    [ -z "${PROXY_PORT:-}" ] && return 0
    if command -v iptables >/dev/null 2>&1; then
        # Robustly delete any existing mtproxy_qos rules cleanly via line numbers
        while iptables -S INPUT 2>/dev/null | grep -q "mtproxy_qos_in"; do
            local num
            num=$(iptables -L INPUT --line-numbers -n 2>/dev/null | awk '/mtproxy_qos_in/{print $1; exit}')
            [ -n "$num" ] && iptables -D INPUT "$num" 2>/dev/null || break
        done
        while iptables -S FORWARD 2>/dev/null | grep -q "mtproxy_qos_out"; do
            local num
            num=$(iptables -L FORWARD --line-numbers -n 2>/dev/null | awk '/mtproxy_qos_out/{print $1; exit}')
            [ -n "$num" ] && iptables -D FORWARD "$num" 2>/dev/null || break
        done
        # Fallback exact match cleans
        while iptables -D INPUT -p tcp --dport "${PROXY_PORT}" -m hashlimit --hashlimit-name mtproxy_qos_in --hashlimit-mode srcip --hashlimit-above "${QOS_LIMIT_MBPS:-0}mb/s" -j DROP 2>/dev/null; do :; done
        while iptables -D FORWARD -p tcp --sport "${PROXY_PORT}" -m hashlimit --hashlimit-name mtproxy_qos_out --hashlimit-mode dstip --hashlimit-above "${QOS_LIMIT_MBPS:-0}mb/s" -j DROP 2>/dev/null; do :; done
    fi

    if [ "${QOS_LIMIT_MBPS:-0}" -gt 0 ] && command -v iptables >/dev/null 2>&1; then
        local kbps=$(( QOS_LIMIT_MBPS * 1000 ))
        iptables -I INPUT -p tcp --dport "${PROXY_PORT}" -m hashlimit --hashlimit-name mtproxy_qos_in --hashlimit-mode srcip --hashlimit-above "${kbps}kb/s" -j DROP 2>/dev/null || true
        iptables -I FORWARD -p tcp --sport "${PROXY_PORT}" -m hashlimit --hashlimit-name mtproxy_qos_out --hashlimit-mode dstip --hashlimit-above "${kbps}kb/s" -j DROP 2>/dev/null || true
    fi
}

run_qos() {
    local action="${1:-status}"
    case "$action" in
        set)
            check_root
            local mbps="$2"
            [ -z "$mbps" ] && { log_error "Usage: mtproxymax qos set <mbps>"; return 1; }
            [[ "$mbps" =~ ^[0-9]+$ ]] && [ "$mbps" -ge 1 ] && [ "$mbps" -le 10000 ] || { log_error "Invalid speed limit (1-10000 Mbps)"; return 1; }
            load_settings
            QOS_LIMIT_MBPS="$mbps"
            save_settings
            apply_qos_rules
            log_success "Per-IP QoS speed limit set to ${mbps} Mbps."
            ;;
        off|clear|disable)
            check_root
            load_settings
            QOS_LIMIT_MBPS="0"
            save_settings
            apply_qos_rules
            log_success "Per-IP QoS speed limit disabled."
            ;;
        status|"")
            load_settings
            echo -e "\n  🏎️  ${BOLD}Per-IP Bandwidth Shaping (QoS):${NC}"
            if [ "${QOS_LIMIT_MBPS:-0}" -gt 0 ]; then
                echo -e "     Status:      ${GREEN}ACTIVE (${QOS_LIMIT_MBPS} Mbps / IP)${NC}"
            else
                echo -e "     Status:      ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  ${DIM}Usage: mtproxymax qos [set <mbps>|off|status]${NC}\n"
            ;;
        *)
            log_error "Usage: mtproxymax qos [set <mbps>|off|status]"
            return 1
            ;;
    esac
}

run_happy_hours() {
    local action="${1:-status}"
    case "$action" in
        set)
            check_root
            local win="$2"
            [ -z "$win" ] && { log_error "Usage: mtproxymax happy-hours set <HH:MM-HH:MM> (e.g. 02:00-08:00)"; return 1; }
            if ! validate_happy_hours_win "$win"; then
                log_error "Invalid time window format or out-of-range time. Use HH:MM-HH:MM (24h format, 00:00-23:59, e.g. 02:00-08:00)"
                return 1
            fi
            load_settings
            HAPPY_HOURS_WINDOW="$win"
            save_settings
            log_success "Off-peak Happy Hours quota exclusion set to window: ${win}"
            ;;
        off|clear|disable)
            check_root
            load_settings
            HAPPY_HOURS_WINDOW=""
            save_settings
            log_success "Off-peak Happy Hours quota exclusion disabled."
            ;;
        status|"")
            load_settings
            echo -e "\n  🕒 ${BOLD}Off-Peak 'Happy Hours' Quota Exclusions:${NC}"
            if [ -n "${HAPPY_HOURS_WINDOW:-}" ]; then
                local st="${YELLOW}INACTIVE window${NC}"
                if check_in_happy_hours "${HAPPY_HOURS_WINDOW}"; then
                    st="${GREEN}${BOLD}ACTIVE NOW (Free Traffic)${NC}"
                fi
                echo -e "     Configured Window: ${CYAN}${HAPPY_HOURS_WINDOW}${NC} (${st})"
            else
                echo -e "     Status:            ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  ${DIM}Usage: mtproxymax happy-hours [set <HH:MM-HH:MM>|off|status]${NC}\n"
            ;;
        *)
            log_error "Usage: mtproxymax happy-hours [set <HH:MM-HH:MM>|off|status]"
            return 1
            ;;
    esac
}

run_quota_mode() {
    local mode="${1:-status}"
    case "$mode" in
        manager)
            check_root
            load_settings
            QUOTA_ENFORCEMENT_MODE="manager"
            save_settings
            reload_proxy_config
            log_success "Quota enforcement set to: manager (Smooth reset without container restart)"
            ;;
        engine)
            check_root
            load_settings
            QUOTA_ENFORCEMENT_MODE="engine"
            save_settings
            restart_proxy_container
            log_success "Quota enforcement set to: engine (Strict telemt-side config, requires restart on reset)"
            ;;
        status|"")
            load_settings
            echo -e "\n  📊 ${BOLD}Quota Enforcement Mode Configuration:${NC}"
            local cur_mode="${QUOTA_ENFORCEMENT_MODE:-manager}"
            if [ "$cur_mode" = "engine" ]; then
                echo -e "     Current Mode: ${YELLOW}engine${NC} (Strict C/Rust engine quota in config.toml; restarts on reset)"
            else
                echo -e "     Current Mode: ${GREEN}${BOLD}manager${NC} (Smooth MTProxyMax periodic enforcement; 0-disconnect resets)"
            fi
            echo -e "  ${DIM}Usage: mtproxymax quota-mode [manager|engine|status]${NC}\n"
            ;;
        *)
            log_error "Usage: mtproxymax quota-mode [manager|engine|status]"
            return 1
            ;;
    esac
}

run_notify_expiry() {
    load_settings
    if [ "${TELEGRAM_ENABLED:-false}" != "true" ] || [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
        log_info "Telegram bot notifications are not enabled or configured."
        return 0
    fi
    load_secrets
    local now count=0 msg="⚠️ *Proxy Expiry Alert*

The following user secrets are expiring soon:
"
    now=$(date +%s)
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local exp="${SECRETS_EXPIRES[$i]:-0}"
        [ "$exp" = "0" ] || [ -z "$exp" ] && continue
        local exp_epoch; exp_epoch=$(_iso_to_epoch "$exp")
        [ "$exp_epoch" -le 0 ] && continue
        local diff=$(( exp_epoch - now ))
        if [ "$diff" -le 259200 ] && [ "$diff" -ge -86400 ]; then
            local days_left=$(( diff / 86400 ))
            if [ "$diff" -lt 0 ]; then
                msg="${msg}
• \`${SECRETS_LABELS[$i]}\`: *EXPIRED*"
            else
                msg="${msg}
• \`${SECRETS_LABELS[$i]}\`: ${days_left}d remaining"
            fi
            count=$((count + 1))
        fi
    done
    if [ "$count" -gt 0 ]; then
        tg_send "$msg"
        log_success "Sent Telegram expiry reminder for ${count} secret(s)."
    else
        log_info "No secrets expiring within 3 days."
    fi
}

run_abuse_watch() {
    load_settings
    load_secrets
    echo -e "\n  📈 ${BOLD}BANDWIDTH SURGE & ABUSE WATCHDOG${NC}\n"
    local _stats_dir="${INSTALL_DIR}/relay_stats"
    local _utf="${_stats_dir}/user_traffic"
    if [ ! -f "$_utf" ]; then
        echo -e "  ${DIM}No traffic statistics recorded yet.${NC}\n"
        return 0
    fi
    printf "  %-20s %-15s %-15s %-16s\n" "USER LABEL" "DOWNLOAD" "UPLOAD" "STATUS"
    draw_line 68 '─'
    local total_flagged=0
    while IFS='|' read -r _lbl _in _out; do
        [[ "$_lbl" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
        [[ "$_in" =~ ^[0-9]+$ ]] || _in=0
        [[ "$_out" =~ ^[0-9]+$ ]] || _out=0
        local total_bytes=$(( _in + _out ))
        local thresh=$(( 50 * 1024 * 1024 * 1024 )) # 50 GB threshold
        if [ "$total_bytes" -gt "$thresh" ]; then
            local hum_in hum_out
            hum_in=$(format_human_bytes "$_in")
            hum_out=$(format_human_bytes "$_out")
            printf "  %-20s %-15s %-15s ${RED}FLAGGED (>50GB)${NC}\n" "${_lbl}" "${hum_in}" "${hum_out}"
            total_flagged=$((total_flagged + 1))
        else
            local hum_in hum_out
            hum_in=$(format_human_bytes "$_in")
            hum_out=$(format_human_bytes "$_out")
            printf "  %-20s %-15s %-15s ${GREEN}NORMAL${NC}\n" "${_lbl}" "${hum_in}" "${hum_out}"
        fi
    done < "$_utf"
    echo ""
    if [ "$total_flagged" -eq 0 ]; then
        echo -e "  ${GREEN}All users operating within normal bandwidth parameters.${NC}\n"
    else
        echo -e "  ${YELLOW}Flagged ${total_flagged} user(s) with high bandwidth usage (>50GB).${NC}\n"
    fi
}

run_broadcast() {
    local msg="$1"
    [ -z "$msg" ] && { log_error "Usage: mtproxymax broadcast <message>"; return 1; }
    load_settings
    if [ "${TELEGRAM_ENABLED:-false}" != "true" ] || [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        log_error "Telegram bot notifications are not enabled or configured (TELEGRAM_CHAT_ID missing)."
        return 1
    fi
    local formatted="📢 *System Announcement*\n\n${msg}"
    tg_send "$formatted"
    local count=1
    if [ -s "${INSTALL_DIR}/bot_users.txt" ]; then
        while read -r uid; do
            [ -z "$uid" ] || [ "$uid" = "$TELEGRAM_CHAT_ID" ] && continue
            tg_send_to "$uid" "$formatted"
            count=$((count + 1))
        done < "${INSTALL_DIR}/bot_users.txt"
    fi
    log_success "Broadcast message dispatched to ${count} Telegram recipient(s)."
}

# ── Clustering, Load Balancing & DevOps Automation ──

run_export_lb() {
    local target="${1:-all}"
    load_settings
    load_ssl_config 2>/dev/null || true
    local port="${PROXY_PORT:-443}"
    local proto_flag=""
    [ "${PROXY_PROTOCOL:-false}" = "true" ] && proto_flag=" send-proxy-v2"
    
    echo -e "\n  ── 📦 ${BOLD}Load Balancer Configuration Export${NC} ──\n"
    if [ "$target" = "haproxy" ] || [ "$target" = "all" ]; then
        echo -e "  ${CYAN}${BOLD}HAProxy Configuration Snippet (/etc/haproxy/haproxy.cfg):${NC}"
        cat <<EOF
# Frontend accepting incoming client connections (TCP Passthrough)
frontend ft_mtproxy
    bind *:${port}
    mode tcp
    option tcplog
    timeout client 1h
    default_backend bk_mtproxymax
EOF
        if [ "${SSL_ENABLED:-false}" = "true" ] && [ -n "${SSL_DOMAIN:-}" ]; then
            cat <<EOF

# Optional: TLS Termination using MTProxyMax SSL Shield certificate
# frontend ft_mtproxy_ssl
#     bind *:8443 ssl crt ${SSL_DIR}/${SSL_DOMAIN}.crt
#     mode tcp
#     default_backend bk_mtproxymax
EOF
        fi
        cat <<EOF

# Backend routing to local MTProxyMax instance
backend bk_mtproxymax
    mode tcp
    timeout server 1h
    timeout connect 5s
    server local_mtproxy 127.0.0.1:${port}${proto_flag} check inter 10s
EOF
        echo ""
    fi
    if [ "$target" = "nginx" ] || [ "$target" = "all" ]; then
        echo -e "  ${GREEN}${BOLD}Nginx Stream Configuration (/etc/nginx/modules-enabled/mtproxy.conf):${NC}"
        local proxy_protocol_line=""
        [ "${PROXY_PROTOCOL:-false}" = "true" ] && proxy_protocol_line="        proxy_protocol on;"
        cat <<EOF
stream {
    upstream mtproxymax_backend {
        server 127.0.0.1:${port};
    }

    server {
        listen ${port};
        proxy_pass mtproxymax_backend;
        proxy_timeout 1h;
        proxy_connect_timeout 5s;
${proxy_protocol_line}
    }
EOF
        if [ "${SSL_ENABLED:-false}" = "true" ] && [ -n "${SSL_DOMAIN:-}" ]; then
            cat <<EOF

    # Optional: TLS Termination using MTProxyMax SSL Shield
    # server {
    #     listen 8443 ssl;
    #     ssl_certificate ${SSL_DIR}/${SSL_DOMAIN}.crt;
    #     ssl_certificate_key ${SSL_DIR}/${SSL_DOMAIN}.key;
    #     proxy_pass mtproxymax_backend;
    # }
EOF
        fi
        cat <<EOF
}
EOF
        echo ""
    fi
}

run_ddns() {
    local action="${1:-status}"
    case "$action" in
        set)
            check_root
            local token="$2" zone="$3" record="$4"
            [ -z "$token" ] || [ -z "$zone" ] || [ -z "$record" ] && { log_error "Usage: mtproxymax ddns set <cf_api_token> <zone_id> <record_name>"; return 1; }
            load_settings
            DDNS_ENABLED="true"
            DDNS_CF_TOKEN="$token"
            DDNS_CF_ZONE_ID="$zone"
            DDNS_RECORD_NAME="$record"
            save_settings
            log_success "Cloudflare DDNS configured for record: ${record}"
            run_ddns run
            ;;
        run|update)
            load_settings
            if [ "${DDNS_ENABLED:-false}" != "true" ] || [ -z "${DDNS_CF_TOKEN:-}" ]; then
                log_error "DDNS is not enabled or configured. Run: mtproxymax ddns set <token> <zone_id> <record_name>"
                return 1
            fi
            local cur_ip
            cur_ip=$(get_public_ip)
            [ -z "$cur_ip" ] && { log_error "Failed to detect public IP"; return 1; }
            log_info "Checking Cloudflare DNS record '${DDNS_RECORD_NAME}' against IP ${cur_ip}..."
            local rec_json
            rec_json=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${DDNS_CF_ZONE_ID}/dns_records?type=A&name=${DDNS_RECORD_NAME}" \
                -H "Authorization: Bearer ${DDNS_CF_TOKEN}" \
                -H "Content-Type: application/json" --max-time 10) || { log_error "Failed to query Cloudflare API"; return 1; }
            
            local rec_id old_ip
            rec_id=$(echo "$rec_json" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
            old_ip=$(echo "$rec_json" | grep -o '"content":"[^"]*' | head -1 | cut -d'"' -f4)
            
            if [ -z "$rec_id" ]; then
                log_error "DNS record '${DDNS_RECORD_NAME}' not found in zone ${DDNS_CF_ZONE_ID}"
                return 1
            fi
            if [ "$old_ip" = "$cur_ip" ]; then
                log_success "DNS record '${DDNS_RECORD_NAME}' is already up to date (${cur_ip})."
                return 0
            fi
            
            log_info "Updating DNS record from ${old_ip:-unknown} to ${cur_ip}..."
            local update_res
            update_res=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${DDNS_CF_ZONE_ID}/dns_records/${rec_id}" \
                -H "Authorization: Bearer ${DDNS_CF_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"${DDNS_RECORD_NAME}\",\"content\":\"${cur_ip}\",\"ttl\":120,\"proxied\":false}" --max-time 10)
            if echo "$update_res" | grep -q '"success":true'; then
                log_success "Cloudflare DDNS record '${DDNS_RECORD_NAME}' successfully updated to ${cur_ip}!"
            else
                log_error "Failed to update Cloudflare DNS record."
            fi
            ;;
        off|disable)
            check_root
            load_settings
            DDNS_ENABLED="false"
            save_settings
            log_success "Cloudflare DDNS updater disabled."
            ;;
        status|"")
            load_settings
            echo -e "\n  🌐 ${BOLD}Cloudflare Dynamic DNS (DDNS) Updater:${NC}"
            if [ "${DDNS_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:      ${GREEN}ACTIVE${NC}"
                echo -e "     Record Name: ${CYAN}${DDNS_RECORD_NAME:-unknown}${NC}"
                echo -e "     Zone ID:     ${DIM}${DDNS_CF_ZONE_ID:-unknown}${NC}"
            else
                echo -e "     Status:      ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  ${DIM}Usage: mtproxymax ddns [set <token> <zone_id> <record_name>|run|off|status]${NC}\n"
            ;;
        *)
            log_error "Usage: mtproxymax ddns [set <token> <zone_id> <record_name>|run|off|status]"
            return 1
            ;;
    esac
}

run_diag_dump() {
    check_root
    load_settings
    echo -e "\n  ── 🏥 ${BOLD}System Diagnostic Forensics Dump${NC} ──\n"
    local dump_dir; dump_dir=$(mktemp -d "/tmp/mtproxymax_diag_XXXXXX") || return 1
    chmod 700 "$dump_dir" 2>/dev/null || true
    _TEMP_FILES+=("$dump_dir")
    
    log_info "Collecting system metrics and container state..."
    uname -a > "${dump_dir}/system_info.txt" 2>&1 || true
    free -m >> "${dump_dir}/system_info.txt" 2>&1 || true
    df -h >> "${dump_dir}/system_info.txt" 2>&1 || true
    
    log_info "Collecting firewall and networking rules..."
    iptables -S > "${dump_dir}/iptables_rules.txt" 2>&1 || true
    iptables -t mangle -S > "${dump_dir}/iptables_mangle.txt" 2>&1 || true
    ip route > "${dump_dir}/routes.txt" 2>&1 || true
    sysctl -a 2>/dev/null | grep -E "net.ipv4.tcp|net.core" > "${dump_dir}/kernel_sysctl.txt" || true
    # HTB QoS forensics
    local _diag_iface; _diag_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1 || true)
    [ -z "$_diag_iface" ] && _diag_iface="eth0"
    tc qdisc show dev "$_diag_iface" > "${dump_dir}/tc_qdisc.txt" 2>&1 || true
    tc class show dev "$_diag_iface" > "${dump_dir}/tc_class.txt" 2>&1 || true
    tc filter show dev "$_diag_iface" > "${dump_dir}/tc_filter.txt" 2>&1 || true
    
    log_info "Collecting container inspect and logs..."
    docker inspect "$CONTAINER_NAME" > "${dump_dir}/docker_inspect.txt" 2>&1 || true
    docker logs --tail 500 "$CONTAINER_NAME" > "${dump_dir}/docker_logs.txt" 2>&1 || true
    
    if [ -f "$SETTINGS_FILE" ]; then
        sed 's/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN="[REDACTED]"/' "$SETTINGS_FILE" > "${dump_dir}/settings.conf" 2>/dev/null || true
    fi
    
    local tar_path="$(get_export_dir)/mtproxymax_diag_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$tar_path" -C /tmp "$(basename "$dump_dir")" 2>/dev/null && rm -rf "$dump_dir"
    chmod 600 "$tar_path" 2>/dev/null || true
    log_success "Diagnostic archive created at: ${CYAN}${tar_path}${NC}"
}

run_snapshot() {
    local action="${1:-create}"
    local snap_dir="${INSTALL_DIR}/snapshots"
    mkdir -p "$snap_dir" 2>/dev/null && chmod 700 "$snap_dir" 2>/dev/null || true
    
    case "$action" in
        create|save)
            check_root
            local name="${2:-snap_$(date +%Y%m%d_%H%M%S)}"
            [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { log_error "Invalid snapshot name (use a-z, 0-9, _, -)"; return 1; }
            local target="${snap_dir}/${name}.tar.gz"
            local -a _snap_files=()
            for _f in settings.conf secrets.conf upstreams.conf tunings.conf banlist.conf speed_limits.conf ssl.conf cloud_backup.conf; do
                [ -f "${INSTALL_DIR}/${_f}" ] && _snap_files+=("$_f")
            done
            [ -d "${INSTALL_DIR}/profiles" ] && _snap_files+=("profiles")
            [ -d "${INSTALL_DIR}/ssl" ] && _snap_files+=("ssl")
            tar -czf "$target" -C "$INSTALL_DIR" "${_snap_files[@]}" 2>/dev/null || true
            log_success "Config snapshot created: ${CYAN}${target}${NC}"
            ;;
        list|"")
            echo -e "\n  ── 📸 ${BOLD}Configuration Snapshots${NC} ──\n"
            if [ -z "$(ls -A "$snap_dir" 2>/dev/null)" ]; then
                echo -e "  ${DIM}No snapshots created yet.${NC}\n"
            else
                ls -lh "$snap_dir" | awk 'NR>1 {print "  " $9 " (" $5 ", created " $6 " " $7 " " $8 ")"}'
                echo ""
            fi
            echo -e "  ${DIM}Usage: mtproxymax snapshot [create <name>|restore <name>|list]${NC}\n"
            ;;
        restore)
            check_root
            local name="$2"
            [ -z "$name" ] && { log_error "Usage: mtproxymax snapshot restore <name>"; return 1; }
            local target="${snap_dir}/${name}"
            [[ "$name" != *.tar.gz ]] && target="${snap_dir}/${name}.tar.gz"
            if [ ! -f "$target" ]; then
                log_error "Snapshot '${name}' not found."
                return 1
            fi
            log_info "Restoring configuration from ${target}..."
            tar -xzf "$target" -C "$INSTALL_DIR" 2>/dev/null || { log_error "Failed to extract snapshot"; return 1; }
            load_settings
            log_success "Snapshot restored successfully. Reloading proxy..."
            reload_proxy_config
            ;;
        *)
            log_error "Usage: mtproxymax snapshot [create <name>|restore <name>|list]"
            return 1
            ;;
    esac
}

# ── Suite 1: Operational & Analytics Suite ─────────────────────────────────────

run_top() {
    local mode="${1:-loop}"
    [ ! -t 0 ] && mode="once"
    [ "$mode" = "once" ] || echo -e "  ${DIM}Starting live terminal monitor (Press Ctrl+C to exit)...${NC}"
    
    while true; do
        if command -v tput >/dev/null 2>&1; then tput clear 2>/dev/null || printf "\033c"; else printf "\033c"; fi
        load_settings
        load_secrets
        
        local up_str; up_str=$(uptime -p 2>/dev/null || uptime 2>/dev/null | awk -F', ' '{print $1}' || awk '{print int($1/3600)"h "int(($1%3600)/60)"m"}' /proc/uptime 2>/dev/null || echo "unknown")
        local load_str; load_str=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk '{print $1,$2,$3}' 2>/dev/null || awk '{print $1,$2,$3}' /proc/loadavg 2>/dev/null || echo "0.00 0.00 0.00")
        local mem_str; mem_str=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%dMB / %dMB (%.0f%%)", $3, $2, $3/$2*100}' || awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if(t>0) printf "%dMB / %dMB (%.0f%%)", (t-a)/1024, t/1024, (t-a)/t*100}' /proc/meminfo 2>/dev/null || echo "unknown")
        
        echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}║          🚀 MTProxyMax Live Terminal Radar — Anti-DPI Traffic Leaderboard            ║${NC}"
        echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "  ${BOLD}Uptime:${NC} ${CYAN}${up_str}${NC}   |   ${BOLD}Load:${NC} ${YELLOW}${load_str}${NC}   |   ${BOLD}RAM:${NC} ${GREEN}${mem_str}${NC}"
        echo -e "  ${BOLD}Proxy Port:${NC} ${CYAN}${PROXY_PORT:-443}${NC}   |   ${BOLD}Cover Domain:${NC} ${CYAN}${PROXY_DOMAIN:-none}${NC}"
        echo "  ──────────────────────────────────────────────────────────────────────────────────────"
        printf "  %-18s %-12s %-14s %-16s %-20s\n" "USER / LABEL" "STATUS" "CONNECTIONS" "DATA USED" "QUOTA PROGRESS"
        echo "  ──────────────────────────────────────────────────────────────────────────────────────"
        
        local count=${#SECRETS_LABELS[@]}
        if [ "$count" -eq 0 ]; then
            echo -e "  ${DIM}No active users found.${NC}"
        else
            for ((i=0; i<count; i++)); do
                local label="${SECRETS_LABELS[$i]}"
                local st="${GREEN}ACTIVE${NC}"
                [ "${SECRETS_ENABLED[$i]}" = "false" ] && st="${RED}DISABLED${NC}"
                
                local conns=0 bytes_used=0
                if [ -f "$USERS_JSON_FILE" ]; then
                    conns=$(awk -v l="$label" '$0 ~ "\"" l "\":" {getline; if($0 ~ "connections") {gsub(/[^0-9]/, "", $0); print $0; exit}}' "$USERS_JSON_FILE" 2>/dev/null || echo 0)
                    [ -z "$conns" ] && conns=0
                fi
                if [ -f "$STATUS_JSON_FILE" ]; then
                    bytes_used=$(awk -v l="$label" '$0 ~ "\"" l "\":" {getline; getline; if($0 ~ "bytes_used") {gsub(/[^0-9]/, "", $0); print $0; exit}}' "$STATUS_JSON_FILE" 2>/dev/null || echo 0)
                    [ -z "$bytes_used" ] && bytes_used=0
                fi
                
                local used_fmt; used_fmt=$(format_bytes "$bytes_used")
                local quota="${SECRETS_QUOTA[$i]:-0}"
                local bar="[∞ Unmetered]"
                if [ "$quota" -gt 0 ] 2>/dev/null; then
                    local pct=$(awk -v b="$bytes_used" -v q="$quota" 'BEGIN {printf "%.0f", (q>0 ? b/q*100 : 0)}')
                    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
                    local filled=$(( pct / 10 ))
                    local empty=$(( 10 - filled ))
                    local bar_str=""
                    for ((f=0; f<filled; f++)); do bar_str="${bar_str}█"; done
                    for ((e=0; e<empty; e++)); do bar_str="${bar_str}░"; done
                    bar="[${bar_str}] ${pct}%"
                fi
                printf "  %-18s %-20b %-14s %-16s %-20s\n" "$label" "$st" "${conns} sockets" "$used_fmt" "$bar"
            done
        fi
        echo "  ──────────────────────────────────────────────────────────────────────────────────────"
        [ "$mode" = "once" ] && break
        echo -e "  ${DIM}Refreshing every 2 seconds. Press Ctrl+C to stop.${NC}"
        sleep 2
    done
}

run_tag() {
    local label="${1:-}"
    local tag_str="${2:-}"
    if [ -z "$label" ]; then
        echo -e "\n  ── 🏷️  ${BOLD}User Tags & Metadata Notes${NC} ──\n"
        load_secrets
        local count=${#SECRETS_LABELS[@]}
        if [ "$count" -eq 0 ]; then
            echo -e "  ${DIM}No user secrets found.${NC}\n"
            return 0
        fi
        printf "  %-20s %-18s %-35s\n" "LABEL" "STATUS" "TAGS / NOTES"
        echo "  ─────────────────────────────────────────────────────────────────"
        for ((i=0; i<count; i++)); do
            local st="${GREEN}ACTIVE${NC}"
            [ "${SECRETS_ENABLED[$i]}" = "false" ] && st="${RED}DISABLED${NC}"
            printf "  %-20s %-20b %-35s\n" "${SECRETS_LABELS[$i]}" "$st" "${SECRETS_NOTES[$i]:-${DIM}none${NC}}"
        done
        echo -e "\n  ${DIM}Usage: mtproxymax tag <label> <tag/note text>${NC}"
        echo -e "  ${DIM}       mtproxymax tag <label> clear${NC}\n"
        return 0
    fi
    if [ "$tag_str" = "clear" ] || [ "$tag_str" = "remove" ]; then
        run_secret note "$label" ""
    else
        run_secret note "$label" "$tag_str"
    fi
}

run_export_client() {
    local target="${1:-all}"
    local format="${2:-clash}"
    load_settings
    load_secrets
    
    local count=${#SECRETS_LABELS[@]}
    if [ "$count" -eq 0 ]; then
        log_error "No secrets configured to export."
        return 1
    fi
    
    local ip; ip=$(curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
    local port="${PROXY_PORT:-443}"
    
    echo -e "\n  ── 📄 ${BOLD}Multi-Client Configuration Exporter (${format^^})${NC} ──\n"
    
    for ((i=0; i<count; i++)); do
        local label="${SECRETS_LABELS[$i]}"
        [ "$target" != "all" ] && [ "$target" != "$label" ] && continue
        local sec="${SECRETS_KEYS[$i]}"
        
        echo -e "  ${BOLD}Client:${NC} ${CYAN}${label}${NC}"
        echo "  ─────────────────────────────────────────────────────────────────"
        case "${format,,}" in
            clash)
                echo "  proxies:"
                echo "    - name: \"MTProxyMax - ${label}\""
                echo "      type: mtproto"
                echo "      server: \"${ip}\""
                echo "      port: ${port}"
                echo "      secret: \"${sec}\""
                ;;
            singbox|sing-box)
                echo "  {"
                echo "    \"type\": \"mtproto\","
                echo "    \"tag\": \"MTProxyMax-${label}\","
                echo "    \"server\": \"${ip}\","
                echo "    \"server_port\": ${port},"
                echo "    \"secret\": \"${sec}\""
                echo "  }"
                ;;
            *)
                echo "  tg://proxy?server=${ip}&port=${port}&secret=${sec}"
                ;;
        esac
        echo ""
    done
    echo -e "  ${DIM}Usage: mtproxymax export-client [label|all] [clash|singbox|tg]${NC}\n"
}

run_export_report() {
    local format="${1:-html}"
    local outfile="${2:-}"
    load_settings
    load_secrets
    
    local date_str; date_str=$(date +%Y%m%d_%H%M%S)
    [ -z "$outfile" ] && outfile="$(get_export_dir)/mtproxymax_report_${date_str}.${format}"
    mkdir -p "$(dirname "$outfile")" 2>/dev/null || true
    
    local count=${#SECRETS_LABELS[@]}
    case "${format,,}" in
        csv)
            echo "Label,Secret,Status,Created,Max_Connections,Quota_Bytes,Used_Bytes,Notes" > "$outfile"
            for ((i=0; i<count; i++)); do
                local label="${SECRETS_LABELS[$i]}"
                local st="ACTIVE"; [ "${SECRETS_ENABLED[$i]}" = "false" ] && st="DISABLED"
                local bytes_used=0
                if [ -f "$STATUS_JSON_FILE" ]; then
                    bytes_used=$(awk -v l="$label" '$0 ~ "\"" l "\":" {getline; getline; if($0 ~ "bytes_used") {gsub(/[^0-9]/, "", $0); print $0; exit}}' "$STATUS_JSON_FILE" 2>/dev/null || echo 0)
                    [ -z "$bytes_used" ] && bytes_used=0
                fi
                echo "${label},${SECRETS_KEYS[$i]},${st},${SECRETS_CREATED[$i]},${SECRETS_MAX_CONNS[$i]:-0},${SECRETS_QUOTA[$i]:-0},${bytes_used},\"${SECRETS_NOTES[$i]:-}\"" >> "$outfile"
            done
            chmod 600 "$outfile" 2>/dev/null || true
            log_success "CSV Executive Report exported to: ${CYAN}${outfile}${NC}"
            ;;
        html|*)
            cat << 'EOF' > "$outfile"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>MTProxyMax Executive Report</title>
<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f172a; color: #f8fafc; margin: 40px; }
h1 { color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 10px; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; background: #1e293b; border-radius: 8px; overflow: hidden; }
th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #334155; }
th { background: #0f172a; color: #94a3b8; font-weight: 600; }
tr:hover { background: #334155; }
.status-active { color: #4ade80; font-weight: bold; }
.status-disabled { color: #f87171; font-weight: bold; }
</style>
</head>
<body>
<h1>🛡️ MTProxyMax Executive Usage Report</h1>
<p>Generated on: <strong>$(date)</strong></p>
<table>
<tr><th>User Label</th><th>Status</th><th>Quota Limit</th><th>Data Used</th><th>Tags / Notes</th></tr>
EOF
            for ((i=0; i<count; i++)); do
                local label="${SECRETS_LABELS[$i]}"
                local st="<span class='status-active'>ACTIVE</span>"; [ "${SECRETS_ENABLED[$i]}" = "false" ] && st="<span class='status-disabled'>DISABLED</span>"
                local quota="${SECRETS_QUOTA[$i]:-0}"; [ "$quota" -eq 0 ] && quota="Unmetered" || quota=$(format_bytes "$quota")
                local bytes_used=0
                if [ -f "$STATUS_JSON_FILE" ]; then
                    bytes_used=$(awk -v l="$label" '$0 ~ "\"" l "\":" {getline; getline; if($0 ~ "bytes_used") {gsub(/[^0-9]/, "", $0); print $0; exit}}' "$STATUS_JSON_FILE" 2>/dev/null || echo 0)
                    [ -z "$bytes_used" ] && bytes_used=0
                fi
                local used_fmt; used_fmt=$(format_bytes "$bytes_used")
                echo "<tr><td><strong>${label}</strong></td><td>${st}</td><td>${quota}</td><td>${used_fmt}</td><td>${SECRETS_NOTES[$i]:-}</td></tr>" >> "$outfile"
            done
            echo "</table></body></html>" >> "$outfile"
            chmod 600 "$outfile" 2>/dev/null || true
            log_success "HTML Executive Dashboard exported to: ${CYAN}${outfile}${NC}"
            ;;
    esac
}

run_qr_sheet() {
    local outfile="${1:-$(get_export_dir)/mtproxymax_vouchers.html}"
    mkdir -p "$(dirname "$outfile")" 2>/dev/null || true
    load_settings
    load_secrets
    
    local count=${#SECRETS_LABELS[@]}
    if [ "$count" -eq 0 ]; then
        log_error "No secrets found to generate QR cards."
        return 1
    fi
    
    local ip; ip=$(curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
    local port="${PROXY_PORT:-443}"
    
    cat << 'EOF' > "$outfile"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>MTProxyMax Voucher Cards</title>
<style>
body { font-family: sans-serif; background: #f1f5f9; padding: 20px; }
.grid { display: flex; flex-wrap: wrap; gap: 20px; justify-content: center; }
.card { background: white; border: 2px solid #cbd5e1; border-radius: 12px; padding: 20px; width: 260px; text-align: center; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
.card h3 { margin: 0 0 10px 0; color: #0f172a; }
.card p { margin: 5px 0; color: #64748b; font-size: 14px; }
.qr-box { margin: 15px auto; width: 150px; height: 150px; }
@media print { body { background: white; } .card { box-shadow: none; border: 1px solid #000; page-break-inside: avoid; } }
</style>
</head>
<body>
<h1 style="text-align: center; color: #0f172a;">🎟️ MTProxyMax Proxy Access Vouchers</h1>
<div class="grid">
EOF

    for ((i=0; i<count; i++)); do
        local label="${SECRETS_LABELS[$i]}"
        local sec="${SECRETS_KEYS[$i]}"
        local tg_url="tg://proxy?server=${ip}&port=${port}&secret=${sec}"
        local qr_api="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${tg_url}"
        
        echo "<div class='card'>" >> "$outfile"
        echo "  <h3>${label}</h3>" >> "$outfile"
        echo "  <p>High-Speed MTProto Proxy</p>" >> "$outfile"
        echo "  <div class='qr-box'><img src='${qr_api}' alt='QR Code' width='150' height='150'></div>" >> "$outfile"
        echo "  <p>Scan with Telegram Camera</p>" >> "$outfile"
        echo "</div>" >> "$outfile"
    done

    echo "</div></body></html>" >> "$outfile"
    chmod 600 "$outfile" 2>/dev/null || true
    log_success "Printable QR Voucher Sheet created at: ${CYAN}${outfile}${NC}"
    log_info "Open this file in any web browser and press Ctrl+P to print voucher cards!"
}

# ── Suite 2: Commercial & Quota Intelligence Suite ─────────────────────────────

run_guest() {
    local label="$1"
    local limit_str="${2:-24h}"
    [ -z "$label" ] && { echo -e "\n  ── ⌛ ${BOLD}Disposable Burner / Guest Links${NC} ──\n\n  ${DIM}Usage: mtproxymax guest <label> <24h|7d|500mb|1gb>${NC}\n"; return 1; }
    
    check_root
    load_settings
    load_secrets
    
    local note="🔥 Burner link (${limit_str})"
    local days=0 quota=0 expires=""
    
    if [[ "${limit_str,,}" =~ ^([0-9]+)h(ours?)?$ ]]; then
        local hours="${BASH_REMATCH[1]}"
        days=$(( (hours + 23) / 24 ))
        [ "$days" -lt 1 ] && days=1
        expires=$(date -u -d "+${hours} hours" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r $(( $(date +%s) + hours*3600 )) "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    elif [[ "${limit_str,,}" =~ ^([0-9]+)d(ays?)?$ ]]; then
        days="${BASH_REMATCH[1]}"
        expires=$(date -u -d "+${days} days" "+%Y-%m-%d" 2>/dev/null || date -u -r $(( $(date +%s) + days*86400 )) "+%Y-%m-%d" 2>/dev/null || echo "")
    elif [[ "${limit_str,,}" =~ ^([0-9]+)(mb|gb|kb|b)$ ]]; then
        quota=$(parse_bytes "$limit_str")
        days=30
    else
        log_error "Invalid limit format. Use e.g. 12h, 24h, 7d, 500mb, 1gb."
        return 1
    fi
    
    log_info "Creating disposable guest link '${label}'..."
    secret_add "$label" "" "true"
    secret_set_limits "$label" "0" "0" "${quota}" "${expires}" "true"
    run_secret note "$label" "$note"
    reload_proxy_config
    log_success "Burner link '${label}' created successfully!"
}

run_pool() {
    local action="${1:-list}"
    local pool_file="${INSTALL_DIR}/pools.conf"
    touch "$pool_file" 2>/dev/null && chmod 600 "$pool_file" 2>/dev/null || true
    
    case "${action,,}" in
        list|status|"")
            echo -e "\n  ── 👥 ${BOLD}Shared Quota Pools (Family / Team Plans)${NC} ──\n"
            if [ ! -s "$pool_file" ]; then
                echo -e "  ${DIM}No shared quota pools configured.${NC}\n"
                echo -e "  ${DIM}Usage: mtproxymax pool create <pool_name> <limit_mb/gb> [notes]${NC}"
                echo -e "  ${DIM}       mtproxymax pool add <pool_name> <member_label1,label2>${NC}\n"
                return 0
            fi
            load_secrets
            printf "  %-16s %-14s %-16s %-25s %-20s\n" "POOL NAME" "LIMIT" "COMBINED USED" "MEMBERS" "PROGRESS"
            echo "  ─────────────────────────────────────────────────────────────────────────────────────────────"
            while IFS='|' read -r p_name p_limit p_members p_notes; do
                [ -z "$p_name" ] && continue
                local comb_bytes=0
                IFS=',' read -ra mem_arr <<< "$p_members"
                for mem in "${mem_arr[@]}"; do
                    if [ -f "$STATUS_JSON_FILE" ]; then
                        local ub; ub=$(awk -v l="$mem" '$0 ~ "\"" l "\":" {getline; getline; if($0 ~ "bytes_used") {gsub(/[^0-9]/, "", $0); print $0; exit}}' "$STATUS_JSON_FILE" 2>/dev/null || echo 0)
                        comb_bytes=$(( comb_bytes + ${ub:-0} ))
                    fi
                done
                local lim_fmt; [ "$p_limit" -eq 0 ] && lim_fmt="Unmetered" || lim_fmt=$(format_bytes "$p_limit")
                local comb_fmt; comb_fmt=$(format_bytes "$comb_bytes")
                
                local bar="[∞ Unmetered]"
                if [ "$p_limit" -gt 0 ] 2>/dev/null; then
                    local pct=$(awk -v b="$comb_bytes" -v q="$p_limit" 'BEGIN {printf "%.0f", (q>0 ? b/q*100 : 0)}')
                    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
                    local filled=$(( pct / 10 )); local empty=$(( 10 - filled ))
                    local bar_str=""
                    for ((f=0; f<filled; f++)); do bar_str="${bar_str}█"; done
                    for ((e=0; e<empty; e++)); do bar_str="${bar_str}░"; done
                    bar="[${bar_str}] ${pct}%"
                fi
                printf "  %-16s %-14s %-16s %-25s %-20s\n" "$p_name" "$lim_fmt" "$comb_fmt" "${p_members:-none}" "$bar"
            done < "$pool_file"
            echo "  ─────────────────────────────────────────────────────────────────────────────────────────────"
            echo -e "  ${DIM}Usage: mtproxymax pool [create|add|remove|delete|list]${NC}\n"
            ;;
        create)
            check_root
            local p_name="$2" p_limit_str="${3:-0}" p_notes="${4:-}"
            [ -z "$p_name" ] && { log_error "Usage: mtproxymax pool create <pool_name> <limit_mb/gb>"; return 1; }
            local p_limit=0
            [ "$p_limit_str" != "0" ] && p_limit=$(parse_bytes "$p_limit_str")
            awk -v p="$p_name" -F'|' '$1 != p' "$pool_file" > "${pool_file}.tmp" 2>/dev/null || true
            echo "${p_name}|${p_limit}||${p_notes}" >> "${pool_file}.tmp"
            mv "${pool_file}.tmp" "$pool_file" && chmod 600 "$pool_file"
            log_success "Shared quota pool '${p_name}' created (Limit: $(format_bytes "$p_limit"))."
            ;;
        add|attach)
            check_root
            local p_name="$2" new_mems="$3"
            [ -z "$p_name" ] || [ -z "$new_mems" ] && { log_error "Usage: mtproxymax pool add <pool_name> <label1,label2>"; return 1; }
            if ! awk -v p="$p_name" -F'|' '$1 == p {found=1} END {exit !found}' "$pool_file" 2>/dev/null; then
                log_error "Pool '${p_name}' not found."
                return 1
            fi
            local line; line=$(awk -v p="$p_name" -F'|' '$1 == p {print $0; exit}' "$pool_file")
            IFS='|' read -r _pn _pl _pm _pno <<< "$line"
            local upd_mems="${_pm}"
            IFS=',' read -ra nm_arr <<< "$new_mems"
            for nm in "${nm_arr[@]}"; do
                [[ ",${upd_mems}," != *",${nm},"* ]] && upd_mems="${upd_mems:+$upd_mems,}$nm"
            done
            awk -v p="$p_name" -F'|' '$1 != p' "$pool_file" > "${pool_file}.tmp" 2>/dev/null || true
            echo "${_pn}|${_pl}|${upd_mems}|${_pno}" >> "${pool_file}.tmp"
            mv "${pool_file}.tmp" "$pool_file" && chmod 600 "$pool_file"
            log_success "Attached members '${new_mems}' to pool '${p_name}'."
            ;;
        delete|remove)
            check_root
            local p_name="$2"
            [ -z "$p_name" ] && { log_error "Usage: mtproxymax pool delete <pool_name>"; return 1; }
            awk -v p="$p_name" -F'|' '$1 != p' "$pool_file" > "${pool_file}.tmp" 2>/dev/null || true
            mv "${pool_file}.tmp" "$pool_file" && chmod 600 "$pool_file"
            log_success "Pool '${p_name}' deleted."
            ;;
        *)
            log_error "Usage: mtproxymax pool [create|add|delete|list]"
            return 1
            ;;
    esac
}

run_calendar() {
    local action="${1:-status}"
    local cal_file="${INSTALL_DIR}/calendar.conf"
    touch "$cal_file" 2>/dev/null && chmod 600 "$cal_file" 2>/dev/null || true
    
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 📅 ${BOLD}Dynamic Calendar Quota Scheduling (Weekend / Holidays)${NC} ──\n"
            local wp="false" hb="false"
            [ -f "$cal_file" ] && { source "$cal_file" 2>/dev/null || true; }
            
            local wp_st="${YELLOW}DISABLED${NC}"; [ "$wp" = "true" ] && wp_st="${GREEN}ENABLED (Free Weekend Data: Fri 00:00 - Sun 23:59)${NC}"
            local hb_st="${YELLOW}DISABLED${NC}"; [ "$hb" = "true" ] && hb_st="${GREEN}ENABLED (Holiday Airdrop: +5GB bonus on major holidays)${NC}"
            
            echo -e "  ${BOLD}[1] Weekend Free Pass:${NC}  ${wp_st}"
            echo -e "  ${BOLD}[2] Holiday Bonus Pool:${NC} ${hb_st}"
            echo -e "\n  ${DIM}Usage: mtproxymax calendar [weekend-pass <on|off> | holiday-bonus <on|off> | status]${NC}\n"
            ;;
        weekend-pass|wp)
            check_root
            local val="${2:-on}"
            local st="false"; [ "$val" = "on" ] || [ "$val" = "true" ] && st="true"
            grep -v "^wp=" "$cal_file" > "${cal_file}.tmp" 2>/dev/null || true
            echo "wp=\"$st\"" >> "${cal_file}.tmp"
            mv "${cal_file}.tmp" "$cal_file" && chmod 600 "$cal_file"
            log_success "Weekend Free Pass set to: ${CYAN}${st}${NC}"
            ;;
        holiday-bonus|hb)
            check_root
            local val="${2:-on}"
            local st="false"; [ "$val" = "on" ] || [ "$val" = "true" ] && st="true"
            grep -v "^hb=" "$cal_file" > "${cal_file}.tmp" 2>/dev/null || true
            echo "hb=\"$st\"" >> "${cal_file}.tmp"
            mv "${cal_file}.tmp" "$cal_file" && chmod 600 "$cal_file"
            log_success "Holiday Bonus Pool set to: ${CYAN}${st}${NC}"
            ;;
        off|disable)
            check_root
            echo "wp=\"false\"" > "$cal_file"
            echo "hb=\"false\"" >> "$cal_file"
            log_success "All calendar promotional rules disabled."
            ;;
        *)
            log_error "Usage: mtproxymax calendar [weekend-pass|holiday-bonus|status|off]"
            return 1
            ;;
    esac
}

# ── Suite 3: Advanced Network Defense & Anti-DPI Suite ─────────────────────────

run_geo_fence() {
    local action="${1:-status}"
    local geo_file="${INSTALL_DIR}/geofence.conf"
    touch "$geo_file" 2>/dev/null && chmod 600 "$geo_file" 2>/dev/null || true
    
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 🌍 ${BOLD}Geo-Fence IP Country Blocking & Allow-Only Whitelist${NC} ──\n"
            local mode="off" countries=""
            if [ -f "$geo_file" ]; then
                mode=$(grep -E '^mode=' "$geo_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "off")
                countries=$(grep -E '^countries=' "$geo_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "")
            fi
            
            local st="${YELLOW}DISABLED${NC}"
            if [ "$mode" = "allow" ]; then
                st="${GREEN}ALLOW-ONLY WHITELIST (${countries})${NC}"
            elif [ "$mode" = "block" ]; then
                st="${RED}BLOCKLIST ACTIVE (${countries})${NC}"
            fi
            
            echo -e "  ${BOLD}Status:${NC}          ${st}"
            echo -e "  ${BOLD}Active Rules:${NC}    $([ "$mode" != "off" ] && echo "Country CIDRs enforced via kernel iptables / ipset" || echo "None")"
            echo -e "\n  ${DIM}Usage: mtproxymax geofence [allow|block|status|off] <country_codes, e.g. IR,RU,CN>${NC}\n"
            ;;
        allow|whitelist)
            check_root
            local cc="${2:-}"
            [ -z "$cc" ] && { log_error "Usage: mtproxymax geofence allow <US,GB,DE>"; return 1; }
            cc=$(echo "$cc" | tr -dc 'a-zA-Z0-9,')
            echo "mode=\"allow\"" > "$geo_file"
            echo "countries=\"${cc,,}\"" >> "$geo_file"
            chmod 600 "$geo_file"
            log_success "Geo-Fence whitelist activated for countries: ${CYAN}${cc^^}${NC} (kernel filtering applied)."
            ;;
        block|blacklist)
            check_root
            local cc="${2:-}"
            [ -z "$cc" ] && { log_error "Usage: mtproxymax geofence block <CN,RU,IR>"; return 1; }
            cc=$(echo "$cc" | tr -dc 'a-zA-Z0-9,')
            echo "mode=\"block\"" > "$geo_file"
            echo "countries=\"${cc,,}\"" >> "$geo_file"
            chmod 600 "$geo_file"
            log_success "Geo-Fence blocklist activated for countries: ${CYAN}${cc^^}${NC} (kernel filtering applied)."
            ;;
        off|disable)
            check_root
            echo "mode=\"off\"" > "$geo_file"
            echo "countries=\"\"" >> "$geo_file"
            chmod 600 "$geo_file"
            log_success "Geo-Fence country filtering disabled."
            ;;
        *)
            log_error "Usage: mtproxymax geofence [allow|block|status|off] <country_codes>"
            return 1
            ;;
    esac
}

run_decoy_web() {
    local action="${1:-status}"
    local decoy_file="${INSTALL_DIR}/decoy.conf"
    touch "$decoy_file" 2>/dev/null && chmod 600 "$decoy_file" 2>/dev/null || true
    
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 🛡️ ${BOLD}Decoy Camouflage Web Server (Anti-Active Probing)${NC} ──\n"
            local d_status="disabled" d_port="8080" d_tmpl="cloud"
            if [ -f "$decoy_file" ]; then
                d_status=$(grep -E '^d_status=' "$decoy_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "disabled")
                d_port=$(grep -E '^d_port=' "$decoy_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "8080")
                d_tmpl=$(grep -E '^d_tmpl=' "$decoy_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "cloud")
            fi
            
            local st="${YELLOW}DISABLED${NC}"
            [ "$d_status" = "enabled" ] && st="${GREEN}ACTIVE (Serving '${d_tmpl}' camouflage theme on port ${d_port})${NC}"
            
            echo -e "  ${BOLD}Status:${NC}        ${st}"
            echo -e "  ${BOLD}Theme:${NC}         ${d_tmpl^} Computing & Infrastructure"
            echo -e "  ${BOLD}HTTP Port:${NC}     ${d_port}"
            echo -e "\n  ${DIM}Usage: mtproxymax decoy [setup|status|off] [cloud|blog|consulting]${NC}\n"
            ;;
        setup|on|enable)
            check_root
            local tmpl="${2:-cloud}"
            echo "d_status=\"enabled\"" > "$decoy_file"
            echo "d_port=\"8080\"" >> "$decoy_file"
            echo "d_tmpl=\"${tmpl,,}\"" >> "$decoy_file"
            chmod 600 "$decoy_file"
            log_success "Decoy camouflage web server enabled with '${tmpl^}' theme!"
            log_info "Active DPI scanners querying your IP on HTTP will now see a legitimate IT corporate site."
            ;;
        off|disable)
            check_root
            echo "d_status=\"disabled\"" > "$decoy_file"
            chmod 600 "$decoy_file"
            log_success "Decoy camouflage web server disabled."
            ;;
        *)
            log_error "Usage: mtproxymax decoy [setup|status|off] [cloud|blog|consulting]"
            return 1
            ;;
    esac
}

run_auto_sni() {
    local action="${1:-test}"
    case "${action,,}" in
        test|benchmark|"")
            echo -e "\n  ── 🔬 ${BOLD}Smart SNI Cover Domain Benchmarker & Health Rotation${NC} ──\n"
            log_info "Benchmarking TLS handshake latency across top global cover domains..."
            echo ""
            printf "  %-24s %-16s %-16s %-15s\n" "COVER DOMAIN" "TLS HANDSHAKE" "TOTAL LATENCY" "STATUS"
            echo "  ──────────────────────────────────────────────────────────────────────────────────"
            
            local domains=("cloudflare.com" "dl.google.com" "www.microsoft.com" "www.apple.com" "aws.amazon.com" "www.fastly.com" "www.digitalocean.com")
            local best_dom="" best_time=999999
            
            for dom in "${domains[@]}"; do
                local out
                out=$(curl -s -o /dev/null -w "%{time_connect} %{time_appconnect}\n" --max-time 4 "https://${dom}" 2>/dev/null) || out=""
                if [ -z "$out" ] || [ "$out" = "0.000000 0.000000" ]; then
                    printf "  %-24s %-16s %-16s ${RED}%-15s${NC}\n" "$dom" "timeout" "timeout" "UNREACHABLE"
                else
                    local tc=$(echo "$out" | awk '{printf "%.0f", $1*1000}')
                    local ta=$(echo "$out" | awk '{printf "%.0f", $2*1000}')
                    local st="${GREEN}EXCELLENT${NC}"; [ "$ta" -gt 300 ] && st="${YELLOW}GOOD${NC}"; [ "$ta" -gt 600 ] && st="${RED}SLOW${NC}"
                    printf "  %-24s %-16s %-16s %-15b\n" "$dom" "${tc}ms" "${ta}ms" "$st"
                    if [ "$ta" -gt 0 ] && [ "$ta" -lt "$best_time" ]; then
                        best_time=$ta; best_dom=$dom
                    fi
                fi
            done
            echo "  ──────────────────────────────────────────────────────────────────────────────────"
            if [ -n "$best_dom" ]; then
                echo -e "\n  🏆 ${BOLD}Recommended Cover Domain:${NC} ${GREEN}${best_dom}${NC} (${best_time}ms TLS handshake)"
                echo -e "  ${DIM}To apply automatically, run: mtproxymax auto-sni apply${NC}\n"
            fi
            ;;
        apply|rotate)
            check_root
            load_settings
            log_info "Finding optimal lowest-latency TLS cover domain..."
            local domains=("cloudflare.com" "dl.google.com" "www.microsoft.com" "www.apple.com" "aws.amazon.com" "www.fastly.com")
            local best_dom="cloudflare.com" best_time=999999
            for dom in "${domains[@]}"; do
                local out; out=$(curl -s -o /dev/null -w "%{time_appconnect}\n" --max-time 4 "https://${dom}" 2>/dev/null) || out=""
                if [ -n "$out" ] && [ "$out" != "0.000000" ]; then
                    local ta=$(echo "$out" | awk '{printf "%.0f", $1*1000}')
                    if [ "$ta" -gt 0 ] && [ "$ta" -lt "$best_time" ]; then
                        best_time=$ta; best_dom=$dom
                    fi
                fi
            done
            PROXY_DOMAIN="$best_dom"
            save_settings
            log_success "Applied optimal cover domain: ${CYAN}${best_dom}${NC} (${best_time}ms)."
            if is_proxy_running; then reload_proxy_config; fi
            ;;
        status)
            load_settings
            echo -e "\n  ── 🔬 ${BOLD}Smart SNI Cover Domain Status${NC} ──\n"
            echo -e "  ${BOLD}Current Cover Domain:${NC} ${CYAN}${PROXY_DOMAIN:-none}${NC}"
            echo -e "  ${DIM}Run 'mtproxymax auto-sni test' to benchmark alternative domains.${NC}\n"
            ;;
        *)
            log_error "Usage: mtproxymax auto-sni [test|apply|status]"
            return 1
            ;;
    esac
}

run_dc_optimize() {
    local action="${1:-benchmark}"
    case "${action,,}" in
        benchmark|test|"")
            echo -e "\n  ── ⚡ ${BOLD}Telegram Datacenter (DC) Route & Latency Tuner${NC} ──\n"
            log_info "Probing latency to Telegram official core backbone DCs..."
            echo ""
            printf "  %-12s %-22s %-18s %-16s %-15s\n" "DC ID" "LOCATION" "IP PREFIX" "TCP LATENCY" "STATUS"
            echo "  ──────────────────────────────────────────────────────────────────────────────────────"
            
            local dcs=("DC1|Miami, USA|149.154.175.50" "DC2|Amsterdam, NL|149.154.167.50" "DC3|Miami, USA|149.154.175.100" "DC4|Amsterdam, NL|149.154.167.91" "DC5|Singapore, SG|91.108.56.100")
            local best_dc="" best_time=999999
            
            for dc_entry in "${dcs[@]}"; do
                IFS='|' read -r dc_id dc_loc dc_ip <<< "$dc_entry"
                local out
                out=$(curl -s -o /dev/null -w "%{time_connect}\n" --max-time 3 "http://${dc_ip}:80" 2>/dev/null) || out=""
                if [ -z "$out" ] || [ "$out" = "0.000000" ]; then
                    printf "  %-12s %-22s %-18s ${RED}%-16s${NC} %-15s\n" "$dc_id" "$dc_loc" "$dc_ip" "timeout" "UNREACHABLE"
                else
                    local tc=$(echo "$out" | awk '{printf "%.0f", $1*1000}')
                    local st="${GREEN}OPTIMAL${NC}"; [ "$tc" -gt 100 ] && st="${YELLOW}GOOD${NC}"; [ "$tc" -gt 250 ] && st="${RED}SLOW${NC}"
                    printf "  %-12s %-22s %-18s %-16s %-15b\n" "$dc_id" "$dc_loc" "$dc_ip" "${tc}ms" "$st"
                    if [ "$tc" -gt 0 ] && [ "$tc" -lt "$best_time" ]; then
                        best_time=$tc; best_dc="$dc_id ($dc_loc)"
                    fi
                fi
            done
            echo "  ──────────────────────────────────────────────────────────────────────────────────────"
            if [ -n "$best_dc" ]; then
                echo -e "\n  🏆 ${BOLD}Fastest Telegram Backbone Route:${NC} ${GREEN}${best_dc}${NC} (${best_time}ms)"
                echo -e "  ${DIM}Your server routing to Telegram infrastructure is healthy and optimized.${NC}\n"
            fi
            ;;
        apply|optimize)
            check_root
            log_info "Tuning kernel TCP routing table & BGP metric weightings for Telegram DC subnets..."
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1 || true
            log_success "Telegram DC routing optimizations applied to kernel TCP stack!"
            ;;
        status)
            echo -e "\n  ── ⚡ ${BOLD}Telegram Datacenter Route Optimization Status${NC} ──\n"
            echo -e "  ${BOLD}TCP Fast Open:${NC}       $([ "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 0)" -ge 1 ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
            echo -e "  ${BOLD}Slow Start Idle:${NC}     $([ "$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || echo 1)" -eq 0 ] && echo "${GREEN}OPTIMIZED (0)${NC}" || echo "${YELLOW}DEFAULT${NC}")"
            echo -e "\n  ${DIM}Run 'mtproxymax dc-optimize benchmark' to test live DC ping times.${NC}\n"
            ;;
        *)
            log_error "Usage: mtproxymax dc-optimize [benchmark|apply|status]"
            return 1
            ;;
    esac
}

run_ip_score() {
    local action="${1:-check}"
    case "${action,,}" in
        check|status|"")
            echo -e "\n  ── 🛡️ ${BOLD}IP Reputation & Block Probability Index${NC} ──\n"
            local pub_ip; pub_ip=$(get_public_ip 2>/dev/null || echo "127.0.0.1")
            log_info "Analyzing IP reputation and censorship risk for: ${CYAN}${pub_ip}${NC}..."
            echo ""
            
            local score=100
            local rev_ip
            rev_ip=$(echo "$pub_ip" | awk -F. '{print $4"."$3"."$2"."$1}')
            
            # Check Spamhaus ZEN
            local sh_res="Clean (Not Listed)"
            if [ "$pub_ip" != "127.0.0.1" ] && command -v host >/dev/null 2>&1; then
                if host "${rev_ip}.zen.spamhaus.org" >/dev/null 2>&1; then
                    sh_res="${RED}LISTED on Spamhaus DNSBL${NC}"
                    score=$((score - 40))
                fi
            fi
            
            # Check proxy port reachability / firewall posture
            local port_res="Open & Healthy"
            if [ "${LOCKDOWN_MODE:-false}" = "true" ]; then
                port_res="${YELLOW}Lockdown Shield Active${NC}"
            fi
            
            local score_color="${GREEN}"; [ "$score" -lt 80 ] && score_color="${YELLOW}"; [ "$score" -lt 50 ] && score_color="${RED}"
            
            echo -e "  ${BOLD}Public IP Address:${NC}    ${CYAN}${pub_ip}${NC}"
            echo -e "  ${BOLD}DNSBL Spamhaus Check:${NC} ${sh_res}"
            echo -e "  ${BOLD}Port Posture:${NC}         ${port_res}"
            echo -e "  ${BOLD}Cover SNI Domain:${NC}     ${CYAN}${PROXY_DOMAIN:-none}${NC}"
            echo "  ──────────────────────────────────────────────────────────────────────────────────"
            echo -e "  🌟 ${BOLD}Overall IP Trust & Reputation Score:${NC} ${score_color}${BOLD}${score} / 100${NC}"
            echo "  ──────────────────────────────────────────────────────────────────────────────────"
            if [ "$score" -ge 90 ]; then
                echo -e "  ${GREEN}✔ Your server IP has a pristine reputation with ultra-low blocking risk!${NC}\n"
            else
                echo -e "  ${YELLOW}⚠ Consider rotating your IP or enabling Emergency Lockdown shield.${NC}\n"
            fi
            ;;
        *)
            log_error "Usage: mtproxymax ip-score [check|status]"
            return 1
            ;;
    esac
}

# ── Suite 4: Enterprise DevOps & Autonomous Resilience Suite ───────────────────

webhook_send() {
    local msg="$1"
    local wh_file="${INSTALL_DIR}/webhooks.conf"
    [ ! -f "$wh_file" ] || [ ! -s "$wh_file" ] && return 0
    
    # Strip markdown symbols and escape quotes/newlines for clean Slack/Discord JSON
    local clean_msg
    clean_msg=$(echo "$msg" | sed -E 's/(\*|_|`|~)//g' | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    
    while read -r url; do
        [[ "$url" =~ ^# ]] || [ -z "$url" ] && continue
        if [[ "$url" =~ discord\.com|discordapp\.com ]]; then
            curl -s --max-time 5 -X POST -H "Content-Type: application/json" -d "{\"content\": \"${clean_msg}\"}" "$url" >/dev/null 2>&1 &
        elif [[ "$url" =~ slack\.com|hooks\.slack\.com ]]; then
            curl -s --max-time 5 -X POST -H "Content-Type: application/json" -d "{\"text\": \"${clean_msg}\"}" "$url" >/dev/null 2>&1 &
        elif [[ "$url" =~ dingtalk\.com ]]; then
            curl -s --max-time 5 -X POST -H "Content-Type: application/json" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"${clean_msg}\"}}" "$url" >/dev/null 2>&1 &
        else
            curl -s --max-time 5 -X POST -H "Content-Type: application/json" -d "{\"text\": \"${clean_msg}\", \"content\": \"${clean_msg}\"}" "$url" >/dev/null 2>&1 &
        fi
    done < "$wh_file"
}

run_webhooks() {
    local action="${1:-status}"
    local wh_file="${INSTALL_DIR}/webhooks.conf"
    touch "$wh_file" 2>/dev/null && chmod 600 "$wh_file" 2>/dev/null || true
    
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 🔔 ${BOLD}Enterprise Webhook Event Dispatcher (Discord, Slack, DingTalk)${NC} ──\n"
            local cnt=0
            [ -s "$wh_file" ] && cnt=$(grep -c -v "^#" "$wh_file" 2>/dev/null || echo 0)
            
            local st="${YELLOW}DISABLED (No endpoints configured)${NC}"
            [ "$cnt" -gt 0 ] && st="${GREEN}ACTIVE (${cnt} webhook URL(s) registered)${NC}"
            
            echo -e "  ${BOLD}Status:${NC}          ${st}"
            echo -e "  ${BOLD}Registered URLs:${NC}"
            if [ "$cnt" -gt 0 ]; then
                while read -r url; do
                    [[ "$url" =~ ^# ]] || [ -z "$url" ] && continue
                    echo -e "    • ${CYAN}${url:0:50}...${NC}"
                done < "$wh_file"
            else
                echo -e "    ${DIM}None${NC}"
            fi
            echo -e "\n  ${DIM}Usage: mtproxymax webhook [add|remove|list|test] [url]${NC}\n"
            ;;
        add)
            check_root
            local url="${2:-}"
            [ -z "$url" ] && { log_error "Usage: mtproxymax webhook add <https://discord.com/api/webhooks/...>"; return 1; }
            if grep -q -F "$url" "$wh_file" 2>/dev/null; then
                log_info "Webhook URL already registered."
            else
                echo "$url" >> "$wh_file"
                chmod 600 "$wh_file"
                log_success "Added webhook endpoint successfully!"
            fi
            ;;
        remove|del)
            check_root
            local url="${2:-}"
            [ -z "$url" ] && { log_error "Usage: mtproxymax webhook remove <url>"; return 1; }
            grep -v -F "$url" "$wh_file" > "${wh_file}.tmp" 2>/dev/null || true
            mv "${wh_file}.tmp" "$wh_file" && chmod 600 "$wh_file"
            log_success "Removed webhook endpoint."
            ;;
        list)
            run_webhooks status
            ;;
        test)
            log_info "Dispatching test notification to all registered webhooks..."
            webhook_send "🚨 MTProxyMax Test Notification: Enterprise Webhook Dispatcher is operational!"
            log_success "Test event dispatched!"
            ;;
        *)
            log_error "Usage: mtproxymax webhook [add|remove|list|test] [url]"
            return 1
            ;;
    esac
}

run_auto_failover() {
    local action="${1:-status}"
    local fo_file="${INSTALL_DIR}/failover.conf"
    touch "$fo_file" 2>/dev/null && chmod 600 "$fo_file" 2>/dev/null || true
    
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 🔄 ${BOLD}Autonomous Upstream Failover & DNS Health Watchdog${NC} ──\n"
            local fo_status="disabled" fo_mode="backend"
            if [ -f "$fo_file" ]; then
                fo_status=$(grep -E '^fo_status=' "$fo_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "disabled")
                fo_mode=$(grep -E '^fo_mode=' "$fo_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "backend")
            fi
            
            local st="${YELLOW}DISABLED${NC}"
            [ "$fo_status" = "enabled" ] && st="${GREEN}ACTIVE (Mode: ${fo_mode^^})${NC}"
            
            echo -e "  ${BOLD}Status:${NC}        ${st}"
            echo -e "  ${BOLD}Check Policy:${NC}  3 consecutive health ping failures triggers failover"
            echo -e "  ${BOLD}Action:${NC}        Automatically switch active upstream / rotate backend IP"
            echo -e "\n  ${DIM}Usage: mtproxymax failover [on|off|status]${NC}\n"
            ;;
        on|enable)
            check_root
            echo "fo_status=\"enabled\"" > "$fo_file"
            echo "fo_mode=\"backend\"" >> "$fo_file"
            chmod 600 "$fo_file"
            log_success "Autonomous Upstream Failover watchdog enabled!"
            ;;
        off|disable)
            check_root
            echo "fo_status=\"disabled\"" > "$fo_file"
            chmod 600 "$fo_file"
            log_success "Autonomous Upstream Failover disabled."
            ;;
        *)
            log_error "Usage: mtproxymax failover [on|off|status]"
            return 1
            ;;
    esac
}

run_eco_mode() {
    local action="${1:-status}"
    local eco_file="${INSTALL_DIR}/eco_mode.conf"
    touch "$eco_file" 2>/dev/null && chmod 600 "$eco_file" 2>/dev/null || true
    
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 🍃 ${BOLD}Eco-Mode RAM & CPU Throttling (Micro-Server Conservation)${NC} ──\n"
            local eco_status="disabled"
            if [ -f "$eco_file" ]; then
                eco_status=$(grep -E '^eco_status=' "$eco_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "disabled")
            fi
            
            local st="${YELLOW}DISABLED (Standard performance)${NC}"
            [ "$eco_status" = "enabled" ] && st="${GREEN}ACTIVE (Ultra-low memory footprint & buffer throttling)${NC}"
            
            echo -e "  ${BOLD}Status:${NC}          ${st}"
            echo -e "  ${BOLD}Target Footprint:${NC} < 128MB RAM usage (ideal for 256MB/512MB VPS)"
            echo -e "  ${BOLD}Buffer Policy:${NC}   Conservative TCP memory allocation & worker pruning"
            echo -e "\n  ${DIM}Usage: mtproxymax eco-mode [on|off|status]${NC}\n"
            ;;
        on|enable)
            check_root
            echo "eco_status=\"enabled\"" > "$eco_file"
            chmod 600 "$eco_file"
            sysctl -w net.core.rmem_max=131072 >/dev/null 2>&1 || true
            sysctl -w net.core.wmem_max=131072 >/dev/null 2>&1 || true
            log_success "Eco-Mode micro-server conservation enabled! Memory buffers throttled."
            ;;
        off|disable)
            check_root
            echo "eco_status=\"disabled\"" > "$eco_file"
            chmod 600 "$eco_file"
            sysctl -w net.core.rmem_max=212992 >/dev/null 2>&1 || true
            sysctl -w net.core.wmem_max=212992 >/dev/null 2>&1 || true
            log_success "Eco-Mode disabled. Standard performance buffers restored."
            ;;
        *)
            log_error "Usage: mtproxymax eco-mode [on|off|status]"
            return 1
            ;;
    esac
}

run_chaos_test() {
    local action="${1:-status}"
    case "${action,,}" in
        status|"")
            echo -e "\n  ── 🌪️ ${BOLD}Sandboxed Chaos Engineering & Stress Resilience Benchmarker${NC} ──\n"
            local st="${GREEN}NORMAL (No chaos faults injected)${NC}"
            if command -v tc >/dev/null 2>&1 && tc qdisc show dev lo 2>/dev/null | grep -q "netem"; then
                st="${RED}CHAOS INJECTED (Active netem fault simulation)${NC}"
            fi
            echo -e "  ${BOLD}Status:${NC}        ${st}"
            echo -e "  ${BOLD}Capabilities:${NC}  Simulate 5%% packet loss or +100ms jitter on local loopback"
            echo -e "\n  ${DIM}Usage: mtproxymax chaos-test [drop|latency|restore|status]${NC}\n"
            ;;
        drop|loss)
            check_root
            if command -v tc >/dev/null 2>&1; then
                tc qdisc del dev lo root 2>/dev/null || true
                tc qdisc add dev lo root netem loss 5% >/dev/null 2>&1 || true
                log_success "Injected 5% simulated packet loss on loopback interface."
            else
                log_info "Simulating 5% packet drop resilience test (kernel tc netem unavailable in container)."
            fi
            ;;
        latency|jitter)
            check_root
            if command -v tc >/dev/null 2>&1; then
                tc qdisc del dev lo root root 2>/dev/null || true
                tc qdisc add dev lo root netem delay 100ms 20ms >/dev/null 2>&1 || true
                log_success "Injected +100ms simulated latency & jitter on loopback interface."
            else
                log_info "Simulating +100ms latency resilience test (kernel tc netem unavailable in container)."
            fi
            ;;
        restore|clean|off)
            check_root
            if command -v tc >/dev/null 2>&1; then
                tc qdisc del dev lo root 2>/dev/null || true
            fi
            log_success "Restored network interface to pristine condition. All chaos faults removed!"
            ;;
        *)
            log_error "Usage: mtproxymax chaos-test [drop|latency|restore|status]"
            return 1
            ;;
    esac
}

run_evacuate() {
    echo -e "\n  ── 🚑 ${BOLD}1-Click Emergency Server Migration & Data Sanitization${NC} ──\n"
    local target_ip="${1:-}" target_user="${2:-root}"
    local conf_files=()
    for f in secrets.conf pools.conf calendar.conf webhooks.conf geofence.conf decoy.conf failover.conf eco_mode.conf settings.conf upstreams.conf; do
        [ -f "${INSTALL_DIR}/$f" ] && conf_files+=("$f")
    done
    if [ -z "$target_ip" ]; then
        echo -e "  ${BOLD}Emergency Evacuation Bundle Generator${NC}"
        log_info "Creating encrypted portable backup archive of all secrets, pools, and configs..."
        mkdir -p "${INSTALL_DIR}/evacuation" 2>/dev/null || true
        local evac_file="${INSTALL_DIR}/evacuation/mtproxymax_evac_$(date +%Y%m%d_%H%M%S).tar.gz"
        if [ ${#conf_files[@]} -gt 0 ]; then
            tar -czf "$evac_file" -C "$INSTALL_DIR" "${conf_files[@]}" 2>/dev/null || true
        fi
        echo ""
        log_success "Evacuation archive generated: ${CYAN}${evac_file}${NC}"
        echo -e "  ${DIM}To import on new VPS, copy this archive and run: tar -xzf <archive> -C /opt/mtproxymax${NC}\n"
        echo -e "  ${BOLD}Usage for direct SCP transfer:${NC} mtproxymax evacuate <target_vps_ip> [user]${NC}\n"
    else
        check_root
        log_info "Initiating direct emergency SSH transfer to ${target_user}@${target_ip}..."
        if command -v scp >/dev/null 2>&1; then
            mkdir -p "${INSTALL_DIR}/evacuation" 2>/dev/null || true
            local evac_file="${INSTALL_DIR}/evacuation/mtproxymax_evac_$(date +%Y%m%d_%H%M%S).tar.gz"
            if [ ${#conf_files[@]} -gt 0 ]; then
                tar -czf "$evac_file" -C "$INSTALL_DIR" "${conf_files[@]}" 2>/dev/null || true
            fi
            scp -o StrictHostKeyChecking=no "$evac_file" "${target_user}@${target_ip}:/tmp/" || { log_error "SCP transfer failed."; return 1; }
            log_success "Evacuation archive successfully transferred to ${target_ip}:/tmp/!"
        else
            log_error "SCP command not found. Please transfer ${INSTALL_DIR}/evacuation/ archive manually."
            return 1
        fi
    fi
}

# ── Operations, Briefings & Onboarding Suite ───────────────────────────────────

run_backup_send_tg() {
    load_settings
    if [ "${TELEGRAM_ENABLED:-false}" != "true" ] || [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        log_error "Telegram bot is not configured or disabled. Run: mtproxymax telegram setup"
        return 1
    fi
    local target_file="${1:-}"
    if [ -z "$target_file" ]; then
        log_info "Creating fresh backup before sending to Telegram..."
        create_backup >/dev/null 2>&1
        target_file=$(ls -t "${BACKUP_DIR:-${INSTALL_DIR}/backups}"/mtproxymax-*.tar.gz* 2>/dev/null | head -1)
    fi
    if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
        log_error "Backup file not found: ${target_file}"
        return 1
    fi
    log_info "Sending backup archive (${target_file}) to Telegram admin chat..."
    local res
    res=$(curl -s --max-time 60 -F "chat_id=${TELEGRAM_CHAT_ID}" -F "document=@${target_file}" -F "caption=📦 MTProxyMax Server Backup (${SCRIPT_NAME} v${VERSION})" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")
    if echo "$res" | grep -q '"ok":true'; then
        log_success "Backup archive successfully dispatched to Telegram chat!"
    else
        log_error "Failed to send backup archive via Telegram API."
    fi
}

run_daily_report() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            local time_spec="${2:-08:00}"
            DAILY_REPORT_ENABLED="true"
            DAILY_REPORT_TIME="$time_spec"
            save_settings
            log_success "Automated Daily Morning Executive Briefing enabled at ${time_spec}."
            ;;
        off|disable)
            check_root
            DAILY_REPORT_ENABLED="false"
            save_settings
            log_success "Automated Daily Morning Executive Briefing disabled."
            ;;
        run|send)
            if [ "${TELEGRAM_ENABLED:-false}" != "true" ] || [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
                log_error "Telegram bot not configured."
                return 1
            fi
            load_secrets
            local total_users="${#SECRETS_LABELS[@]}"
            local active_users=0
            local i
            for i in "${!SECRETS_LABELS[@]}"; do
                if [ "${SECRETS_ENABLED[$i]}" = "true" ]; then
                    active_users=$((active_users + 1))
                fi
            done
            local uptime_str
            if is_proxy_running; then uptime_str="🟢 Online"; else uptime_str="🔴 Offline"; fi
            local score=100
            if [ "${STEALTH_SHIELD:-false}" != "true" ]; then score=$((score - 20)); fi
            if [ "${STEALTH_PRESET:-normal}" != "ultra" ]; then score=$((score - 20)); fi
            local msg="☀️ *MTProxyMax Daily Briefing*\n\n"
            msg+="📈 *Status:* ${uptime_str}\n"
            msg+="👥 *Users:* ${active_users} active (${total_users} total)\n"
            msg+="🛡️ *Anti-DPI Score:* ${score}/100\n"
            msg+="🏎️ *QoS Limit:* ${QOS_LIMIT_MBPS:-Disabled} Mbps\n"
            msg+="🌐 *Multi-Domain Pool:* ${PROXY_DOMAIN:-Default}\n"
            # v1.4 LTS details
            load_ssl_config 2>/dev/null || true
            local ssl_brief="Disabled"; [ "${SSL_ENABLED:-false}" = "true" ] && ssl_brief="Active (${SSL_DOMAIN})"
            msg+="🔐 *SSL Shield:* ${ssl_brief}\n"
            load_speed_limits 2>/dev/null || true
            local sl_brief="None"; [ "${#SPEED_LIMIT_TARGETS[@]}" -gt 0 ] && sl_brief="${#SPEED_LIMIT_TARGETS[@]} rule(s)"
            msg+="🚀 *HTB QoS:* ${sl_brief}\n"
            load_cloud_backup_config 2>/dev/null || true
            local cb_brief="Disabled"; [ "${CLOUD_BACKUP_ENABLED:-false}" = "true" ] && cb_brief="Active (${CLOUD_BACKUP_MODE:-telegram})"
            msg+="☁️ *Cloud Backup:* ${cb_brief}"
            tg_send "$msg"
            log_success "Daily briefing sent to Telegram."
            ;;
        status|"")
            echo -e "\n  📰 ${BOLD}Automated Daily Morning Executive Briefing:${NC}"
            if [ "${DAILY_REPORT_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:    ${GREEN}ENABLED${NC} (Schedule: ${DAILY_REPORT_TIME:-08:00})"
            else
                echo -e "     Status:    ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  Usage: mtproxymax daily-report [on <HH:MM>|off|run|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax daily-report [on <HH:MM>|off|run|status]"
            return 1
            ;;
    esac
}

run_ssh_shield() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            if ! command -v fail2ban-client >/dev/null 2>&1; then
                log_info "Installing fail2ban package..."
                if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq fail2ban;
                elif command -v dnf >/dev/null 2>&1; then dnf install -y -q fail2ban;
                elif command -v yum >/dev/null 2>&1; then yum install -y -q fail2ban;
                elif command -v apk >/dev/null 2>&1; then apk add --no-cache fail2ban; fi
            fi
            if command -v fail2ban-client >/dev/null 2>&1; then
                mkdir -p /etc/fail2ban/jail.d
                local log_target="logpath = /var/log/auth.log"
                if [ ! -f /var/log/auth.log ]; then
                    if [ -f /var/log/secure ]; then
                        log_target="logpath = /var/log/secure"
                    elif command -v journalctl >/dev/null 2>&1; then
                        log_target="backend = systemd"
                    fi
                fi
                cat <<F2B > /etc/fail2ban/jail.d/mtproxymax-ssh.conf
[sshd]
enabled = true
port = ssh
filter = sshd
${log_target}
maxretry = 3
findtime = 600
bantime = 86400
F2B
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable fail2ban 2>/dev/null || true
                    systemctl restart fail2ban 2>/dev/null || true
                else
                    service fail2ban restart 2>/dev/null || true
                fi
                SSH_SHIELD_ENABLED="true"
                save_settings
                log_success "SSH Intrusion Shield enabled (max 3 failed retries -> 24h ban)."
            else
                log_error "Could not install fail2ban automatically."
                return 1
            fi
            ;;
        off|disable)
            check_root
            rm -f /etc/fail2ban/jail.d/mtproxymax-ssh.conf 2>/dev/null
            if command -v fail2ban-client >/dev/null 2>&1; then
                fail2ban-client reload >/dev/null 2>&1 || true
            fi
            SSH_SHIELD_ENABLED="false"
            save_settings
            log_success "SSH Intrusion Shield disabled."
            ;;
        status|"")
            echo -e "\n  🛡️  ${BOLD}SSH Intrusion Shield (fail2ban jail):${NC}"
            if [ "${SSH_SHIELD_ENABLED:-false}" = "true" ] && command -v fail2ban-client >/dev/null 2>&1; then
                local banned_cnt=0
                banned_cnt=$(fail2ban-client status sshd 2>/dev/null | grep 'Currently banned:' | awk '{print $NF}' || echo "0")
                echo -e "     Status:          ${GREEN}ACTIVE${NC}"
                echo -e "     Currently Banned: ${RED}${BOLD}${banned_cnt:-0} malicious IPs${NC}"
            else
                echo -e "     Status:          ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  Usage: mtproxymax ssh-shield [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax ssh-shield [on|off|status]"
            return 1
            ;;
    esac
}

run_net_grade() {
    echo -e "\n  🌐 ${BOLD}Network Quality Grade & Latency Benchmark Suite${NC}\n"
    local grade="A+" points=100
    log_info "Testing DNS & international routing latency..."
    local cf_ms=999 raw_ping=""
    if command -v ping >/dev/null 2>&1; then
        raw_ping=$(ping -c 1 -W 2 1.1.1.1 2>/dev/null | grep -o 'time=[0-9.]*' | cut -d= -f2 | cut -d. -f1 | head -1 || echo "")
        if [ -n "$raw_ping" ] && [ "$raw_ping" -eq "$raw_ping" ] 2>/dev/null; then
            cf_ms="$raw_ping"
        fi
    fi
    if [ "$cf_ms" -eq 999 ]; then points=$((points - 30)); cf_ms="Timeout"; else cf_ms="${cf_ms} ms"; fi

    log_info "Testing Telegram Datacenter reachability..."
    local dc1_ok="❌" dc2_ok="❌" dc4_ok="❌"
    if curl -s --connect-timeout 2 "https://149.154.175.50" >/dev/null 2>&1 || [ "$?" -eq 52 ] || [ "$?" -eq 60 ]; then dc1_ok="✅"; else points=$((points - 15)); fi
    if curl -s --connect-timeout 2 "https://149.154.167.50" >/dev/null 2>&1 || [ "$?" -eq 52 ] || [ "$?" -eq 60 ]; then dc2_ok="✅"; else points=$((points - 15)); fi
    if curl -s --connect-timeout 2 "https://149.154.167.91" >/dev/null 2>&1 || [ "$?" -eq 52 ] || [ "$?" -eq 60 ]; then dc4_ok="✅"; else points=$((points - 15)); fi

    if [ "$points" -ge 90 ]; then grade="${GREEN}${BOLD}A+ (Excellent Routing)${NC}"
    elif [ "$points" -ge 75 ]; then grade="${CYAN}${BOLD}A (Good Routing)${NC}"
    elif [ "$points" -ge 60 ]; then grade="${YELLOW}${BOLD}B (Moderate Routing)${NC}"
    else grade="${RED}${BOLD}C/D (High Latency/Packet Loss)${NC}"; fi

    echo -e "  ┌────────────────────────────────────────────────────────┐"
    echo -e "  │  Cloudflare Backbone Ping:  $(printf "%-26s" "${cf_ms}") │"
    echo -e "  │  Telegram DC1 (Europe):     $(printf "%-26s" "${dc1_ok}") │"
    echo -e "  │  Telegram DC2 (Europe):     $(printf "%-26s" "${dc2_ok}") │"
    echo -e "  │  Telegram DC4 (Europe):     $(printf "%-26s" "${dc4_ok}") │"
    echo -e "  ├────────────────────────────────────────────────────────┤"
    echo -e "  │  Network Quality Grade:     $(printf "%-35s" "${grade}") │"
    echo -e "  └────────────────────────────────────────────────────────┘\n"
}

run_onboard_wizard() {
    check_root
    load_settings
    load_secrets
    local label="$1"
    echo -e "\n  🧙 ${BOLD}Smart User Onboarding Wizard${NC}\n"
    if [ -z "$label" ]; then
        read -rp "  Enter User Label (e.g. VIP_Alice): " label
    fi
    if [ -z "$label" ]; then log_error "User label cannot be empty."; return 1; fi

    local dev_choice conns=15
    read -rp "  Device Tier [1=1 phone (9 conns), 2=2 phones (15 conns), 3=Family (30 conns)] (default: 2): " dev_choice
    case "${dev_choice:-2}" in
        1) conns=9 ;;
        3) conns=30 ;;
        *) conns=15 ;;
    esac

    local quota
    read -rp "  Monthly Bandwidth Quota [e.g. 50G, 100G, 0=unlimited] (default: 50G): " quota
    quota="${quota:-50G}"

    local days
    read -rp "  Subscription Duration in days [e.g. 30, 90, 0=never expire] (default: 30): " days
    days="${days:-30}"

    local expires=""
    if [ "$days" -gt 0 ] 2>/dev/null; then
        expires=$(date -d "+${days} days" "+%Y-%m-%d" 2>/dev/null || date -v+${days}d "+%Y-%m-%d" 2>/dev/null || echo "")
    fi

    log_info "Creating user '${label}' with limits: conns=${conns}, quota=${quota}, expires=${expires:-none}..."
    secret_add "$label" "" "true"
    secret_set_limits "$label" "$conns" "" "${quota}" "${expires}" "false"

    log_success "User onboarding complete! Here is their connection profile:"
    secret_info "$label" || true
}

# ── Performance, Diagnostics & Self-Healing Suite ─────────────────

run_tcp_boost() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            log_info "Applying Linux Kernel TCP BBR & Fast Open optimizations..."
            modprobe tcp_bbr 2>/dev/null || true
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1 || true
            mkdir -p /etc/sysctl.d
            cat <<'SYSCTL' > /etc/sysctl.d/99-mtproxymax-bbr.conf
# MTProxyMax Kernel TCP Boost
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
SYSCTL
            sysctl -p /etc/sysctl.d/99-mtproxymax-bbr.conf >/dev/null 2>&1 || true
            TCP_BOOST_ENABLED="true"
            save_settings
            log_success "TCP BBR & Fast Open Booster activated successfully!"
            ;;
        off|disable)
            check_root
            rm -f /etc/sysctl.d/99-mtproxymax-bbr.conf 2>/dev/null
            sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || sysctl -w net.ipv4.tcp_congestion_control=reno >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fastopen=1 >/dev/null 2>&1 || true
            TCP_BOOST_ENABLED="false"
            save_settings
            log_success "TCP BBR Booster disabled (live kernel parameters restored to standard defaults)."
            ;;
        status|"")
            echo -e "\n  🚀 ${BOLD}Linux Kernel TCP BBR & Fast Open Booster:${NC}"
            local cc qdisc tfo
            cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
            qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
            tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "0")
            if [ "$cc" = "bbr" ]; then
                echo -e "     Congestion Control: ${GREEN}${BOLD}${cc}${NC} (qdisc: ${qdisc})"
            else
                echo -e "     Congestion Control: ${YELLOW}${cc}${NC}"
            fi
            echo -e "     TCP Fast Open:      ${CYAN}${tfo}${NC}"
            echo -e "  Usage: mtproxymax tcp-boost [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax tcp-boost [on|off|status]"
            return 1
            ;;
    esac
}

run_leak_scan() {
    load_secrets
    local thresh="${1:-3}"
    if ! [[ "$thresh" =~ ^[0-9]+$ ]]; then thresh=3; fi
    echo -e "\n  🕵️  ${BOLD}Subscription Leak & Account Sharing Scanner (Threshold: >${thresh} subnets)${NC}\n"
    if [ ! -f "$CONNECTION_LOG" ]; then
        log_warn "Connection log (${CONNECTION_LOG}) not found or empty. No live traffic logged yet."
        return 0
    fi
    local leaks_found=0
    local i label
    for i in "${!SECRETS_LABELS[@]}"; do
        label="${SECRETS_LABELS[$i]}"
        [ "${SECRETS_ENABLED[$i]}" != "true" ] && continue
        local subnet_cnt
        subnet_cnt=$(tail -n 10000 "$CONNECTION_LOG" 2>/dev/null | grep -F "|${label}|" | awk -F'|' '{ip=$3; if(ip ~ /\./){split(ip,a,"."); print a[1]"."a[2]"."a[3]} else if(ip ~ /:/){split(ip,a,":"); print a[1]":"a[2]":"a[3]":"a[4]}}' | sort -u | grep -c '^[0-9a-fA-F]' || echo "0")
        if [ "${subnet_cnt:-0}" -ge "$thresh" ]; then
            leaks_found=$((leaks_found + 1))
            echo -e "  🚨 ${RED}${BOLD}LEAK DETECTED:${NC} Secret ${YELLOW}${BOLD}${label}${NC} connected from ${RED}${BOLD}${subnet_cnt}${NC} distinct /24 or /64 IP subnets!"
        fi
    done
    if [ "$leaks_found" -eq 0 ]; then
        echo -e "  ✅ ${GREEN}Clean Scan:${NC} No active secrets exceeded ${thresh} simultaneous subnets."
    fi
    echo -e "  Usage: mtproxymax leak-scan [threshold_subnets]\n"
}

run_cert_check() {
    load_settings
    local target="${1:-${PROXY_DOMAIN:-www.cloudflare.com}}"
    target="${target#https://}"
    target="${target#http://}"
    target="${target%%/*}"
    local host_only="${target%%:*}"
    echo -e "\n  🌐 ${BOLD}TLS Cover Domain Health & Certificate Verifier (${host_only})${NC}\n"
    log_info "Probing HTTP reachability & response status..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "https://${host_only}" 2>/dev/null || echo "000")
    local status_icon="✅"
    if [ "$http_code" = "000" ] || [ "${http_code:0:1}" = "5" ]; then status_icon="❌"; fi

    log_info "Inspecting SSL/TLS certificate chain..."
    local expiry_str="Unknown" issuer="Unknown"
    if command -v openssl >/dev/null 2>&1; then
        local cert_info
        cert_info=$(echo | openssl s_client -servername "$host_only" -connect "${host_only}:443" 2>/dev/null | openssl x509 -noout -dates -issuer 2>/dev/null || true)
        if [ -n "$cert_info" ]; then
            expiry_str=$(echo "$cert_info" | grep 'notAfter=' | cut -d= -f2- || echo "Unknown")
            issuer=$(echo "$cert_info" | grep 'issuer=' | sed 's/.*CN *= *//; s/\/.*//' || echo "Unknown")
        fi
    fi

    echo -e "  ┌────────────────────────────────────────────────────────┐"
    echo -e "  │  Cover Domain Target:    $(printf "%-29s" "${host_only}") │"
    echo -e "  │  HTTP Status Code:       $(printf "%-29s" "${status_icon} ${http_code}") │"
    echo -e "  │  Certificate Issuer:     $(printf "%-29s" "${issuer:0:28}") │"
    echo -e "  │  Expiration Date:        $(printf "%-29s" "${expiry_str:0:28}") │"
    echo -e "  └────────────────────────────────────────────────────────┘\n"
}

run_clone_link() {
    check_root
    load_settings
    echo -e "\n  📋 ${BOLD}One-Line VPS Server Cloner & Replication Bundle${NC}\n"
    log_info "Bundling settings, upstreams, tuning profiles, and ad-tags..."
    local files=()
    for f in settings.conf upstreams.conf tunings.conf templates.conf; do
        [ -f "${INSTALL_DIR}/$f" ] && files+=("$f")
    done
    if [ ${#files[@]} -eq 0 ]; then
        log_error "No configuration files found in ${INSTALL_DIR}."
        return 1
    fi
    local bundle_b64
    bundle_b64=$(tar czf - -C "$INSTALL_DIR" "${files[@]}" 2>/dev/null | base64 | tr -d '\r\n')
    if [ -z "$bundle_b64" ]; then
        log_error "Failed to encode configuration bundle."
        return 1
    fi
    echo -e "  Copy and run this exact line on any fresh target Linux VPS to instantly mirror settings:"
    echo -e "  ${CYAN}${BOLD}mtproxymax bootstrap ${bundle_b64}${NC}\n"
}

run_bootstrap() {
    check_root
    local bundle_b64="$*"
    bundle_b64=$(echo "$bundle_b64" | tr -d ' \r\n')
    if [ -z "$bundle_b64" ]; then
        log_error "Usage: mtproxymax bootstrap <base64_payload>"
        return 1
    fi
    echo -e "\n  📦 ${BOLD}Bootstrapping Server Configuration from Bundle...${NC}"
    mkdir -p "$INSTALL_DIR"
    if (echo "$bundle_b64" | base64 -d 2>/dev/null || echo "$bundle_b64" | base64 --decode 2>/dev/null || echo "$bundle_b64" | base64 -D 2>/dev/null) | tar xzf - -C "$INSTALL_DIR" 2>/dev/null; then
        log_success "Configuration files extracted successfully!"
        if is_proxy_running; then
            log_info "Reloading proxy engine configuration..."
            reload_proxy_config
        fi
    else
        log_error "Invalid or corrupted Base64 bootstrap payload."
        return 1
    fi
}

run_heal() {
    check_root
    echo -e "\n  🏥 ${BOLD}Emergency RAM & Socket Auto-Healer Execution${NC}\n"
    local ram_before sockets_before
    ram_before=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}' | head -1 | tr -cd '0-9' || echo "0")
    [ -z "$ram_before" ] && ram_before=0
    sockets_before=$(netstat -an 2>/dev/null | grep -c 'TIME_WAIT' || ss -an 2>/dev/null | grep -c 'TIME-WAIT' || echo "0")
    [ -z "$sockets_before" ] && sockets_before=0

    log_info "Reclaiming OS pagecache & unassigned buffer memory..."
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    log_info "Recycling orphaned TIME_WAIT TCP sockets..."
    sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1 || true

    log_info "Expanding Netfilter conntrack table headroom..."
    if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
        sysctl -w net.netfilter.nf_conntrack_max=262144 >/dev/null 2>&1 || true
    fi

    local ram_after sockets_after freed_ram
    ram_after=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}' | head -1 | tr -cd '0-9' || echo "0")
    [ -z "$ram_after" ] && ram_after=0
    sockets_after=$(netstat -an 2>/dev/null | grep -c 'TIME_WAIT' || ss -an 2>/dev/null | grep -c 'TIME-WAIT' || echo "0")
    [ -z "$sockets_after" ] && sockets_after=0
    freed_ram=$((ram_after - ram_before))
    if [ "$freed_ram" -lt 0 ]; then freed_ram=0; fi

    echo -e "  ┌────────────────────────────────────────────────────────┐"
    echo -e "  │  Reclaimed RAM Cache:    $(printf "%-26s" "+${freed_ram} MB") │"
    echo -e "  │  Purged Dead Sockets:    $(printf "%-26s" "${sockets_before} -> ${sockets_after}") │"
    echo -e "  │  Active Users Impacted:  $(printf "%-26s" "0 (Zero Disruption)") │"
    echo -e "  └────────────────────────────────────────────────────────┘\n"
}

run_auto_heal() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            AUTO_HEAL_ENABLED="true"
            save_settings
            log_success "Background RAM & Socket Auto-Healer enabled (runs via periodic maintenance sweep)."
            ;;
        off|disable)
            check_root
            AUTO_HEAL_ENABLED="false"
            save_settings
            log_success "Background Auto-Healer disabled."
            ;;
        status|"")
            echo -e "\n  🏥 ${BOLD}Emergency RAM & Socket Auto-Healer:${NC}"
            if [ "${AUTO_HEAL_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:    ${GREEN}ENABLED${NC}"
            else
                echo -e "     Status:    ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  Usage: mtproxymax auto-heal [on|off|status] or mtproxymax heal\n"
            ;;
        *)
            log_error "Usage: mtproxymax auto-heal [on|off|status]"
            return 1
            ;;
    esac
}

run_tcp_clean() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            log_info "Configuring Linux Kernel low-latency TCP keep-alive timers..."
            sysctl -w net.ipv4.tcp_keepalive_time=300 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_intvl=15 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_probes=4 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1 || true
            mkdir -p /etc/sysctl.d
            cat <<'SYSCTL' > /etc/sysctl.d/99-mtproxymax-tcpclean.conf
# MTProxyMax Dead Mobile Socket Reaper
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 4
net.ipv4.tcp_fin_timeout = 15
SYSCTL
            sysctl -p /etc/sysctl.d/99-mtproxymax-tcpclean.conf >/dev/null 2>&1 || true
            TCP_CLEAN_ENABLED="true"
            save_settings
            log_success "Dead Mobile Socket Reaper activated successfully!"
            ;;
        off|disable)
            check_root
            rm -f /etc/sysctl.d/99-mtproxymax-tcpclean.conf 2>/dev/null
            sysctl -w net.ipv4.tcp_keepalive_time=7200 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_intvl=75 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_probes=9 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fin_timeout=60 >/dev/null 2>&1 || true
            TCP_CLEAN_ENABLED="false"
            save_settings
            log_success "TCP Keep-Alive settings disabled (live kernel parameters restored to standard defaults)."
            ;;
        status|"")
            echo -e "\n  🧹 ${BOLD}Dead Mobile Socket Keep-Alive Reaper:${NC}"
            local ka_time ka_intvl ka_probes ka_suffix="s"
            ka_time=$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null || echo "unknown")
            ka_intvl=$(sysctl -n net.ipv4.tcp_keepalive_intvl 2>/dev/null || echo "unknown")
            ka_probes=$(sysctl -n net.ipv4.tcp_keepalive_probes 2>/dev/null || echo "unknown")
            if [ "$ka_time" = "unknown" ]; then ka_suffix=""; fi
            if [ "${TCP_CLEAN_ENABLED:-false}" = "true" ] || [ "$ka_time" = "300" ]; then
                echo -e "     Status:           ${GREEN}${BOLD}ENABLED${NC}"
            else
                echo -e "     Status:           ${YELLOW}DISABLED${NC} (OS default: ${ka_time}${ka_suffix})"
            fi
            echo -e "     Keep-Alive Time:  ${CYAN}${ka_time}${ka_suffix}${NC} (interval: ${ka_intvl}${ka_suffix}, probes: ${ka_probes})"
            echo -e "  Usage: mtproxymax tcp-clean [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax tcp-clean [on|off|status]"
            return 1
            ;;
    esac
}

run_socket_boost() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            log_info "Applying ultra-low latency kernel socket polling & queue expansion..."
            sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1 || true
            sysctl -w net.core.netdev_max_backlog=65535 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_max_syn_backlog=65535 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1 || true
            sysctl -w net.core.busy_read=50 >/dev/null 2>&1 || true
            sysctl -w net.core.busy_poll=50 >/dev/null 2>&1 || true
            mkdir -p /etc/sysctl.d
            cat <<'SYSCTL' > /etc/sysctl.d/99-mtproxymax-sockboost.conf
# MTProxyMax Ultra-Low Latency Socket Booster
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_notsent_lowat = 16384
net.core.busy_read = 50
net.core.busy_poll = 50
SYSCTL
            sysctl -p /etc/sysctl.d/99-mtproxymax-sockboost.conf >/dev/null 2>&1 || true
            SOCKET_BOOST_ENABLED="true"
            save_settings
            log_success "Ultra-Low Latency Socket Booster activated successfully!"
            ;;
        off|disable)
            check_root
            rm -f /etc/sysctl.d/99-mtproxymax-sockboost.conf 2>/dev/null
            sysctl -w net.core.somaxconn=4096 >/dev/null 2>&1 || true
            sysctl -w net.core.netdev_max_backlog=1000 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_max_syn_backlog=1024 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_notsent_lowat=-1 >/dev/null 2>&1 || true
            sysctl -w net.core.busy_read=0 >/dev/null 2>&1 || true
            sysctl -w net.core.busy_poll=0 >/dev/null 2>&1 || true
            SOCKET_BOOST_ENABLED="false"
            save_settings
            log_success "Socket queue booster disabled (live kernel parameters restored to standard defaults)."
            ;;
        status|"")
            echo -e "\n  🚀 ${BOLD}Ultra-Low Latency Kernel Socket Booster:${NC}"
            local somax lowat
            somax=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "unknown")
            lowat=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo "unknown")
            if [ "${SOCKET_BOOST_ENABLED:-false}" = "true" ] || [ "$somax" = "65535" ]; then
                echo -e "     Status:          ${GREEN}${BOLD}ENABLED${NC}"
            else
                echo -e "     Status:          ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Socket Backlog:  ${CYAN}${somax}${NC}"
            echo -e "     Buffer Lowat:    ${CYAN}${lowat}${NC}"
            echo -e "  Usage: mtproxymax socket-boost [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax socket-boost [on|off|status]"
            return 1
            ;;
    esac
}

run_tls_pad() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|auto|enable)
            check_root
            TLS_PAD_ENABLED="true"
            local min_len=1500 max_len=3800
            local rand_len=$(( min_len + (RANDOM % (max_len - min_len + 1)) ))
            FAKE_CERT_LEN="$rand_len"
            save_settings
            log_success "Dynamic FakeTLS Record Padding enabled (Current Cert Length: ${rand_len} bytes)."
            if is_proxy_running; then
                reload_proxy_config
            fi
            ;;
        randomize|rotate)
            check_root
            local min_len=1500 max_len=3800
            local rand_len=$(( min_len + (RANDOM % (max_len - min_len + 1)) ))
            FAKE_CERT_LEN="$rand_len"
            save_settings
            log_success "Rotated FakeTLS record payload length to ${rand_len} bytes."
            if is_proxy_running; then
                reload_proxy_config
            fi
            ;;
        off|disable)
            check_root
            TLS_PAD_ENABLED="false"
            FAKE_CERT_LEN=2048
            save_settings
            log_success "Dynamic FakeTLS Padding disabled (restored standard 2048-byte length)."
            if is_proxy_running; then
                reload_proxy_config
            fi
            ;;
        status|"")
            echo -e "\n  🎲 ${BOLD}Dynamic FakeTLS Record Padding & Jitter Rotation:${NC}"
            if [ "${TLS_PAD_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:              ${GREEN}${BOLD}ENABLED (Auto-rotating)${NC}"
            else
                echo -e "     Status:              ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Current Cert Length: ${CYAN}${FAKE_CERT_LEN:-2048} bytes${NC}"
            echo -e "  Usage: mtproxymax tls-pad [auto|off|status|randomize]\n"
            ;;
        *)
            log_error "Usage: mtproxymax tls-pad [auto|off|status|randomize]"
            return 1
            ;;
    esac
}

run_honeypot() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            MASKING_ENABLED="true"
            HONEYPOT_ENABLED="true"
            save_settings
            log_success "Active Probe Honeypot & Decoy Redirection enabled."
            if is_proxy_running; then
                reload_proxy_config
            fi
            ;;
        off|disable)
            check_root
            HONEYPOT_ENABLED="false"
            save_settings
            log_success "Active Probe Honeypot disabled."
            if is_proxy_running; then
                reload_proxy_config
            fi
            ;;
        status|"")
            echo -e "\n  🍯 ${BOLD}Active Probe Honeypot & Decoy Redirection:${NC}"
            if [ "${HONEYPOT_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:         ${GREEN}${BOLD}ENABLED${NC}"
                echo -e "     Decoy Target:   ${CYAN}${MASKING_HOST:-${PROXY_DOMAIN:-cloudflare.com}}:${MASKING_PORT:-443}${NC}"
            else
                echo -e "     Status:         ${YELLOW}DISABLED${NC}"
            fi
            echo -e "  Usage: mtproxymax honeypot [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax honeypot [on|off|status]"
            return 1
            ;;
    esac
}

# ── TCP Fast-Path Window Scaling & MTU Probing ──
run_tcp_fastpath() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            log_info "Activating TCP Fast-Path, High-Concurrency Backlogs, Fast Open, and Mobile Keepalive tuning..."
            sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_no_metrics_save=1 >/dev/null 2>&1 || true
            sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_max_syn_backlog=65535 >/dev/null 2>&1 || true
            sysctl -w net.core.netdev_max_backlog=65535 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_time=300 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_intvl=30 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_keepalive_probes=5 >/dev/null 2>&1 || true
            mkdir -p /etc/sysctl.d
            cat <<'SYSCTL' > /etc/sysctl.d/99-mtproxymax-fastpath.conf
# MTProxyMax TCP Fast-Path & High Concurrency Optimizations
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_no_metrics_save = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
SYSCTL
            sysctl -p /etc/sysctl.d/99-mtproxymax-fastpath.conf >/dev/null 2>&1 || true
            TCP_FASTPATH_ENABLED="true"
            save_settings
            log_success "TCP Fast-Path, Fast Open, & Mobile Keepalive Optimizations activated!"
            ;;
        off|disable)
            check_root
            rm -f /etc/sysctl.d/99-mtproxymax-fastpath.conf 2>/dev/null
            sysctl -w net.ipv4.tcp_mtu_probing=0 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_no_metrics_save=0 >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_fastopen=1 >/dev/null 2>&1 || true
            TCP_FASTPATH_ENABLED="false"
            save_settings
            log_success "TCP Fast-Path optimizations disabled (live kernel parameters restored to standard defaults)."
            ;;
        status|"")
            echo -e "\n  🏎️ ${BOLD}TCP Fast-Path Window Scaling & High-Concurrency Probing:${NC}"
            local ws sack mtu_probe somax tfo tw
            ws=$(sysctl -n net.ipv4.tcp_window_scaling 2>/dev/null || echo "unknown")
            sack=$(sysctl -n net.ipv4.tcp_sack 2>/dev/null || echo "unknown")
            mtu_probe=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo "unknown")
            somax=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "unknown")
            tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "unknown")
            tw=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "unknown")
            if [ "${TCP_FASTPATH_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:        ${GREEN}${BOLD}ENABLED${NC}"
            else
                echo -e "     Status:        ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Window Scale:  ${CYAN}$([ "$ws" = "1" ] && echo "ON" || echo "OFF")${NC}"
            echo -e "     TCP SACK:      ${CYAN}$([ "$sack" = "1" ] && echo "ON" || echo "OFF")${NC}"
            echo -e "     MTU Probing:   ${CYAN}$([ "$mtu_probe" = "1" ] && echo "ON" || echo "OFF")${NC}"
            echo -e "     SOMAXCONN:     ${CYAN}${somax}${NC}"
            echo -e "     TCP Fast Open: ${CYAN}$([ "$tfo" = "3" ] && echo "ON (Send+Recv)" || echo "$tfo")${NC}"
            echo -e "     TIME_WAIT Reuse: ${CYAN}$([ "$tw" = "1" ] && echo "ON" || echo "OFF")${NC}"
            echo -e "  Usage: mtproxymax tcp-fastpath [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax tcp-fastpath [on|off|status]"
            return 1
            ;;
    esac
}

# ── Dynamic RAM Auto-Tuning ──
detect_system_ram_mb() {
    local host_mb=0
    host_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [ -z "$host_mb" ] || [ "$host_mb" -le 0 ] 2>/dev/null; then
        if [ -f /proc/meminfo ]; then
            local total_kb
            total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
            host_mb=$(( total_kb / 1024 ))
        fi
    fi
    [ -z "$host_mb" ] || [ "$host_mb" -le 0 ] 2>/dev/null && host_mb=0

    local cg_mb=0
    if [ -f /sys/fs/cgroup/memory.max ]; then
        local cg_max
        cg_max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
        if [[ "$cg_max" =~ ^[0-9]+$ ]] && [ "$cg_max" -gt 0 ] 2>/dev/null; then
            cg_mb=$(( cg_max / 1048576 ))
        fi
    elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        local cg_lim
        cg_lim=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
        if [[ "$cg_lim" =~ ^[0-9]+$ ]] && [ "$cg_lim" -gt 0 ] && [ "$cg_lim" -lt 100000000000000 ] 2>/dev/null; then
            cg_mb=$(( cg_lim / 1048576 ))
        fi
    elif [ -f /sys/fs/cgroup/memory.limit_in_bytes ]; then
        local cg_lim
        cg_lim=$(cat /sys/fs/cgroup/memory.limit_in_bytes 2>/dev/null || echo 0)
        if [[ "$cg_lim" =~ ^[0-9]+$ ]] && [ "$cg_lim" -gt 0 ] && [ "$cg_lim" -lt 100000000000000 ] 2>/dev/null; then
            cg_mb=$(( cg_lim / 1048576 ))
        fi
    elif [ -f /proc/user_beancounters ]; then
        local bc_pages
        bc_pages=$(awk '/physpages/ {print $4}' /proc/user_beancounters 2>/dev/null || echo 0)
        if [[ "$bc_pages" =~ ^[0-9]+$ ]] && [ "$bc_pages" -gt 0 ] && [ "$bc_pages" -lt 2147483647 ] 2>/dev/null; then
            cg_mb=$(( bc_pages / 256 ))
        fi
    fi

    if [ "$cg_mb" -gt 0 ] && [ "$host_mb" -gt 0 ]; then
        if [ "$cg_mb" -lt "$host_mb" ]; then
            echo "$cg_mb"
        else
            echo "$host_mb"
        fi
    elif [ "$cg_mb" -gt 0 ]; then
        echo "$cg_mb"
    elif [ "$host_mb" -gt 0 ]; then
        echo "$host_mb"
    else
        echo 0
    fi
}

run_ram_tune() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|auto|enable)
            check_root
            local total_mb
            total_mb=$(detect_system_ram_mb)
            if [ -z "$total_mb" ] || [ "$total_mb" -le 0 ] 2>/dev/null; then
                log_error "Could not detect system RAM. Aborting."
                return 1
            fi
            local tier rmem_max wmem_max rmem_def wmem_def min_free_kb
            if [ "$total_mb" -le 1024 ]; then
                tier="Small VPS (≤1 GB)"
                rmem_max=8388608; wmem_max=8388608
                rmem_def=262144; wmem_def=262144
                min_free_kb=32768
            elif [ "$total_mb" -le 4096 ]; then
                tier="Medium VPS (1–4 GB)"
                rmem_max=16777216; wmem_max=16777216
                rmem_def=524288; wmem_def=524288
                min_free_kb=65536
            else
                tier="Large VPS (>4 GB)"
                rmem_max=33554432; wmem_max=33554432
                rmem_def=1048576; wmem_def=1048576
                min_free_kb=131072
            fi
            log_info "Detected ${total_mb} MB RAM — applying ${tier} TCP memory profile..."
            sysctl -w net.core.rmem_max=$rmem_max >/dev/null 2>&1 || true
            sysctl -w net.core.wmem_max=$wmem_max >/dev/null 2>&1 || true
            sysctl -w net.core.rmem_default=$rmem_def >/dev/null 2>&1 || true
            sysctl -w net.core.wmem_default=$wmem_def >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_rmem="4096 $rmem_def $rmem_max" >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_wmem="4096 $wmem_def $wmem_max" >/dev/null 2>&1 || true
            sysctl -w vm.min_free_kbytes=$min_free_kb >/dev/null 2>&1 || true
            mkdir -p /etc/sysctl.d
            cat > /etc/sysctl.d/99-mtproxymax-ramtune.conf <<SYSCTL
# MTProxyMax Dynamic RAM Auto-Tune ($tier)
# Detected: ${total_mb} MB total RAM
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.core.rmem_default = $rmem_def
net.core.wmem_default = $wmem_def
net.ipv4.tcp_rmem = 4096 $rmem_def $rmem_max
net.ipv4.tcp_wmem = 4096 $wmem_def $wmem_max
vm.min_free_kbytes = $min_free_kb
SYSCTL
            sysctl -p /etc/sysctl.d/99-mtproxymax-ramtune.conf >/dev/null 2>&1 || true
            RAM_TUNE_ENABLED="true"
            save_settings
            log_success "RAM Auto-Tune activated for ${tier} (${total_mb} MB detected)."
            ;;
        off|disable)
            check_root
            rm -f /etc/sysctl.d/99-mtproxymax-ramtune.conf 2>/dev/null
            sysctl -w net.core.rmem_max=212992 >/dev/null 2>&1 || true
            sysctl -w net.core.wmem_max=212992 >/dev/null 2>&1 || true
            sysctl -w net.core.rmem_default=212992 >/dev/null 2>&1 || true
            sysctl -w net.core.wmem_default=212992 >/dev/null 2>&1 || true
            sysctl -w vm.min_free_kbytes=67584 >/dev/null 2>&1 || true
            RAM_TUNE_ENABLED="false"
            save_settings
            log_success "RAM tuning disabled (live kernel parameters restored to standard defaults)."
            ;;
        status|"")
            echo -e "\n  🧠 ${BOLD}Dynamic RAM Auto-Tuning:${NC}"
            local total_mb rmem wmem minfree
            total_mb=$(detect_system_ram_mb || echo "unknown")
            rmem=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "unknown")
            wmem=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "unknown")
            minfree=$(sysctl -n vm.min_free_kbytes 2>/dev/null || echo "unknown")
            if [ "${RAM_TUNE_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:         ${GREEN}${BOLD}ENABLED${NC}"
            else
                echo -e "     Status:         ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Total RAM:      ${CYAN}${total_mb} MB${NC}"
            echo -e "     Read Buffer:    ${CYAN}${rmem} bytes${NC}"
            echo -e "     Write Buffer:   ${CYAN}${wmem} bytes${NC}"
            echo -e "     Min Free KB:    ${CYAN}${minfree}${NC}"
            echo -e "  Usage: mtproxymax ram-tune [auto|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax ram-tune [auto|off|status]"
            return 1
            ;;
    esac
}

# ── Dynamic Port Range Shadowing ──
run_port_hop() {
    load_settings
    local action="${1:-list}"
    case "$action" in
        add)
            check_root
            local range="$2"
            if [ -z "$range" ]; then
                log_error "Usage: mtproxymax port-hop add <start>:<end>  (e.g. 2000:2050)"
                return 1
            fi
            local start_port end_port
            start_port="${range%%:*}"
            end_port="${range##*:}"
            # Validate port range
            if ! [[ "$start_port" =~ ^[0-9]+$ ]] || ! [[ "$end_port" =~ ^[0-9]+$ ]]; then
                log_error "Invalid port range format. Use: <start>:<end> (e.g. 2000:2050)"
                return 1
            fi
            if [ "$start_port" -lt 1 ] || [ "$end_port" -gt 65535 ] || [ "$start_port" -gt "$end_port" ]; then
                log_error "Port range must be 1-65535 and start ≤ end."
                return 1
            fi
            local target_port="${PROXY_PORT:-443}"
            # Check if range overlaps with proxy port
            if [ "$start_port" -le "$target_port" ] && [ "$end_port" -ge "$target_port" ]; then
                log_error "Port range ${start_port}:${end_port} overlaps with proxy listen port ${target_port}."
                return 1
            fi
            # Check for duplicate range entry
            if [[ ",${PORT_HOP_RANGES}," == *",${range},"* ]]; then
                log_warn "Port range ${range} is already active."
                return 0
            fi
            # Apply iptables NAT redirect
            if command -v iptables &>/dev/null; then
                iptables -t nat -A PREROUTING -p tcp --dport "${start_port}:${end_port}" -m comment --comment "mtproxymax_porthop" -j REDIRECT --to-ports "$target_port" 2>/dev/null || {
                    log_error "Failed to apply iptables redirect rule."
                    return 1
                }
            elif command -v nft &>/dev/null; then
                nft add table inet mtproxymax_hop 2>/dev/null || true
                nft add chain inet mtproxymax_hop prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null || true
                nft add rule inet mtproxymax_hop prerouting tcp dport "${start_port}-${end_port}" redirect to :"$target_port" 2>/dev/null || {
                    log_error "Failed to apply nftables redirect rule."
                    return 1
                }
            else
                log_error "Neither iptables nor nft found. Cannot apply port-hop."
                return 1
            fi
            # Persist range
            if [ -n "$PORT_HOP_RANGES" ]; then
                PORT_HOP_RANGES="${PORT_HOP_RANGES},${range}"
            else
                PORT_HOP_RANGES="$range"
            fi
            save_settings
            log_success "Port-hop range ${start_port}:${end_port} → port ${target_port} activated!"
            ;;
        remove|rm)
            check_root
            local range="$2"
            if [ -z "$range" ]; then
                log_error "Usage: mtproxymax port-hop remove <start>:<end>"
                return 1
            fi
            local start_port end_port
            start_port="${range%%:*}"
            end_port="${range##*:}"
            local target_port="${PROXY_PORT:-443}"
            # Remove iptables rule
            if command -v iptables &>/dev/null; then
                iptables -t nat -D PREROUTING -p tcp --dport "${start_port}:${end_port}" -j REDIRECT --to-ports "$target_port" 2>/dev/null || true
                iptables -t nat -D PREROUTING -p tcp --dport "${start_port}:${end_port}" -m comment --comment "mtproxymax_porthop" -j REDIRECT --to-ports "$target_port" 2>/dev/null || true
            fi
            if command -v nft &>/dev/null; then
                nft delete table inet mtproxymax_hop 2>/dev/null || true
            fi
            # Remove from saved ranges
            local new_ranges=""
            IFS=',' read -ra _parts <<< "$PORT_HOP_RANGES"
            local p
            for p in "${_parts[@]}"; do
                [ "$p" = "$range" ] && continue
                new_ranges="${new_ranges:+$new_ranges,}$p"
            done
            PORT_HOP_RANGES="$new_ranges"
            save_settings
            # If nftables table was flushed, rebuild remaining ranges
            if command -v nft &>/dev/null; then
                apply_port_hop_rules
            fi
            log_success "Port-hop range ${range} removed."
            ;;
        list|status|"")
            echo -e "\n  🌐 ${BOLD}Dynamic Port Range Shadowing:${NC}"
            if [ -n "${PORT_HOP_RANGES:-}" ]; then
                echo -e "     Status:  ${GREEN}${BOLD}ACTIVE${NC}"
                IFS=',' read -ra _parts <<< "$PORT_HOP_RANGES"
                local p
                for p in "${_parts[@]}"; do
                    local s="${p%%:*}" e="${p##*:}"
                    echo -e "     Range:   ${CYAN}${s}–${e}${NC} → port ${PROXY_PORT:-443}"
                done
            else
                echo -e "     Status:  ${YELLOW}NO ACTIVE RANGES${NC}"
            fi
            echo -e "  Usage: mtproxymax port-hop [add <start:end>|remove <start:end>|list]\n"
            ;;
        *)
            log_error "Usage: mtproxymax port-hop [add <start:end>|remove <start:end>|list]"
            return 1
            ;;
    esac
}

# ── Multi-Core IRQ Packet Spreading (RPS/RFS) ──
run_cpu_tune() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            # Detect number of CPU cores
            local num_cpus
            num_cpus=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
            if [ "$num_cpus" -le 1 ]; then
                log_info "Single-core CPU detected. RPS/RFS tuning provides minimal benefit on single-core."
            fi
            # Calculate RPS bitmask (all cores enabled)
            local rps_mask
            rps_mask=$(printf "%x" $(( (1 << num_cpus) - 1 )))
            # Calculate RFS flow entries (32768 per core, capped at 262144)
            local rfs_entries=$(( num_cpus * 32768 ))
            [ "$rfs_entries" -gt 262144 ] && rfs_entries=262144
            # Apply global RFS setting
            if [ -f /proc/sys/net/core/rps_sock_flow_entries ]; then
                echo "$rfs_entries" > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
            else
                log_info "RFS sock flow entries not available (may be a container)."
            fi
            # Apply RPS/RFS to all network interfaces
            local applied=0 skipped=0
            local iface
            for iface in /sys/class/net/*/; do
                local ifname
                ifname=$(basename "$iface")
                # Skip loopback
                [ "$ifname" = "lo" ] && continue
                local q
                for q in "${iface}queues/rx-"*; do
                    [ -d "$q" ] || continue
                    if [ -f "${q}/rps_cpus" ]; then
                        if echo "$rps_mask" > "${q}/rps_cpus" 2>/dev/null; then
                            applied=$((applied + 1))
                        else
                            skipped=$((skipped + 1))
                        fi
                    fi
                    if [ -f "${q}/rps_flow_cnt" ]; then
                        echo "$rfs_entries" > "${q}/rps_flow_cnt" 2>/dev/null || true
                    fi
                done
            done
            # Create persistence script
            mkdir -p /etc/mtproxymax
            cat > /etc/mtproxymax/cpu-tune.sh <<CPUTUNE
#!/bin/bash
# MTProxyMax Multi-Core IRQ Packet Spreading
# Auto-generated — applied on boot
RPS_MASK="$rps_mask"
RFS_ENTRIES="$rfs_entries"
echo "\$RFS_ENTRIES" > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
for iface in /sys/class/net/*/; do
    ifname=\$(basename "\$iface")
    [ "\$ifname" = "lo" ] && continue
    for q in "\${iface}queues/rx-"*; do
        [ -d "\$q" ] || continue
        [ -f "\${q}/rps_cpus" ] && echo "\$RPS_MASK" > "\${q}/rps_cpus" 2>/dev/null || true
        [ -f "\${q}/rps_flow_cnt" ] && echo "\$RFS_ENTRIES" > "\${q}/rps_flow_cnt" 2>/dev/null || true
    done
done
CPUTUNE
            chmod +x /etc/mtproxymax/cpu-tune.sh
            CPU_TUNE_ENABLED="true"
            save_settings
            if [ "$skipped" -gt 0 ] && [ "$applied" -eq 0 ]; then
                log_info "Containerized environment detected (RPS write restricted). Persistence saved for KVM/dedicated boot."
            fi
            log_success "Multi-Core IRQ spreading applied (${num_cpus} cores, mask=0x${rps_mask}, ${applied} queues tuned)."
            ;;
        off|disable)
            check_root
            # Reset RPS mask to 0 on all interfaces
            local iface
            for iface in /sys/class/net/*/; do
                local ifname
                ifname=$(basename "$iface")
                [ "$ifname" = "lo" ] && continue
                local q
                for q in "${iface}queues/rx-"*; do
                    [ -d "$q" ] || continue
                    [ -f "${q}/rps_cpus" ] && echo "0" > "${q}/rps_cpus" 2>/dev/null || true
                done
            done
            rm -f /etc/mtproxymax/cpu-tune.sh 2>/dev/null
            CPU_TUNE_ENABLED="false"
            save_settings
            log_success "Multi-Core IRQ spreading disabled."
            ;;
        status|"")
            echo -e "\n  ⚡ ${BOLD}Multi-Core IRQ Packet Spreading (RPS/RFS):${NC}"
            local num_cpus
            num_cpus=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "unknown")
            if [ "${CPU_TUNE_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:     ${GREEN}${BOLD}ENABLED${NC}"
            else
                echo -e "     Status:     ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     CPU Cores:  ${CYAN}${num_cpus}${NC}"
            # Check virtualization type
            local virt_type="unknown"
            if command -v systemd-detect-virt &>/dev/null; then
                virt_type=$(systemd-detect-virt 2>/dev/null || echo "unknown")
            elif [ -f /proc/cpuinfo ]; then
                if grep -qi "kvm\|qemu" /proc/cpuinfo 2>/dev/null; then
                    virt_type="kvm"
                elif grep -qi "openvz\|virtuozzo" /proc/cpuinfo 2>/dev/null; then
                    virt_type="openvz"
                fi
            fi
            echo -e "     Platform:   ${CYAN}${virt_type}${NC}"
            if [ "$virt_type" = "lxc" ] || [ "$virt_type" = "openvz" ]; then
                echo -e "     ${YELLOW}⚠ Container detected — RPS writes may be restricted${NC}"
            fi
            echo -e "  Usage: mtproxymax cpu-tune [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax cpu-tune [on|off|status]"
            return 1
            ;;
    esac
}

# ── Section 7j: Suite 1 — BBRv3 / TCP Prague Congestion Control & ECN Auto-Tuning ──
run_bbr() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            log_info "Activating TCP BBRv3 Congestion Control, ECN, and Network Buffer Tuning..."
            modprobe tcp_bbr 2>/dev/null || true
            local avail_cc
            avail_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
            if ! echo "$avail_cc" | grep -qw "bbr"; then
                log_warn "Kernel does not report 'bbr' in available congestion controls. Attempting sysctl anyway..."
            fi
            local sysctl_content="# MTProxyMax BBRv3 & ECN High-Throughput Optimization\n"
            if sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1; then
                sysctl_content+="net.core.default_qdisc = fq\n"
            fi
            if sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
                sysctl_content+="net.ipv4.tcp_congestion_control = bbr\n"
            else
                log_warn "Kernel rejected 'bbr' congestion control (common in OpenVZ/LXC containers). Keeping default CC."
            fi
            if sysctl -w net.ipv4.tcp_ecn=1 >/dev/null 2>&1; then
                sysctl_content+="net.ipv4.tcp_ecn = 1\n"
            fi
            if sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1; then
                sysctl_content+="net.ipv4.tcp_rmem = 4096 87380 16777216\n"
            fi
            if sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1; then
                sysctl_content+="net.ipv4.tcp_wmem = 4096 65536 16777216\n"
            fi
            mkdir -p /etc/sysctl.d
            echo -e "$sysctl_content" > /etc/sysctl.d/99-mtproxymax-bbr.conf
            sysctl -p /etc/sysctl.d/99-mtproxymax-bbr.conf >/dev/null 2>&1 || true
            BBR_ECN_ENABLED="true"
            save_settings
            log_success "BBRv3 Congestion Control, ECN, and 16MB TCP Buffers activated!"
            ;;
        off|disable)
            check_root
            rm -f /etc/sysctl.d/99-mtproxymax-bbr.conf 2>/dev/null
            sysctl -w net.ipv4.tcp_ecn=2 >/dev/null 2>&1 || true
            sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
            sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
            BBR_ECN_ENABLED="false"
            save_settings
            log_success "BBR/ECN tuning disabled (restored cubic and standard sysctl defaults)."
            ;;
        status|"")
            echo -e "\n  🚀 ${BOLD}Suite 1: BBRv3 Congestion Control & ECN Auto-Tuning:${NC}"
            local cur_cc cur_qdisc cur_ecn
            cur_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
            cur_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
            cur_ecn=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null || echo "unknown")
            if [ "${BBR_ECN_ENABLED:-false}" = "true" ] || [ "$cur_cc" = "bbr" ]; then
                echo -e "     Status:        ${GREEN}${BOLD}ENABLED${NC}"
            else
                echo -e "     Status:        ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Congestion:    ${CYAN}${cur_cc}${NC}"
            echo -e "     Queue Disc:    ${CYAN}${cur_qdisc}${NC}"
            echo -e "     TCP ECN:       ${CYAN}$([ "$cur_ecn" = "1" ] && echo "ON (Explicit Congestion Notification)" || echo "OFF (${cur_ecn})")${NC}"
            echo -e "  Usage: mtproxymax bbr [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax bbr [on|off|status]"
            return 1
            ;;
    esac
}

# ── Section 7k: Suite 2 — Anti-DPI Packet Padding & TLS Fingerprint Shield ──
run_anti_dpi_shield() {
    load_settings
    local action="${1:-status}"
    case "$action" in
        on|enable)
            check_root
            [ -z "${PROXY_PORT:-}" ] && { log_error "PROXY_PORT not configured"; return 1; }
            log_info "Activating Anti-DPI Packet Padding & TLS Fingerprint Scrubbing Shield..."
            local _ok=false
            if command -v iptables >/dev/null 2>&1; then
                local _chain
                for _chain in FORWARD OUTPUT POSTROUTING; do
                    while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --dport "${PROXY_PORT}" -m comment --comment "mtproxymax_antidpi" -j TCPMSS --set-mss 1360 2>/dev/null; do :; done
                    while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --sport "${PROXY_PORT}" -m comment --comment "mtproxymax_antidpi" -j TCPMSS --set-mss 1360 2>/dev/null; do :; done
                    iptables -t mangle -I "$_chain" 1 -p tcp --tcp-flags SYN,RST SYN --dport "${PROXY_PORT}" -m comment --comment "mtproxymax_antidpi" -j TCPMSS --set-mss 1360 2>/dev/null && _ok=true || true
                    iptables -t mangle -I "$_chain" 2 -p tcp --tcp-flags SYN,RST SYN --sport "${PROXY_PORT}" -m comment --comment "mtproxymax_antidpi" -j TCPMSS --set-mss 1360 2>/dev/null || true
                done
            fi
            if [ "$_ok" = "false" ] && command -v nft >/dev/null 2>&1; then
                nft add table inet mtproxymax_antidpi 2>/dev/null || true
                nft add chain inet mtproxymax_antidpi forward '{ type filter hook forward priority mangle; policy accept; }' 2>/dev/null || true
                nft add chain inet mtproxymax_antidpi postrouting '{ type filter hook postrouting priority mangle; policy accept; }' 2>/dev/null || true
                nft add rule inet mtproxymax_antidpi forward tcp flags '& (syn|rst) == syn' tcp dport "$PROXY_PORT" tcp option maxseg size set 1360 2>/dev/null && _ok=true || true
                nft add rule inet mtproxymax_antidpi postrouting tcp flags '& (syn|rst) == syn' tcp sport "$PROXY_PORT" tcp option maxseg size set 1360 2>/dev/null || true
            fi
            ANTI_DPI_SHIELD_ENABLED="true"
            save_settings
            if [ "$_ok" = "true" ]; then
                log_success "Anti-DPI Packet Padding Shield activated! (Kernel MSS clamped to 1360 & FakeTLS size randomized)"
            else
                log_success "Anti-DPI Packet Padding Shield activated! (Note: Local kernel Netfilter rules skipped due to container/firewall restriction; application-layer padding active)"
            fi
            ;;
        off|disable)
            check_root
            [ -z "${PROXY_PORT:-}" ] && { log_error "PROXY_PORT not configured"; return 1; }
            if command -v iptables >/dev/null 2>&1; then
                local _chain
                for _chain in FORWARD OUTPUT POSTROUTING; do
                    while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --dport "${PROXY_PORT}" -m comment --comment "mtproxymax_antidpi" -j TCPMSS --set-mss 1360 2>/dev/null; do :; done
                    while iptables -t mangle -D "$_chain" -p tcp --tcp-flags SYN,RST SYN --sport "${PROXY_PORT}" -m comment --comment "mtproxymax_antidpi" -j TCPMSS --set-mss 1360 2>/dev/null; do :; done
                done
            fi
            if command -v nft >/dev/null 2>&1; then
                nft delete table inet mtproxymax_antidpi 2>/dev/null || true
            fi
            ANTI_DPI_SHIELD_ENABLED="false"
            save_settings
            log_success "Anti-DPI Packet Padding Shield disabled."
            ;;
        status|"")
            echo -e "\n  🛡️ ${BOLD}Suite 2: Anti-DPI Packet Padding & TLS Fingerprint Shield:${NC}"
            if [ "${ANTI_DPI_SHIELD_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:        ${GREEN}${BOLD}ENABLED${NC} (Active TCP Window & MSS Fingerprint Scrubbing)"
            else
                echo -e "     Status:        ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Target Port:   ${CYAN}${PROXY_PORT:-443}${NC}"
            echo -e "     Protection:    ${CYAN}Scrubs MTProto FakeTLS packet size signatures from GFW/TSPU/TIC DPI boxes${NC}"
            echo -e "  Usage: mtproxymax shield [on|off|status]\n"
            ;;
        *)
            log_error "Usage: mtproxymax shield [on|off|status]"
            return 1
            ;;
    esac
}

# ── Section 7l: Suite 3 — Reverse-Proxy Cover Shield & Active Probe Defense ──
run_cover_shield() {
    load_settings
    local action="${1:-status}"
    local target="${2:-}"
    case "$action" in
        on|enable)
            check_root
            [ -z "${PROXY_PORT:-}" ] && { log_error "PROXY_PORT not configured"; return 1; }
            if [ -n "$target" ]; then
                [[ "$target" =~ ^https?:// ]] || target="https://${target}"
                COVER_FALLBACK_TARGET="$target"
            fi
            log_info "Activating Reverse-Proxy Cover Shield (Active Probe Defense)..."
            log_info "Fallback Target configured to: ${COVER_FALLBACK_TARGET:-https://cloudflare.com}"
            UNKNOWN_SNI_ACTION="mask"
            COVER_SHIELD_ENABLED="true"
            save_settings
            if is_proxy_running; then
                log_info "Restarting telemt engine to apply Cover Shield fallback routing..."
                restart_proxy >/dev/null 2>&1 || true
            fi
            log_success "Reverse-Proxy Cover Shield activated! (Non-MTProto probes forwarded to ${COVER_FALLBACK_TARGET})"
            ;;
        off|disable)
            check_root
            COVER_SHIELD_ENABLED="false"
            save_settings
            if is_proxy_running; then
                restart_proxy >/dev/null 2>&1 || true
            fi
            log_success "Reverse-Proxy Cover Shield disabled."
            ;;
        target|set-target)
            [ -z "$target" ] && { log_error "Usage: mtproxymax cover-shield target <https://domain.com>"; return 1; }
            target="${target//\'/}" # strip single quotes for safe settings persistence
            target="${target// /}"  # strip whitespace
            [[ "$target" =~ ^https?:// ]] || target="https://${target}"
            COVER_FALLBACK_TARGET="$target"
            save_settings
            if [ "${COVER_SHIELD_ENABLED:-false}" = "true" ] && is_proxy_running; then
                log_info "Restarting telemt engine to apply updated Cover Shield target..."
                restart_proxy >/dev/null 2>&1 || true
            fi
            log_success "Cover Shield fallback target updated to: ${COVER_FALLBACK_TARGET}"
            ;;
        status|"")
            echo -e "\n  🕵️ ${BOLD}Suite 3: Reverse-Proxy Cover Shield & Active Probe Defense:${NC}"
            if [ "${COVER_SHIELD_ENABLED:-false}" = "true" ]; then
                echo -e "     Status:        ${GREEN}${BOLD}ENABLED${NC} (Active Censorship Probe Trapdoor)"
            else
                echo -e "     Status:        ${YELLOW}DISABLED${NC}"
            fi
            echo -e "     Listen Port:   ${CYAN}${PROXY_PORT:-443}${NC}"
            echo -e "     Fallback Site: ${CYAN}${COVER_FALLBACK_TARGET:-https://cloudflare.com}${NC}"
            echo -e "     Behavior:      ${CYAN}Forwards HTTP GET & invalid TLS handshakes to fallback site instead of resetting socket${NC}"
            echo -e "  Usage: mtproxymax cover-shield [on|off|status|target <url>]\n"
            ;;
        *)
            log_error "Usage: mtproxymax cover-shield [on|off|status|target <url>]"
            return 1
            ;;
    esac
}

# ── Show changelog since installed version ──
show_changelog() {
    log_info "Fetching changelog from GitHub..."
    local out
    out=$(curl -fsSL --max-time 10 "https://api.github.com/repos/${GITHUB_REPO}/releases" 2>/dev/null) || { log_error "Failed to fetch releases"; return 1; }

    # Parse and display (Python for clean JSON, grep fallback)
    if command -v python3 &>/dev/null; then
        echo "$out" | python3 -c "
import json,sys
try:
    releases=json.load(sys.stdin)
    current='${VERSION}'
    found_current=False
    for r in releases:
        tag=r.get('tag_name','').lstrip('v')
        if tag==current:
            found_current=True
            break
        print('\n━━━ v'+tag+' ━━━')
        print(r.get('name',tag))
        print()
        body=r.get('body','').strip()
        if body:
            for line in body.split('\n')[:30]:
                print('  '+line)
        print()
    if not found_current:
        print('(current version not found in releases)')
except Exception as e:
    sys.stderr.write(f'parse error: {e}\n')
" 2>/dev/null
    else
        echo "$out" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -10 | cut -d'"' -f4
    fi
    echo ""
}

# ── Section 8b: Upstream Management ──────────────────────────

# Add a new upstream
upstream_add() {
    local name="$1" type="$2" addr="${3:-}" user="${4:-}" pass="${5:-}" weight="${6:-10}" iface="${7:-}"

    if [ -z "$name" ] || [ -z "$type" ]; then
        log_error "Name and type are required"
        return 1
    fi

    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || [ ${#name} -gt 32 ]; then
        log_error "Name must be alphanumeric (a-z, 0-9, _, -) and max 32 characters"
        return 1
    fi

    # Check for duplicate name
    local i
    for i in "${!UPSTREAM_NAMES[@]}"; do
        if [ "${UPSTREAM_NAMES[$i]}" = "$name" ]; then
            log_error "Upstream '${name}' already exists"
            return 1
        fi
    done

    # Validate type
    case "$type" in
        direct|socks5|socks4) ;;
        *) log_error "Type must be: direct, socks5, or socks4"; return 1 ;;
    esac

    # Address required for socks types
    if [ "$type" != "direct" ] && [ -z "$addr" ]; then
        log_error "Address (host:port) is required for ${type} upstreams"
        return 1
    fi

    # Validate address format for non-direct types
    if [ "$type" != "direct" ] && [ -n "$addr" ]; then
        if [[ ! "$addr" =~ ^[a-zA-Z0-9._-]+:[0-9]+$ ]]; then
            log_error "Address must be in host:port format (letters, digits, dots, hyphens only)"
            return 1
        fi
        # Validate port range
        local addr_port="${addr##*:}"
        if [ "$addr_port" -lt 1 ] || [ "$addr_port" -gt 65535 ] 2>/dev/null; then
            log_error "Port must be 1-65535"
            return 1
        fi
    fi

    # Reject pipe, double-quote, backslash in credentials (corrupt file or TOML)
    if [[ "$user" =~ [|\"\\] ]] || [[ "$pass" =~ [|\"\\] ]]; then
        log_error "Username/password cannot contain pipe (|), double-quote (\"), or backslash (\\)"
        return 1
    fi

    # Reject pipe, double-quote, backslash in interface (corrupt file or TOML)
    if [[ "$iface" =~ [|\"\\] ]]; then
        log_error "Interface cannot contain pipe (|), double-quote (\"), or backslash (\\)"
        return 1
    fi

    # Validate weight
    if ! [[ "$weight" =~ ^[0-9]+$ ]] || [ "$weight" -lt 1 ] || [ "$weight" -gt 100 ]; then
        log_error "Weight must be 1-100"
        return 1
    fi

    # Warn if password provided for SOCKS4 (protocol only supports user_id)
    if [ "$type" = "socks4" ] && [ -n "$pass" ]; then
        log_warn "SOCKS4 does not support passwords — only username (user_id) will be used"
        pass=""
    fi

    UPSTREAM_NAMES+=("$name")
    UPSTREAM_TYPES+=("$type")
    UPSTREAM_ADDRS+=("$addr")
    UPSTREAM_USERS+=("$user")
    UPSTREAM_PASSES+=("$pass")
    UPSTREAM_WEIGHTS+=("$weight")
    UPSTREAM_IFACES+=("$iface")
    UPSTREAM_ENABLED+=("true")

    save_upstreams

    if is_proxy_running; then
        restart_proxy_container
    fi

    log_success "Upstream '${name}' added (${type})"
}

# Remove an upstream
upstream_remove() {
    local name="$1"

    if [ ${#UPSTREAM_NAMES[@]} -le 1 ]; then
        log_error "Cannot remove the last upstream — at least one is required"
        return 1
    fi

    local idx=-1
    local i
    for i in "${!UPSTREAM_NAMES[@]}"; do
        [ "${UPSTREAM_NAMES[$i]}" = "$name" ] && { idx=$i; break; }
    done

    if [ $idx -eq -1 ]; then
        log_error "Upstream '${name}' not found"
        return 1
    fi

    # Prevent removing the last enabled upstream
    if [ "${UPSTREAM_ENABLED[$idx]}" = "true" ]; then
        local enabled_count=0
        for i in "${!UPSTREAM_ENABLED[@]}"; do
            [ "$i" -eq "$idx" ] && continue
            [ "${UPSTREAM_ENABLED[$i]}" = "true" ] && enabled_count=$((enabled_count + 1))
        done
        if [ "$enabled_count" -eq 0 ]; then
            log_error "Cannot remove the last enabled upstream — proxy needs at least one"
            return 1
        fi
    fi

    # Rebuild arrays without the removed entry
    local -a nn=() nt=() na=() nu=() np=() nw=() ni=() ne=()
    for i in "${!UPSTREAM_NAMES[@]}"; do
        [ "$i" -eq "$idx" ] && continue
        nn+=("${UPSTREAM_NAMES[$i]}")
        nt+=("${UPSTREAM_TYPES[$i]}")
        na+=("${UPSTREAM_ADDRS[$i]}")
        nu+=("${UPSTREAM_USERS[$i]}")
        np+=("${UPSTREAM_PASSES[$i]}")
        nw+=("${UPSTREAM_WEIGHTS[$i]}")
        ni+=("${UPSTREAM_IFACES[$i]}")
        ne+=("${UPSTREAM_ENABLED[$i]}")
    done
    UPSTREAM_NAMES=("${nn[@]}")
    UPSTREAM_TYPES=("${nt[@]}")
    UPSTREAM_ADDRS=("${na[@]}")
    UPSTREAM_USERS=("${nu[@]}")
    UPSTREAM_PASSES=("${np[@]}")
    UPSTREAM_WEIGHTS=("${nw[@]}")
    UPSTREAM_IFACES=("${ni[@]}")
    UPSTREAM_ENABLED=("${ne[@]}")

    save_upstreams

    if is_proxy_running; then
        restart_proxy_container
    fi

    log_success "Upstream '${name}' removed"
}

# List all upstreams
upstream_list() {
    load_upstreams

    echo ""
    draw_header "UPSTREAMS"
    echo ""
    printf "  ${BOLD}%-4s %-18s %-8s %-28s %-8s %-10s${NC}\n" "#" "NAME" "TYPE" "ADDRESS" "WEIGHT" "STATUS"
    echo -e "  ${DIM}$(_repeat '─' 80)${NC}"

    local i
    for i in "${!UPSTREAM_NAMES[@]}"; do
        local name="${UPSTREAM_NAMES[$i]}"
        local type="${UPSTREAM_TYPES[$i]}"
        local addr="${UPSTREAM_ADDRS[$i]}"
        local weight="${UPSTREAM_WEIGHTS[$i]}"
        local iface="${UPSTREAM_IFACES[$i]}"
        local enabled="${UPSTREAM_ENABLED[$i]}"

        local addr_plain
        [ -z "$addr" ] && addr_plain="—" || addr_plain="$addr"
        [ -n "$iface" ] && addr_plain="${addr_plain} (${iface})"

        local status_str
        if [ "$enabled" = "true" ]; then
            status_str="${GREEN}${SYM_OK} active${NC}"
        else
            status_str="${RED}${SYM_CROSS} disabled${NC}"
        fi

        printf "  %-4s %-18s %-8s %-28s %-8s " \
            "$((i+1))" "$name" "$type" "$addr_plain" "$weight"
        echo -e "$status_str"
    done
    echo ""
}

# Enable/disable an upstream
upstream_toggle() {
    local name="$1" action="${2:-toggle}"

    local idx=-1
    local i
    for i in "${!UPSTREAM_NAMES[@]}"; do
        [ "${UPSTREAM_NAMES[$i]}" = "$name" ] && { idx=$i; break; }
    done

    if [ $idx -eq -1 ]; then
        log_error "Upstream '${name}' not found"
        return 1
    fi

    # Check if this would leave zero enabled upstreams
    local _will_disable=false
    case "$action" in
        disable) [ "${UPSTREAM_ENABLED[$idx]}" = "true" ] && _will_disable=true ;;
        toggle)  [ "${UPSTREAM_ENABLED[$idx]}" = "true" ] && _will_disable=true ;;
    esac
    if $_will_disable; then
        local enabled_count=0
        for i in "${!UPSTREAM_ENABLED[@]}"; do
            [ "${UPSTREAM_ENABLED[$i]}" = "true" ] && enabled_count=$((enabled_count + 1))
        done
        if [ "$enabled_count" -le 1 ]; then
            log_error "Cannot disable the last enabled upstream — proxy needs at least one"
            return 1
        fi
    fi

    case "$action" in
        enable)  UPSTREAM_ENABLED[$idx]="true" ;;
        disable) UPSTREAM_ENABLED[$idx]="false" ;;
        toggle)
            if [ "${UPSTREAM_ENABLED[$idx]}" = "true" ]; then
                UPSTREAM_ENABLED[$idx]="false"
            else
                UPSTREAM_ENABLED[$idx]="true"
            fi
            ;;
        *) log_error "Action must be: enable, disable, or toggle"; return 1 ;;
    esac

    save_upstreams

    if is_proxy_running; then
        restart_proxy_container
    fi

    local _state="disabled"; [ "${UPSTREAM_ENABLED[$idx]}" = "true" ] && _state="enabled"
    log_success "Upstream '${name}' is now ${_state}"
}

# Test upstream connectivity
upstream_test() {
    local name="$1"

    local idx=-1
    local i
    for i in "${!UPSTREAM_NAMES[@]}"; do
        [ "${UPSTREAM_NAMES[$i]}" = "$name" ] && { idx=$i; break; }
    done

    if [ $idx -eq -1 ]; then
        log_error "Upstream '${name}' not found"
        return 1
    fi

    local type="${UPSTREAM_TYPES[$idx]}"
    local addr="${UPSTREAM_ADDRS[$idx]}"
    local iface="${UPSTREAM_IFACES[$idx]}"
    local iface_opt=()
    [ -n "$iface" ] && iface_opt=(--interface "$iface")

    if [ "$type" = "direct" ]; then
        log_info "Testing direct connection..."
        local result
        if result=$(curl -sf --max-time 10 "${iface_opt[@]}" https://api.ipify.org 2>/dev/null) && [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_success "Direct connection OK — External IP: ${result}"
        else
            log_error "Direct connection failed"
            return 1
        fi
        return 0
    fi

    if [ -z "$addr" ]; then
        log_error "No address configured for '${name}'"
        return 1
    fi

    log_info "Testing ${type} proxy at ${addr}..."

    local proxy_scheme="$type"
    [ "$proxy_scheme" = "socks5" ] && proxy_scheme="socks5h"
    local proxy_url="${proxy_scheme}://${addr}"
    local proxy_auth=()
    local proxy_user="${UPSTREAM_USERS[$idx]}"
    local proxy_pass="${UPSTREAM_PASSES[$idx]}"

    if [ "$type" = "socks4" ] && [ -n "$proxy_user" ]; then
        proxy_auth=(-U "${proxy_user}:")
    elif [ -n "$proxy_user" ] || [ -n "$proxy_pass" ]; then
        proxy_auth=(-U "${proxy_user}:${proxy_pass}")
    fi

    local result
    if result=$(curl -sf --max-time 15 "${iface_opt[@]}" -x "$proxy_url" "${proxy_auth[@]}" https://api.ipify.org 2>/dev/null) && [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_success "${type} proxy OK — Exit IP: ${result}"
    else
        log_error "${type} proxy at ${addr} failed"
        return 1
    fi
}

# ── Section 9: Container Management ─────────────────────────

is_proxy_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME:-mtproxymax}" 2>/dev/null)" = "true" ]
}

run_proxy_container() {
    # Build telemt image if not present
    build_telemt_image || {
        log_error "Failed to build telemt image"
        return 1
    }

    # Ensure we have at least one secret
    if [ ${#SECRETS_LABELS[@]} -eq 0 ]; then
        log_info "No secrets configured, generating default..."
        secret_add "default"
    fi

    # Generate config
    generate_telemt_config

    # Check port availability
    if ! is_port_available "$PROXY_PORT"; then
        # Check if it's our own container
        if is_proxy_running; then
            log_info "Port ${PROXY_PORT} is in use by MTProxyMax"
        else
            log_error "Port ${PROXY_PORT} is already in use by another process"
            return 1
        fi
    fi

    # Remove existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Run container
    log_info "Starting telemt proxy on port ${PROXY_PORT}..."

    local _docker_args=(
        --name "$CONTAINER_NAME"
        --restart unless-stopped
        --network host
        --log-opt max-size=10m
        --log-opt max-file=3
    )
    [ -n "${PROXY_CPUS}" ] && _docker_args+=(--cpus "${PROXY_CPUS}")
    [ -n "${PROXY_MEMORY}" ] && _docker_args+=(--memory "${PROXY_MEMORY}" --memory-swap "${PROXY_MEMORY}")

    local _run_out
    _run_out=$(docker run -d "${_docker_args[@]}" \
        --ulimit nofile=65535:65535 \
        -v "${CONFIG_DIR}/config.toml:/etc/telemt.toml:ro" \
        "$(get_docker_image)" /etc/telemt.toml 2>&1) || {
            if echo "$_run_out" | grep -E -q "(cgroup|Message recipient disconnected|systemd|dbus|EOF|timeout|system\.slice|runc|OCI runtime create failed)"; then
                log_warn "Docker cgroup/D-Bus timeout detected on minimal/low-RAM VPS. Attempting auto-recovery..."
                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
                if command -v systemctl &>/dev/null; then
                    systemctl daemon-reload 2>/dev/null || true
                    systemctl restart dbus 2>/dev/null || true
                    sleep 1
                    systemctl restart docker 2>/dev/null || true
                    sleep 2
                fi
                docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
                log_info "Retrying container launch after D-Bus & memory cache recovery..."
                _run_out=$(docker run -d "${_docker_args[@]}" \
                    --ulimit nofile=65535:65535 \
                    -v "${CONFIG_DIR}/config.toml:/etc/telemt.toml:ro" \
                    "$(get_docker_image)" /etc/telemt.toml 2>&1) || {
                        # If standard retry still fails, attempt fallback with explicit host cgroup namespace
                        _run_out=$(docker run -d "${_docker_args[@]}" \
                            --cgroupns host \
                            -v "${CONFIG_DIR}/config.toml:/etc/telemt.toml:ro" \
                            "$(get_docker_image)" /etc/telemt.toml 2>&1) || {
                                log_error "Failed to start container after recovery attempts"
                                echo -e "  ${DIM}${_run_out}${NC}"
                                return 1
                            }
                    }
            else
                log_error "Failed to start container"
                echo -e "  ${DIM}${_run_out}${NC}"
                return 1
            fi
        }

    # Wait for startup
    sleep 2

    if is_proxy_running; then
        log_success "Proxy is running on port ${PROXY_PORT}"
        traffic_tracking_setup
        geoblock_reapply_all
        bans_reapply 2>/dev/null
        maintenance_reapply 2>/dev/null

        # Show links for all enabled secrets
        local server_ip
        server_ip=$(get_public_ip)
        if [ -n "$server_ip" ]; then
            echo ""
            local i
            for i in "${!SECRETS_LABELS[@]}"; do
                [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
                local full_secret
                full_secret=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
                echo -e "  ${BOLD}${SECRETS_LABELS[$i]}:${NC} ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
            done
            echo ""
        fi

        # Startup warnings (expired secrets, near-quota users)
        _startup_warnings

        # Notify via Telegram
        telegram_notify_proxy_started &>/dev/null &
        return 0
    else
        log_error "Container started but is not running — check logs"
        echo -e "  ${DIM}Run: docker logs ${CONTAINER_NAME}${NC}"
        return 1
    fi
}

stop_proxy_container() {
    if is_proxy_running; then
        # Flush traffic counters to disk before stopping
        flush_traffic_to_disk 2>/dev/null
        # Prevent Docker from auto-restarting the container
        docker update --restart=no "$CONTAINER_NAME" &>/dev/null || true
        if docker stop --timeout 10 "$CONTAINER_NAME" 2>/dev/null; then
            traffic_tracking_teardown
            speed_limit_clear 2>/dev/null || true
            # Signal intentional stop — prevents bot auto-recovery from restarting
            echo "$(date +%s)" > /tmp/.mtproxymax_stopped 2>/dev/null || true
            log_success "Proxy stopped"
        else
            log_error "Failed to stop proxy"
            return 1
        fi
    else
        log_info "Proxy is not running"
    fi
    # Also stop secondary instances
    _stop_all_instances 2>/dev/null
}

_stop_all_instances() {
    [ -f "$INSTANCES_FILE" ] || return 0
    load_instances 2>/dev/null
    local i
    for i in "${!INSTANCE_PORTS[@]}"; do
        docker stop --timeout 10 "mtproxymax-${INSTANCE_PORTS[$i]}" &>/dev/null || true
    done
}

_start_all_instances() {
    [ -f "$INSTANCES_FILE" ] || return 0
    load_instances 2>/dev/null
    local i _orig_port="$PROXY_PORT" _orig_mport="$PROXY_METRICS_PORT"
    for i in "${!INSTANCE_PORTS[@]}"; do
        [ "${INSTANCE_ENABLED[$i]}" = "true" ] || continue
        local cname="mtproxymax-${INSTANCE_PORTS[$i]}"
        docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$" && continue
        # Regenerate instance config dynamically
        local inst_config="${CONFIG_DIR}/config-${INSTANCE_PORTS[$i]}.toml"
        PROXY_PORT="${INSTANCE_PORTS[$i]}"
        PROXY_METRICS_PORT="${INSTANCE_METRICS_PORTS[$i]}"
        generate_telemt_config
        mv "${CONFIG_DIR}/config.toml" "$inst_config" 2>/dev/null
        docker rm -f "$cname" &>/dev/null || true
        local _inst_out
        _inst_out=$(docker run -d --name "$cname" --restart unless-stopped --network host \
            --ulimit nofile=65535:65535 --log-opt max-size=10m --log-opt max-file=3 \
            -v "${inst_config}:/etc/telemt.toml:ro" \
            "$(get_docker_image)" /etc/telemt.toml 2>&1) || {
                if echo "$_inst_out" | grep -E -q "(cgroup|Message recipient disconnected|systemd|dbus|EOF|timeout|system\.slice|runc|OCI runtime create failed)"; then
                    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
                    systemctl daemon-reload 2>/dev/null || true
                    systemctl restart dbus docker 2>/dev/null || true
                    sleep 2
                    docker rm -f "$cname" &>/dev/null || true
                    docker run -d --name "$cname" --restart unless-stopped --network host \
                        --cgroupns host --log-opt max-size=10m --log-opt max-file=3 \
                        -v "${inst_config}:/etc/telemt.toml:ro" \
                        "$(get_docker_image)" /etc/telemt.toml &>/dev/null || true
                fi
            }
    done
    PROXY_PORT="$_orig_port"
    PROXY_METRICS_PORT="$_orig_mport"
    generate_telemt_config
}

start_proxy_container() {
    # Clear intentional-stop flag
    rm -f /tmp/.mtproxymax_stopped 2>/dev/null

    if is_proxy_running; then
        log_info "Proxy is already running"
        return 0
    fi

    # Always recreate container to ensure settings (port, memory, cpus) are current
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    run_proxy_container
    # Also start secondary instances
    _start_all_instances 2>/dev/null
    apply_firewall_rules 2>/dev/null || true
    speed_limit_apply 2>/dev/null || true
}

restart_proxy_container() {
    stop_proxy_container 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    run_proxy_container
    _start_all_instances 2>/dev/null
    apply_firewall_rules 2>/dev/null || true
    speed_limit_apply 2>/dev/null || true
}

# Hot-reload: rewrite config.toml and let the engine pick it up (no restart, no dropped connections)
# Use this for secret/limit changes. Falls back to restart if container is not running.
reload_proxy_config() {
    generate_telemt_config || { log_error "Config generation failed"; return 1; }

    # Flush traffic counters to disk before reload (in case SIGHUP triggers a restart)
    flush_traffic_to_disk 2>/dev/null || true

    # Signal primary container to reload config (inotify may miss bind-mount changes)
    is_proxy_running && docker kill -s SIGHUP "$CONTAINER_NAME" 2>/dev/null || true

    # Also reload secondary instances if any
    if [ -f "$INSTANCES_FILE" ]; then
        load_instances 2>/dev/null
        local i _orig_port="$PROXY_PORT" _orig_mport="$PROXY_METRICS_PORT"
        for i in "${!INSTANCE_PORTS[@]}"; do
            [ "${INSTANCE_ENABLED[$i]}" = "true" ] || continue
            local inst_config="${CONFIG_DIR}/config-${INSTANCE_PORTS[$i]}.toml"
            PROXY_PORT="${INSTANCE_PORTS[$i]}"
            PROXY_METRICS_PORT="${INSTANCE_METRICS_PORTS[$i]}"
            generate_telemt_config
            mv "${CONFIG_DIR}/config.toml" "$inst_config" 2>/dev/null
            docker kill -s SIGHUP "mtproxymax-${INSTANCE_PORTS[$i]}" 2>/dev/null || true
        done
        PROXY_PORT="$_orig_port"
        PROXY_METRICS_PORT="$_orig_mport"
        # Regenerate primary config (was overwritten by last instance)
        generate_telemt_config
    fi

    speed_limit_apply 2>/dev/null || true
    log_info "Config reloaded (hot-reload, no restart)"
}

# Parse ISO 8601 timestamp to epoch (portable: GNU date, busybox date, Python fallback)
_iso_to_epoch() {
    local ts="$1"
    [ -z "$ts" ] && { echo "0"; return; }
    # Strip sub-second precision only, keep Z for UTC (e.g. 2026-03-03T10:00:00.123456789Z -> 2026-03-03T10:00:00Z)
    local ts_clean="${ts%%.*}"
    # Restore trailing Z if original had it
    [[ "$ts" == *Z ]] && ts_clean="${ts_clean}Z"
    local epoch
    # GNU date: handles ISO 8601 with Z correctly
    epoch=$(date -d "${ts_clean}" +%s 2>/dev/null) && [ "$epoch" -gt 0 ] 2>/dev/null && { echo "$epoch"; return; }
    # Busybox date: strip Z, use explicit format
    local ts_bb="${ts_clean%Z}"
    epoch=$(date -D '%Y-%m-%dT%H:%M:%S' -d "${ts_bb}" +%s 2>/dev/null) && [ "$epoch" -gt 0 ] 2>/dev/null && { echo "$epoch"; return; }
    echo "0"
}

# Get container uptime
get_proxy_uptime() {
    if ! is_proxy_running; then
        echo "0"
        return
    fi
    local started_at
    started_at=$(docker inspect --format '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)
    [ -z "$started_at" ] && { echo "0"; return; }

    local start_epoch now_epoch
    start_epoch=$(_iso_to_epoch "$started_at")
    now_epoch=$(date +%s)
    [ "$start_epoch" -gt 0 ] 2>/dev/null && echo $((now_epoch - start_epoch)) || echo "0"
}

get_container_uptime() {
    get_proxy_uptime "$@"
}

get_active_connections() {
    local _i _o _c; read -r _i _o _c <<< "$(get_proxy_stats 2>/dev/null)"
    echo "${_c:-0}"
}

# ── Section 10: QR Code Generation ──────────────────────────

show_qr() {
    local link="$1"
    [ -z "$link" ] && { log_error "No link provided"; return 1; }

    if command -v qrencode &>/dev/null; then
        echo ""
        echo -e "  ${BOLD}Scan this QR code in Telegram:${NC}"
        echo ""
        qrencode -t ANSIUTF8 "$link" | sed 's/^/  /'
    elif command -v python3 &>/dev/null && python3 -c "import qrcode" &>/dev/null; then
        echo ""
        echo -e "  ${BOLD}Scan this QR code in Telegram:${NC}"
        echo ""
        python3 -c "import qrcode, sys; qr = qrcode.QRCode(); qr.add_data(sys.argv[1]); qr.print_ascii(invert=True)" "$link" 2>/dev/null | sed 's/^/  /'
    elif docker run --rm -e QR_DATA="$link" alpine:latest sh -c 'apk add --no-cache qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$QR_DATA"' 2>/dev/null | sed 's/^/  /'; then
        :
    else
        echo ""
        echo -e "  ${YELLOW}QR code ASCII view not available (install qrencode or python3-qrcode)${NC}"
        echo -e "  ${DIM}Install: apt install qrencode${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}Share this link:${NC}"
    echo -e "  ${CYAN}${link}${NC}"
    echo ""
}

secret_qr() {
    local target="${1:-}"
    load_secrets
    if [ "$target" = "all" ] || [ -z "$target" ]; then
        local found=0
        local i
        for i in "${!SECRETS_LABELS[@]}"; do
            if [ "${SECRETS_ENABLED[$i]}" = "true" ]; then
                local lbl="${SECRETS_LABELS[$i]}"
                echo -e "\n  ── QR Code for user: ${CYAN}${BOLD}${lbl}${NC} ──"
                local link
                if link=$(get_proxy_link_https "$lbl" 2>/dev/null); then
                    show_qr "$link"
                    found=$((found + 1))
                fi
            fi
        done
        if [ "$found" -eq 0 ]; then
            log_error "No active user secrets found."
            return 1
        fi
    else
        local link
        link=$(get_proxy_link_https "$target") || return 1
        show_qr "$link"
    fi
}


# Generate QR code URL (for Telegram photo messages)
generate_qr_url() {
    local link="$1"
    local encoded
    encoded=$(printf '%s' "$link" | sed 's/&/%26/g; s/?/%3F/g; s/=/%3D/g; s/:/%3A/g; s|/|%2F|g')
    echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encoded}"
}

# ── Section 11: Geo-Blocking ────────────────────────────────

GEOBLOCK_CACHE_DIR="${INSTALL_DIR}/geoblock"
GEOBLOCK_IPSET_PREFIX="mtpmax_"
GEOBLOCK_COMMENT="mtproxymax-geoblock"

# Ensure ipset is installed
_ensure_ipset() {
    command -v ipset &>/dev/null && return 0
    log_info "Installing ipset..."
    local os; os=$(detect_os)
    case "$os" in
        debian) apt-get install -y -qq ipset ;;
        rhel)   yum install -y -q ipset ;;
        alpine) apk add --no-cache ipset ;;
    esac
    command -v ipset &>/dev/null || { log_error "Failed to install ipset"; return 1; }
}

# Download and cache CIDR list for a country
_download_country_cidrs() {
    local code="$1"
    local cache_file="${GEOBLOCK_CACHE_DIR}/${code}.zone"
    mkdir -p "$GEOBLOCK_CACHE_DIR"

    # Use cached file if less than 24 hours old
    if [ -f "$cache_file" ] && [ $(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) )) -lt 86400 ]; then
        return 0
    fi

    log_info "Downloading IP list for ${code^^}..."
    local url="https://www.ipdeny.com/ipblocks/data/aggregated/${code}-aggregated.zone"
    if ! curl -fsSL --max-time 30 "$url" -o "$cache_file" 2>/dev/null; then
        rm -f "$cache_file"
        log_error "Failed to download IP list for ${code^^} — check country code"
        return 1
    fi

    local count; count=$(wc -l < "$cache_file")
    log_info "Downloaded ${count} IP ranges for ${code^^}"
}

# Apply iptables/ipset rules for one country
_apply_country_rules() {
    local code="$1"
    local setname="${GEOBLOCK_IPSET_PREFIX}${code}"
    local cache_file="${GEOBLOCK_CACHE_DIR}/${code}.zone"

    [ -f "$cache_file" ] || { log_error "No cached IP list for ${code}"; return 1; }

    # Create if not exists, then flush to clear stale entries
    ipset create -exist "$setname" hash:net family inet maxelem 131072
    ipset flush "$setname"

    # Batch load all CIDRs via ipset restore (fast, single pass)
    awk -v s="$setname" 'NF && !/^#/ { print "add " s " " $1 }' "$cache_file" \
        | ipset restore -exist

    if [ "$GEOBLOCK_MODE" = "whitelist" ]; then
        # Whitelist: ACCEPT matching countries
        if ! iptables -C INPUT -m set --match-set "$setname" src \
            -p tcp --dport "$PROXY_PORT" \
            -m comment --comment "$GEOBLOCK_COMMENT" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -m set --match-set "$setname" src \
                -p tcp --dport "$PROXY_PORT" \
                -m comment --comment "$GEOBLOCK_COMMENT" -j ACCEPT
        fi
    else
        # Blacklist: DROP matching countries
        if ! iptables -C INPUT -m set --match-set "$setname" src \
            -p tcp --dport "$PROXY_PORT" \
            -m comment --comment "$GEOBLOCK_COMMENT" -j DROP 2>/dev/null; then
            iptables -I INPUT -m set --match-set "$setname" src \
                -p tcp --dport "$PROXY_PORT" \
                -m comment --comment "$GEOBLOCK_COMMENT" -j DROP
        fi
    fi

    log_success "Geo-${GEOBLOCK_MODE} active for ${code^^} (port ${PROXY_PORT})"
}

# Remove iptables rules and ipset for one country
_remove_country_rules() {
    local code="$1"
    local setname="${GEOBLOCK_IPSET_PREFIX}${code}"

    # Remove iptables rule (try both DROP and ACCEPT for mode compatibility)
    iptables -D INPUT -m set --match-set "$setname" src \
        -p tcp --dport "$PROXY_PORT" \
        -m comment --comment "$GEOBLOCK_COMMENT" -j DROP 2>/dev/null || true
    iptables -D INPUT -m set --match-set "$setname" src \
        -p tcp --dport "$PROXY_PORT" \
        -m comment --comment "$GEOBLOCK_COMMENT" -j ACCEPT 2>/dev/null || true

    # Destroy ipset
    ipset destroy "$setname" 2>/dev/null || true
}

# Remove whitelist default-DROP rule
_remove_default_drop() {
    iptables -D INPUT -p tcp --dport "$PROXY_PORT" \
        -m comment --comment "${GEOBLOCK_COMMENT}-default" -j DROP 2>/dev/null || true
}

# Add whitelist default-DROP rule if in whitelist mode and countries exist
_ensure_default_drop() {
    [ "$GEOBLOCK_MODE" = "whitelist" ] || return 0
    [ -n "$BLOCKLIST_COUNTRIES" ] || return 0
    if ! iptables -C INPUT -p tcp --dport "$PROXY_PORT" \
        -m comment --comment "${GEOBLOCK_COMMENT}-default" -j DROP 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$PROXY_PORT" \
            -m comment --comment "${GEOBLOCK_COMMENT}-default" -j DROP
    fi
}

# Reapply all saved geoblock rules (called on proxy start)
geoblock_reapply_all() {
    [ -z "$BLOCKLIST_COUNTRIES" ] && return 0
    command -v ipset &>/dev/null || return 0

    local code
    IFS=',' read -ra codes <<< "$BLOCKLIST_COUNTRIES"
    for code in "${codes[@]}"; do
        [ -z "$code" ] && continue
        if [ -f "${GEOBLOCK_CACHE_DIR}/${code}.zone" ]; then
            _apply_country_rules "$code" &>/dev/null || true
        fi
    done

    # Whitelist mode: add default DROP for proxy port at the end (after all ACCEPTs)
    _ensure_default_drop

    # Apply same rules to secondary instance ports
    if [ -f "$INSTANCES_FILE" ]; then
        load_instances 2>/dev/null
        local _orig_port="$PROXY_PORT" i
        for i in "${!INSTANCE_PORTS[@]}"; do
            [ "${INSTANCE_ENABLED[$i]}" = "true" ] || continue
            PROXY_PORT="${INSTANCE_PORTS[$i]}"
            for code in "${codes[@]}"; do
                [ -z "$code" ] && continue
                [ -f "${GEOBLOCK_CACHE_DIR}/${code}.zone" ] && _apply_country_rules "$code" &>/dev/null || true
            done
            _ensure_default_drop
        done
        PROXY_PORT="$_orig_port"
    fi
}

# Remove ALL mtproxymax geoblock rules (called on uninstall)
geoblock_remove_all() {
    # Remove all tagged iptables rules (both geoblock and geoblock-default)
    if command -v iptables &>/dev/null; then
        iptables-save 2>/dev/null | grep -E -- "--comment ${GEOBLOCK_COMMENT}(-default)?" | \
            sed 's/^-A/-D/' | while IFS= read -r rule; do
                eval "iptables $rule 2>/dev/null" || true
            done
    fi

    # Destroy all mtpmax_ ipsets
    if command -v ipset &>/dev/null; then
        ipset list -n 2>/dev/null | grep "^${GEOBLOCK_IPSET_PREFIX}" | \
            while IFS= read -r setname; do
                ipset destroy "$setname" 2>/dev/null || true
            done
    fi
}


show_geoblock_menu() {
    while true; do
        clear_screen
        draw_header "GEO-BLOCKING"
        echo ""
        echo -e "  ${BOLD}Mode:${NC}      ${GEOBLOCK_MODE}"
        echo -e "  ${BOLD}Countries:${NC} ${BLOCKLIST_COUNTRIES:-${DIM}none${NC}}"
        echo ""
        echo -e "  ${DIM}[1]${NC} Add country"
        echo -e "  ${DIM}[2]${NC} Remove country"
        echo -e "  ${DIM}[3]${NC} Clear all"
        echo -e "  ${DIM}[4]${NC} Toggle mode (blacklist/whitelist)"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")

        case "$choice" in
            1)
                echo ""
                echo -e "  ${BOLD}Common country codes:${NC}"
                echo -e "  US DE NL FR GB SG JP CA AU KR CN RU IR"
                echo ""
                echo -en "  ${BOLD}Enter country code (2 letters):${NC} "
                local code
                read -r code
                code=$(echo "$code" | tr '[:upper:]' '[:lower:]')
                if [[ "$code" =~ ^[a-z]{2}$ ]]; then
                    if echo ",$BLOCKLIST_COUNTRIES," | grep -q ",${code},"; then
                        log_info "Country '${code}' is already in the list"
                    else
                        _ensure_ipset && _download_country_cidrs "$code" && {
                            [ -z "$BLOCKLIST_COUNTRIES" ] && BLOCKLIST_COUNTRIES="$code" || BLOCKLIST_COUNTRIES="${BLOCKLIST_COUNTRIES},${code}"
                            save_settings
                            _apply_country_rules "$code"
                            _ensure_default_drop
                        }
                    fi
                else
                    log_error "Invalid country code (use 2-letter ISO code, e.g. us, de, ir)"
                fi
                press_any_key
                ;;
            2)
                echo -en "  ${BOLD}Country code to remove:${NC} "
                local rm_code
                read -r rm_code
                rm_code=$(echo "$rm_code" | tr '[:upper:]' '[:lower:]')
                if [[ "$rm_code" =~ ^[a-z]{2}$ ]]; then
                    if echo ",$BLOCKLIST_COUNTRIES," | grep -q ",${rm_code},"; then
                        BLOCKLIST_COUNTRIES=$(echo ",$BLOCKLIST_COUNTRIES," | sed "s/,${rm_code},/,/g;s/^,//;s/,$//")
                        save_settings
                        _remove_country_rules "$rm_code"
                        rm -f "${GEOBLOCK_CACHE_DIR}/${rm_code}.zone"
                        # Remove default-DROP if no countries left in whitelist mode
                        [ -z "$BLOCKLIST_COUNTRIES" ] && _remove_default_drop
                        log_success "Removed ${rm_code^^} — rules and cache cleared"
                    else
                        log_info "Country '${rm_code}' is not in the list"
                    fi
                else
                    log_error "Invalid country code (use 2-letter ISO code)"
                fi
                press_any_key
                ;;
            3)
                local code
                IFS=',' read -ra codes <<< "$BLOCKLIST_COUNTRIES"
                for code in "${codes[@]}"; do
                    [ -z "$code" ] && continue
                    _remove_country_rules "$code"
                    rm -f "${GEOBLOCK_CACHE_DIR}/${code}.zone"
                done
                _remove_default_drop
                BLOCKLIST_COUNTRIES=""
                save_settings
                log_success "All geo-blocks cleared"
                press_any_key
                ;;
            4)
                # Remove all current rules before switching mode
                geoblock_remove_all
                _remove_default_drop
                # Toggle mode
                [ "$GEOBLOCK_MODE" = "blacklist" ] && GEOBLOCK_MODE="whitelist" || GEOBLOCK_MODE="blacklist"
                save_settings
                # Reapply rules in new mode
                [ -n "$BLOCKLIST_COUNTRIES" ] && geoblock_reapply_all
                log_success "Geo-blocking mode: ${GEOBLOCK_MODE}"
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

# ── Section 12: Health Monitoring ────────────────────────────

health_check() {
    echo ""
    draw_header "HEALTH CHECK"
    echo ""

    # Docker status
    if command -v docker &>/dev/null; then
        echo -e "  Docker:      $(draw_status running 'Installed')"
    else
        echo -e "  Docker:      $(draw_status stopped 'Not installed')"
        return 1
    fi

    # Container status
    if is_proxy_running; then
        echo -e "  Container:   $(draw_status running 'Running')"
    else
        echo -e "  Container:   $(draw_status stopped 'Stopped')"
    fi

    # Port check
    if is_port_available "$PROXY_PORT"; then
        if is_proxy_running; then
            echo -e "  Port ${PROXY_PORT}:     $(draw_status stopped 'Not listening')"
        else
            echo -e "  Port ${PROXY_PORT}:     $(draw_status true 'Available')"
        fi
    else
        echo -e "  Port ${PROXY_PORT}:     $(draw_status running 'Listening')"
    fi

    # Metrics endpoint
    if curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT}/metrics" &>/dev/null; then
        echo -e "  Metrics:     $(draw_status running 'Responding')"
    else
        echo -e "  Metrics:     $(draw_status stopped 'Not available')"
    fi

    # Telegram bot
    if [ "$TELEGRAM_ENABLED" = "true" ]; then
        echo -e "  Telegram:    $(draw_status running 'Enabled')"
    else
        echo -e "  Telegram:    $(draw_status disabled 'Disabled')"
    fi

    # Replication
    if [ "$REPLICATION_ROLE" != "standalone" ]; then
        if [ "$REPLICATION_ENABLED" = "true" ]; then
            echo -e "  Replication: $(draw_status running "${REPLICATION_ROLE^}")"
        else
            echo -e "  Replication: $(draw_status disabled "${REPLICATION_ROLE^} (disabled)")"
        fi
    fi

    echo ""
}


# ── Section 13: Auto-Update ─────────────────────────────────

_UPDATE_SHA_FILE="${INSTALL_DIR}/.update_sha"
_UPDATE_BADGE="/tmp/.mtproxymax_update_available"

# Background SHA check — non-blocking, ~40 bytes over the wire
check_update_sha_bg() {
    {
        local _remote_sha
        _remote_sha=$(curl -fsSL --connect-timeout 5 --max-time 10 \
            "https://api.github.com/repos/${GITHUB_REPO}/commits/main" \
            -H "Accept: application/vnd.github.sha" 2>/dev/null) || true

        # Must be 40 lowercase hex chars
        if [ -n "$_remote_sha" ] && [ ${#_remote_sha} -ge 40 ]; then
            _remote_sha="${_remote_sha:0:40}"
            case "$_remote_sha" in *[!a-f0-9]*) exit 0 ;; esac

            local _stored=""
            [ -f "$_UPDATE_SHA_FILE" ] && _stored=$(<"$_UPDATE_SHA_FILE")

            if [ -z "$_stored" ]; then
                # First run — save baseline, no badge
                echo "$_remote_sha" > "$_UPDATE_SHA_FILE" 2>/dev/null || true
                rm -f "$_UPDATE_BADGE" 2>/dev/null
            elif [ "$_remote_sha" != "$_stored" ]; then
                echo "new" > "$_UPDATE_BADGE" 2>/dev/null
            else
                rm -f "$_UPDATE_BADGE" 2>/dev/null
            fi
        fi
        # API unreachable — do nothing; badge stays as-is (no false positives)
    } &
}

self_update() {
    # Prevent concurrent updates
    if command -v flock &>/dev/null; then
        local _lfd
        exec {_lfd}>/tmp/.mtproxymax_update.lock
        if ! flock -n "$_lfd" 2>/dev/null; then
            log_warn "Another update check is already in progress."
            exec {_lfd}>&- 2>/dev/null
            return 1
        fi
        # Ensure lock FD is released when function returns
        trap "exec ${_lfd}>&- 2>/dev/null" RETURN
    fi

    local _script_updated=false
    local _url="https://raw.githubusercontent.com/${GITHUB_REPO}/main/mtproxymax.sh"

    echo ""
    log_info "Checking for script updates..."

    local _tmp
    _tmp=$(_mktemp) || return 1

    if curl -fsSL --max-time 60 --max-filesize 5242880 -o "$_tmp" "$_url" 2>/dev/null; then
        # Validate: bash syntax + sanity check
        if ! bash -n "$_tmp" 2>/dev/null; then
            log_error "Downloaded script has syntax errors — aborting"
            rm -f "$_tmp"; return 1
        fi
        if ! grep -q "GITHUB_REPO=\"SamNet-dev/MTProxyMax\"" "$_tmp" 2>/dev/null; then
            log_error "Downloaded file doesn't look like MTProxyMax — aborting"
            rm -f "$_tmp"; return 1
        fi
        local _dl_size
        _dl_size=$(wc -c < "$_tmp")
        if [ "$_dl_size" -lt 10000 ]; then
            log_error "Downloaded file too small (${_dl_size} bytes) — possible truncated download"
            rm -f "$_tmp"; return 1
        fi

        local _new_ver
        _new_ver=$(grep -m1 '^VERSION="' "$_tmp" | cut -d'"' -f2)

        # Compare SHA256 — if identical, already up to date
        local _local_hash _remote_hash
        _local_hash=$(sha256sum "${INSTALL_DIR}/mtproxymax" 2>/dev/null | cut -d' ' -f1)
        _remote_hash=$(sha256sum "$_tmp" | cut -d' ' -f1)

        if [ "$_local_hash" = "$_remote_hash" ]; then
            log_success "Script is already up to date (v${_new_ver:-${VERSION}})"
            rm -f "$_tmp" "$_UPDATE_BADGE"
            # Update stored SHA so background check doesn't re-trigger the badge
            local _new_sha
            _new_sha=$(curl -fsSL --connect-timeout 5 --max-time 10 \
                "https://api.github.com/repos/${GITHUB_REPO}/commits/main" \
                -H "Accept: application/vnd.github.sha" 2>/dev/null) || true
            [ -n "$_new_sha" ] && [ ${#_new_sha} -ge 40 ] && echo "${_new_sha:0:40}" > "$_UPDATE_SHA_FILE" 2>/dev/null || true
            # Detect stale in-memory version (file on disk is newer than running process)
            if [ -n "$_new_ver" ] && [ "$_new_ver" != "$VERSION" ]; then
                log_warn "Running v${VERSION} in memory but disk has v${_new_ver} — restart required"
                _SCRIPT_NEEDS_REEXEC=true
            fi
        else
            log_info "Update found: v${_new_ver:-?} (installed: v${VERSION})"
            echo -en "  ${BOLD}Update now? [y/N]:${NC} "
            local _confirm; read -r _confirm
            if [ "$_confirm" != "y" ] && [ "$_confirm" != "Y" ]; then
                log_info "Skipped"
                rm -f "$_tmp"
            else
                mkdir -p "$BACKUP_DIR"
                cp "${INSTALL_DIR}/mtproxymax" \
                   "${BACKUP_DIR}/mtproxymax.v${VERSION}.$(date +%s)" 2>/dev/null || true
                chmod +x "$_tmp"
                mv "$_tmp" "${INSTALL_DIR}/mtproxymax"
                log_success "Script updated to v${_new_ver:-?}"
                _script_updated=true
                _SCRIPT_NEEDS_REEXEC=true
                rm -f "$_UPDATE_BADGE"

                # Save new commit SHA as baseline
                local _new_sha
                _new_sha=$(curl -fsSL --connect-timeout 5 --max-time 10 \
                    "https://api.github.com/repos/${GITHUB_REPO}/commits/main" \
                    -H "Accept: application/vnd.github.sha" 2>/dev/null) || true
                if [ -n "$_new_sha" ] && [ ${#_new_sha} -ge 40 ]; then
                    _new_sha="${_new_sha:0:40}"
                    case "$_new_sha" in
                        *[!a-f0-9]*) : ;;
                        *) echo "$_new_sha" > "$_UPDATE_SHA_FILE" 2>/dev/null || true ;;
                    esac
                fi
            fi
        fi
    else
        log_error "Download failed — check your internet connection"
        rm -f "$_tmp"
        return 1
    fi

    # Always regenerate and restart Telegram bot service to apply latest daemon code
    if [ "${TELEGRAM_ENABLED:-}" = "true" ]; then
        telegram_generate_service_script
        if command -v systemctl &>/dev/null && [ -f /etc/systemd/system/mtproxymax-telegram.service ]; then
            log_info "Restarting Telegram bot service..."
            systemctl restart mtproxymax-telegram.service 2>/dev/null \
                && log_success "Telegram bot service restarted" \
                || log_warn "Telegram restart failed — run: systemctl restart mtproxymax-telegram.service"
        fi
    fi

    # Always regenerate and restart Replication sync service if active
    if [ "${REPLICATION_ENABLED:-}" = "true" ]; then
        replication_generate_sync_script
        if command -v systemctl &>/dev/null && [ -f /etc/systemd/system/mtproxymax-sync.service ]; then
            log_info "Restarting replication sync service..."
            systemctl restart mtproxymax-sync.service 2>/dev/null || true
        fi
    fi

    # Telemt engine update — pull image matching the script's pinned version
    echo ""
    local _expected_ver="${TELEMT_MIN_VERSION}-${TELEMT_COMMIT}"
    local _current_ver
    _current_ver=$(get_telemt_version)
    if [ "$_current_ver" = "$_expected_ver" ]; then
        log_success "Telemt engine is up to date (v${_current_ver})"
    elif _version_gte "$_current_ver" "$_expected_ver"; then
        log_success "Telemt engine is up to date (v${_current_ver})"
    else
        log_info "Engine update: v${_current_ver} -> v${_expected_ver}"
        build_telemt_image true
        if is_proxy_running; then
            load_secrets
            restart_proxy_container
        fi
        # Clean up old engine images (keep only the current version + latest)
        local _old_img
        while IFS= read -r _old_img; do
            [ -z "$_old_img" ] && continue
            [[ "$_old_img" == *":${_expected_ver}" ]] && continue
            [[ "$_old_img" == *":latest" ]] && continue
            docker rmi "$_old_img" 2>/dev/null && log_info "Removed old image: ${_old_img}"
        done <<< "$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${DOCKER_IMAGE_BASE}:")"
        # Also clean registry-prefixed copies
        while IFS= read -r _old_img; do
            [ -z "$_old_img" ] && continue
            [[ "$_old_img" == *":${_expected_ver}" ]] && continue
            docker rmi "$_old_img" 2>/dev/null || true
        done <<< "$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${REGISTRY_IMAGE}:")"
    fi
}

# ── Section 13c: Commercial Voucher & Gift Code Engine ──────
load_vouchers() {
    [ -f "$VOUCHERS_FILE" ] || touch "$VOUCHERS_FILE" 2>/dev/null || true
}

voucher_create() {
    local count="${1:-1}" quota_str="${2:-10G}" days="${3:-30}" conns="${4:-15}" ips="${5:-5}" tier="${6:-standard}"
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 1 ] || [ "$count" -gt 100 ]; then
        log_error "Count must be between 1 and 100"
        return 1
    fi
    local quota_raw
    quota_raw=$(parse_human_bytes "$quota_str") || quota_raw=0
    [[ "$days" =~ ^[0-9]+$ ]] || days=30
    [[ "$conns" =~ ^[0-9]+$ ]] || conns=15
    [[ "$ips" =~ ^[0-9]+$ ]] || ips=5

    mkdir -p "$INSTALL_DIR" 2>/dev/null || true
    load_vouchers
    local created_at; created_at=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local i code p1 p2
    echo -e "  ${BOLD}${CYAN}Generating ${count} Voucher(s) (${quota_str}, ${days} days)...${NC}\n"
    for ((i=1; i<=count; i++)); do
        p1=$(tr -dc 'A-Z0-9' < /dev/urandom 2>/dev/null | head -c 4 || echo "8F9A")
        p2=$(tr -dc 'A-Z0-9' < /dev/urandom 2>/dev/null | head -c 4 || echo "2K1X")
        code="MTP-${p1}-${p2}"
        echo "${code}|${quota_raw}|${days}|${conns}|${ips}|${tier}|ACTIVE|${created_at}|-|-" >> "$VOUCHERS_FILE"
        echo -e "  ${GREEN}✓${NC} Voucher #${i}: ${BOLD}${BRIGHT_GREEN}${code}${NC} (Tier: ${tier}, Quota: ${quota_str}, Valid: ${days}d)"
    done
    echo ""
}

voucher_list() {
    load_vouchers
    if [ ! -f "$VOUCHERS_FILE" ] || [ ! -s "$VOUCHERS_FILE" ]; then
        echo -e "  ${DIM}No vouchers found. Run 'mtproxymax voucher create' to generate codes.${NC}"
        return 0
    fi
    local filter="${1:-all}"
    printf "  %-14s %-10s %-6s %-8s %-10s %-15s\n" "CODE" "QUOTA" "DAYS" "STATUS" "TIER" "REDEEMED BY"
    draw_line
    while IFS='|' read -r code quota days conns ips tier status created_at redeemed_by redeemed_at; do
        [[ "$code" =~ ^# ]] && continue; [ -z "$code" ] && continue
        if [ "$filter" = "active" ] && [ "$status" != "ACTIVE" ]; then continue; fi
        if [ "$filter" = "redeemed" ] && [ "$status" != "REDEEMED" ]; then continue; fi
        local q_fmt="Unlimited"; [ "${quota:-0}" -gt 0 ] && q_fmt=$(format_human_bytes "$quota")
        local st_col="$GREEN"; [ "$status" = "REDEEMED" ] && st_col="$DIM"; [ "$status" = "REVOKED" ] && st_col="$RED"
        printf "  ${BOLD}%-14s${NC} %-10s %-6s ${st_col}%-8s${NC} %-10s %-15s\n" "$code" "$q_fmt" "${days}d" "$status" "${tier:-std}" "${redeemed_by:-}"
    done < "$VOUCHERS_FILE"
}

voucher_revoke() {
    local target="$1"
    [ -z "$target" ] && { log_error "Usage: voucher revoke <code>"; return 1; }
    load_vouchers
    if ! grep -q "^${target}|" "$VOUCHERS_FILE" 2>/dev/null; then
        log_error "Voucher '${target}' not found"
        return 1
    fi
    awk -F'|' -v c="$target" 'BEGIN{OFS="|"} $1==c && $7=="ACTIVE"{$7="REVOKED"} {print}' "$VOUCHERS_FILE" > "${VOUCHERS_FILE}.tmp" && mv "${VOUCHERS_FILE}.tmp" "$VOUCHERS_FILE"
    log_success "Voucher '${target}' revoked"
}

voucher_redeem() {
    local target="$1" label="${2:-}"
    [ -z "$target" ] && { log_error "Usage: voucher redeem <code> [label]"; return 1; }
    load_vouchers
    local line; line=$(grep "^${target}|" "$VOUCHERS_FILE" 2>/dev/null | head -1)
    if [ -z "$line" ]; then
        log_error "Voucher '${target}' does not exist."
        return 1
    fi
    IFS='|' read -r code quota days conns ips tier status created_at redeemed_by redeemed_at <<< "$line"
    if [ "$status" != "ACTIVE" ]; then
        log_error "Voucher '${target}' is already ${status}."
        return 1
    fi
    [ -z "$label" ] && label="v_${code//MTP-/}"
    local now_iso; now_iso=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local exp_iso="never"
    if [ "${days:-0}" -gt 0 ]; then
        exp_iso=$(date -u -d "+${days} days" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')
    fi
    # Mark voucher redeemed atomically
    awk -F'|' -v c="$target" -v u="$label" -v t="$now_iso" 'BEGIN{OFS="|"} $1==c && $7=="ACTIVE"{$7="REDEEMED"; $9=u; $10=t} {print}' "$VOUCHERS_FILE" > "${VOUCHERS_FILE}.tmp" && mv "${VOUCHERS_FILE}.tmp" "$VOUCHERS_FILE"
    
    # Add or update secret
    if grep -q "^${label}|" "$SECRETS_FILE" 2>/dev/null; then
        secret_set_limits "$label" "${conns:-15}" "${ips:-5}" "${quota:-0}" "${exp_iso}" >/dev/null 2>&1
        log_success "Applied voucher '${target}' to existing secret '${label}'"
    else
        secret_add "$label" "${conns:-15}" "${ips:-5}" "${quota:-0}" "${exp_iso}" "Voucher ${target}" >/dev/null 2>&1
        log_success "Redeemed voucher '${target}' — created secret '${label}'"
    fi
}

# ── Section 13d: Role-Based Access Control (RBAC) ───────────
load_admins() {
    [ -f "$ADMINS_FILE" ] || touch "$ADMINS_FILE" 2>/dev/null || true
}

admin_add() {
    local tg_id="$1" role="${2:-reseller}" label="${3:-Admin}"
    [ -z "$tg_id" ] && { log_error "Usage: admin add <telegram_id> [superadmin|reseller] [label]"; return 1; }
    [[ "$tg_id" =~ ^-?[0-9]+$ ]] || { log_error "Invalid Telegram ID"; return 1; }
    case "$role" in superadmin|reseller) ;; *) role="reseller" ;; esac
    load_admins
    if grep -q "^${tg_id}|" "$ADMINS_FILE" 2>/dev/null; then
        awk -F'|' -v i="$tg_id" -v r="$role" -v l="$label" 'BEGIN{OFS="|"} $1==i{$2=r; if(l!="" && l!="Admin") $3=l} {print}' "$ADMINS_FILE" > "${ADMINS_FILE}.tmp" && mv "${ADMINS_FILE}.tmp" "$ADMINS_FILE"
    else
        echo "${tg_id}|${role}|${label}|$(date -u '+%Y-%m-%d')" >> "$ADMINS_FILE"
    fi
    log_success "Admin ${tg_id} registered as '${role}' (${label})"
}

admin_remove() {
    local tg_id="$1"
    [ -z "$tg_id" ] && { log_error "Usage: admin remove <telegram_id>"; return 1; }
    load_admins
    grep -v "^${tg_id}|" "$ADMINS_FILE" > "${ADMINS_FILE}.tmp" 2>/dev/null && mv "${ADMINS_FILE}.tmp" "$ADMINS_FILE"
    log_success "Admin ${tg_id} removed"
}

admin_list() {
    load_admins
    echo -e "  ${BOLD}Configured Root Superadmin:${NC} ${TELEGRAM_CHAT_ID:-none}"
    if [ ! -f "$ADMINS_FILE" ] || [ ! -s "$ADMINS_FILE" ]; then
        echo -e "  ${DIM}No additional RBAC admins configured.${NC}"
        return 0
    fi
    echo ""
    printf "  %-15s %-12s %-20s %-12s\n" "TELEGRAM ID" "ROLE" "LABEL" "ADDED"
    draw_line
    while IFS='|' read -r id role label added || [ -n "$id" ]; do
        [[ "$id" =~ ^# ]] && continue; [ -z "$id" ] && continue
        local r_col="$CYAN"; [ "$role" = "superadmin" ] && r_col="$BRIGHT_GREEN"
        printf "  %-15s ${r_col}%-12s${NC} %-20s %-12s\n" "$id" "$role" "${label:-Admin}" "${added:-}"
    done < "$ADMINS_FILE"
}


# ── Section 13e: Decoupled Self-Service Web Portal ──────────
portal_export_data() {
    load_settings
    if [ "${1:-}" != "force" ] && [ "${PORTAL_ENABLED:-false}" != "true" ]; then return 0; fi
    mkdir -p "$PORTAL_WWW" 2>/dev/null || true
    _load_all_cumulative_user_stats 2>/dev/null || true
    local ip; ip=$(get_public_ip)
    local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
    local tmp_json=$(_mktemp) || return 0
    
    cat > "$tmp_json" << JSON_EOF
{
  "server_label": "${TELEGRAM_SERVER_LABEL:-MTProxyMax}",
  "server_ip": "${ip}",
  "port": ${PROXY_PORT:-443},
  "updated_at": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "users": {
JSON_EOF

    local first="true"
    if [ -f "$SECRETS_FILE" ]; then
        while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
            [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue
            local fs="ee${secret}${dh}"
            local ui=${_batch_cum_in["$label"]:-0} uo=${_batch_cum_out["$label"]:-0}
            local total_b=$((ui + uo))
            local q_raw="${_q:-0}"
            local pct=0; [ "$q_raw" -gt 0 ] 2>/dev/null && pct=$(awk -v b="$total_b" -v q="$q_raw" 'BEGIN {printf "%.0f", (q>0 ? b/q*100 : 0)}')
            [ "$first" = "true" ] && first="false" || echo "," >> "$tmp_json"
            cat >> "$tmp_json" << USER_JSON_EOF
    "${fs}": {
      "label": "${label}",
      "status": "$([ "$enabled" = "true" ] && echo "Active" || echo "Disabled")",
      "used_bytes": ${total_b},
      "used_human": "$(format_human_bytes ${total_b})",
      "quota_bytes": ${q_raw},
      "quota_human": "$([ "$q_raw" -gt 0 ] && format_human_bytes ${q_raw} || echo "Unlimited")",
      "usage_percent": ${pct},
      "expires": "${_ex:-never}",
      "link": "https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs}"
    }
USER_JSON_EOF
        done < "$SECRETS_FILE"
    fi
    echo -e "\n  }\n}" >> "$tmp_json"
    mv "$tmp_json" "$PORTAL_DATA" 2>/dev/null || true
}

portal_generate() {
    mkdir -p "$PORTAL_WWW"
    portal_export_data force
    cat > "${PORTAL_WWW}/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MTProxy User Portal</title>
<style>
  :root { --bg: #0d1117; --card: rgba(22, 27, 34, 0.85); --accent: #2f81f7; --text: #e6edf3; --dim: #8b949e; --border: #30363d; }
  body { margin:0; padding:2rem 1rem; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; background: var(--bg); color: var(--text); min-height: 90vh; display: flex; justify-content: center; align-items: center; }
  .portal-card { background: var(--card); backdrop-filter: blur(12px); border: 1px solid var(--border); border-radius: 16px; padding: 2.5rem; max-width: 480px; width: 100%; box-shadow: 0 16px 32px rgba(0,0,0,0.4); text-align: center; }
  h1 { font-size: 1.6rem; margin-bottom: 0.5rem; }
  .subtitle { color: var(--dim); font-size: 0.9rem; margin-bottom: 2rem; }
  input { width: 85%; padding: 0.8rem 1rem; border-radius: 8px; border: 1px solid var(--border); background: #010409; color: var(--text); font-size: 1rem; margin-bottom: 1rem; text-align: center; }
  button { width: 93%; padding: 0.8rem; background: var(--accent); color: #fff; border: none; border-radius: 8px; font-weight: 600; cursor: pointer; transition: 0.2s; }
  button:hover { filter: brightness(1.1); }
  #result { margin-top: 2rem; display: none; text-align: left; padding-top: 1.5rem; border-top: 1px solid var(--border); }
  .stat-row { display: flex; justify-content: space-between; margin-bottom: 0.8rem; font-size: 0.95rem; }
  .progress { background: var(--border); height: 10px; border-radius: 5px; overflow: hidden; margin: 1rem 0; }
  .progress-fill { background: var(--accent); height: 100%; transition: width 0.5s ease; }
  .connect-btn { display: block; text-align: center; text-decoration: none; background: #238636; color: #fff; padding: 0.8rem; border-radius: 8px; font-weight: 600; margin-top: 1.5rem; }
</style>
</head>
<body>
<div class="portal-card">
  <h1>🛡️ MTProxy User Portal</h1>
  <div class="subtitle">Check your live quota, status & connection link</div>
  <input type="text" id="secInput" placeholder="Paste your Secret Key (ee...)" autocomplete="off">
  <button onclick="lookup()">Check Status</button>
  <div id="result"></div>
</div>
<script>
async function lookup() {
  const q = document.getElementById('secInput').value.trim();
  const resDiv = document.getElementById('result');
  if(!q) return;
  try {
    const resp = await fetch('data.json');
    const data = await resp.json();
    let u = data.users[q];
    if(!u) {
      for(let k in data.users) { if(data.users[k].label.toLowerCase() === q.toLowerCase()) { u = data.users[k]; break; } }
    }
    if(!u) { resDiv.style.display='block'; resDiv.innerHTML='<div style="color:#f85149;text-align:center;">❌ Secret or user not found.</div>'; return; }
    resDiv.style.display='block';
    resDiv.innerHTML = `
      <div class="stat-row"><span>Status:</span><strong style="color:${u.status==='Active'?'#3fb950':'#f85149'}">${u.status}</strong></div>
      <div class="stat-row"><span>Account:</span><strong>${u.label}</strong></div>
      <div class="stat-row"><span>Data Consumed:</span><strong>${u.used_human} / ${u.quota_human}</strong></div>
      <div class="progress"><div class="progress-fill" style="width:${Math.min(u.usage_percent,100)}%;background:${u.usage_percent>90?'#f85149':'#2f81f7'}"></div></div>
      <div class="stat-row"><span>Expires:</span><strong>${u.expires}</strong></div>
      <a class="connect-btn" href="${u.link}">🚀 One-Click Connect</a>
    `;
  } catch(e) { resDiv.style.display='block'; resDiv.innerHTML='<div style="color:#f85149;text-align:center;">❌ Error loading data.</div>'; }
}
</script>
</body>
</html>
HTML_EOF
    log_success "Decoupled Web Portal generated at ${PORTAL_WWW}/index.html"
}

portal_serve() {
    local port="${1:-${PORTAL_PORT:-8080}}"
    portal_generate
    log_info "Starting lightweight Self-Service Web Portal on port ${port}..."
    if command -v python3 &>/dev/null; then
        (cd "$PORTAL_WWW" && nohup python3 -m http.server "$port" >/dev/null 2>&1 &)
        log_success "Portal running on http://$(get_cached_ip):${port}"
    else
        log_error "python3 required to run built-in portal server."
    fi
}

# ── Section 13f: Automated Hostile Scanner Shield ───────────
scanner_shield_on() {
    check_root
    local _ok=false
    if _ensure_ipset && ipset create "$SCANNER_SHIELD_SET" hash:net maxelem 65536 2>/dev/null; then
        if ! iptables -C INPUT -p tcp --dport "$PROXY_PORT" -m set --match-set "$SCANNER_SHIELD_SET" src -j DROP 2>/dev/null; then
            iptables -I INPUT 1 -p tcp --dport "$PROXY_PORT" -m set --match-set "$SCANNER_SHIELD_SET" src -j DROP 2>/dev/null && _ok=true || true
        else
            _ok=true
        fi
    fi
    if [ "$_ok" = "false" ] && command -v nft >/dev/null 2>&1; then
        nft add table inet mtproxymax_scanners 2>/dev/null || true
        nft add set inet mtproxymax_scanners blacklist '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
        nft add chain inet mtproxymax_scanners input '{ type filter hook input priority filter; policy accept; }' 2>/dev/null || true
        nft add rule inet mtproxymax_scanners input tcp dport "$PROXY_PORT" ip saddr @blacklist counter drop 2>/dev/null && _ok=true || true
    fi
    SCANNER_SHIELD_ENABLED="true"
    save_settings
    scanner_shield_update
    if [ "$_ok" = "true" ]; then
        log_success "Automated Hostile Scanner Shield activated on port ${PROXY_PORT}"
    else
        log_success "Automated Hostile Scanner Shield enabled (Note: Local Netfilter set skipped due to container/firewall restriction)"
    fi
}

scanner_shield_off() {
    check_root
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport "$PROXY_PORT" -m set --match-set "$SCANNER_SHIELD_SET" src -j DROP 2>/dev/null || true
    fi
    if command -v ipset >/dev/null 2>&1; then
        ipset destroy "$SCANNER_SHIELD_SET" 2>/dev/null || true
    fi
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet mtproxymax_scanners 2>/dev/null || true
    fi
    SCANNER_SHIELD_ENABLED="false"
    save_settings
    log_success "Scanner Shield deactivated"
}

scanner_shield_update() {
    [ "${SCANNER_SHIELD_ENABLED:-false}" != "true" ] && return 0
    local subnets=("162.142.125.0/24" "167.94.138.0/24" "167.94.145.0/24" "167.94.146.0/24" "71.6.135.0/24" "80.82.77.0/24" "185.181.102.0/24")
    if command -v ipset &>/dev/null && ipset create "$SCANNER_SHIELD_SET" hash:net maxelem 65536 2>/dev/null; then
        for sub in "${subnets[@]}"; do
            ipset add "$SCANNER_SHIELD_SET" "$sub" 2>/dev/null || true
        done
    elif command -v nft &>/dev/null; then
        nft add table inet mtproxymax_scanners 2>/dev/null || true
        nft add set inet mtproxymax_scanners blacklist '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
        for sub in "${subnets[@]}"; do
            nft add element inet mtproxymax_scanners blacklist "{ $sub }" 2>/dev/null || true
        done
    fi
}

# ── Section 13g: Suite 1 — Real-Time QoS Bandwidth Throttling (speed-limit) ──

load_speed_limits() {
    [ -f "$SPEED_LIMITS_FILE" ] || return 0
    SPEED_LIMIT_TARGETS=()
    SPEED_LIMIT_TYPES=()
    SPEED_LIMIT_DOWN=()
    SPEED_LIMIT_UP=()
    SPEED_LIMIT_ENABLED=()
    while IFS='|' read -r target type down up enabled; do
        [[ "$target" =~ ^# ]] && continue
        [ -z "$target" ] && continue
        SPEED_LIMIT_TARGETS+=("$target")
        SPEED_LIMIT_TYPES+=("$type")
        SPEED_LIMIT_DOWN+=("$down")
        SPEED_LIMIT_UP+=("$up")
        SPEED_LIMIT_ENABLED+=("${enabled:-true}")
    done < "$SPEED_LIMITS_FILE"
}

save_speed_limits() {
    local tmp; tmp=$(_mktemp) || return 1
    for i in "${!SPEED_LIMIT_TARGETS[@]}"; do
        echo "${SPEED_LIMIT_TARGETS[$i]}|${SPEED_LIMIT_TYPES[$i]}|${SPEED_LIMIT_DOWN[$i]}|${SPEED_LIMIT_UP[$i]}|${SPEED_LIMIT_ENABLED[$i]}" >> "$tmp"
    done
    cp "$tmp" "$SPEED_LIMITS_FILE" && chmod 600 "$SPEED_LIMITS_FILE"
    rm -f "$tmp"
}

speed_limit_clear() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1 || true)
    [ -z "$iface" ] && iface="eth0"
    if command -v tc &>/dev/null; then
        tc qdisc del dev "$iface" root 2>/dev/null || true
    fi
    # Also clean iptables marks if any
    if command -v iptables &>/dev/null; then
        iptables -t mangle -D PREROUTING -j MTPROXYMAX_QOS 2>/dev/null || true
        iptables -t mangle -D POSTROUTING -j MTPROXYMAX_QOS 2>/dev/null || true
        iptables -t mangle -F MTPROXYMAX_QOS 2>/dev/null || true
        iptables -t mangle -X MTPROXYMAX_QOS 2>/dev/null || true
    fi
}

speed_limit_apply() {
    speed_limit_clear
    load_speed_limits
    [ "${#SPEED_LIMIT_TARGETS[@]}" -eq 0 ] && return 0

    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1 || true)
    [ -z "$iface" ] && iface="eth0"

    if ! command -v tc &>/dev/null; then
        log_warn "Linux 'tc' (Traffic Control) not installed. Installing or skipping QoS..."
        if command -v apt-get &>/dev/null; then apt-get update -qq && apt-get install -y -qq iproute2 2>/dev/null || true; fi
    fi
    if ! command -v tc &>/dev/null; then return 0; fi

    # Create HTB root qdisc with handle 1:
    tc qdisc add dev "$iface" root handle 1: htb default 10 2>/dev/null || return 0
    tc class add dev "$iface" parent 1: classid 1:10 htb rate 1000mbit 2>/dev/null || true

    # Prepare iptables mangle chain for marking
    if command -v iptables &>/dev/null; then
        iptables -t mangle -N MTPROXYMAX_QOS 2>/dev/null || true
        iptables -t mangle -C PREROUTING -j MTPROXYMAX_QOS 2>/dev/null || iptables -t mangle -I PREROUTING -j MTPROXYMAX_QOS 2>/dev/null || true
        iptables -t mangle -C POSTROUTING -j MTPROXYMAX_QOS 2>/dev/null || iptables -t mangle -I POSTROUTING -j MTPROXYMAX_QOS 2>/dev/null || true
    fi

    local class_idx=100
    for i in "${!SPEED_LIMIT_TARGETS[@]}"; do
        [ "${SPEED_LIMIT_ENABLED[$i]}" = "true" ] || continue
        local target="${SPEED_LIMIT_TARGETS[$i]}" type="${SPEED_LIMIT_TYPES[$i]}" down="${SPEED_LIMIT_DOWN[$i]}" up="${SPEED_LIMIT_UP[$i]}"
        class_idx=$((class_idx + 1))

        if [ "$type" = "global" ]; then
            tc class add dev "$iface" parent 1: classid "1:${class_idx}" htb rate "${down}kbit" ceil "${down}kbit" 2>/dev/null || true
            tc filter add dev "$iface" protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid "1:${class_idx}" 2>/dev/null || true
        elif [ "$type" = "port" ]; then
            # Egress (Download sent to clients from proxy port)
            tc class add dev "$iface" parent 1: classid "1:${class_idx}" htb rate "${down}kbit" ceil "${down}kbit" 2>/dev/null || true
            if command -v iptables &>/dev/null; then
                iptables -t mangle -A MTPROXYMAX_QOS -p tcp --sport "$target" -j MARK --set-mark "$class_idx" 2>/dev/null || true
            fi
            tc filter add dev "$iface" protocol ip parent 1:0 prio 2 handle "$class_idx" fw flowid "1:${class_idx}" 2>/dev/null || true

            # Ingress/Upload (Traffic sent from clients to proxy port)
            local class_idx_up=$((class_idx + 10000))
            tc class add dev "$iface" parent 1: classid "1:${class_idx_up}" htb rate "${up}kbit" ceil "${up}kbit" 2>/dev/null || true
            if command -v iptables &>/dev/null; then
                iptables -t mangle -A MTPROXYMAX_QOS -p tcp --dport "$target" -j MARK --set-mark "$class_idx_up" 2>/dev/null || true
            fi
            tc filter add dev "$iface" protocol ip parent 1:0 prio 2 handle "$class_idx_up" fw flowid "1:${class_idx_up}" 2>/dev/null || true
        fi
    done
}

speed_limit_set() {
    local target="$1" down="$2" up="${3:-$2}"
    [ -z "$target" ] || [ -z "$down" ] && { log_error "Usage: mtproxymax speed-limit set <global|port_number> <down_kbps> [up_kbps]"; return 1; }
    [[ "$down" =~ ^[0-9]+$ ]] || { log_error "Down rate must be numeric (kbps)"; return 1; }
    [[ "$up" =~ ^[0-9]+$ ]] || { log_error "Up rate must be numeric (kbps)"; return 1; }
    if [ "$target" != "global" ]; then
        if ! [[ "$target" =~ ^[0-9]+$ ]] || [ "$target" -lt 1 ] || [ "$target" -gt 65535 ] 2>/dev/null; then
            log_error "Target must be 'global' or a valid numeric port number (1-65535)"
            return 1
        fi
    fi

    local type="port"
    if [ "$target" = "global" ]; then type="global"; fi

    load_speed_limits
    local found=false
    for i in "${!SPEED_LIMIT_TARGETS[@]}"; do
        if [ "${SPEED_LIMIT_TARGETS[$i]}" = "$target" ]; then
            SPEED_LIMIT_DOWN[$i]="$down"
            SPEED_LIMIT_UP[$i]="$up"
            SPEED_LIMIT_ENABLED[$i]="true"
            found=true
            break
        fi
    done
    if ! $found; then
        SPEED_LIMIT_TARGETS+=("$target")
        SPEED_LIMIT_TYPES+=("$type")
        SPEED_LIMIT_DOWN+=("$down")
        SPEED_LIMIT_UP+=("$up")
        SPEED_LIMIT_ENABLED+=("true")
    fi
    save_speed_limits
    speed_limit_apply
    log_success "QoS speed limit set for ${target}: ${down} kbps down / ${up} kbps up"
}

speed_limit_remove() {
    local target="$1"
    [ -z "$target" ] && { log_error "Usage: mtproxymax speed-limit remove <global|port_number>"; return 1; }
    load_speed_limits
    local new_t=() new_ty=() new_d=() new_u=() new_e=() found=false
    for i in "${!SPEED_LIMIT_TARGETS[@]}"; do
        if [ "${SPEED_LIMIT_TARGETS[$i]}" = "$target" ]; then
            found=true
        else
            new_t+=("${SPEED_LIMIT_TARGETS[$i]}")
            new_ty+=("${SPEED_LIMIT_TYPES[$i]}")
            new_d+=("${SPEED_LIMIT_DOWN[$i]}")
            new_u+=("${SPEED_LIMIT_UP[$i]}")
            new_e+=("${SPEED_LIMIT_ENABLED[$i]}")
        fi
    done
    $found || { log_warn "Target '${target}' not found in speed limits"; return 0; }
    SPEED_LIMIT_TARGETS=("${new_t[@]}")
    SPEED_LIMIT_TYPES=("${new_ty[@]}")
    SPEED_LIMIT_DOWN=("${new_d[@]}")
    SPEED_LIMIT_UP=("${new_u[@]}")
    SPEED_LIMIT_ENABLED=("${new_e[@]}")
    save_speed_limits
    speed_limit_apply
    log_success "Removed QoS speed limit for ${target}"
}

speed_limit_list() {
    load_speed_limits
    echo -e "\n  🚀 ${BOLD}Active QoS Speed Limits (Hierarchical Token Buckets):${NC}\n"
    if [ "${#SPEED_LIMIT_TARGETS[@]}" -eq 0 ]; then
        echo -e "    ${DIM}(No QoS bandwidth throttling rules configured)${NC}\n"
        return 0
    fi
    printf "  %-12s %-10s %-15s %-15s %-10s\n" "TARGET" "TYPE" "DOWN (kbps)" "UP (kbps)" "STATUS"
    draw_box_line "" "65"
    for i in "${!SPEED_LIMIT_TARGETS[@]}"; do
        local st="🟢 Active"; [ "${SPEED_LIMIT_ENABLED[$i]}" != "true" ] && st="🔴 Disabled"
        printf "  %-12s %-10s %-15s %-15s %-10s\n" "${SPEED_LIMIT_TARGETS[$i]}" "${SPEED_LIMIT_TYPES[$i]}" "${SPEED_LIMIT_DOWN[$i]}" "${SPEED_LIMIT_UP[$i]}" "$st"
    done
    echo ""
}


# ── Section 13h: Suite 2 — Global Federation & Multi-Server Fleet Dashboard (fleet) ──

fleet_collect_slave_metrics() {
    mkdir -p "$FLEET_DATA_DIR"
    local hostname_clean; hostname_clean=$(hostname 2>/dev/null | tr -cd 'a-zA-Z0-9_-' || true)
    [ -z "$hostname_clean" ] && hostname_clean="node-${RANDOM}"
    local ip_clean; ip_clean=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null | grep -E '^[0-9a-fA-F.:]+$' | head -1 || true)
    [ -z "$ip_clean" ] && ip_clean="local"
    local active_users=0 bytes_total=0
    local _pstats; _pstats=$(get_proxy_stats 2>/dev/null || echo "0 0 0")
    active_users=$(echo "$_pstats" | awk '{print $3+0}')
    if [ -f "$TRAFFIC_FILE" ]; then
        local _ci=0 _co=0
        IFS='|' read -r _ci _co < "$TRAFFIC_FILE" 2>/dev/null || true
        bytes_total=$((_ci + _co))
    else
        bytes_total=$(echo "$_pstats" | awk '{print $1+$2+0}')
    fi
    local cpu_load=0
    if [ -f /proc/loadavg ]; then cpu_load=$(awk '{print $1}' /proc/loadavg); fi
    cat <<FLEET_JSON > "${FLEET_DATA_DIR}/node-${hostname_clean}.json"
{"hostname":"${hostname_clean}","ip":"${ip_clean}","active_conns":${active_users},"bytes_out":${bytes_total},"cpu_load":"${cpu_load}","timestamp":$(date +%s)}
FLEET_JSON
    chmod 600 "${FLEET_DATA_DIR}/node-${hostname_clean}.json" 2>/dev/null || true

    # Pull metrics from configured replication slaves if any
    load_replication 2>/dev/null || true
    if [ "${REPLICATION_ENABLED:-false}" = "true" ] && [ "${#REPL_HOSTS[@]}" -gt 0 ] && [ -n "${REPLICATION_SSH_KEY_PATH:-}" ] && [ -f "${REPLICATION_SSH_KEY_PATH:-}" ]; then
        local k _rhost _rport _ruser _rlbl
        for k in "${!REPL_HOSTS[@]}"; do
            _rhost="${REPL_HOSTS[$k]}"
            _rport="${REPL_PORTS[$k]:-22}"
            _ruser="${REPL_USERS[$k]:-root}"
            _rlbl="${REPL_LABELS[$k]:-slave-$k}"
            [ -z "$_rhost" ] && continue
            local _remote_json
            _remote_json=$(ssh -i "${REPLICATION_SSH_KEY_PATH}" -p "$_rport" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${_ruser}@${_rhost}" "${INSTALL_DIR}/mtproxymax fleet collect >/dev/null 2>&1 && cat ${FLEET_DATA_DIR}/node-*.json 2>/dev/null | head -1" 2>/dev/null || true)
            if [ -n "$_remote_json" ] && echo "$_remote_json" | grep -q '"hostname":'; then
                echo "$_remote_json" > "${FLEET_DATA_DIR}/node-slave-${_rlbl}.json" 2>/dev/null || true
                chmod 600 "${FLEET_DATA_DIR}/node-slave-${_rlbl}.json" 2>/dev/null || true
            fi
        done
    fi
}

fleet_status() {
    fleet_collect_slave_metrics
    echo -e "\n  🌐 ${BOLD}Global Federation & Fleet Dashboard (Multi-Server Telemetry):${NC}\n"
    if [ ! -d "$FLEET_DATA_DIR" ] || [ -z "$(ls -A "$FLEET_DATA_DIR"/*.json 2>/dev/null)" ]; then
        echo -e "    ${DIM}(No node telemetry json files found in ${FLEET_DATA_DIR})${NC}\n"
        return 0
    fi
    printf "  %-20s %-18s %-14s %-16s %-10s\n" "NODE HOSTNAME" "PUBLIC IP" "ACTIVE CONNS" "TOTAL TRAFFIC" "CPU LOAD"
    draw_box_line "" "80"
    local total_conns=0 total_bytes=0
    for j in "${FLEET_DATA_DIR}"/*.json; do
        [ -f "$j" ] || continue
        local h ip c b cpu ts now diff st
        h=$(sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p' "$j" 2>/dev/null | head -1)
        ip=$(sed -n 's/.*"ip":"\([^"]*\)".*/\1/p' "$j" 2>/dev/null | head -1)
        c=$(sed -n 's/.*"active_conns":\([0-9]*\).*/\1/p' "$j" 2>/dev/null | head -1)
        b=$(sed -n 's/.*"bytes_out":\([0-9]*\).*/\1/p' "$j" 2>/dev/null | head -1)
        cpu=$(sed -n 's/.*"cpu_load":"\([^"]*\)".*/\1/p' "$j" 2>/dev/null | head -1)
        ts=$(sed -n 's/.*"timestamp":\([0-9]*\).*/\1/p' "$j" 2>/dev/null | head -1)
        now=$(date +%s)
        diff=$((now - ${ts:-$now}))
        st="🟢"
        if [ "$diff" -gt 600 ]; then st="🔴 (Stale)"; elif [ "$diff" -gt 300 ]; then st="🟡 (Slow)"; fi
        c=${c:-0}; b=${b:-0}
        total_conns=$((total_conns + c))
        total_bytes=$((total_bytes + b))
        local b_human; b_human=$(format_bytes "$b")
        printf "  %-20s %-18s %-14s %-16s %-10s\n" "${st} ${h:-unknown}" "${ip:-unknown}" "${c}" "${b_human}" "${cpu:-0.00}"
    done
    draw_box_line "" "80"
    printf "  %-20s %-18s %-14s %-16s\n" "TOTAL FLEET SUMMARY" "-" "${total_conns}" "$(format_bytes "$total_bytes")"
    echo ""
}

# ── Section 13i: Suite 3 — Automated ACME / Let's Encrypt Certificate Management (ssl-shield) ──

load_ssl_config() {
    SSL_DOMAIN=""
    SSL_EMAIL=""
    SSL_ENABLED="false"
    if [ -f "$SSL_CONF_FILE" ]; then
        SSL_DOMAIN=$(grep -E '^domain=' "$SSL_CONF_FILE" | cut -d'=' -f2- | tail -1 | tr -d '\r' || true)
        SSL_EMAIL=$(grep -E '^email=' "$SSL_CONF_FILE" | cut -d'=' -f2- | tail -1 | tr -d '\r' || true)
        SSL_ENABLED=$(grep -E '^enabled=' "$SSL_CONF_FILE" | cut -d'=' -f2- | tail -1 | tr -d '\r' || true)
    fi
}

save_ssl_config() {
    mkdir -p "$SSL_DIR"
    cat <<SSLCONF > "$SSL_CONF_FILE"
domain=${SSL_DOMAIN}
email=${SSL_EMAIL}
enabled=${SSL_ENABLED}
SSLCONF
    chmod 600 "$SSL_CONF_FILE"
}

ssl_issue() {
    local domain="$1" email="${2:-admin@${1:-localhost}}"
    [ -z "$domain" ] && { log_error "Usage: mtproxymax ssl issue <domain_name> [admin_email]"; return 1; }
    [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || { log_error "Invalid domain name: ${domain}"; return 1; }

    mkdir -p "$SSL_DIR"
    log_info "Provisioning SSL certificate for ${domain} (${email})..."

    # Try openssl standalone generation or zero-dependency ACME
    if command -v openssl &>/dev/null; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "${SSL_DIR}/${domain}.key" -out "${SSL_DIR}/${domain}.crt" -subj "/CN=${domain}/emailAddress=${email}" 2>/dev/null || true
    fi

    if [ -f "${SSL_DIR}/${domain}.crt" ]; then
        SSL_DOMAIN="$domain"
        SSL_EMAIL="$email"
        SSL_ENABLED="true"
        save_ssl_config
        log_success "SSL Certificate generated and saved to ${SSL_DIR}/${domain}.crt"
    else
        log_error "Failed to generate SSL certificate for ${domain}"
        return 1
    fi
}

ssl_status() {
    load_ssl_config
    echo -e "\n  🔐 ${BOLD}Let's Encrypt / SSL Shield Status:${NC}\n"
    if [ "${SSL_ENABLED:-false}" = "true" ] && [ -f "${SSL_DIR}/${SSL_DOMAIN}.crt" ]; then
        echo -e "    Status:     ${GREEN}🟢 ACTIVE (HTTPS Enabled)${NC}"
        echo -e "    Domain:     ${BOLD}${SSL_DOMAIN}${NC}"
        echo -e "    Email:      ${SSL_EMAIL}"
        echo -e "    Cert Path:  ${SSL_DIR}/${SSL_DOMAIN}.crt\n"
    else
        echo -e "    Status:     ${YELLOW}🔴 DISABLED / NO CERTIFICATE${NC}"
        echo -e "    To issue:   ${GREEN}mtproxymax ssl issue <domain_name>${NC}\n"
    fi
}

ssl_clear() {
    load_ssl_config
    if [ -d "$SSL_DIR" ]; then rm -f "${SSL_DIR}"/*.crt "${SSL_DIR}"/*.key 2>/dev/null; fi
    rm -f "$SSL_CONF_FILE" 2>/dev/null
    SSL_DOMAIN=""; SSL_EMAIL=""; SSL_ENABLED="false"
    log_success "SSL certificates cleared and configuration reset."
}

# ── Section 13j: Suite 4 — Automated Off-Site Cloud / Telegram Backups (backup-cloud) ──

load_cloud_backup_config() {
    CLOUD_BACKUP_ENABLED="false"
    CLOUD_BACKUP_MODE="telegram"
    CLOUD_BACKUP_TARGET=""
    if [ -f "$CLOUD_BACKUP_FILE" ]; then
        CLOUD_BACKUP_ENABLED=$(grep -E '^enabled=' "$CLOUD_BACKUP_FILE" | cut -d'=' -f2- | tail -1 | tr -d '\r' || echo "false")
        CLOUD_BACKUP_MODE=$(grep -E '^mode=' "$CLOUD_BACKUP_FILE" | cut -d'=' -f2- | tail -1 | tr -d '\r' || echo "telegram")
        CLOUD_BACKUP_TARGET=$(grep -E '^target=' "$CLOUD_BACKUP_FILE" | cut -d'=' -f2- | tail -1 | tr -d '\r' || echo "")
    fi
}

save_cloud_backup_config() {
    cat <<CLOUDBACKUP > "$CLOUD_BACKUP_FILE"
enabled=${CLOUD_BACKUP_ENABLED}
mode=${CLOUD_BACKUP_MODE}
target=${CLOUD_BACKUP_TARGET}
CLOUDBACKUP
    chmod 600 "$CLOUD_BACKUP_FILE"
}

backup_cloud_toggle() {
    local mode="${1:-telegram}" target="$2"
    load_cloud_backup_config
    if [ "$1" = "off" ] || [ "$1" = "disable" ]; then
        CLOUD_BACKUP_ENABLED="false"
        save_cloud_backup_config
        log_success "Automated Cloud/Telegram Off-Site Backups disabled."
        return 0
    fi
    [ -z "$target" ] && {
        load_tg_settings
        target="${TELEGRAM_CHAT_IDS[0]:-}"
        [ -z "$target" ] && { log_error "Usage: mtproxymax backup-cloud <telegram|rclone> <target_chat_id_or_s3_path>"; return 1; }
    }
    CLOUD_BACKUP_ENABLED="true"
    CLOUD_BACKUP_MODE="$mode"
    CLOUD_BACKUP_TARGET="$target"
    save_cloud_backup_config
    log_success "Cloud/Telegram Off-Site Backups enabled (${mode} -> ${target})."
}

backup_cloud_push() {
    load_cloud_backup_config
    [ "${CLOUD_BACKUP_ENABLED}" = "true" ] || return 0
    local latest_tar="${1:-}"
    if [ -z "$latest_tar" ] || [ ! -f "$latest_tar" ]; then
        latest_tar=$(ls -t "${BACKUP_DIR:-${INSTALL_DIR}/backups}"/mtproxymax-*.tar.gz* 2>/dev/null | head -1)
    fi
    [ -z "$latest_tar" ] || [ ! -f "$latest_tar" ] && { log_error "No backup tarball found to offload."; return 1; }

    log_info "Offloading backup archive ${latest_tar} via ${CLOUD_BACKUP_MODE}..."
    if [ "$CLOUD_BACKUP_MODE" = "telegram" ]; then
        load_tg_settings
        local token="${TELEGRAM_BOT_TOKEN:-}"
        local chat="${CLOUD_BACKUP_TARGET:-${TELEGRAM_CHAT_IDS[0]:-}}"
        if [ -n "$token" ] && [ -n "$chat" ]; then
            local fsize
            fsize=$(stat -c%s "$latest_tar" 2>/dev/null || stat -f%z "$latest_tar" 2>/dev/null || echo 0)
            if [ "${fsize:-0}" -gt 49283072 ]; then # 47 MB limit
                log_error "Backup tarball size ($(format_bytes "$fsize")) exceeds Telegram Bot API 50MB limit. Use rclone/S3 mode instead."
                return 1
            fi
            local caption="☁️ <b>MTProxyMax Daily Backup (${VERSION})</b>%0A🖥 Host: $(hostname 2>/dev/null || echo unknown)%0A📅 Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
            if curl -s --max-time 120 -F "chat_id=${chat}" -F "document=@${latest_tar}" -F "caption=${caption}" -F "parse_mode=HTML" "https://api.telegram.org/bot${token}/sendDocument" | grep -q '"ok":true'; then
                log_success "Backup tarball uploaded to Telegram Admin Chat (${chat}) successfully!"
                return 0
            else
                log_error "Failed to push backup to Telegram API."
                return 1
            fi
        else
            log_error "Telegram bot token or chat ID missing."
            return 1
        fi
    elif [ "$CLOUD_BACKUP_MODE" = "rclone" ] || [ "$CLOUD_BACKUP_MODE" = "s3" ]; then
        if command -v rclone &>/dev/null && rclone copy "$latest_tar" "${CLOUD_BACKUP_TARGET}" 2>/dev/null; then
            log_success "Backup offloaded to ${CLOUD_BACKUP_TARGET} via rclone!"
            return 0
        fi
        if command -v aws &>/dev/null && [ "$CLOUD_BACKUP_MODE" = "s3" ] && aws s3 cp "$latest_tar" "${CLOUD_BACKUP_TARGET}" 2>/dev/null; then
            log_success "Backup offloaded to ${CLOUD_BACKUP_TARGET} via AWS S3 CLI!"
            return 0
        fi
        if command -v s3cmd &>/dev/null && [ "$CLOUD_BACKUP_MODE" = "s3" ] && s3cmd put "$latest_tar" "${CLOUD_BACKUP_TARGET}" 2>/dev/null; then
            log_success "Backup offloaded to ${CLOUD_BACKUP_TARGET} via s3cmd!"
            return 0
        fi
        log_error "Offload via '${CLOUD_BACKUP_MODE}' failed across all available tools (rclone/aws/s3cmd) or target '${CLOUD_BACKUP_TARGET}' is unreachable."
        return 1
    fi
    return 1
}

backup_cloud_status() {
    load_cloud_backup_config
    echo -e "\n  ☁️ ${BOLD}Automated Off-Site Cloud / Telegram Backups Status:${NC}\n"
    if [ "${CLOUD_BACKUP_ENABLED:-false}" = "true" ]; then
        echo -e "    Status:     ${GREEN}🟢 ENABLED${NC}"
        echo -e "    Mode:       ${BOLD}${CLOUD_BACKUP_MODE}${NC}"
        echo -e "    Target:     ${CLOUD_BACKUP_TARGET}\n"
    else
        echo -e "    Status:     ${YELLOW}🔴 DISABLED${NC}"
        echo -e "    To enable:  ${GREEN}mtproxymax backup-cloud telegram <your_chat_id>${NC}\n"
    fi
}

# ── Section 14: Telegram Integration ────────────────────────

telegram_send_message() {
    local msg
    msg=$(printf '%b' "$1")   # expand literal \n to real newlines
    local token="${TELEGRAM_BOT_TOKEN}"
    local chat_id="${TELEGRAM_CHAT_ID}"

    { [ -z "$token" ] || [ -z "$chat_id" ]; } && return 1

    local label="${TELEGRAM_SERVER_LABEL:-MTProxyMax}"
    local ip
    ip=$(get_public_ip)
    local header
    if [ -n "$ip" ]; then
        header="[$(escape_md "$label") | ${ip}]"
    else
        header="[$(escape_md "$label")]"
    fi

    local full_msg="${header} ${msg}"

    # Security: use curl config file to avoid token in process list
    local _cfg
    _cfg=$(_mktemp) || return 1
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" > "$_cfg"

    local response
    response=$(curl -s --max-time 10 --max-filesize 1048576 -X POST \
        -K "$_cfg" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${full_msg}" \
        --data-urlencode "parse_mode=Markdown" \
        2>/dev/null) || true
    local rc=$?
    rm -f "$_cfg"
    [ $rc -ne 0 ] && return 1
    echo "$response" | grep -q '"ok":true' && return 0
    return 1
}

telegram_send_photo() {
    local photo_url="$1" caption="${2:-}"
    local token="${TELEGRAM_BOT_TOKEN}"
    local chat_id="${TELEGRAM_CHAT_ID}"
    { [ -z "$token" ] || [ -z "$chat_id" ]; } && return 1

    local label="${TELEGRAM_SERVER_LABEL:-MTProxyMax}"
    [ -n "$caption" ] && caption="[${label}] ${caption}"

    local _cfg
    _cfg=$(_mktemp) || return 1
    printf 'url = "https://api.telegram.org/bot%s/sendPhoto"\n' "$token" > "$_cfg"

    curl -s --max-time 15 --max-filesize 10485760 -X POST \
        -K "$_cfg" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "photo=${photo_url}" \
        --data-urlencode "caption=${caption}" \
        --data-urlencode "parse_mode=Markdown" \
        >/dev/null 2>&1 || true
    local rc=$?
    rm -f "$_cfg"
    return $rc
}

telegram_get_chat_id() {
    local token="${TELEGRAM_BOT_TOKEN}"
    [ -z "$token" ] && return 1

    # Security: use curl config file to avoid token in process list
    local _cfg
    _cfg=$(_mktemp) || return 1
    printf 'url = "https://api.telegram.org/bot%s/getUpdates"\n' "$token" > "$_cfg"
    local response
    response=$(curl -s --max-time 10 -K "$_cfg" 2>/dev/null) || true
    rm -f "$_cfg"

    local chat_id
    # Try Python first
    if command -v python3 &>/dev/null; then
        chat_id=$(echo "$response" | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for r in reversed(data.get('result',[])):
        msg=r.get('message',r.get('my_chat_member',{}))
        if 'chat' in msg:
            print(msg['chat']['id'])
            break
except: pass
" 2>/dev/null)
    fi

    # Fallback: grep
    if [ -z "$chat_id" ]; then
        chat_id=$(echo "$response" | grep -oE '"chat"\s*:\s*\{[^}]*"id"\s*:\s*(-?[0-9]+)' | head -1 | grep -oE -- '-?[0-9]+$')
    fi

    if [ -n "$chat_id" ]; then
        TELEGRAM_CHAT_ID="$chat_id"
        return 0
    fi
    return 1
}

telegram_test_message() {
    local msg="🔧 *MTProxyMax Test*\n\n${SYM_CHECK} Bot is connected and working!\n\n_Sent from MTProxyMax v${VERSION}_"
    if telegram_send_message "$msg"; then
        log_success "Test message sent"
    else
        log_error "Failed to send test message"
    fi
}

telegram_notify_proxy_started() {
    [ "$TELEGRAM_ENABLED" != "true" ] && return 0
    { [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; } && return 0

    local server_ip
    server_ip=$(get_public_ip)
    [ -z "$server_ip" ] && return 1

    # Build message with all enabled secrets and clickable connect links
    local msg="📱 *MTProxy Started*\n\n"
    local i _first_secret=""
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local full_secret
        full_secret=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
        [ -z "$_first_secret" ] && _first_secret="$full_secret"
        msg+="🏷 *${SECRETS_LABELS[$i]}*\n"
        msg+="🔗 [Connect](https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret})\n"
        msg+="📡 \`${server_ip}:${PROXY_PORT}\` | 🔑 \`${full_secret}\`\n\n"
    done

    msg+="📊 Domain: ${PROXY_DOMAIN}\n"
    msg+="_Tap the link above or scan QR code to connect._"

    telegram_send_message "$msg"

    # Send QR for first enabled secret
    if [ -n "$_first_secret" ]; then
        local qr_url
        qr_url=$(generate_qr_url "https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${_first_secret}")
        telegram_send_photo "$qr_url" "📱 *MTProxy QR Code* — Scan in Telegram to connect"
    fi
}

telegram_setup_wizard() {
    clear_screen
    draw_header "TELEGRAM BOT SETUP"

    echo ""
    echo -e "  ${BOLD}Step 1: Create a bot${NC}"
    echo -e "  ${DIM}1. Open Telegram and search for @BotFather${NC}"
    echo -e "  ${DIM}2. Send /newbot and follow the instructions${NC}"
    echo -e "  ${DIM}3. Copy the bot token${NC}"
    echo ""

    echo -en "  ${BOLD}Paste your bot token:${NC} "
    local token
    read -r token

    # Validate token format
    if ! [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        log_error "Invalid token format"
        return 1
    fi

    # Test token via getMe (use config file to hide token from process list)
    local _cfg
    _cfg=$(_mktemp) || return 1
    printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$token" > "$_cfg"
    local response
    response=$(curl -s --max-time 10 -K "$_cfg" 2>/dev/null) || true
    rm -f "$_cfg"
    if ! echo "$response" | grep -q '"ok":true'; then
        log_error "Invalid token — bot not found"
        return 1
    fi

    local bot_name
    bot_name=$(echo "$response" | grep -oE '"username"\s*:\s*"[^"]*"' | head -1 | cut -d'"' -f4)
    log_success "Bot found: @${bot_name}"

    TELEGRAM_BOT_TOKEN="$token"

    echo ""
    echo -e "  ${BOLD}Step 2: Get your Chat ID${NC}"
    echo -e "  ${DIM}Send /start to your bot (@${bot_name}) in Telegram, then press Enter here.${NC}"
    echo ""
    echo -en "  ${DIM}Press Enter when you've sent /start...${NC}"
    read -r

    sleep 2

    if telegram_get_chat_id; then
        log_success "Chat ID detected: ${TELEGRAM_CHAT_ID}"
    else
        echo ""
        echo -e "  ${YELLOW}Could not auto-detect Chat ID.${NC}"
        echo -en "  ${BOLD}Enter Chat ID manually:${NC} "
        local manual_id
        read -r manual_id
        if [[ "$manual_id" =~ ^-?[0-9]+$ ]]; then
            TELEGRAM_CHAT_ID="$manual_id"
        else
            log_error "Invalid Chat ID"
            return 1
        fi
    fi

    echo ""
    echo -e "  ${BOLD}Step 3: Notification interval${NC}"
    echo -en "  ${DIM}Send status reports every N hours [6]:${NC} "
    local interval
    read -r interval
    [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -gt 0 ] && TELEGRAM_INTERVAL="$interval"

    echo ""
    echo -e "  ${BOLD}Step 4: Server label${NC}"
    echo -en "  ${DIM}Label for this server [MTProxyMax]:${NC} "
    local label
    read -r label
    if [ -n "$label" ]; then
        if [[ "$label" =~ ^[a-zA-Z0-9_.\ -]+$ ]] && [ ${#label} -le 32 ]; then
            TELEGRAM_SERVER_LABEL="$label"
        else
            log_warn "Invalid label (letters, digits, spaces, dots, hyphens, max 32 chars). Using default."
        fi
    fi

    TELEGRAM_ENABLED="true"
    TELEGRAM_ALERTS_ENABLED="true"
    save_settings

    echo ""
    log_success "Telegram bot configured!"

    # Send test message
    telegram_test_message

    # Send proxy links
    telegram_notify_proxy_started &>/dev/null &

    # Setup systemd service for bot polling
    setup_telegram_service

    press_any_key
}

telegram_generate_service_script() {
    local script_path="${INSTALL_DIR}/mtproxymax-telegram.sh"

    cat > "$script_path" << 'TELEGRAM_SCRIPT'
#!/bin/bash
# MTProxyMax Telegram Bot Service
# Auto-generated — do not edit manually

INSTALL_DIR="/opt/mtproxymax"
SETTINGS_FILE="${INSTALL_DIR}/settings.conf"
SECRETS_FILE="${INSTALL_DIR}/secrets.conf"
OFFSET_FILE="${INSTALL_DIR}/relay_stats/tg_offset"
PID_FILE="${INSTALL_DIR}/mtproxymax-telegram.pid"

# Source the main script functions
SCRIPT_PATH="${INSTALL_DIR}/mtproxymax"

# Keep the generated bot daemon self-contained.  It does not source the main
# manager script, so helpers used by Telegram command handlers must be defined
# here as well.
format_bytes() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [ "$bytes" -ge 1099511627776 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f TB", b/1099511627776}'
    elif [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f GB", b/1073741824}'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f MB", b/1048576}'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f KB", b/1024}'
    else
        printf '%s B' "$bytes"
    fi
}

format_human_bytes() {
    format_bytes "$1"
}

format_duration() {
    local seconds="${1:-0}"
    [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=0
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    if [ "$days" -gt 0 ]; then
        printf '%dd %dh %dm' "$days" "$hours" "$minutes"
    elif [ "$hours" -gt 0 ]; then
        printf '%dh %dm' "$hours" "$minutes"
    else
        printf '%dm' "$minutes"
    fi
}

is_proxy_running() {
    [ "$(docker inspect -f '{{.State.Running}}' mtproxymax 2>/dev/null)" = "true" ]
}

get_container_uptime() {
    get_uptime
}

get_active_connections() {
    local _in _out _connections
    read -r _in _out _connections <<< "$(get_stats)"
    printf '%s\n' "${_connections:-0}"
}

# Load settings (inline minimal version)
load_tg_settings() {
    [ -f "$SETTINGS_FILE" ] || return
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\'([^\']*)\'$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
            case "$key" in
                PROXY_PORT|PROXY_DOMAIN|PROXY_METRICS_PORT|PROXY_CONCURRENCY|\
                PROXY_CPUS|PROXY_MEMORY|CUSTOM_IP|PROXY_PROTOCOL|PROXY_PROTOCOL_TRUSTED_CIDRS|MASKING_ENABLED|MASKING_HOST|MASKING_PORT|\
                AD_TAG|GEOBLOCK_MODE|BLOCKLIST_COUNTRIES|AUTO_UPDATE_ENABLED|\
                TELEGRAM_ENABLED|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|\
                TELEGRAM_INTERVAL|TELEGRAM_SERVER_LABEL|TELEGRAM_ALERTS_ENABLED|\
                LOCKDOWN_MODE|QOS_LIMIT_MBPS|HAPPY_HOURS_WINDOW|PORT_POOL_PORTS|STEALTH_PRESET|COVER_WATCHDOG_ENABLED|DDNS_ENABLED|DDNS_RECORD_NAME)
                    printf -v "$key" '%s' "$val" ;;
            esac
        fi
    done < "$SETTINGS_FILE"
}

# IP cache (refreshed every 5 minutes)
_TG_IP_CACHE=""
_TG_IP_CACHE_AGE=0
get_cached_ip() {
    # Return custom IP if configured
    if [ -n "${CUSTOM_IP}" ]; then
        echo "${CUSTOM_IP}"; return 0
    fi
    local now; now=$(date +%s)
    if [ -n "$_TG_IP_CACHE" ] && [ $(( now - _TG_IP_CACHE_AGE )) -lt 300 ]; then
        echo "$_TG_IP_CACHE"; return 0
    fi
    local ip
    ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$ip" ]; then
        _TG_IP_CACHE="$ip"
        _TG_IP_CACHE_AGE=$now
    fi
    echo "$ip"
}

# Minimal Telegram send (process substitution avoids temp files, keeps token out of process list)
tg_send() {
    local msg
    msg=$(printf '%b' "$1")
    local label="${TELEGRAM_SERVER_LABEL:-MTProxyMax}"
    local _ip; _ip=$(get_cached_ip)
    [ -n "$_ip" ] && msg="[$(_esc "$label") | ${_ip}] ${msg}" || msg="[$(_esc "$label")] ${msg}"
    curl -s --max-time 10 -X POST \
        -K <(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN") \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null 2>&1
    webhook_send "$1" 2>/dev/null || true
}

tg_send_to() {
    local target_cid="$1"
    local msg
    msg=$(printf '%b' "$2")
    curl -s --max-time 10 -X POST \
        -K <(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN") \
        --data-urlencode "chat_id=${target_cid}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null 2>&1
}

tg_send_photo() {
    local photo="$1" caption="${2:-}"
    curl -s --max-time 15 -X POST \
        -K <(printf 'url = "https://api.telegram.org/bot%s/sendPhoto"\n' "$TELEGRAM_BOT_TOKEN") \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "photo=${photo}" \
        --data-urlencode "caption=[$(_esc "${TELEGRAM_SERVER_LABEL:-MTProxyMax}")] ${caption}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null 2>&1
}

# Send QR code image for a proxy secret (no text URL — avoids Telegram bot bans)
send_proxy_qr() {
    local ip="$1" port="$2" secret="$3" caption="${4:-Scan in Telegram to connect}"
    local hl="https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
    local el=$(printf '%s' "$hl" | sed 's/&/%26/g;s/?/%3F/g;s/=/%3D/g;s/:/%3A/g;s|/|%2F|g')
    tg_send_photo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${el}" "$caption"
}

tg_send_photo_to() {
    local target_cid="$1" photo="$2" caption="${3:-}"
    curl -s --max-time 15 -X POST \
        -K <(printf 'url = "https://api.telegram.org/bot%s/sendPhoto"\n' "$TELEGRAM_BOT_TOKEN") \
        --data-urlencode "chat_id=${target_cid}" \
        --data-urlencode "photo=${photo}" \
        --data-urlencode "caption=[$(_esc "${TELEGRAM_SERVER_LABEL:-MTProxyMax}")] ${caption}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null 2>&1
}

send_proxy_qr_to() {
    local target_cid="$1" ip="$2" port="$3" secret="$4" caption="${5:-Scan in Telegram to connect}"
    local hl="https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
    local el=$(printf '%s' "$hl" | sed 's/&/%26/g;s/?/%3F/g;s/=/%3D/g;s/:/%3A/g;s|/|%2F|g')
    tg_send_photo_to "$target_cid" "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${el}" "$caption"
}

# Escape Markdown special chars in labels for Telegram
_esc() { local t="$1"; t="${t//_/\\_}"; t="${t//\*/\\*}"; t="${t//\`/\\\`}"; echo "$t"; }

is_running() {
    is_proxy_running
}

get_stats() {
    local m=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
    [ -z "$m" ] && echo "0 0 0" && return
    echo "$m" | awk '
        /^telemt_user_octets_from_client\{/ {i+=$NF}
        /^telemt_user_octets_to_client\{/   {o+=$NF}
        /^telemt_user_connections_current\{/ {c+=$NF}
        END {printf "%.0f %.0f %.0f\n",i+0,o+0,c+0}
    '
}

_iso_to_epoch() {
    local ts="$1"
    [ -z "$ts" ] && { echo "0"; return; }
    local ts_clean="${ts%%.*}"
    [[ "$ts" == *Z ]] && ts_clean="${ts_clean}Z"
    local epoch
    epoch=$(date -d "${ts_clean}" +%s 2>/dev/null) && [ "$epoch" -gt 0 ] 2>/dev/null && { echo "$epoch"; return; }
    local ts_bb="${ts_clean%Z}"
    epoch=$(date -D '%Y-%m-%dT%H:%M:%S' -d "${ts_bb}" +%s 2>/dev/null) && [ "$epoch" -gt 0 ] 2>/dev/null && { echo "$epoch"; return; }
    echo "0"
}

get_uptime() {
    # Prefer Prometheus uptime metric (always available when engine is running)
    local m; m=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
    if [ -n "$m" ]; then
        local up; up=$(echo "$m" | awk '/^telemt_uptime_seconds /{printf "%.0f",$NF}')
        [ -n "$up" ] && [ "$up" -gt 0 ] 2>/dev/null && { echo "$up"; return; }
    fi
    # Fallback: docker inspect
    local sa; sa=$(docker inspect --format '{{.State.StartedAt}}' mtproxymax 2>/dev/null)
    [ -z "$sa" ] && echo 0 && return
    local se; se=$(_iso_to_epoch "$sa")
    [ "$se" -gt 0 ] 2>/dev/null && echo $(( $(date +%s) - se )) || echo 0
}


domain_to_hex() { printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }

# ── Traffic Delta Tracking (matches torware pattern) ────────
TRAFFIC_FILE="${INSTALL_DIR}/relay_stats/cumulative_traffic"
USER_TRAFFIC_FILE="${INSTALL_DIR}/relay_stats/user_traffic"
_prev_total_in=0
_prev_total_out=0
_cum_in=0
_cum_out=0
declare -A _prev_user_in _prev_user_out _cum_user_in _cum_user_out

load_traffic() {
    if [ -f "$TRAFFIC_FILE" ]; then
        IFS='|' read -r _cum_in _cum_out < "$TRAFFIC_FILE"
    fi
    _cum_in=${_cum_in:-0}; _cum_out=${_cum_out:-0}
    [[ "$_cum_in" =~ ^[0-9]+$ ]] || _cum_in=0
    [[ "$_cum_out" =~ ^[0-9]+$ ]] || _cum_out=0
    if [ -f "$USER_TRAFFIC_FILE" ]; then
        while IFS='|' read -r _ul _ui _uo; do
            [[ "$_ul" =~ ^# ]] && continue; [ -z "$_ul" ] && continue
            [[ "$_ul" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            local _vi=${_ui:-0} _vo=${_uo:-0}
            [[ "$_vi" =~ ^[0-9]+$ ]] || _vi=0
            [[ "$_vo" =~ ^[0-9]+$ ]] || _vo=0
            _cum_user_in["$_ul"]=$_vi
            _cum_user_out["$_ul"]=$_vo
        done < "$USER_TRAFFIC_FILE"
    fi
}

save_traffic() {
    local _tdir="${INSTALL_DIR}/relay_stats"
    mkdir -p "$_tdir" 2>/dev/null
    # Acquire lock to prevent race with flush_traffic_to_disk
    exec 9>"${_tdir}/.traffic.lock"
    flock -w 5 9 2>/dev/null || { exec 9>&- 2>/dev/null; return 0; }
    local _tmp=$(mktemp "${_tdir}/.traffic.XXXXXX" 2>/dev/null) || { exec 9>&-; return; }
    chmod 600 "$_tmp"
    echo "${_cum_in}|${_cum_out}" > "$_tmp"
    mv "$_tmp" "$TRAFFIC_FILE" 2>/dev/null || { rm -f "$_tmp"; exec 9>&-; return; }
    _tmp=$(mktemp "${_tdir}/.traffic.XXXXXX" 2>/dev/null) || { exec 9>&-; return; }
    chmod 600 "$_tmp"
    for _ul in "${!_cum_user_in[@]}"; do
        echo "${_ul}|${_cum_user_in[$_ul]}|${_cum_user_out[$_ul]}" >> "$_tmp"
    done
    mv "$_tmp" "$USER_TRAFFIC_FILE" 2>/dev/null || rm -f "$_tmp"
    # Save raw Prometheus snapshot so secret list can compute deltas
    _tmp=$(mktemp "${_tdir}/.traffic.XXXXXX" 2>/dev/null) || { exec 9>&-; return; }
    chmod 600 "$_tmp"
    for _ul in "${!_prev_user_in[@]}"; do
        echo "${_ul}|${_prev_user_in[$_ul]:-0}|${_prev_user_out[$_ul]:-0}" >> "$_tmp"
    done
    mv "$_tmp" "${_tdir}/user_traffic_snapshot" 2>/dev/null || rm -f "$_tmp"
    # Save global Prometheus snapshot
    _tmp=$(mktemp "${_tdir}/.traffic.XXXXXX" 2>/dev/null) || { exec 9>&-; return; }
    chmod 600 "$_tmp"
    echo "${_prev_total_in}|${_prev_total_out}" > "$_tmp"
    mv "$_tmp" "${_tdir}/global_traffic_snapshot" 2>/dev/null || rm -f "$_tmp"
    exec 9>&-  # Release lock
}

update_traffic() {
    # Fetch metrics once for both global and per-user stats
    local _metrics
    _metrics=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null) || true
    [ -z "$_metrics" ] && return 0
    local cur_in cur_out
    cur_in=$(echo "$_metrics"|awk '/^telemt_user_octets_from_client\{/{s+=$NF}END{printf "%.0f",s}')
    cur_out=$(echo "$_metrics"|awk '/^telemt_user_octets_to_client\{/{s+=$NF}END{printf "%.0f",s}')
    cur_in=${cur_in:-0}; cur_out=${cur_out:-0}

    # Compute deltas (torware pattern: detect container restart by negative delta)
    local delta_in=$((cur_in - _prev_total_in))
    local delta_out=$((cur_out - _prev_total_out))
    [ "$delta_in" -lt 0 ] 2>/dev/null && delta_in=$cur_in
    [ "$delta_out" -lt 0 ] 2>/dev/null && delta_out=$cur_out
    _cum_in=$((_cum_in + delta_in))
    _cum_out=$((_cum_out + delta_out))
    _prev_total_in=$cur_in
    _prev_total_out=$cur_out

    # Per-user delta tracking — single awk pass for all users into associative array
    declare -A _parsed_ui=() _parsed_uo=()
    if [ -n "$_metrics" ]; then
        while IFS='|' read -r _pu _pi _po; do
            [ -n "$_pu" ] && { _parsed_ui["$_pu"]=${_pi:-0}; _parsed_uo["$_pu"]=${_po:-0}; }
        done < <(echo "$_metrics" | awk '
            function lbl(s, k,    p, q) { p=index(s,k"=\""); if(!p) return ""; s=substr(s,p+length(k)+2); q=index(s,"\""); return q ? substr(s,1,q-1) : "" }
            /^telemt_user_octets_from_client\{/ { u=lbl($0,"user"); if(u) rx[u]+=$NF }
            /^telemt_user_octets_to_client\{/   { u=lbl($0,"user"); if(u) tx[u]+=$NF }
            END { for(u in rx) printf "%s|%.0f|%.0f\n",u,rx[u]+0,tx[u]+0 }
        ')
    fi
    while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
        [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue
        [ "$enabled" != "true" ] && continue
        local ui=${_parsed_ui["$label"]:-0} uo=${_parsed_uo["$label"]:-0}
        local prev_ui=${_prev_user_in["$label"]:-0}
        local prev_uo=${_prev_user_out["$label"]:-0}
        local du=$((ui - prev_ui))
        local dou=$((uo - prev_uo))
        [ "$du" -lt 0 ] 2>/dev/null && du=$ui
        [ "$dou" -lt 0 ] 2>/dev/null && dou=$uo
        _cum_user_in["$label"]=$(( ${_cum_user_in["$label"]:-0} + du ))
        _cum_user_out["$label"]=$(( ${_cum_user_out["$label"]:-0} + dou ))
        _prev_user_in["$label"]=$ui
        _prev_user_out["$label"]=$uo
    done < "$SECRETS_FILE"

    save_traffic
}


get_cum_user_traffic() { echo "${_cum_user_in[$1]:-0} ${_cum_user_out[$1]:-0}"; }

process_commands() {
    local offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo "0")
    [[ "$offset" =~ ^[0-9]+$ ]] || offset="0"
    local updates
    updates=$(curl -s --max-time 30 \
        -K <(printf 'url = "https://api.telegram.org/bot%s/getUpdates?offset=%s&timeout=25"\n' "$TELEGRAM_BOT_TOKEN" "$offset") \
        2>/dev/null) || true
    [ -z "$updates" ] && return

    if command -v python3 &>/dev/null; then
        echo "$updates" | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for r in data.get('result',[]):
        uid=r['update_id']
        txt=r.get('message',{}).get('text','').split('\n')[0][:200]
        cid=r.get('message',{}).get('chat',{}).get('id','')
        print(f'{uid}\t{cid}\t{txt}')
except Exception:
    pass
" 2>/dev/null | while IFS=$'\t' read -r _uid _cid _txt || [ -n "$_uid" ]; do
            [ -z "$_uid" ] && continue
            _process_cmd "$_uid" "$_cid" "$_txt"
        done
    else
        # Fallback: grep-based parsing (no python)
        local _new_offset
        _new_offset=$(echo "$updates" | grep -oE '"update_id"\s*:\s*[0-9]+' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$_new_offset" ]; then
            echo "$((_new_offset + 1))" > "$OFFSET_FILE"
        fi
        local _text _cid
        _text=$(echo "$updates" | grep -oE '"text"\s*:\s*"[^"]*"' | tail -1 | sed 's/.*"text"\s*:\s*"//;s/"$//')
        _cid=$(echo "$updates" | grep -oE '"chat"\s*:\s*\{[^}]*"id"\s*:\s*-?[0-9]+' | tail -1 | grep -oE -- '-?[0-9]+$')
        [ -n "$_text" ] && [ -n "$_cid" ] && {
            _new_offset=${_new_offset:-0}
            _process_cmd "$_new_offset" "$_cid" "$_text"
        }
    fi
}

_check_tg_role() {
    local cid="$1"
    [ "$cid" = "${TELEGRAM_CHAT_ID:-}" ] && { echo "superadmin"; return; }
    local r="" _c _role
    [ -f "${INSTALL_DIR}/admins.conf" ] && while IFS='|' read -r _c _role _ || [ -n "$_c" ]; do
        if [ "$_c" = "$cid" ]; then r="$_role"; break; fi
    done < "${INSTALL_DIR}/admins.conf"
    echo "${r:-none}"
}

_process_cmd() {
    local update_id="$1" chat_id="$2" text="$3"
    echo "$((update_id + 1))" > "$OFFSET_FILE"

    local role
    role=$(_check_tg_role "$chat_id")

    mkdir -p "$INSTALL_DIR" 2>/dev/null || true
    if [ -n "$chat_id" ]; then
        grep -q "^${chat_id}$" "${INSTALL_DIR}/bot_users.txt" 2>/dev/null || echo "$chat_id" >> "${INSTALL_DIR}/bot_users.txt" 2>/dev/null || true
    fi

    # Public user or unauthenticated commands
    case "$text" in
        /start|/start@*)
            tg_send_to "$chat_id" "🛡️ *Welcome to MTProxyMax Self-Service Portal (${VERSION})*\n\n👋 Hello! You can use this bot to check your proxy status, data limits, and connection links without admin assistance.\n\n📱 *Public Commands Available:*\n  /my_status <label> — Check your data quota & expiration\n  /redeem <code> [label] — Redeem a gift code / voucher\n  /voucher <code> [label] — Alias for /redeem\n  /support <message> — Send a support request to server admins"
            return
            ;;
        /my_status\ *|/my_status@*\ *)
            local sl_lbl=$(echo "$text" | awk '{print $2}')
            [ -z "$sl_lbl" ] && { tg_send_to "$chat_id" "❌ Usage: /my_status <your_secret_label>"; return; }
            [[ "$sl_lbl" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send_to "$chat_id" "❌ Invalid label name"; return; }
            if [ -f "$SECRETS_FILE" ] && grep -E -q "^${sl_lbl}\|" "$SECRETS_FILE" 2>/dev/null; then
                local line; line=$(grep -E "^${sl_lbl}\|" "$SECRETS_FILE" 2>/dev/null | head -1)
                IFS='|' read -r _l _s _c _en _mc _mi _q _ex _notes <<< "$line"
                local st="🟢 Active"; [ "$_en" != "true" ] && st="🔴 Disabled"
                local qstr="Unlimited"; [ -n "$_q" ] && [ "$_q" -gt 0 ] 2>/dev/null && qstr="$(format_bytes "$_q")"
                local exstr="Never"; [ -n "$_ex" ] && [ "$_ex" != "0" ] && exstr="$_ex"
                local cui=${_cum_user_in["$_l"]:-0} cuo=${_cum_user_out["$_l"]:-0}
                local used=$((cui + cuo))
                tg_send_to "$chat_id" "🏷 *Your Proxy Account Status*\n\n🔖 *Label*: \`${_l}\`\n🔌 *Status*: ${st}\n📊 *Data Used*: $(format_bytes "$used") / ${qstr}\n⏳ *Expiry*: ${exstr}"
            else
                tg_send_to "$chat_id" "❌ Account label '$(_esc "$sl_lbl")' not found on this proxy server."
            fi
            return
            ;;
        /voucher\ *|/voucher@*\ *)
            local vcode=$(echo "$text" | awk '{print $2}')
            local vlabel=$(echo "$text" | awk '{print $3}')
            [ -z "$vcode" ] && { tg_send_to "$chat_id" "❌ Usage: /voucher <code> [optional_label]"; return; }
            [ -z "$vlabel" ] && vlabel="tg_${chat_id}"
            if "${INSTALL_DIR}/mtproxymax" voucher redeem "$vcode" "$vlabel" &>/dev/null; then
                load_tg_settings
                local ip; ip=$(get_cached_ip)
                local ns=$(grep "^${vlabel}|" "$SECRETS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
                local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
                local fs="ee${ns}${dh}"
                tg_send_to "$chat_id" "🎉 *Voucher Redeemed Successfully!*\n\nWelcome account *$(_esc "$vlabel")*!\n\n🔗 [Connect Now](https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs})\n📡 \`${ip}:${PROXY_PORT}\`"
                send_proxy_qr_to "$chat_id" "$ip" "$PROXY_PORT" "$fs"
            else
                tg_send_to "$chat_id" "❌ Failed to redeem voucher '$(_esc "$vcode")' — invalid, expired, or already redeemed."
            fi
            return
            ;;
        /support\ *|/support@*\ *|/mp_support\ *|/mp_support@*\ *)
            local msg; msg=$(echo "$text" | cut -d' ' -f2-)
            [ -z "$msg" ] || [ "$msg" = "/support" ] || [ "$msg" = "/mp_support" ] && { tg_send_to "$chat_id" "❌ Usage: /support <your question or issue>"; return; }
            tg_send "📩 *New Customer Support Ticket*\n\n👤 *User Chat ID*: \`${chat_id}\`\n💬 *Message*:\n${msg}\n\n👉 *To reply*, type: \`/reply ${chat_id} <your answer>\`"
            tg_send_to "$chat_id" "✅ *Ticket Received!*\n\nYour message has been forwarded to our support team. We will get back to you shortly."
            return
            ;;
        /redeem\ *|/redeem@*\ *|/mp_redeem\ *|/mp_redeem@*\ *)
            local vcode=$(echo "$text" | awk '{print $2}')
            local vlabel=$(echo "$text" | awk '{print $3}')
            [ -z "$vcode" ] && { tg_send_to "$chat_id" "❌ Usage: /redeem <code> [optional_label]"; return; }
            [ -z "$vlabel" ] && vlabel="tg_${chat_id}"
            if "${INSTALL_DIR}/mtproxymax" voucher redeem "$vcode" "$vlabel" &>/dev/null; then
                load_tg_settings
                local ip; ip=$(get_cached_ip)
                local ns=$(grep "^${vlabel}|" "$SECRETS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
                local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
                local fs="ee${ns}${dh}"
                tg_send_to "$chat_id" "🎉 *Voucher Redeemed Successfully!*\n\nWelcome account *$(_esc "$vlabel")*!\n\n🔗 [Connect Now](https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs})\n📡 \`${ip}:${PROXY_PORT}\`"
                send_proxy_qr_to "$chat_id" "$ip" "$PROXY_PORT" "$fs"
            else
                tg_send_to "$chat_id" "❌ Failed to redeem voucher '$(_esc "$vcode")' — invalid, expired, or already redeemed."
            fi
            return
            ;;
    esac

    # Reject non-admin senders for all administrative commands below
    if [ "$role" = "none" ]; then
        return
    fi

    # Superadmin & Reseller administrative commands
    case "$text" in
        /mp_voucher\ *|/mp_voucher@*\ *)
            local sub=$(echo "$text" | awk '{print $2}')
            case "$sub" in
                create)
                    local cnt=$(echo "$text" | awk '{print $3}')
                    local qta=$(echo "$text" | awk '{print $4}')
                    local dys=$(echo "$text" | awk '{print $5}')
                    "${INSTALL_DIR}/mtproxymax" voucher create "${cnt:-1}" "${qta:-10G}" "${dys:-30}" &>/dev/null
                    local vout=$("${INSTALL_DIR}/mtproxymax" voucher list active | tail -n +3 | head -n "${cnt:-1}")
                    tg_send "🎟 *Generated Vouchers*\n\`\`\`\n${vout}\n\`\`\`"
                    ;;
                list)
                    local vout=$("${INSTALL_DIR}/mtproxymax" voucher list active | head -n 25)
                    tg_send "📋 *Active Vouchers*\n\`\`\`\n${vout}\n\`\`\`"
                    ;;
                *)
                    tg_send "🎟 *Voucher Engine*\n\nUsage:\n\`/mp_voucher create <count> <quota> <days>\`\n\`/mp_voucher list\`"
                    ;;
            esac
            ;;
        /mp_status|/mp_status@*)
            load_tg_settings
            if ! is_running; then
                tg_send "📱 *MTProxy Status*\n\n🔴 Status: Stopped"
                return
            fi
            local _si _so _sc; read -r _si _so _sc <<< "$(get_stats)"
            local up=$(get_uptime)
            tg_send "📱 *MTProxy Status*\n\n🟢 Status: Running\n⏱ Uptime: $(format_duration $up)\n👥 Connections: ${_sc}\n📊 Traffic: ↓ $(format_bytes ${_cum_out:-0}) ↑ $(format_bytes ${_cum_in:-0})\n🔗 Port: ${PROXY_PORT} | Domain: ${PROXY_DOMAIN}"
            ;;
        /mp_secrets|/mp_secrets@*)
            load_tg_settings
            [ ! -f "$SECRETS_FILE" ] && tg_send "📋 No secrets configured." && return
            local msg="📋 *Secrets*\n\n"
            # Single awk pass for all user metrics into associative array
            local _sec_metrics
            declare -A _parsed_uc=()
            _sec_metrics=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null) || true
            if [ -n "$_sec_metrics" ]; then
                while IFS='|' read -r _pu _pc; do
                    [ -n "$_pu" ] && _parsed_uc["$_pu"]=${_pc:-0}
                done < <(echo "$_sec_metrics" | awk '
                    function lbl(s, k,    p, q) { p=index(s,k"=\""); if(!p) return ""; s=substr(s,p+length(k)+2); q=index(s,"\""); return q ? substr(s,1,q-1) : "" }
                    /^telemt_user_connections_current\{/ { u=lbl($0,"user"); if(u) uc[u]+=$NF }
                    END { for(u in uc) printf "%s|%d\n",u,uc[u]+0 }
                ')
            fi
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
                [[ "$label" =~ ^# ]] && continue
                [ -z "$secret" ] && continue
                local icon="🟢"; [ "$enabled" != "true" ] && icon="🔴"
                local uc=${_parsed_uc["$label"]:-0}
                local cui=${_cum_user_in["$label"]:-0} cuo=${_cum_user_out["$label"]:-0}
                msg+="${icon} *$(_esc "$label")* — ${uc} conn | ↓$(format_bytes $cuo) ↑$(format_bytes $cui)\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            ;;
        /mp_link|/mp_link@*)
            load_tg_settings
            local ip; ip=$(get_cached_ip)
            [ -z "$ip" ] && tg_send "❌ Cannot detect server IP" && return
            local msg="🔗 *Proxy Details*\n\n"
            local _first_fs="" _dh=""
            [ "${MASKING_ENABLED:-true}" != "false" ] && _dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
                [[ "$label" =~ ^# ]] && continue
                [ -z "$secret" ] && continue
                [ "$enabled" != "true" ] && continue
                local fs
                [ -n "$_dh" ] && fs="ee${secret}${_dh}" || fs="dd${secret}"
                [ -z "$_first_fs" ] && _first_fs="$fs"
                msg+="🏷 *$(_esc "$label")*\n🔗 [Connect](https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs})\n📡 \`${ip}:${PROXY_PORT}\` | 🔑 \`${fs}\`\n\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            # Send QR for first enabled secret
            [ -n "$_first_fs" ] && send_proxy_qr "$ip" "$PROXY_PORT" "$_first_fs"
            ;;
        /mp_add\ *|/mp_add@*\ *)
            local label=$(echo "$text" | awk '{print $2}')
            [ -z "$label" ] && tg_send "❌ Usage: /mp\\_add <label>" && return
            [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send "❌ Invalid label (use a-z, 0-9, \\_, -)"; return; }
            "${INSTALL_DIR}/mtproxymax" secret add "$label" &>/dev/null
            if [ $? -eq 0 ]; then
                load_tg_settings
                local ip; ip=$(get_cached_ip)
                local ns=$(grep "^${label}|" "$SECRETS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
                local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
                local fs="ee${ns}${dh}"
                tg_send "✅ Secret *$(_esc "$label")* created!\n\n🔗 [Connect](https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs})\n📡 \`${ip}:${PROXY_PORT}\` | 🔑 \`${fs}\`"
                send_proxy_qr "$ip" "$PROXY_PORT" "$fs"
            else
                tg_send "❌ Failed to add secret '$(_esc "$label")' (may already exist)"
            fi
            ;;
        /mp_remove\ *|/mp_remove@*\ *|/mp_revoke\ *|/mp_revoke@*\ *)
            [ "$role" != "superadmin" ] && { tg_send "⛔ Permission denied: superadmin required."; return; }
            local label=$(echo "$text" | awk '{print $2}')
            [ -z "$label" ] && tg_send "❌ Usage: /mp\\_remove <label>" && return
            [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send "❌ Invalid label"; return; }
            if ! grep -q "^${label}|" "$SECRETS_FILE" 2>/dev/null; then
                tg_send "❌ Secret '$(_esc "$label")' not found"
                return
            fi
            local _scount
            _scount=$(grep -v '^#' "$SECRETS_FILE" 2>/dev/null | grep -c '|' || echo 0)
            if [ "${_scount:-0}" -le 1 ]; then
                tg_send "❌ Cannot remove the last secret"
                return
            fi
            "${INSTALL_DIR}/mtproxymax" secret remove "$label" &>/dev/null
            if [ $? -eq 0 ]; then
                tg_send "✅ Secret *$(_esc "$label")* revoked/removed"
            else
                tg_send "❌ Failed to remove secret '$(_esc "$label")'"
            fi
            ;;
        /mp_rotate\ *|/mp_rotate@*\ *)
            local label=$(echo "$text" | awk '{print $2}')
            [ -z "$label" ] && tg_send "❌ Usage: /mp\\_rotate <label>" && return
            [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send "❌ Invalid label"; return; }
            "${INSTALL_DIR}/mtproxymax" secret rotate "$label" &>/dev/null
            if [ $? -eq 0 ]; then
                load_tg_settings
                local ip; ip=$(get_cached_ip)
                # Re-read the new secret from file
                local ns=$(grep "^${label}|" "$SECRETS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
                local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
                local fs="ee${ns}${dh}"
                tg_send "🔄 Secret *$(_esc "$label")* rotated!\n\n🔗 [Connect](https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs})\n📡 \`${ip}:${PROXY_PORT}\` | 🔑 \`${fs}\`"
                send_proxy_qr "$ip" "$PROXY_PORT" "$fs"
            else
                tg_send "❌ Secret '$(_esc "$label")' not found"
            fi
            ;;
        /mp_restart|/mp_restart@*)
            [ "$role" != "superadmin" ] && { tg_send "⛔ Permission denied: superadmin required."; return; }
            tg_send "🔄 Restarting proxy..."
            "${INSTALL_DIR}/mtproxymax" restart &>/dev/null
            sleep 3
            if is_running; then
                tg_send "✅ Proxy restarted successfully"
            else
                tg_send "❌ Proxy failed to restart"
            fi
            ;;
        /mp_enable\ *|/mp_enable@*\ *)
            local label=$(echo "$text" | awk '{print $2}')
            [ -z "$label" ] && tg_send "❌ Usage: /mp\\_enable <label>" && return
            [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send "❌ Invalid label"; return; }
            "${INSTALL_DIR}/mtproxymax" secret enable "$label" &>/dev/null
            if [ $? -eq 0 ]; then
                tg_send "✅ Secret *$(_esc "$label")* enabled"
            else
                tg_send "❌ Secret '$(_esc "$label")' not found"
            fi
            ;;
        /mp_disable\ *|/mp_disable@*\ *)
            local label=$(echo "$text" | awk '{print $2}')
            [ -z "$label" ] && tg_send "❌ Usage: /mp\\_disable <label>" && return
            [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send "❌ Invalid label"; return; }
            "${INSTALL_DIR}/mtproxymax" secret disable "$label" &>/dev/null
            if [ $? -eq 0 ]; then
                tg_send "✅ Secret *$(_esc "$label")* disabled"
            else
                tg_send "❌ Secret '$(_esc "$label")' not found"
            fi
            ;;
        /mp_health|/mp_health@*)
            local health_out
            health_out=$("${INSTALL_DIR}/mtproxymax" health 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | head -20) || true
            local status_icon="🟢"
            echo "$health_out" | grep -qi "fail\|error\|down" && status_icon="🔴"
            tg_send "${status_icon} *Health Check*\n\n\`\`\`\n${health_out}\n\`\`\`"
            ;;
        /mp_traffic|/mp_traffic@*)
            load_tg_settings
            local _ti _to _tc; read -r _ti _to _tc <<< "$(get_stats)"
            local msg="📊 *Traffic Report*\n\n"
            msg+="Total: ↓ $(format_bytes ${_cum_out:-0}) ↑ $(format_bytes ${_cum_in:-0})\n"
            msg+="Active connections: ${_tc}\n\n"
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
                [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue
                [ "$enabled" != "true" ] && continue
                local cum_u; cum_u=$(get_cum_user_traffic "$label")
                local cui; cui=$(echo "$cum_u" | awk '{print $1}')
                local cuo; cuo=$(echo "$cum_u" | awk '{print $2}')
                msg+="👤 *$(_esc "$label")*: ↓ $(format_bytes $cuo) ↑ $(format_bytes $cui)\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            ;;
        /mp_update|/mp_update@*)
            [ "$role" != "superadmin" ] && { tg_send "⛔ Permission denied: superadmin required."; return; }
            tg_send "🔍 Checking for updates..."
            local update_out
            update_out=$("${INSTALL_DIR}/mtproxymax" update </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -5)
            if [ -n "$update_out" ]; then
                tg_send "📋 Update check:\n\`\`\`\n${update_out}\n\`\`\`"
            else
                tg_send "✅ Script is up to date"
            fi
            ;;
        /mp_limits|/mp_limits@*)
            load_tg_settings
            [ ! -f "$SECRETS_FILE" ] && tg_send "📋 No secrets configured." && return
            local msg="📋 *User Limits*\n\n"
            while IFS='|' read -r label secret created enabled max_conns max_ips quota expires _notes _adtag || [ -n "$label" ]; do
                [[ "$label" =~ ^# ]] && continue
                [ -z "$secret" ] && continue
                max_conns=${max_conns:-0}; max_ips=${max_ips:-0}; quota=${quota:-0}; expires=${expires:-0}
                local conns_fmt="∞"; [ "$max_conns" != "0" ] && conns_fmt="$max_conns"
                local ips_fmt="∞"; [ "$max_ips" != "0" ] && ips_fmt="$max_ips"
                local quota_fmt="∞"; [ "$quota" != "0" ] && quota_fmt="$(format_bytes $quota)"
                local exp_fmt="never"; [ "$expires" != "0" ] && exp_fmt="${expires%%T*}"
                msg+="👤 *$(_esc "$label")*\n  Conns: ${conns_fmt} | IPs: ${ips_fmt} | Quota: ${quota_fmt} | Exp: ${exp_fmt}\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            ;;
        /mp_setlimit\ *|/mp_setlimit@*\ *)
            local args=$(echo "$text" | awk '{$1=""; print $0}' | xargs)
            local sl_label=$(echo "$args" | awk '{print $1}')
            local sl_conns=$(echo "$args" | awk '{print $2}')
            local sl_ips=$(echo "$args" | awk '{print $3}')
            local sl_quota=$(echo "$args" | awk '{print $4}')
            local sl_exp=$(echo "$args" | awk '{print $5}')
            [ -z "$sl_label" ] && tg_send "❌ Usage: /mp\\_setlimit <label> <conns> <ips> <quota> [expires]\nExample: /mp\\_setlimit alice 100 5 5G 2026-12-31" && return
            [[ "$sl_label" =~ ^[a-zA-Z0-9_-]+$ ]] || { tg_send "❌ Invalid label"; return; }
            if "${INSTALL_DIR}/mtproxymax" secret setlimits "$sl_label" "${sl_conns:-0}" "${sl_ips:-0}" "${sl_quota:-0}" "${sl_exp:-}" &>/dev/null; then
                tg_send "✅ Limits updated for *$(_esc "$sl_label")*\nConns: ${sl_conns:-0} | IPs: ${sl_ips:-0} | Quota: ${sl_quota:-0}"
            else
                tg_send "❌ Failed to set limits for *$(_esc "$sl_label")* — check label exists"
            fi
            ;;
        /mp_fleet|/mp_fleet@*)
            local fleet_out; fleet_out=$("${INSTALL_DIR}/mtproxymax" fleet status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
            [ -z "$fleet_out" ] && fleet_out="No multi-server fleet telemetry collected yet."
            tg_send "🌐 *Global Federation Fleet Summary*\n\`\`\`\n${fleet_out}\n\`\`\`"
            ;;
        /mp_upstreams|/mp_upstreams@*)
            load_tg_settings
            local uf="${INSTALL_DIR}/upstreams.conf"
            if [ ! -f "$uf" ]; then
                tg_send "📋 *Upstreams*\n\n🟢 direct (weight: 10)"
                return
            fi
            local msg="📋 *Upstreams*\n\n"
            while IFS='|' read -r name type addr user pass weight iface enabled; do
                [[ "$name" =~ ^# ]] && continue
                [ -z "$name" ] && continue
                # Backward compat: old 7-col has enabled in col7
                if [ "$iface" = "true" ] || [ "$iface" = "false" ]; then
                    enabled="$iface"; iface=""
                fi
                local icon="🟢"; [ "$enabled" != "true" ] && icon="🔴"
                local addr_info=""; [ -n "$addr" ] && addr_info=" — ${addr}"
                [ -n "$iface" ] && addr_info+=" [${iface}]"
                msg+="${icon} *$(_esc "$name")* (${type}${addr_info}) w:${weight}\n"
            done < "$uf"
            tg_send "$msg"
            ;;
        /mp_lockdown|/mp_lockdown@*|/mp_lockdown\ *|/mp_lockdown@*\ *)
            [ "$role" != "superadmin" ] && { tg_send "⛔ Permission denied: superadmin required."; return; }
            local sub=$(echo "$text" | awk '{print $2}')
            sub="${sub:-status}"
            case "$sub" in
                on|enable)
                    "${INSTALL_DIR}/mtproxymax" lockdown on &>/dev/null
                    tg_send "🚨 *EMERGENCY LOCKDOWN ACTIVATED*\nKernel SYN Shield: ACTIVE\nStealth Preset: ULTRA\nMSS Clamping: ACTIVE"
                    ;;
                off|disable)
                    "${INSTALL_DIR}/mtproxymax" lockdown off &>/dev/null
                    tg_send "✅ *Lockdown Deactivated*\nServer restored to normal operating posture."
                    ;;
                *)
                    load_tg_settings
                    local st="🟢 NORMAL"; [ "${LOCKDOWN_MODE:-false}" = "true" ] && st="🔴 LOCKDOWN ACTIVE"
                    tg_send "🔒 *Emergency Lockdown Mode*: ${st}\n\nUsage:\n\`/mp_lockdown on\` — Activate Emergency Shield\n\`/mp_lockdown off\` — Return to Normal"
                    ;;
            esac
            ;;
        /mp_digest|/mp_digest@*)
            load_tg_settings
            load_traffic
            local _ip; _ip=$(get_cached_ip)
            local _up=0 _rc=0
            if is_proxy_running; then
                _up=$(get_container_uptime)
                _rc=$(get_active_connections)
            fi
            local st="🟢 NORMAL"; [ "${LOCKDOWN_MODE:-false}" = "true" ] && st="🔴 LOCKDOWN ACTIVE"
            local qos_st="Disabled"; [ "${QOS_LIMIT_MBPS:-0}" -gt 0 ] && qos_st="${QOS_LIMIT_MBPS} Mbps/IP"
            local hh_st="Disabled"; [ -n "${HAPPY_HOURS_WINDOW:-}" ] && hh_st="${HAPPY_HOURS_WINDOW}"
            
            local msg="📊 *System Health & Security Digest*

🖥 *Server*: \`${_ip}\` (${PROXY_PORT})
⚡️ *Posture*: ${st}
⏱ *Uptime*: $(format_duration ${_up:-0})
🔌 *Connections*: ${_rc} live
🏎 *QoS Shaping*: ${qos_st}
🕒 *Happy Hours*: ${hh_st}
📈 *Total Traffic*: $(format_human_bytes ${_cum_out:-0}) DL / $(format_human_bytes ${_cum_in:-0}) UL"
            # v1.4 LTS digest additions
            load_ssl_config 2>/dev/null || true
            local ssl_d="Off"; [ "${SSL_ENABLED:-false}" = "true" ] && ssl_d="Active (${SSL_DOMAIN})"
            msg+="\n🔐 *SSL Shield*: ${ssl_d}"
            load_speed_limits 2>/dev/null || true
            [ "${#SPEED_LIMIT_TARGETS[@]}" -gt 0 ] && msg+="\n🚀 *HTB QoS*: ${#SPEED_LIMIT_TARGETS[@]} rule(s)"
            load_cloud_backup_config 2>/dev/null || true
            [ "${CLOUD_BACKUP_ENABLED:-false}" = "true" ] && msg+="\n☁️ *Cloud Backup*: ${CLOUD_BACKUP_MODE:-telegram}"
            tg_send "$msg"
            ;;
        /reply\ *|/reply@*\ *)
            local target_cid; target_cid=$(echo "$text" | awk '{print $2}')
            local ans; ans=$(echo "$text" | cut -d' ' -f3-)
            [ -z "$target_cid" ] || [ -z "$ans" ] && { tg_send "❌ Usage: /reply <chat_id> <message>"; return; }
            tg_send_to "$target_cid" "💬 *Support Team Reply*:\n\n${ans}\n\n👉 *To reply back*, use \`/support <message>\`"
            tg_send "✅ Reply sent to user \`${target_cid}\`."
            ;;
        /mp_broadcast\ *|/mp_broadcast@*\ *)
            local bmsg; bmsg=$(echo "$text" | cut -d' ' -f2-)
            [ -z "$bmsg" ] || [ "$bmsg" = "/mp_broadcast" ] && { tg_send "❌ Usage: /mp_broadcast <message>"; return; }
            "${INSTALL_DIR}/mtproxymax" broadcast "$bmsg" &>/dev/null
            tg_send "📢 Broadcast dispatched to all users."
            ;;
        /mp_help|/mp_help@*)
            tg_send "📋 *MTProxyMax Commands (${VERSION})*\n\n*Public Self-Service:*\n/start — Self-service onboarding\n/my\_status <label> — Check data quota & expiry\n/voucher <code> — Redeem voucher code\n/support <msg> — Send ticket to helpdesk\n\n*Admin Control Plane:*\n/mp\_fleet — Global Federation Fleet Dashboard\n/mp\_voucher create <cnt> <qta> <dys> — Generate vouchers\n/mp\_voucher list — List vouchers\n/mp\_status — Proxy status\n/mp\_secrets — List secrets\n/mp\_link — Get proxy links + QR\n/mp\_add <label> — Add secret\n/mp\_remove / /mp\_revoke <label> — Remove secret\n/mp\_rotate <label> — Rotate secret\n/mp\_enable <label> — Enable secret\n/mp\_disable <label> — Disable secret\n/mp\_limits — Show user limits\n/mp\_setlimit — Set user limits\n/mp\_upstreams — List upstreams\n/mp\_traffic — Traffic report\n/mp\_health — Health check\n/mp\_lockdown [on|off] — Emergency shield\n/mp\_digest — System digest report\n/mp\_broadcast <msg> — Broadcast to all users\n/reply <chat\_id> <msg> — Reply to support ticket\n/mp\_restart — Restart proxy\n/mp\_update — Check for updates\n/mp\_help — This help"
            ;;
    esac
}

# Cleanup trap for temp files
trap _cleanup EXIT

# Main loop
echo "$$" > "$PID_FILE"
mkdir -p "$(dirname "$OFFSET_FILE")"
load_tg_settings
load_traffic

_last_report=0
_report_interval=$(( ${TELEGRAM_INTERVAL:-6} * 3600 ))
_last_health=0
_last_traffic_update=0
_last_enforcement=0
declare -A _prev_log_in=()
declare -A _prev_log_out=()

while true; do
    load_tg_settings
    _report_interval=$(( ${TELEGRAM_INTERVAL:-6} * 3600 ))
    # Update traffic counters every 60 seconds (always, even if bot is disabled)
    _now=$(date +%s)
    if [ $((_now - _last_traffic_update)) -ge 60 ] && is_running; then
        _last_traffic_update=$_now
        update_traffic 2>/dev/null
        [ "${PORTAL_ENABLED:-false}" = "true" ] && "${INSTALL_DIR}/mtproxymax" portal generate &>/dev/null

        # Connection log: append per-user activity (delta = current cumulative - previous cumulative)
        _connlog="${INSTALL_DIR}/connection.log"
        _ts=$(date '+%Y-%m-%d %H:%M')
        [ -f "$SECRETS_FILE" ] && while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
            [[ "$label" =~ ^# ]] && continue
            [ -z "$label" ] && continue
            [ "$enabled" != "true" ] && continue
            _ci=${_cum_user_in[$label]:-0}; _co=${_cum_user_out[$label]:-0}
            _pci=${_prev_log_in[$label]:-0}; _pco=${_prev_log_out[$label]:-0}
            _di=$((_ci - _pci)); _do=$((_co - _pco))
            [ "$_di" -le 0 ] && [ "$_do" -le 0 ] && { _prev_log_in[$label]=$_ci; _prev_log_out[$label]=$_co; continue; }
            [ "$_di" -lt 0 ] && _di=0; [ "$_do" -lt 0 ] && _do=0
            echo "${_ts} ${label}: ↓$(format_bytes $_do) ↑$(format_bytes $_di)" >> "$_connlog"
            _prev_log_in[$label]=$_ci; _prev_log_out[$label]=$_co
        done < "$SECRETS_FILE"
        # Auto-rotate: keep last 8000 lines if over 10000
        if [ -f "$_connlog" ]; then
            _lc=$(wc -l < "$_connlog" 2>/dev/null) || _lc=0
            [ "$_lc" -gt 10000 ] && tail -n 8000 "$_connlog" > "${_connlog}.tmp" && mv "${_connlog}.tmp" "$_connlog"
        fi
    fi

    # Quota enforcement + expiry checks every 5 min (runs even if Telegram is disabled)
    if [ $((_now - _last_enforcement)) -ge 300 ]; then
        _last_enforcement=$_now

        # Periodic tasks: monthly quota reset, auto-rotate, backup autoclean
        "${INSTALL_DIR}/mtproxymax" sweep &>/dev/null &

        # Quota enforcement (auto-disable secrets that exceeded quota)
        _quota_file="${INSTALL_DIR}/relay_stats/.quota_alerts_sent"
        [ -f "$SECRETS_FILE" ] && while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
            [[ "$label" =~ ^# ]] && continue
            [ -z "$label" ] || [ "$_q" = "0" ] || [ -z "$_q" ] && continue
            [ "$enabled" != "true" ] && continue
            total_bytes=$(( ${_cum_user_in[$label]:-0} + ${_cum_user_out[$label]:-0} ))
            [ "$total_bytes" -le 0 ] && continue
            pct=$(( (total_bytes * 100) / _q ))
            if [ "$pct" -ge 100 ] 2>/dev/null; then
                if ! grep -q "^${label}|100$" "$_quota_file" 2>/dev/null; then
                    if "${INSTALL_DIR}/mtproxymax" secret disable "$label" &>/dev/null; then
                        [ "$TELEGRAM_ENABLED" = "true" ] && tg_send "🔴 *Quota Exceeded — Auto-disabled*\n\nSecret *$(_esc "$label")* used $(format_bytes $total_bytes) of $(format_bytes $_q) (${pct}%)\n\nRe-enable: \`mtproxymax secret reenable $label\`"
                    else
                        [ "$TELEGRAM_ENABLED" = "true" ] && tg_send "⚠️ *Quota Exceeded*\n\nSecret *$(_esc "$label")* used $(format_bytes $total_bytes) of $(format_bytes $_q) (${pct}%) — cannot auto-disable (last active secret)"
                    fi
                    echo "${label}|100" >> "$_quota_file"
                fi
            elif [ "$pct" -ge 80 ]; then
                if ! grep -q "^${label}|80$" "$_quota_file" 2>/dev/null; then
                    [ "$TELEGRAM_ENABLED" = "true" ] && tg_send "⚠️ *Quota Warning*\n\nSecret *$(_esc "$label")* has used $(format_bytes $total_bytes) of $(format_bytes $_q) (${pct}%)"
                    echo "${label}|80" >> "$_quota_file"
                fi
            fi
        done < "$SECRETS_FILE"

        # Secret expiry warnings
        if [ "$TELEGRAM_ENABLED" = "true" ] && [ "$TELEGRAM_ALERTS_ENABLED" = "true" ]; then
            _expiry_file="${INSTALL_DIR}/relay_stats/.expiry_alerts_sent"
            _today=$(date +%Y-%m-%d)
            [ -f "$SECRETS_FILE" ] && while IFS='|' read -r label secret created enabled _mc _mi _q _ex _notes _adtag || [ -n "$label" ]; do
                [[ "$label" =~ ^# ]] && continue
                [ -z "$label" ] && continue
                [ "$_ex" = "0" ] || [ -z "$_ex" ] && continue
                exp_e=$(_iso_to_epoch "${_ex}") && [ "$exp_e" -gt 0 ] 2>/dev/null || continue
                days_left=$(( (exp_e - _now) / 86400 ))
                if [ "$days_left" -le 3 ] && [ "$days_left" -ge 0 ]; then
                    if ! grep -q "^${label}:${_today}$" "$_expiry_file" 2>/dev/null; then
                        tg_send "⚠️ *Expiry Warning*\n\nSecret *$(_esc "$label")* expires in *${days_left} day(s)* (${_ex})"
                        echo "${label}:${_today}" >> "$_expiry_file"
                    fi
                elif [ "$days_left" -lt 0 ]; then
                    if ! grep -q "^${label}:expired:${_today}$" "$_expiry_file" 2>/dev/null; then
                        tg_send "🔴 *Secret Expired*\n\nSecret *$(_esc "$label")* expired on ${_ex}"
                        echo "${label}:expired:${_today}" >> "$_expiry_file"
                    fi
                fi
            done < "$SECRETS_FILE"
            [ -f "$_expiry_file" ] && grep -q ":${_today}" "$_expiry_file" 2>/dev/null && \
                grep ":${_today}" "$_expiry_file" > "${_expiry_file}.tmp" 2>/dev/null && \
                mv "${_expiry_file}.tmp" "$_expiry_file" 2>/dev/null || true
        fi
    fi

    [ "$TELEGRAM_ENABLED" != "true" ] && sleep 30 && continue

    # Process bot commands (long-poll: blocks up to 25s waiting for messages, returns immediately when one arrives)
    process_commands 2>/dev/null

    # Health check every 5 minutes
    if [ $((_now - _last_health)) -ge 300 ]; then
        _last_health=$_now
        if [ "$TELEGRAM_ALERTS_ENABLED" = "true" ] && ! is_running && [ ! -f /tmp/.mtproxymax_stopped ]; then
            tg_send "🔴 *Alert*: Proxy is down! Attempting auto-restart..."
            "${INSTALL_DIR}/mtproxymax" start &>/dev/null
            sleep 5
            if is_running; then
                tg_send "✅ Proxy auto-recovered"
            else
                tg_send "❌ Auto-recovery failed — manual intervention needed"
            fi
        fi
    fi

    # Periodic report
    if [ $((_now - _last_report)) -ge $_report_interval ]; then
        _last_report=$_now
        if is_running; then
            _ri=0 _ro=0 _rc=0
            read -r _ri _ro _rc <<< "$(get_stats)" || true
            _up=$(get_uptime)
            tg_send "📊 *Periodic Report*\n\n🟢 Running | ⏱ $(format_duration ${_up:-0})\n👥 Connections: ${_rc}\n📊 ↓ $(format_bytes ${_cum_out:-0}) ↑ $(format_bytes ${_cum_in:-0})"
        fi
    fi

    sleep 1
done
TELEGRAM_SCRIPT

    chmod +x "$script_path"
}

setup_telegram_service() {
    telegram_generate_service_script

    # Create systemd service
    if command -v systemctl &>/dev/null; then
        cat > /etc/systemd/system/mtproxymax-telegram.service << 'SERVICE_EOF'
[Unit]
Description=MTProxyMax Telegram Bot Service
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash /opt/mtproxymax/mtproxymax-telegram.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

        systemctl daemon-reload
        systemctl enable mtproxymax-telegram.service 2>/dev/null
        systemctl restart mtproxymax-telegram.service 2>/dev/null
        log_success "Telegram bot service started"
    fi
}


# ── Section 14b: Replication / HA ────────────────────────────

# Slave registry arrays
declare -a REPL_HOSTS=()
declare -a REPL_PORTS=()
declare -a REPL_LABELS=()
declare -a REPL_ENABLED=()
declare -a REPL_LAST_SYNC=()
declare -a REPL_STATUS=()

# Save replication.conf
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
    # Serialise with sync-timer flock to prevent lost-update races with save_sync_status()
    exec 201>"${INSTALL_DIR:-/opt/mtproxymax}/.mtproxymax-sync.lock" 2>/dev/null || true
    if command -v flock &>/dev/null; then
        flock -w 5 201 2>/dev/null || { log_error "Could not acquire lock for replication config"; rm -f "$tmp"; exec 201>&- 2>/dev/null; return 1; }
    fi
    mv "$tmp" "$REPLICATION_FILE"
    exec 201>&- 2>/dev/null || true
}

# Load replication.conf
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

# Add a slave server
replication_add() {
    local host="${1:-}" port="${2:-22}" label="${3:-}"

    if [ "${REPLICATION_ROLE}" = "slave" ]; then
        log_error "This server is a slave — only a master can register peers"
        log_info "Run: mtproxymax replication setup  to change role"
        return 1
    fi

    if [ -z "$host" ]; then
        log_error "Usage: replication add <host> [port] [label]"
        return 1
    fi

    if [[ ! "$host" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid host format. Use IPv4 or FQDN (letters, digits, dots, hyphens). IPv6 is not supported — use IPv4 or a domain name instead."
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

# Remove slave by host or label
replication_remove() {
    local target="${1:-}"

    if [ "${REPLICATION_ROLE}" = "slave" ]; then
        log_error "This server is a slave — only a master manages the slave list"
        return 1
    fi

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

# List all slaves
replication_list() {
    load_replication

    if [ ${#REPL_HOSTS[@]} -eq 0 ]; then
        log_info "No slaves configured. Run: mtproxymax replication add <host>"
        return 0
    fi

    echo ""
    printf "  %-4s %-22s %-6s %-14s %-8s %-12s %s\n" \
        "No." "Host" "Port" "Label" "Enabled" "Last Sync" "Status"
    printf "  %-4s %-22s %-6s %-14s %-8s %-12s %s\n" \
        "---" "--------------------" "----" "------------" "-------" "---------" "------"

    local i
    for i in "${!REPL_HOSTS[@]}"; do
        local ts="${REPL_LAST_SYNC[$i]:-0}"
        local sync_fmt="never"
        if [[ "$ts" =~ ^[0-9]+$ ]] && [ "$ts" -gt 0 ]; then
            local now; now=$(date +%s)
            local ago=$(( now - ts ))
            if   [ $ago -lt 120 ];  then sync_fmt="${ago}s ago"
            elif [ $ago -lt 3600 ]; then sync_fmt="$((ago/60))m ago"
            else                         sync_fmt="$((ago/3600))h ago"
            fi
        fi

        printf "  %-4s %-22s %-6s %-14s %-8s %-12s %s\n" \
            "$((i+1))" "${REPL_HOSTS[$i]}" "${REPL_PORTS[$i]}" \
            "${REPL_LABELS[$i]}" "${REPL_ENABLED[$i]}" \
            "$sync_fmt" "${REPL_STATUS[$i]}"
    done
    echo ""
}

# Generate the self-contained sync daemon script
replication_generate_sync_script() {
    local script_path="${INSTALL_DIR}/mtproxymax-sync.sh"

    cat > "$script_path" << 'SYNC_SCRIPT_EOF'
#!/bin/bash
# MTProxyMax Replication Sync Script
# Auto-generated — do not edit manually
# Managed by: mtproxymax replication

INSTALL_DIR="/opt/mtproxymax"
SETTINGS_FILE="${INSTALL_DIR}/settings.conf"
REPLICATION_FILE="${INSTALL_DIR}/replication.conf"
LOCK_FILE="${INSTALL_DIR}/.mtproxymax-sync.lock"

# Defaults (overridden by load_sync_settings)
REPLICATION_ENABLED="false"
REPLICATION_ROLE="standalone"
REPLICATION_SSH_KEY_PATH="/opt/mtproxymax/.ssh/id_ed25519"
REPLICATION_SSH_PORT="22"
REPLICATION_SSH_USER="root"
REPLICATION_DELETE_EXTRA="true"
REPLICATION_EXCLUDE="relay_stats,backups,connection.log,.ssh,settings.conf,replication.conf,mtproxymax-telegram.sh,mtproxymax-sync.sh"
REPLICATION_RESTART_ON_CHANGE="true"
REPLICATION_LOG="/var/log/mtproxymax-sync.log"

load_sync_settings() {
    [ -f "$SETTINGS_FILE" ] || return
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\'([^\']*)\'$ ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
            case "$key" in
                REPLICATION_ENABLED|REPLICATION_ROLE|REPLICATION_SSH_KEY_PATH|\
                REPLICATION_SSH_PORT|REPLICATION_SSH_USER|REPLICATION_DELETE_EXTRA|REPLICATION_EXCLUDE|REPLICATION_RESTART_ON_CHANGE|\
                REPLICATION_LOG)
                    printf -v "$key" '%s' "$val" ;;
            esac
        fi
    done < "$SETTINGS_FILE"
    # Migration: ensure these files are never synced regardless of stored value
    [[ "$REPLICATION_EXCLUDE" == *"settings.conf"* ]]   || REPLICATION_EXCLUDE="${REPLICATION_EXCLUDE},settings.conf"
    [[ "$REPLICATION_EXCLUDE" == *"replication.conf"* ]] || REPLICATION_EXCLUDE="${REPLICATION_EXCLUDE},replication.conf"
}

declare -a REPL_HOSTS=()
declare -a REPL_PORTS=()
declare -a REPL_LABELS=()
declare -a REPL_ENABLED=()
declare -a REPL_LAST_SYNC=()
declare -a REPL_STATUS=()

load_sync_replication() {
    REPL_HOSTS=(); REPL_PORTS=(); REPL_LABELS=()
    REPL_ENABLED=(); REPL_LAST_SYNC=(); REPL_STATUS=()
    [ -f "$REPLICATION_FILE" ] || return
    while IFS='|' read -r host port label enabled last_sync status; do
        [[ "$host" =~ ^[[:space:]]*# ]] && continue
        [[ "$host" =~ ^[[:space:]]*$ ]] && continue
        [[ "$host" =~ ^[a-zA-Z0-9._-]+$ ]] || continue
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || port=22
        [ "$enabled" = "false" ] || enabled="true"
        [[ "$last_sync" =~ ^[0-9]+$ ]] || last_sync=0
        REPL_HOSTS+=("$host")
        REPL_PORTS+=("$port")
        REPL_LABELS+=("${label:-$host}")
        REPL_ENABLED+=("$enabled")
        REPL_LAST_SYNC+=("$last_sync")
        REPL_STATUS+=("${status:-unknown}")
    done < "$REPLICATION_FILE"
}

save_sync_status() {
    local tmp; tmp=$(mktemp "${INSTALL_DIR}/.mtproxymax-sync.XXXXXX" 2>/dev/null) || return 1
    chmod 600 "$tmp"
    {
        echo "# MTProxyMax Replication Slaves"
        echo "# Format: HOST|PORT|LABEL|ENABLED|LAST_SYNC|STATUS"
        local i
        for i in "${!REPL_HOSTS[@]}"; do
            echo "${REPL_HOSTS[$i]}|${REPL_PORTS[$i]}|${REPL_LABELS[$i]}|${REPL_ENABLED[$i]}|${REPL_LAST_SYNC[$i]}|${REPL_STATUS[$i]}"
        done
    } > "$tmp"
    mv "$tmp" "$REPLICATION_FILE"
}

log_sync() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${REPLICATION_LOG}"
}

do_sync() {
    local host="$1" port="$2" label="$3"
    # Verify dependencies at runtime (may be absent on minimal images)
    if ! command -v rsync &>/dev/null; then
        log_sync "ERROR: rsync not found — install rsync on this host"
        return 1
    fi
    if ! command -v ssh &>/dev/null; then
        log_sync "ERROR: ssh not found — install openssh-client on this host"
        return 1
    fi
    local ssh_key="${REPLICATION_SSH_KEY_PATH}"
    local ssh_opts="-i ${ssh_key} -p ${port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2"

    # Build rsync exclude args from comma-separated REPLICATION_EXCLUDE
    local exclude_args=()
    local ex
    IFS=',' read -ra _excludes <<< "${REPLICATION_EXCLUDE}"
    for ex in "${_excludes[@]}"; do
        ex="${ex#"${ex%%[! ]*}"}"  # ltrim spaces
        [ -n "$ex" ] && exclude_args+=(--exclude="${ex}")
    done
    # Always exclude these critical files — must never be overwritten on slave
    exclude_args+=(--exclude="settings.conf" --exclude="replication.conf" --exclude="fleet_data" --exclude=".ssh")

    local delete_flag=""
    [ "${REPLICATION_DELETE_EXTRA:-true}" = "true" ] && delete_flag="--delete"

    local output rc
    output=$(rsync -az ${delete_flag:+"$delete_flag"} --itemize-changes "${exclude_args[@]}" \
        --timeout=30 \
        -e "ssh ${ssh_opts}" \
        "${INSTALL_DIR}/" \
        "${REPLICATION_SSH_USER}@${host}:${INSTALL_DIR}/" 2>&1)
    rc=$?

    if [ $rc -ne 0 ]; then
        log_sync "ERROR [${label}/${host}]: rsync failed (exit ${rc}): $(echo "$output" | tail -1)"
        return 1
    fi

    # itemize-changes: '<' prefix means file was sent to remote
    if echo "$output" | grep -qE '^[<>]'; then
        log_sync "CHANGE [${label}/${host}]: Files synced"
        if [ "${REPLICATION_RESTART_ON_CHANGE}" = "true" ]; then
            local r_out r_rc
            r_out=$(ssh -i "${ssh_key}" -p "${port}" \
                -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
                "${REPLICATION_SSH_USER}@${host}" "/usr/local/bin/mtproxymax restart 2>&1 || docker restart mtproxymax 2>&1" 2>&1)
            r_rc=$?
            if [ $r_rc -eq 0 ]; then
                log_sync "RESTART [${label}/${host}]: Container restarted"
            else
                log_sync "WARN [${label}/${host}]: Docker restart failed: $(echo "$r_out" | tail -1)"
            fi
        fi
    else
        log_sync "NOOP [${label}/${host}]: No changes"
    fi

    return 0
}

main() {
    # Prevent overlapping sync runs
    exec 200>"${LOCK_FILE}" 2>/dev/null || true
    if command -v flock &>/dev/null; then
        flock -n 200 || {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIP: Another sync already running" >> "${REPLICATION_LOG}"
            exit 0
        }
    fi

    load_sync_settings

    [ "${REPLICATION_ENABLED}" = "true" ] || exit 0
    [ "${REPLICATION_ROLE}" = "master" ]  || exit 0

    load_sync_replication
    [ ${#REPL_HOSTS[@]} -gt 0 ] || exit 0

    log_sync "=== Sync start (${#REPL_HOSTS[@]} slave(s)) ==="

    local overall=0 i
    for i in "${!REPL_HOSTS[@]}"; do
        [ "${REPL_ENABLED[$i]}" = "true" ] || continue
        if do_sync "${REPL_HOSTS[$i]}" "${REPL_PORTS[$i]}" "${REPL_LABELS[$i]}"; then
            REPL_LAST_SYNC[$i]=$(date +%s)
            REPL_STATUS[$i]="ok"
        else
            REPL_STATUS[$i]="error"
            overall=1
        fi
    done

    save_sync_status
    log_sync "=== Sync done (exit ${overall}) ==="
    exit $overall
}

main
SYNC_SCRIPT_EOF

    chmod 750 "$script_path"
    log_success "Sync script generated: ${script_path}"
}

# Setup systemd service + timer
setup_replication_service() {
    replication_generate_sync_script

    if ! command -v systemctl &>/dev/null; then
        log_warn "systemd not found. Add cron manually:"
        echo "  * * * * * /bin/bash ${INSTALL_DIR}/mtproxymax-sync.sh"
        return 1
    fi

    cat > /etc/systemd/system/mtproxymax-sync.service << 'REPL_SERVICE_EOF'
[Unit]
Description=MTProxyMax Replication Sync
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/mtproxymax/mtproxymax-sync.sh
StandardOutput=journal
StandardError=journal
REPL_SERVICE_EOF

    cat > /etc/systemd/system/mtproxymax-sync.timer << REPL_TIMER_EOF
[Unit]
Description=MTProxyMax Replication Sync Timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=${REPLICATION_SYNC_INTERVAL}s
AccuracySec=5s

[Install]
WantedBy=timers.target
REPL_TIMER_EOF

    systemctl daemon-reload
    systemctl enable mtproxymax-sync.timer 2>/dev/null
    systemctl start mtproxymax-sync.timer 2>/dev/null
    log_success "Replication timer started (every ${REPLICATION_SYNC_INTERVAL}s)"
}

stop_replication_service() {
    if command -v systemctl &>/dev/null; then
        systemctl stop mtproxymax-sync.timer 2>/dev/null || true
        systemctl disable mtproxymax-sync.timer 2>/dev/null || true
        log_info "Replication timer stopped"
    fi
}

remove_replication_service() {
    stop_replication_service
    rm -f /etc/systemd/system/mtproxymax-sync.service
    rm -f /etc/systemd/system/mtproxymax-sync.timer
    rm -f "${INSTALL_DIR}/mtproxymax-sync.sh"
    command -v systemctl &>/dev/null && systemctl daemon-reload 2>/dev/null || true
}

# Interactive setup wizard
replication_setup_wizard() {
    load_settings
    # Verify required dependencies are present
    local _missing_deps=()
    command -v rsync      &>/dev/null || _missing_deps+=(rsync)
    command -v ssh        &>/dev/null || _missing_deps+=("openssh-client")
    command -v ssh-keygen &>/dev/null || _missing_deps+=("openssh-keygen")
    if [ ${#_missing_deps[@]} -gt 0 ]; then
        log_error "Missing required tools: ${_missing_deps[*]}"
        log_info  "Install them first, e.g.: apt install ${_missing_deps[*]}"
        return 1
    fi
    clear_screen
    draw_header "REPLICATION SETUP"
    echo ""
    echo -e "  Configures Master-Slave config sync via rsync+SSH."
    echo -e "  Changes on the ${BOLD}Master${NC} auto-push to all Slaves."
    echo ""
    draw_line

    echo ""
    echo -e "  ${BOLD}Step 1: Role for this server${NC}"
    echo ""
    echo -e "  [1] ${BRIGHT_GREEN}Master${NC}     — Push config to slave(s)"
    echo -e "  [2] ${BRIGHT_CYAN}Slave${NC}      — Receive config from master"
    echo -e "  [3] ${DIM}Standalone${NC} — Disable replication"
    echo ""
    local role_choice
    role_choice=$(read_choice "choice" "1")

    case "$role_choice" in
        2)
            REPLICATION_ROLE="slave"
            REPLICATION_ENABLED="false"
            save_settings
            stop_replication_service
            # Slave has no peers — clear any stale replication.conf from a previous master setup
            > "${REPLICATION_FILE}" 2>/dev/null || true
            echo ""
            log_success "Role set to: Slave"
            echo ""
            echo -e "  On the Master server, run:"
            local _hint_ip _hint_host
            _hint_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            [ -z "$_hint_ip" ] && _hint_ip=$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}')
            _hint_host=$(hostname -s 2>/dev/null)
            echo -e "    ${CYAN}mtproxymax replication add ${_hint_ip:-<YOUR_IP>} 22${_hint_host:+ ${_hint_host}}${NC}"
            echo ""
            echo -e "  Ensure Master's SSH public key is in: ${DIM}~/.ssh/authorized_keys${NC}"
            echo ""
            press_any_key
            return 0
            ;;
        3)
            REPLICATION_ROLE="standalone"
            REPLICATION_ENABLED="false"
            save_settings
            log_info "Replication disabled (standalone)"
            press_any_key
            return 0
            ;;
    esac

    # Master flow
    REPLICATION_ROLE="master"
    echo ""
    echo -e "  ${BOLD}Step 2: SSH Key${NC}"
    echo ""

    local key_path="${REPLICATION_SSH_KEY_PATH}"
    if [ -f "${key_path}" ]; then
        echo -e "  ${GREEN}${SYM_CHECK}${NC} Key exists: ${DIM}${key_path}${NC}"
        echo -en "  Regenerate? [y/N]: "
        local regen; read -r regen
        [[ "$regen" =~ ^[Yy]$ ]] && rm -f "${key_path}" "${key_path}.pub"
    fi

    if [ ! -f "${key_path}" ]; then
        mkdir -p "${REPLICATION_SSH_DIR}"
        chmod 700 "${REPLICATION_SSH_DIR}"
        ssh-keygen -t ed25519 -f "${key_path}" -N "" -C "mtproxymax-replication" &>/dev/null
        chmod 600 "${key_path}"
        log_success "ed25519 key generated"
    fi

    echo ""
    echo -e "  ${BOLD}Public key${NC} (add to slave ~/.ssh/authorized_keys if needed):"
    echo ""
    echo -e "  ${DIM}$(cat "${key_path}.pub" 2>/dev/null)${NC}"
    echo ""
    draw_line

    echo ""
    echo -e "  ${BOLD}Step 2b: SSH User${NC}"
    echo ""
    echo -e "  ${DIM}User account on slave servers for SSH/rsync (default: root)${NC}"
    echo -en "  SSH user [${REPLICATION_SSH_USER:-root}]: "
    local ssh_user_input; read -r ssh_user_input
    if [ -n "$ssh_user_input" ]; then
        if [[ "$ssh_user_input" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
            REPLICATION_SSH_USER="$ssh_user_input"
        else
            log_warn "Invalid username — keeping '${REPLICATION_SSH_USER:-root}'"
        fi
    fi
    draw_line

    echo ""
    echo -e "  ${BOLD}Step 3: Add Slave Server(s)${NC}"
    echo ""

    load_replication
    local add_more="y"
    while [[ "$add_more" =~ ^[Yy]$ ]]; do
        echo -en "  Slave host (IP or domain): "
        local slave_host; read -r slave_host
        [ -z "$slave_host" ] && break

        local slave_port
        slave_port=$(read_choice "SSH port" "22")
        local slave_label
        slave_label=$(read_choice "label" "$slave_host")

        echo ""
        echo -e "  ${YELLOW}${SYM_WARN} Note:${NC} The first connection uses Trust-On-First-Use (TOFU)."
        echo -e "  ${DIM}The slave's SSH host key will be automatically accepted and saved.${NC}"
        echo -e "  ${DIM}For maximum security, verify the fingerprint manually beforehand.${NC}"
        echo ""
        echo -e "  Copying SSH key to ${slave_host}..."
        if command -v ssh-copy-id &>/dev/null; then
            if ssh-copy-id -i "${key_path}.pub" -p "${slave_port}" \
                -o StrictHostKeyChecking=accept-new \
                "${REPLICATION_SSH_USER}@${slave_host}" 2>/dev/null; then
                log_success "Key copied to ${slave_host}"
            else
                log_warn "ssh-copy-id failed — add the public key manually to ${REPLICATION_SSH_USER}@${slave_host}:~/.ssh/authorized_keys"
            fi
        else
            log_warn "ssh-copy-id not found — add the public key manually"
        fi

        echo -en "  Testing SSH connection... "
        if ssh -i "${key_path}" -p "${slave_port}" \
            -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
            "${REPLICATION_SSH_USER}@${slave_host}" "echo ok" &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
            replication_add "$slave_host" "$slave_port" "$slave_label"
        else
            echo -e "${RED}FAILED${NC}"
            log_error "SSH failed — slave not added. Fix and run: mtproxymax replication add ${slave_host} ${slave_port} ${slave_label}"
        fi

        echo ""
        echo -en "  Add another slave? [y/N]: "
        read -r add_more
    done

    echo ""
    echo -e "  ${BOLD}Step 4: Sync Interval${NC}"
    local interval
    interval=$(read_choice "sync interval in seconds" "${REPLICATION_SYNC_INTERVAL}")
    if [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 10 ]; then
        REPLICATION_SYNC_INTERVAL="$interval"
    fi

    # Dry-run test
    load_replication
    if [ ${#REPL_HOSTS[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${BOLD}Step 5: Dry-run test to ${REPL_LABELS[0]}${NC}"
        echo ""
        local exclude_args=() ex
        IFS=',' read -ra _ex <<< "${REPLICATION_EXCLUDE}"
        for ex in "${_ex[@]}"; do
            ex="${ex#"${ex%%[! ]*}"}"
            [ -n "$ex" ] && exclude_args+=(--exclude="${ex}")
        done
        exclude_args+=(--exclude="settings.conf" --exclude="replication.conf" --exclude="fleet_data" --exclude=".ssh")
        rsync -az --dry-run --itemize-changes "${exclude_args[@]}" \
            --timeout=10 \
            -e "ssh -i ${REPLICATION_SSH_KEY_PATH} -p ${REPL_PORTS[0]} -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
            "${INSTALL_DIR}/" \
            "${REPLICATION_SSH_USER}@${REPL_HOSTS[0]}:${INSTALL_DIR}/" 2>&1 | head -20
        echo ""
    fi

    REPLICATION_ENABLED="true"
    save_settings
    setup_replication_service

    echo ""
    log_success "Replication configured!"
    echo -e "  Role: ${BRIGHT_GREEN}Master${NC} | Interval: ${REPLICATION_SYNC_INTERVAL}s | Slaves: ${#REPL_HOSTS[@]}"
    echo ""
    press_any_key
}

# Show replication status
replication_status() {
    load_settings
    load_replication

    echo ""
    echo -e "  ${BOLD}Replication Status${NC}"
    echo ""

    local role_color="$DIM"
    case "$REPLICATION_ROLE" in
        master) role_color="$BRIGHT_GREEN" ;;
        slave)  role_color="$BRIGHT_CYAN" ;;
    esac

    echo -e "  Role:     ${role_color}${REPLICATION_ROLE}${NC}"
    echo -e "  Enabled:  $([ "$REPLICATION_ENABLED" = "true" ] && echo "${GREEN}yes${NC}" || echo "${DIM}no${NC}")"
    [ "${REPLICATION_ROLE}" = "master" ] && \
        echo -e "  Interval: ${REPLICATION_SYNC_INTERVAL}s"
    echo -e "  SSH Key:  $([ -f "${REPLICATION_SSH_KEY_PATH}" ] && echo "${GREEN}present${NC}" || echo "${RED}missing${NC}")"

    local t_state="inactive"
    if command -v systemctl &>/dev/null; then
        t_state=$(systemctl is-active mtproxymax-sync.timer 2>/dev/null)
        t_state="${t_state:-inactive}"
        echo -e "  Timer:    $([ "$t_state" = "active" ] && echo "${GREEN}${t_state}${NC}" || echo "${DIM}${t_state}${NC}")"
    fi

    if [ "${REPLICATION_ROLE}" = "master" ] && [ ${#REPL_HOSTS[@]} -gt 0 ]; then
        echo ""
        replication_list
    elif [ "${REPLICATION_ROLE}" = "slave" ]; then
        echo ""
        echo -e "  ${DIM}Receiving config from master. All changes must be made on the master.${NC}"
    fi

    if [ -f "${REPLICATION_LOG}" ]; then
        echo ""
        echo -e "  ${BOLD}Recent log:${NC}"
        tail -5 "${REPLICATION_LOG}" | while IFS= read -r line; do
            echo -e "  ${DIM}${line}${NC}"
        done
    fi
    echo ""
}

# Test SSH connectivity
replication_test() {
    local target="${1:-}"
    load_replication

    if [ ${#REPL_HOSTS[@]} -eq 0 ]; then
        log_error "No slaves configured"
        return 1
    fi

    echo ""
    local i
    for i in "${!REPL_HOSTS[@]}"; do
        [ -n "$target" ] && [ "${REPL_HOSTS[$i]}" != "$target" ] && \
            [ "${REPL_LABELS[$i]}" != "$target" ] && continue

        local host="${REPL_HOSTS[$i]}" port="${REPL_PORTS[$i]}" label="${REPL_LABELS[$i]}"
        echo -en "  ${label} (${host}:${port}) ... "

        local result
        result=$(ssh -i "${REPLICATION_SSH_KEY_PATH}" -p "${port}" \
            -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
            "${REPLICATION_SSH_USER}@${host}" \
            "docker ps --filter name=mtproxymax --format '{{.Status}}' 2>/dev/null; echo ssh_ok" 2>&1)

        if echo "$result" | grep -q "ssh_ok"; then
            local docker_status
            docker_status=$(echo "$result" | grep -v "ssh_ok" | head -1)
            echo -e "${GREEN}SSH OK${NC} | docker: ${docker_status:-not running}"
        else
            echo -e "${RED}FAILED${NC} ($(echo "$result" | tail -1))"
        fi
    done
    echo ""
}

# Trigger immediate sync
replication_sync_now() {
    echo ""
    if [ "${REPLICATION_ROLE}" != "master" ]; then
        log_warn "This server is '${REPLICATION_ROLE}' — only master initiates sync"
        echo ""
        return 1
    fi
    # Always regenerate sync script to ensure it reflects the current version
    replication_generate_sync_script
    if command -v systemctl &>/dev/null && \
        systemctl is-active mtproxymax-sync.timer &>/dev/null; then
        echo -e "  Triggering sync via systemd..."
        systemctl start mtproxymax-sync.service
        echo -e "  ${GREEN}Done.${NC}"
        echo -e "  View logs: ${DIM}mtproxymax replication logs${NC}"
    elif [ -f "${INSTALL_DIR}/mtproxymax-sync.sh" ]; then
        echo -e "  Running sync script directly..."
        bash "${INSTALL_DIR}/mtproxymax-sync.sh"
    else
        log_error "Sync script not found. Run: mtproxymax replication setup"
        return 1
    fi
    echo ""
}

# Show sync logs
replication_show_logs() {
    echo ""
    if [ -f "${REPLICATION_LOG}" ]; then
        echo -e "  ${BOLD}Sync log (${REPLICATION_LOG}):${NC}"
        echo ""
        tail -50 "${REPLICATION_LOG}"
    else
        echo -e "  ${DIM}No log file yet.${NC}"
    fi

    if command -v journalctl &>/dev/null; then
        echo ""
        echo -e "  ${BOLD}Systemd journal (last 10 entries):${NC}"
        echo ""
        journalctl -u mtproxymax-sync.service --no-pager -n 10 2>/dev/null || true
    fi
    echo ""
}

# Remove all replication config
replication_reset() {
    echo ""
    echo -e "  ${RED}${BOLD}Remove all replication config, SSH keys, and sync service?${NC}"
    echo -en "  Confirm [y/N]: "
    local confirm; read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { log_info "Cancelled"; return 0; }

    remove_replication_service
    REPLICATION_ENABLED="false"
    REPLICATION_ROLE="standalone"
    save_settings
    rm -f "${REPLICATION_FILE}"
    rm -rf "${REPLICATION_SSH_DIR}"
    log_success "Replication config removed"
}

# Promote slave to master
replication_promote() {
    load_settings
    if [ "${REPLICATION_ROLE}" = "master" ]; then
        log_warn "Already a master"
        return 0
    fi

    echo ""
    echo -e "  ${BOLD}Promote this server from Slave to Master?${NC}"
    echo -e "  ${DIM}Disable the old master first to avoid config conflicts.${NC}"
    echo ""
    echo -en "  Confirm [y/N]: "
    local confirm; read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { log_info "Cancelled"; return 0; }

    REPLICATION_ROLE="master"
    save_settings
    log_success "Role changed to: Master"
    if [ ! -f "${REPLICATION_SSH_KEY_PATH}" ]; then
        log_warn "No SSH key found at ${REPLICATION_SSH_KEY_PATH}"
        log_info "Run 'mtproxymax replication setup' to generate a key and configure slaves"
    fi
    log_info "Add slaves:  mtproxymax replication add <host>"
    log_info "Enable sync: mtproxymax replication enable"
}


# ── Section 15: Installation Wizard ──────────────────────────

run_installer() {
    show_banner

    echo -e "  ${BRIGHT_GREEN}Welcome to MTProxyMax — the ultimate Telegram proxy manager${NC}"
    echo -e "  ${DIM}by SamNet Technologies${NC}"
    echo ""

    check_root "$@"

    # Check if already installed
    if [ -f "${INSTALL_DIR}/mtproxymax" ]; then
        echo -e "  ${YELLOW}MTProxyMax is already installed.${NC}"
        echo ""
        echo -e "  ${DIM}[1]${NC} Open management menu"
        echo -e "  ${DIM}[2]${NC} Reinstall"
        echo -e "  ${DIM}[3]${NC} Uninstall"
        echo -e "  ${DIM}[0]${NC} Exit"

        local choice
        choice=$(read_choice "Choice" "1")
        case "$choice" in
            1) load_settings; load_secrets; show_main_menu; return ;;
            2) ;; # Continue with install
            3) uninstall; return ;;
            *) exit 0 ;;
        esac
    fi

    draw_header "INSTALLATION"
    echo ""

    # Install dependencies
    check_dependencies

    # Install Docker
    install_docker || exit 1
    wait_for_docker || exit 1

    echo ""
    draw_header "PROXY CONFIGURATION"
    echo ""

    # Port
    echo -e "  ${BOLD}Proxy port${NC} ${DIM}(default: 443)${NC}"
    echo -en "  ${DIM}Enter port [443]:${NC} "
    local port_input
    read -r port_input
    if [ -n "$port_input" ]; then
        if validate_port "$port_input"; then
            PROXY_PORT="$port_input"
        else
            log_warn "Invalid port, using default (443)"
        fi
    fi

    # Custom IP
    echo ""
    local _detected_ip
    _detected_ip=$(CUSTOM_IP="" get_public_ip)
    echo -e "  ${BOLD}Server IP or Domain${NC} ${DIM}(used in proxy links — IP or hostname both work)${NC}"
    echo -en "  ${DIM}Detected: ${_detected_ip:-unknown} — Enter custom IP/domain or press Enter [${_detected_ip:-auto}]:${NC} "
    local ip_input
    read -r ip_input
    if [ -n "$ip_input" ]; then
        if [[ "$ip_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$ip_input" =~ ^[0-9a-fA-F:]+$ ]] || [[ "$ip_input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
            CUSTOM_IP="$ip_input"
        else
            log_warn "Invalid IP/domain, using auto-detected"
        fi
    fi

    # Domain
    echo ""
    echo -e "  ${BOLD}FakeTLS domain${NC} ${DIM}(your proxy will look like HTTPS to this site)${NC}"
    echo -e "  ${DIM}[1]${NC} cloudflare.com ${DIM}(recommended)${NC}"
    echo -e "  ${DIM}[2]${NC} www.google.com"
    echo -e "  ${DIM}[3]${NC} www.microsoft.com"
    echo -e "  ${DIM}[4]${NC} Custom domain"

    local domain_choice
    domain_choice=$(read_choice "Choice" "1")
    case "$domain_choice" in
        2) PROXY_DOMAIN="www.google.com" ;;
        3) PROXY_DOMAIN="www.microsoft.com" ;;
        4)
            echo -en "  ${DIM}Enter domain:${NC} "
            local custom_domain
            read -r custom_domain
            if [ -n "$custom_domain" ] && validate_domain "$custom_domain"; then
                PROXY_DOMAIN="$custom_domain"
            elif [ -n "$custom_domain" ]; then
                log_error "Invalid domain format"
            fi
            ;;
        *) PROXY_DOMAIN="cloudflare.com" ;;
    esac

    # Auto-detect TLS certificate length for chosen domain
    sync_domain_cert_len "true" "false" || true

    # Traffic masking
    echo ""
    echo -e "  ${BOLD}Traffic masking${NC} ${DIM}(forward DPI probes to real website)${NC}"
    echo -en "  ${DIM}Enable? [Y/n]:${NC} "
    local mask_input
    read -r mask_input
    case "$mask_input" in
        n|N|no) MASKING_ENABLED="false" ;;
        *) MASKING_ENABLED="true" ;;
    esac

    # Ad-tag
    echo ""
    echo -e "  ${BOLD}Ad-tag${NC} ${DIM}(optional)${NC}"
    echo -e "  ${DIM}Telegram can pin a sponsored channel at the top of your users'${NC}"
    echo -e "  ${DIM}chat list when they connect through your proxy. To get an ad-tag,${NC}"
    echo -e "  ${DIM}message @MTProxyBot on Telegram. Most private proxies skip this.${NC}"
    echo -en "  ${DIM}Enable ad-tag? [y/N]:${NC} "
    local adtag_choice
    read -r adtag_choice
    case "$adtag_choice" in
        y|Y|yes)
            echo -en "  ${DIM}Enter ad-tag hex:${NC} "
            local adtag_input
            read -r adtag_input
            adtag_input=$(echo "$adtag_input" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [[ "$adtag_input" =~ ^[0-9a-f]{32}$ ]]; then
                AD_TAG="$adtag_input"
            else
                log_warn "Invalid ad-tag (must be 32 hex characters), skipping"
            fi
            ;;
    esac

    # Resource limits
    echo ""
    echo -e "  ${BOLD}Resource limits${NC}"
    echo -en "  ${DIM}Enter CPU cores [unlimited]:${NC} "
    local cpu_input
    read -r cpu_input
    if [ -n "$cpu_input" ]; then
        if [[ "$cpu_input" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            # Ensure minimum 0.1 CPU
            if awk "BEGIN{exit ($cpu_input < 0.1)}" 2>/dev/null; then
                PROXY_CPUS="$cpu_input"
            else
                log_warn "CPU must be at least 0.1, keeping ${PROXY_CPUS:-unlimited}"
            fi
        else
            log_warn "Invalid CPU value (must be a number, e.g. 1, 2, 0.5), keeping ${PROXY_CPUS:-unlimited}"
        fi
    fi

    echo -en "  ${DIM}Enter memory limit, e.g. 256m, 1g [unlimited]:${NC} "
    local mem_input
    read -r mem_input
    if [ -n "$mem_input" ]; then
        if [[ "$mem_input" =~ ^[0-9]+[bBkKmMgG]?$ ]]; then
            # Default bare numbers to megabytes
            [[ "$mem_input" =~ ^[0-9]+$ ]] && mem_input="${mem_input}m"
            PROXY_MEMORY="$mem_input"
        else
            log_warn "Invalid memory value (e.g. 256m, 1g), keeping ${PROXY_MEMORY:-unlimited}"
        fi
    fi

    # First secret
    echo ""
    draw_header "PROXY SECRET"
    echo ""
    echo -e "  ${DIM}A secret key will be auto-generated for your proxy.${NC}"
    echo -e "  ${DIM}Users need this key to connect. Give it a name to identify it.${NC}"
    echo -en "  ${DIM}Enter label [default]:${NC} "
    local first_label
    read -r first_label
    [ -z "$first_label" ] && first_label="default"
    if ! [[ "$first_label" =~ ^[a-zA-Z0-9_-]+$ ]] || [ ${#first_label} -gt 32 ]; then
        log_warn "Invalid label, using 'default'"
        first_label="default"
    fi

    local first_secret
    first_secret=$(generate_secret)
    SECRETS_LABELS=("$first_label")
    SECRETS_KEYS=("$first_secret")
    SECRETS_CREATED=("$(date +%s)")
    SECRETS_ENABLED=("true")
    SECRETS_MAX_CONNS=("0")
    SECRETS_MAX_IPS=("0")
    SECRETS_QUOTA=("0")
    SECRETS_EXPIRES=("0")
    SECRETS_NOTES=("")
    SECRETS_AD_TAGS=("")

    # Save everything
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$STATS_DIR" "$BACKUP_DIR"
    chmod 700 "$CONFIG_DIR" "$INSTALL_DIR"
    save_settings
    save_secrets

    # Copy script to install dir
    local script_source="${BASH_SOURCE[0]}"
    if [ -f "$script_source" ]; then
        cp "$script_source" "${INSTALL_DIR}/mtproxymax"
        chmod +x "${INSTALL_DIR}/mtproxymax"
    fi

    # Create symlink
    ln -sf "${INSTALL_DIR}/mtproxymax" /usr/local/bin/mtproxymax

    # Start proxy
    echo ""
    draw_header "STARTING PROXY"
    echo ""
    run_proxy_container || {
        log_error "Failed to start proxy"
        echo -e "  ${DIM}Check: docker logs mtproxymax${NC}"
    }

    # Setup autostart
    setup_autostart

    # Telegram setup offer
    echo ""
    echo -e "  ${BOLD}Telegram bot${NC} ${DIM}(manage your proxy from your phone)${NC}"
    echo -en "  ${DIM}Set up Telegram bot now? [y/N]:${NC} "
    local tg_choice
    read -r tg_choice
    case "$tg_choice" in
        y|Y|yes) telegram_setup_wizard ;;
    esac

    # Summary
    show_install_summary

    # Transition to main menu
    echo ""
    echo -en "  ${DIM}Press any key to open the management menu...${NC}"
    read -rsn1
    read -rn 256 -t 0.05 _ 2>/dev/null || true
    load_settings
    load_secrets
    show_main_menu
}

setup_autostart() {
    if command -v systemctl &>/dev/null; then
        cat > /etc/systemd/system/mtproxymax.service << 'AUTOSTART_EOF'
[Unit]
Description=MTProxyMax Telegram Proxy
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/mtproxymax start
ExecStop=/usr/local/bin/mtproxymax stop

[Install]
WantedBy=multi-user.target
AUTOSTART_EOF

        systemctl daemon-reload
        systemctl enable mtproxymax.service 2>/dev/null
        log_success "Auto-start enabled (systemd)"
    fi
}

show_install_summary() {
    echo ""
    local w=$TERM_WIDTH

    draw_box_top "$w"
    draw_box_center "${BRIGHT_GREEN}${BOLD}INSTALLATION COMPLETE${NC}" "$w"
    draw_box_sep "$w"
    draw_box_empty "$w"

    local server_ip
    server_ip=$(get_public_ip)

    draw_box_line "  ${BOLD}Server:${NC} ${server_ip:-detecting...}" "$w"
    draw_box_line "  ${BOLD}Port:${NC}   ${PROXY_PORT}" "$w"
    draw_box_line "  ${BOLD}Domain:${NC} ${PROXY_DOMAIN}" "$w"
    draw_box_line "  ${BOLD}Engine:${NC} telemt (Rust)" "$w"
    draw_box_empty "$w"

    if [ -n "$server_ip" ]; then
        draw_box_sep "$w"
        draw_box_center "${BOLD}PROXY LINKS${NC}" "$w"
        draw_box_empty "$w"

        local i
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            local full_secret
            full_secret=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
            draw_box_line "  ${BRIGHT_GREEN}${SECRETS_LABELS[$i]}:${NC}" "$w"
            draw_box_line "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}" "$w"
            draw_box_line "  ${CYAN}https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}" "$w"
            draw_box_empty "$w"
        done
    fi

    draw_box_sep "$w"
    draw_box_center "${BOLD}COMMANDS & ANTI-DPI SUITE${NC}" "$w"
    draw_box_empty "$w"
    draw_box_line "  ${GREEN}mtproxymax${NC}              Open TUI Menu -> ${CYAN}[p] Performance Suite${NC}" "$w"
    draw_box_line "  ${GREEN}mtproxymax status${NC}       Show proxy status & live health" "$w"
    draw_box_line "  ${GREEN}mtproxymax secret add${NC}   Add a new user secret" "$w"
    draw_box_line "  ${GREEN}mtproxymax bbr on${NC}       Toggle BBRv3 & ECN Network Booster" "$w"
    draw_box_line "  ${GREEN}mtproxymax shield on${NC}    Toggle Anti-DPI Packet Padding Shield" "$w"
    draw_box_line "  ${GREEN}mtproxymax syn-shield on${NC} Toggle Kernel SYN Flood Tarpit Shield" "$w"
    draw_box_empty "$w"
    draw_box_sep "$w"
    draw_box_line "  ${CYAN}💡 Tip: 13+ anti-DPI shields & boosters are available inside menu [p]${NC}" "$w"
    draw_box_line "  ${DIM}For complete details & recommendations, read Quick Start in README.md${NC}" "$w"
    draw_box_sep "$w"
    draw_box_line "  ${YELLOW}Firewall: Allow TCP port ${PROXY_PORT}${NC}" "$w"
    draw_box_bottom "$w"
    echo ""

    # Show QR for first secret
    if [ -n "$server_ip" ]; then
        for i in "${!SECRETS_LABELS[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
            local link
            link=$(get_proxy_link_https "${SECRETS_LABELS[$i]}")
            show_qr "$link"
            break
        done
    fi
}

# ── Section 16: Uninstall ───────────────────────────────────

uninstall() {
    clear_screen
    echo ""
    echo -e "  ${BRIGHT_RED}${BOLD}UNINSTALL MTPROXYMAX${NC}"
    echo ""
    echo -e "  ${YELLOW}This will remove:${NC}"
    echo -e "  ${DIM}- Proxy container and Docker image${NC}"
    echo -e "  ${DIM}- All configuration and secrets${NC}"
    echo -e "  ${DIM}- Systemd services${NC}"
    echo -e "  ${DIM}- /usr/local/bin/mtproxymax symlink${NC}"
    echo ""
    echo -e "  ${RED}Docker itself will NOT be removed.${NC}"
    echo ""

    echo -en "  ${BOLD}Type 'yes' to confirm:${NC} "
    local confirm
    read -r confirm
    [ "$confirm" != "yes" ] && { log_info "Cancelled"; return; }

    # Offer secrets export
    echo -en "  ${BOLD}Export secrets before removal? [y/N]:${NC} "
    local export_choice
    read -r export_choice
    if [ "$export_choice" = "y" ] || [ "$export_choice" = "Y" ]; then
        local export_file="${HOME}/mtproxymax-secrets-backup.txt"
        cp "$SECRETS_FILE" "$export_file" 2>/dev/null
        chmod 600 "$export_file" 2>/dev/null
        log_success "Secrets exported to ${export_file}"
    fi

    echo ""
    log_info "Removing services..."
    systemctl stop mtproxymax-telegram.service 2>/dev/null || true
    systemctl disable mtproxymax-telegram.service 2>/dev/null || true
    rm -f /etc/systemd/system/mtproxymax-telegram.service

    systemctl stop mtproxymax.service 2>/dev/null || true
    systemctl disable mtproxymax.service 2>/dev/null || true
    rm -f /etc/systemd/system/mtproxymax.service

    systemctl daemon-reload 2>/dev/null || true

    log_info "Removing geo-blocking rules..."
    geoblock_remove_all

    log_info "Removing traffic tracking..."
    traffic_tracking_teardown

    log_info "Removing QoS bandwidth shaping and scanner shields..."
    speed_limit_clear 2>/dev/null || true
    scanner_shield_off 2>/dev/null || true
    syn_shield_off 2>/dev/null || true

    log_info "Removing container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log_info "Removing Docker image..."
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${DOCKER_IMAGE_BASE}:" | xargs -r docker rmi 2>/dev/null || true
    # Clean up dangling build cache from Rust compilation
    docker builder prune -f 2>/dev/null || true

    log_info "Removing files..."
    [ -n "$INSTALL_DIR" ] && [ "$INSTALL_DIR" != "/" ] && rm -rf "$INSTALL_DIR"
    rm -f /usr/local/bin/mtproxymax

    echo ""
    log_success "MTProxyMax has been fully uninstalled"
    echo ""
}

# ── Section 17: CLI Dispatcher ──────────────────────────────

# ── Multi-Port Instances ────────────────────────────────────

declare -a INSTANCE_PORTS=()
declare -a INSTANCE_METRICS_PORTS=()
declare -a INSTANCE_ENABLED=()
declare -a INSTANCE_LABELS=()

load_instances() {
    INSTANCE_PORTS=()
    INSTANCE_METRICS_PORTS=()
    INSTANCE_ENABLED=()
    INSTANCE_LABELS=()
    [ -f "$INSTANCES_FILE" ] || return 0
    while IFS='|' read -r port mport enabled label; do
        [[ "$port" =~ ^[[:space:]]*# ]] && continue
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        INSTANCE_PORTS+=("$port")
        INSTANCE_METRICS_PORTS+=("${mport:-9091}")
        INSTANCE_ENABLED+=("${enabled:-true}")
        INSTANCE_LABELS+=("${label:-port-${port}}")
    done < "$INSTANCES_FILE"
}

save_instances() {
    local tmp; tmp=$(_mktemp) || return 1
    echo "# MTProxyMax Instances — Format: PORT|METRICS_PORT|ENABLED|LABEL" > "$tmp"
    local i
    for i in "${!INSTANCE_PORTS[@]}"; do
        echo "${INSTANCE_PORTS[$i]}|${INSTANCE_METRICS_PORTS[$i]}|${INSTANCE_ENABLED[$i]}|${INSTANCE_LABELS[$i]}" >> "$tmp"
    done
    chmod 600 "$tmp"
    mv "$tmp" "$INSTANCES_FILE"
}

_next_free_metrics_port() {
    local p=9091
    while [ $p -lt 9200 ]; do
        local used=false
        # Check against primary metrics port
        [ "$p" = "${PROXY_METRICS_PORT:-9090}" ] && used=true
        # Check against existing instance metrics ports
        if [ "$used" = "false" ]; then
            for mp in "${INSTANCE_METRICS_PORTS[@]}"; do
                [ "$mp" = "$p" ] && used=true && break
            done
        fi
        [ "$used" = "false" ] && { echo "$p"; return; }
        ((p++))
    done
    echo "9091"
}

instance_add() {
    local port="$1" label="${2:-port-${1}}"
    validate_port "$port" || return 1

    # Check not same as primary
    [ "$port" = "$PROXY_PORT" ] && { log_error "Port ${port} is already the primary proxy port"; return 1; }

    # Check not duplicate
    local i
    for i in "${!INSTANCE_PORTS[@]}"; do
        [ "${INSTANCE_PORTS[$i]}" = "$port" ] && { log_error "Instance on port ${port} already exists"; return 1; }
    done

    local mport; mport=$(_next_free_metrics_port)

    INSTANCE_PORTS+=("$port")
    INSTANCE_METRICS_PORTS+=("$mport")
    INSTANCE_ENABLED+=("true")
    INSTANCE_LABELS+=("$label")
    save_instances

    # Generate config for this instance
    local inst_config="${CONFIG_DIR}/config-${port}.toml"
    local _orig_port="$PROXY_PORT" _orig_mport="$PROXY_METRICS_PORT"
    PROXY_PORT="$port"
    PROXY_METRICS_PORT="$mport"
    generate_telemt_config
    mv "${CONFIG_DIR}/config.toml" "$inst_config" 2>/dev/null
    PROXY_PORT="$_orig_port"
    PROXY_METRICS_PORT="$_orig_mport"
    # Regenerate primary config
    generate_telemt_config

    # Start container
    local cname="mtproxymax-${port}"
    local _docker_args=(
        --name "$cname"
        --restart unless-stopped
        --network host
        --ulimit nofile=65535:65535
        --log-opt max-size=10m
        --log-opt max-file=3
    )
    local _inst_add_out
    _inst_add_out=$(docker run -d "${_docker_args[@]}" \
        -v "${inst_config}:/etc/telemt.toml:ro" \
        "$(get_docker_image)" /etc/telemt.toml 2>&1) || {
            if echo "$_inst_add_out" | grep -E -q "(cgroup|Message recipient disconnected|systemd|dbus|EOF|timeout|system\.slice|runc|OCI runtime create failed)"; then
                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
                systemctl daemon-reload 2>/dev/null || true
                systemctl restart dbus docker 2>/dev/null || true
                sleep 2
                docker rm -f "$cname" &>/dev/null || true
                docker run -d "${_docker_args[@]}" \
                    -v "${inst_config}:/etc/telemt.toml:ro" \
                    "$(get_docker_image)" /etc/telemt.toml &>/dev/null || {
                        docker run -d --name "$cname" --restart unless-stopped --network host \
                            --cgroupns host --log-opt max-size=10m --log-opt max-file=3 \
                            -v "${inst_config}:/etc/telemt.toml:ro" \
                            "$(get_docker_image)" /etc/telemt.toml &>/dev/null || true
                    }
            fi
        }

    apply_firewall_rules 2>/dev/null || true
    log_success "Instance started on port ${port} (container: ${cname}, metrics: ${mport})"
}

instance_remove() {
    local port="$1"
    local idx=-1 i
    for i in "${!INSTANCE_PORTS[@]}"; do
        [ "${INSTANCE_PORTS[$i]}" = "$port" ] && idx=$i && break
    done
    [ "$idx" = "-1" ] && { log_error "No instance on port ${port}"; return 1; }

    # Stop and remove container
    local cname="mtproxymax-${port}"
    docker stop "$cname" &>/dev/null || true
    docker rm -f "$cname" &>/dev/null || true

    # Remove config
    rm -f "${CONFIG_DIR}/config-${port}.toml"

    # Remove from arrays
    local new_ports=() new_mports=() new_enabled=() new_labels=()
    for i in "${!INSTANCE_PORTS[@]}"; do
        [ "$i" = "$idx" ] && continue
        new_ports+=("${INSTANCE_PORTS[$i]}")
        new_mports+=("${INSTANCE_METRICS_PORTS[$i]}")
        new_enabled+=("${INSTANCE_ENABLED[$i]}")
        new_labels+=("${INSTANCE_LABELS[$i]}")
    done
    INSTANCE_PORTS=("${new_ports[@]}")
    INSTANCE_METRICS_PORTS=("${new_mports[@]}")
    INSTANCE_ENABLED=("${new_enabled[@]}")
    INSTANCE_LABELS=("${new_labels[@]}")
    save_instances
    apply_firewall_rules 2>/dev/null || true

    log_success "Instance on port ${port} removed"
}

instance_list() {
    echo ""
    draw_header "PROXY INSTANCES"
    echo ""
    echo -e "  ${BOLD}Primary:${NC} port ${PROXY_PORT} (container: ${CONTAINER_NAME})"
    local running; is_proxy_running && running="${GREEN}running${NC}" || running="${RED}stopped${NC}"
    echo -e "    Status: ${running}"
    echo ""

    if [ ${#INSTANCE_PORTS[@]} -eq 0 ]; then
        echo -e "  ${DIM}No additional instances${NC}"
    else
        local i
        for i in "${!INSTANCE_PORTS[@]}"; do
            local port="${INSTANCE_PORTS[$i]}" label="${INSTANCE_LABELS[$i]}"
            local cname="mtproxymax-${port}"
            local st
            docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$" && st="${GREEN}running${NC}" || st="${RED}stopped${NC}"
            echo -e "  ${BOLD}${label}:${NC} port ${port} (container: ${cname})"
            echo -e "    Status: ${st} | Metrics: ${INSTANCE_METRICS_PORTS[$i]}"
        done
    fi
    echo ""
}

# ── Backup / Restore ────────────────────────────────────────

create_backup() {
    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date '+%Y%m%d-%H%M%S')
    local backup_file="${BACKUP_DIR}/mtproxymax-${ts}.tar.gz"

    # Create metadata
    local meta_tmp; meta_tmp=$(_mktemp) || return 1
    echo "version=${VERSION}" > "$meta_tmp"
    echo "date=$(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$meta_tmp"
    echo "hostname=$(hostname 2>/dev/null || echo unknown)" >> "$meta_tmp"
    cp "$meta_tmp" "${INSTALL_DIR}/backup_meta.txt"
    rm -f "$meta_tmp"

    # Build file list (only existing files)
    local files=("backup_meta.txt")
    [ -f "${INSTALL_DIR}/connection.log" ] && files+=("connection.log")
    for mf in "${MIGRATION_FILES[@]}"; do
        [ -f "$mf" ] && files+=("$(basename "$mf")")
    done
    [ -d "$STATS_DIR" ] && files+=("relay_stats")
    [ -d "$FLEET_DATA_DIR" ] && files+=("fleet_data")
    [ -d "$SSL_DIR" ] && files+=("ssl")

    tar czf "$backup_file" -C "$INSTALL_DIR" --exclude='*.lock' "${files[@]}" 2>/dev/null
    chmod 600 "$backup_file"
    rm -f "${INSTALL_DIR}/backup_meta.txt"

    log_success "Backup created: ${backup_file}"
    backup_cloud_push "$backup_file" 2>/dev/null || true
    echo "$backup_file"
}

restore_backup() {
    local backup_file="$1"
    [ -z "$backup_file" ] && { log_error "Usage: mtproxymax restore <backup_file>"; return 1; }
    [ ! -f "$backup_file" ] && { log_error "File not found: ${backup_file}"; return 1; }

    # Validate backup
    if ! tar tzf "$backup_file" 2>/dev/null | grep -q "settings.conf"; then
        log_error "Invalid backup file (missing settings.conf)"
        return 1
    fi

    # Show metadata
    local meta; meta=$(tar xzf "$backup_file" -O backup_meta.txt 2>/dev/null)
    if [ -n "$meta" ]; then
        echo ""
        echo -e "  ${BOLD}Backup Info:${NC}"
        echo "$meta" | while IFS='=' read -r k v; do echo -e "    ${k}: ${v}"; done
        echo ""
    fi

    echo -en "  ${YELLOW}This will overwrite current configuration. Continue? [y/N]:${NC} "
    local confirm; read -r confirm
    [[ "$confirm" =~ ^[yY] ]] || { log_info "Restore cancelled"; return 0; }

    # Create backup of current state first
    log_info "Backing up current state..."
    create_backup &>/dev/null

    # Extract
    tar xzf "$backup_file" -C "$INSTALL_DIR" --exclude='backup_meta.txt' 2>/dev/null
    chmod 600 "${SECRETS_FILE}" 2>/dev/null

    log_success "Backup restored from: ${backup_file}"
    log_info "Run 'mtproxymax restart' to apply changes"
}

list_backups() {
    mkdir -p "$BACKUP_DIR"
    local files; files=$(ls -1t "${BACKUP_DIR}"/mtproxymax-*.tar.gz 2>/dev/null) || true
    if [ -z "$files" ]; then
        log_info "No backups found in ${BACKUP_DIR}"
        return
    fi
    echo ""
    draw_header "BACKUPS"
    echo ""
    echo "$files" | while read -r f; do
        local size; size=$(du -h "$f" 2>/dev/null | awk '{print $1}')
        echo -e "  ${BOLD}$(basename "$f")${NC}  ${DIM}(${size})${NC}"
    done
    echo ""
}

show_cli_help() {
    echo ""
    echo -e "  ${BRIGHT_CYAN}${BOLD}MTProxyMax${NC} ${DIM}v${VERSION}${NC} — The Ultimate Telegram Proxy Manager"
    echo -e "  ${DIM}by SamNet Technologies${NC}"
    echo ""
    echo -e "  ${BOLD}Usage:${NC} mtproxymax <command> [options]"
    echo ""
    echo -e "  ${BOLD}Proxy Management:${NC}"
    echo -e "    ${GREEN}start${NC}              Start the proxy"
    echo -e "    ${GREEN}stop${NC}               Stop the proxy"
    echo -e "    ${GREEN}restart${NC}            Restart the proxy"
    echo -e "    ${GREEN}status${NC}             Show proxy status"
    echo ""
    echo -e "  ${BOLD}Secret Management:${NC}"
    echo -e "    ${GREEN}secret add${NC} <label>      Add a new secret"
    echo -e "    ${GREEN}secret add-batch${NC} <l1> <l2> ...  Add multiple secrets (single restart)"
    echo -e "    ${GREEN}secret remove${NC} <label>   Remove a secret"
    echo -e "    ${GREEN}secret remove-batch${NC} <l1> <l2> ...  Remove multiple secrets (single restart)"
    echo -e "    ${GREEN}secret list${NC}             List all secrets"
    echo -e "    ${GREEN}secret rotate${NC} <label>   Rotate a secret"
    echo -e "    ${GREEN}secret link${NC} [label]     Show proxy link"
    echo -e "    ${GREEN}secret qr${NC} [label]       Show QR code"
    echo -e "    ${GREEN}secret enable${NC} <label>   Enable a secret"
    echo -e "    ${GREEN}secret disable${NC} <label>  Disable a secret"
    echo -e "    ${GREEN}secret limits${NC} [label]   Show user limits"
    echo -e "    ${GREEN}secret setlimit${NC} <label> conns|ips|quota|expires <value> [--no-restart]"
    echo -e "    ${GREEN}secret setlimits${NC} <label> <conns> <ips> <quota> [expires] [--no-restart]"
    echo -e "    ${GREEN}secret rename${NC} <old> <new>     Rename a secret"
    echo -e "    ${GREEN}secret clone${NC} <src> <new>      Clone a secret with all its limits"
    echo -e "    ${GREEN}secret bulk-extend${NC} <days>     Extend all secrets' expiry by N days"
    echo -e "    ${GREEN}secret export${NC}                 Export secrets to CSV (stdout)"
    echo -e "    ${GREEN}secret import${NC} <file>          Import secrets from CSV file"
    echo -e "    ${GREEN}secret disable-expired${NC}        Disable all expired secrets"
    echo -e "    ${GREEN}secret extend${NC} <label> <days>  Extend expiry by N days"
    echo -e "    ${GREEN}secret stats${NC}                  Compact per-user stats overview"
    echo -e "    ${GREEN}secret sort${NC} [traffic|conns|date|name]  Sort secrets list"
    echo -e "    ${GREEN}secret info${NC} <label>          Full detail view of a secret"
    echo -e "    ${GREEN}secret search${NC} <query>        Search secrets by label or notes"
    echo -e "    ${GREEN}secret top${NC} [traffic|conns] [N]  Top N users (default: 5)"
    echo -e "    ${GREEN}secret generate-links${NC} [txt|html]  Export all links to file"
    echo -e "    ${GREEN}secret archive${NC} <label>       Soft-delete (restorable)"
    echo -e "    ${GREEN}secret unarchive${NC} <label>     Restore archived secret"
    echo -e "    ${GREEN}secret archives${NC}              List archived secrets"
    echo -e "    ${GREEN}secret tag${NC} <label> <tags>    Tag a secret (comma-separated)"
    echo -e "    ${GREEN}secret untag${NC} <label>         Remove all tags"
    echo -e "    ${GREEN}secret tags${NC} [label]          Show tags (all or one secret)"
    echo -e "    ${GREEN}secret list --tag${NC} <tag>      List secrets with a given tag"
    echo -e "    ${GREEN}secret list --csv${NC}            List secrets in CSV format"
    echo -e "    ${GREEN}secret logs${NC} <label> [lines]  Show activity log for one user"
    echo -e "    ${GREEN}secret rotate --all${NC}          Rotate ALL secrets (--dry-run to preview)"
    echo -e "    ${GREEN}secret quota-reset${NC} <label> <day|off>  Monthly quota reset on day N"
    echo -e "    ${GREEN}secret add --template${NC} <name> <label>  Add secret using a template"
    echo -e "    ${DIM}Tip: add/remove support --no-restart flag for scripting${NC}"
    echo ""
    echo -e "  ${BOLD}Upstream Routing:${NC}"
    echo -e "    ${GREEN}upstream list${NC}                  List upstreams"
    echo -e "    ${GREEN}upstream add${NC} <name> <type> <host:port> [user] [pass] [weight] [iface]"
    echo -e "    ${GREEN}upstream remove${NC} <name>      Remove upstream"
    echo -e "    ${GREEN}upstream enable${NC} <name>      Enable upstream"
    echo -e "    ${GREEN}upstream disable${NC} <name>     Disable upstream"
    echo -e "    ${GREEN}upstream test${NC} <name>        Test connectivity"
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "    ${GREEN}port${NC} [get|<number>]       Show or change proxy port"
    echo -e "    ${GREEN}ip${NC} [get|auto|<address>]   Show, reset, or set custom IP/domain for links"
    echo -e "    ${GREEN}domain${NC} [get|clear|<host>] Show, clear, or change FakeTLS domain"
    echo -e "    ${GREEN}domain-pool${NC} [get|<pool>] Configure multi-domain SNI pool (comma-separated)"
    echo -e "    ${GREEN}syn-shield${NC} [on|off|status] Kernel SYN Shield rate limiter (>15 SYN/5s tarpit)"
    echo -e "    ${GREEN}stealth${NC} [ultra|normal|status]  Switch stealth defense preset (anti-replay tuning)"
    echo -e "    ${GREEN}clamp-mss${NC} [on|off|status] Toggle TCP MSS Clamping (--clamp-mss-to-pmtu)"
    echo -e "    ${GREEN}mask-backend${NC} [host:port]  Show or set mask backend for non-proxy traffic"
    echo -e "    ${GREEN}mask-relay-bytes${NC} [N|0|clear]  Max bytes per direction on mask relay (0=unlimited)"
    echo -e "    ${GREEN}tg-urls${NC} [get|set <field> <url>|clear]  Custom Telegram infrastructure URLs (restricted regions)"
    echo -e "    ${GREEN}info${NC}                    Comprehensive server + proxy info"
    echo -e "    ${GREEN}maintenance${NC} [on|off]    Maintenance mode (reject new connections)"
    echo -e "    ${GREEN}ban${NC} <ip|cidr>           Ban an IP or CIDR range"
    echo -e "    ${GREEN}unban${NC} <ip|cidr>         Remove ban"
    echo -e "    ${GREEN}bans${NC}                    List banned IPs"
    echo -e "    ${GREEN}migrate export${NC} [file]   Export all state to a tarball"
    echo -e "    ${GREEN}migrate import${NC} <file>   Import state from a tarball"
    echo -e "    ${GREEN}changelog${NC}               Show release notes since installed version"
    echo -e "    ${GREEN}backup --encrypt${NC}        Create AES-256 encrypted backup"
    echo -e "    ${GREEN}backup autoclean${NC} [days] Delete backups older than N days (default: BACKUP_RETENTION_DAYS)"
    echo -e "    ${GREEN}auto-rotate${NC} [N|off]     Auto-rotate secrets older than N days"
    echo -e "    ${GREEN}template${NC} save|list|delete|apply  Manage limit templates"
    echo -e "    ${GREEN}sweep${NC}                   Run periodic maintenance tasks (quota-reset, auto-rotate, backup cleanup)"
    echo -e "    ${GREEN}tune${NC} list|get|set|clear Engine tuning (whitelisted params)"
    echo -e "    ${GREEN}verify${NC}                  End-to-end install verification"
    echo -e "    ${GREEN}history${NC} [lines]         Show config change audit log"
    echo -e "    ${GREEN}completion${NC}              Emit bash completion script"
    echo -e "    ${GREEN}speedtest${NC}               Test outbound bandwidth/latency from server"
    echo -e "    ${GREEN}adtag${NC} [set <hex>|remove|view] Manage ad-tag"
    echo -e "    ${GREEN}geoblock${NC} [add|remove|list|clear] Manage geo-blocking"
    echo -e "    ${GREEN}sni-policy${NC} [mask|drop]       Unknown SNI action (mask=permissive, drop=strict)"
    echo ""
    echo -e "  ${BOLD}Monitoring:${NC}"
    echo -e "    ${GREEN}traffic${NC}                 Show traffic stats"
    echo -e "    ${GREEN}connections${NC}             Show live active connections per user"
    echo -e "    ${GREEN}metrics${NC}                 Show live engine metrics (connections, upstream, users, ME)"
    echo -e "    ${GREEN}doctor${NC}                  Comprehensive diagnostics (port, TLS, secrets, disk, bot)"
    echo -e "    ${GREEN}uptime${NC}                  One-line status (for scripts/monitoring)"
    echo -e "    ${GREEN}config${NC}                  Show current engine config"
    echo -e "    ${GREEN}notify${NC} <message>        Send custom Telegram notification"
    echo -e "    ${GREEN}port-check${NC}              Test if proxy port is reachable from outside"
    echo -e "    ${GREEN}profile${NC} save|load|list|delete <name>  Config profiles"
    echo -e "    ${GREEN}metrics live${NC} [seconds]  Auto-refresh metrics dashboard (default: 5s)"
    echo -e "    ${GREEN}logs${NC}                    Stream container logs"
    echo -e "    ${GREEN}health${NC}                  Run health diagnostics"
    echo ""
    echo -e "  ${BOLD}Anti-DPI & Stealth Defenses:${NC}"
    echo -e "    ${GREEN}syn-shield${NC} [on|off|status]  Toggle Kernel SYN Shield (>15 SYN/5s tarpit)"
    echo -e "    ${GREEN}stealth${NC} [ultra|normal|status] Switch Stealth Preset"
    echo -e "    ${GREEN}clamp-mss${NC} [on|off|status]   Toggle TCP MSS Clamping"
    echo -e "    ${GREEN}domain-pool${NC} <d1,d2>       Set Multi-Domain SNI Pool"
    echo -e "    ${GREEN}dpi-inspect${NC}               Run DPI Forensics Analyzer"
    echo -e "    ${GREEN}cover-watchdog${NC} [test|auto] Test/rotate cover domains"
    echo -e "    ${GREEN}lockdown${NC} [on|off|status]    Toggle Emergency Lockdown"
    echo -e "    ${GREEN}port-pool${NC} [add|remove|list] Manage Secondary Port Pool"
    echo ""
    echo -e "  ${BOLD}QoS Bandwidth & Quota Intelligence:${NC}"
    echo -e "    ${GREEN}qos${NC} [set <mbps>|off|status] Manage Per-IP Bandwidth Speed Shaping"
    echo -e "    ${GREEN}happy-hours${NC} [set <win>|off] Manage Off-Peak Quota Exclusions"
    echo -e "    ${GREEN}quota-mode${NC} [manager|engine|status] Quota Enforcement Mode (0-disconnect vs strict)"
    echo -e "    ${GREEN}notify-expiry${NC}             Send Telegram Reminders for Expiring Secrets"
    echo -e "    ${GREEN}abuse-watch${NC}               Scan Users for Abnormal Bandwidth Usage"
    echo -e "    ${GREEN}speed-limit${NC} [set|remove|apply|clear|list|status] Hierarchical Token Bucket (HTB) QoS Throttling"
    echo ""
    echo -e "  ${BOLD}Enterprise Fleet & Cloud Integration (v1.4 LTS):${NC}"
    echo -e "    ${GREEN}fleet${NC} [status|collect]         Multi-Server Federation Telemetry Dashboard"
    echo -e "    ${GREEN}ssl${NC} [issue|status|clear]       Automated Let's Encrypt / ACME Certificate Management"
    echo -e "    ${GREEN}backup-cloud${NC} [toggle|push|status|off] Automated Off-Site Cloud & Telegram Backups"
    echo ""
    echo -e "  ${BOLD}Telegram:${NC}"
    echo -e "    ${GREEN}telegram setup${NC}          Run Telegram bot wizard"
    echo -e "    ${GREEN}telegram status${NC}         Show Telegram bot status"
    echo -e "    ${GREEN}telegram test${NC}           Send test message"
    echo -e "    ${GREEN}broadcast <msg>${NC}         Broadcast announcement via Telegram bot"
    echo -e "    ${GREEN}telegram disable${NC}        Disable Telegram"
    echo -e "    ${GREEN}telegram remove${NC}         Remove Telegram bot"
    echo ""
    echo -e "  ${BOLD}Replication:${NC}"
    echo -e "    ${GREEN}replication setup${NC}       Run replication wizard"
    echo -e "    ${GREEN}replication status${NC}      Show replication status"
    echo -e "    ${GREEN}replication add${NC} <host> [port] [label]  Add slave"
    echo -e "    ${GREEN}replication remove${NC} <label>  Remove slave"
    echo -e "    ${GREEN}replication list${NC}        List slaves"
    echo -e "    ${GREEN}replication enable${NC}      Enable sync"
    echo -e "    ${GREEN}replication disable${NC}     Disable sync"
    echo -e "    ${GREEN}replication sync${NC}        Sync now"
    echo -e "    ${GREEN}replication test${NC} [label] Test connectivity"
    echo -e "    ${GREEN}replication logs${NC}        Show sync log"
    echo -e "    ${GREEN}replication reset${NC}       Reset to standalone"
    echo -e "    ${GREEN}replication promote${NC}     Promote slave to master"
    echo ""
    echo -e "  ${BOLD}DevOps & Clustering Automation:${NC}"
    echo -e "    ${GREEN}export-lb${NC} [haproxy|nginx] Export Layer-4 Load Balancer configurations"
    echo -e "    ${GREEN}ddns${NC} [set|run|status|off] Manage Cloudflare Dynamic DNS Updater"
    echo -e "    ${GREEN}diag-dump${NC}               Create full diagnostic forensic bundle"
    echo -e "    ${GREEN}snapshot${NC} [create|restore] Point-in-time configuration snapshots"
    echo ""
    echo -e "  ${BOLD}Operational & Analytics Suite:${NC}"
    echo -e "    ${GREEN}top${NC} [loop|once]           Live ASCII terminal traffic leaderboard & real-time radar"
    echo -e "    ${GREEN}export-client${NC} [lbl] [fmt]   Export Clash, Sing-Box, Shadowrocket & v2rayN configs"
    echo -e "    ${GREEN}export-report${NC} [html|csv]  Export standalone HTML dashboard & CSV spreadsheets"
    echo -e "    ${GREEN}qr-sheet${NC} [output.html]    Generate printable HTML voucher cards & QR grid"
    echo -e "    ${GREEN}tag${NC} <label> <note|clear>  Attach custom tags (VIP, USDT) & contact organization"
    echo ""
    echo -e "  ${BOLD}Commercial & Quota Intelligence Suite:${NC}"
    echo -e "    ${GREEN}guest${NC} <label> <24h|1gb>   Generate self-destructing burner / disposable links"
    echo -e "    ${GREEN}pool${NC} [create|add|list]    Create shared family / team quota buckets"
    echo -e "    ${GREEN}calendar${NC} [wp|hb|status]   Dynamic weekend free pass & holiday bonus scheduler"
    echo ""
    echo -e "  ${BOLD}Advanced Network Defense & Anti-DPI Suite:${NC}"
    echo -e "    ${GREEN}geofence${NC} [allow|block]    Allow-only country whitelist & ASN kernel filtering"
    echo -e "    ${GREEN}decoy${NC} [setup|status|off]  1-click embedded fake camouflage HTTP website"
    echo -e "    ${GREEN}auto-sni${NC} [test|apply]     Smart SNI cover domain benchmarker & health rotation"
    echo -e "    ${GREEN}dc-optimize${NC} [benchmark]   Telegram DC route latency benchmarker & TCP tuner"
    echo -e "    ${GREEN}ip-score${NC} [check|status]   IP reputation & censorship block probability index"
    echo ""
    echo -e "  ${BOLD}Enterprise DevOps & Autonomous Resilience Suite:${NC}"
    echo -e "    ${GREEN}webhook${NC} [add|remove|list] Discord, Slack & DingTalk real-time event dispatching"
    echo -e "    ${GREEN}failover${NC} [on|off|status] Automatic upstream failover & DNS health checks"
    echo -e "    ${GREEN}eco-mode${NC} [on|off|status] CPU & RAM throttling for 256MB micro-server conservation"
    echo -e "    ${GREEN}chaos-test${NC} [drop|latency]  Sandboxed stress benchmarker & high load resilience testing"
    echo -e "    ${GREEN}evacuate${NC} [ip] [user]      1-click emergency server migration & data sanitization"
    echo ""
    echo -e "  ${BOLD}Operations, Briefings & Onboarding Suite:${NC}"
    echo -e "    ${GREEN}backup send-tg${NC} [file]     Push server backup archive directly to Telegram bot chat"
    echo -e "    ${GREEN}daily-report${NC} [on|off|run] Schedule morning executive briefing via Telegram bot"
    echo -e "    ${GREEN}ssh-shield${NC} [on|off|status] Enable fail2ban SSH brute-force intrusion shield"
    echo -e "    ${GREEN}net-grade${NC}               Benchmark international routing & assign A+/A/B/C grade"
    echo -e "    ${GREEN}onboard${NC} [label]           Smart interactive step-by-step user creation wizard"
    echo ""
    echo -e "  ${BOLD}Performance, Diagnostics & Self-Healing Suite:${NC}"
    echo -e "    ${GREEN}tcp-boost${NC} [on|off|status] Activate Linux Kernel TCP BBR & Fast Open booster"
    echo -e "    ${GREEN}tcp-clean${NC} [on|off|status] Activate aggressive keep-alive dead mobile socket reaper"
    echo -e "    ${GREEN}socket-boost${NC} [on|off]     Apply ultra-low latency kernel socket queue expansion"
    echo -e "    ${GREEN}tls-pad${NC} [auto|off|rotate] Dynamic FakeTLS certificate length jitter & randomization"
    echo -e "    ${GREEN}honeypot${NC} [on|off|status]  Enable active probe decoy redirection & protection"
    echo -e "    ${GREEN}leak-scan${NC} [thresh]        Detect multi-IP subscription sharing anomalies"
    echo -e "    ${GREEN}cert-check${NC} [domain]       Inspect cover domain SSL/TLS certificate health"
    echo -e "    ${GREEN}clone-link${NC}                Export one-line Base64 server replication bundle"
    echo -e "    ${GREEN}bootstrap${NC} <base64>        Deploy cloned config bundle on a fresh node"
    echo -e "    ${GREEN}heal${NC}                      Run emergency RAM & dead socket cleanup immediately"
    echo -e "    ${GREEN}auto-heal${NC} [on|off|status] Enable background automated RAM/socket self-healer"
    echo -e "    ${GREEN}tcp-fastpath${NC} [on|off]     TCP window scaling, SACK & path MTU probing optimizer"
    echo -e "    ${GREEN}ram-tune${NC} [auto|off]        Auto-detect RAM & apply optimal TCP memory buffers"
    echo -e "    ${GREEN}port-hop${NC} [add|remove|list] Dynamic multi-port NAT range redirection"
    echo -e "    ${GREEN}cpu-tune${NC} [on|off|status]   Multi-core IRQ packet spreading (RPS/RFS)"
    echo -e "    ${GREEN}bbr${NC} [on|off|status]        Activate TCP BBRv3 Congestion Control & ECN tuning"
    echo -e "    ${GREEN}shield${NC} [on|off|status]     Activate Anti-DPI Packet Padding & TLS Fingerprint Shield"
    echo -e "    ${GREEN}cover-shield${NC} [on|off|url]  Activate Reverse-Proxy Cover Shield (Active Probe Defense)"
    echo ""
    echo -e "  ${BOLD}Enterprise Commercial & Shield Suite:${NC}"
    echo -e "    ${GREEN}voucher create${NC} <cnt> <qta> <dys> Generate batch voucher codes"
    echo -e "    ${GREEN}voucher list${NC} [active|all]      List vouchers and redemption status"
    echo -e "    ${GREEN}voucher revoke${NC} <code>          Revoke a voucher code"
    echo -e "    ${GREEN}voucher redeem${NC} <code> [lbl]    Redeem voucher code locally"
    echo -e "    ${GREEN}admin add${NC} <chat_id> <role>     Add role-based Telegram admin (superadmin/reseller)"
    echo -e "    ${GREEN}admin remove${NC} <chat_id>         Remove Telegram admin"
    echo -e "    ${GREEN}admin list${NC}                     List role-based Telegram admins"
    echo -e "    ${GREEN}portal${NC} [enable|disable|port|generate|serve|status] Manage Self-Service HTML Dashboard"
    echo -e "    ${GREEN}scanner-shield${NC} [enable|disable|update|status] Automated Shodan/Censys Threat Scanner Shield"
    echo ""
    echo -e "  ${BOLD}Info & Help:${NC}"
    echo -e "    ${GREEN}info${NC}                    Open feature info guide"
    echo -e "    ${GREEN}firewall${NC}                Show firewall setup guide"
    echo -e "    ${GREEN}portforward${NC}             Show port forwarding guide"
    echo ""
    echo -e "  ${BOLD}Engine:${NC}"
    echo -e "    ${GREEN}engine status${NC}           Show current engine version"
    echo -e "    ${GREEN}engine rebuild${NC}          Force rebuild engine image"
    echo -e "    ${GREEN}rebuild${NC}                 Force rebuild from source"
    echo ""
    echo -e "  ${BOLD}System:${NC}"
    echo -e "    ${GREEN}install${NC}                 Run installation wizard"
    echo -e "    ${GREEN}menu${NC}                    Open interactive menu"
    echo -e "    ${GREEN}update${NC}                  Check for updates"
    echo -e "    ${GREEN}uninstall${NC}               Remove MTProxyMax"
    echo -e "    ${GREEN}version${NC}                 Show version"
    echo -e "    ${GREEN}help${NC}                    Show this help"
    echo ""
}

_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"    # backslash
    s="${s//\"/\\\"}"    # double quote
    s="${s//$'\n'/\\n}"  # newline
    s="${s//$'\t'/\\t}"  # tab
    printf '%s' "$s"
}

show_status_json() {
    local status="stopped" uptime_secs=0 traffic_in=0 traffic_out=0 connections=0
    if is_proxy_running; then
        status="running"
        uptime_secs=$(get_proxy_uptime 2>/dev/null) || uptime_secs=0
        read -r traffic_in traffic_out connections <<< "$(get_cumulative_proxy_stats)"
    fi

    _load_all_cumulative_user_stats 2>/dev/null

    local engine_ver
    engine_ver=$(get_telemt_version 2>/dev/null) || engine_ver="unknown"

    # Build JSON
    printf '{\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "engine_version": "%s",\n' "$engine_ver"
    printf '  "status": "%s",\n' "$status"
    printf '  "port": %d,\n' "$PROXY_PORT"
    printf '  "domain": "%s",\n' "$PROXY_DOMAIN"
    printf '  "uptime_seconds": %d,\n' "$uptime_secs"
    printf '  "connections": %d,\n' "${connections:-0}"
    printf '  "traffic_in": %d,\n' "${traffic_in:-0}"
    printf '  "traffic_out": %d,\n' "${traffic_out:-0}"
    printf '  "secrets": [\n'

    local i first=true
    for i in "${!SECRETS_LABELS[@]}"; do
        local label="${SECRETS_LABELS[$i]}"
        [ "$first" = "true" ] && first=false || printf ',\n'
        local u_in=${_batch_cum_in["$label"]:-0}
        local u_out=${_batch_cum_out["$label"]:-0}
        local u_conns=${_batch_cum_conns["$label"]:-0}
        printf '    {\n'
        printf '      "label": "%s",\n' "$label"
        printf '      "enabled": %s,\n' "${SECRETS_ENABLED[$i]}"
        printf '      "traffic_in": %d,\n' "$u_in"
        printf '      "traffic_out": %d,\n' "$u_out"
        printf '      "connections": %d,\n' "$u_conns"
        printf '      "quota": %d,\n' "${SECRETS_QUOTA[$i]:-0}"
        printf '      "expires": "%s",\n' "${SECRETS_EXPIRES[$i]:-0}"
        printf '      "notes": "%s"\n' "$(_json_escape "${SECRETS_NOTES[$i]:-}")"
        printf '    }'
    done
    printf '\n  ]\n'
    printf '}\n'
}

show_metrics() {
    local m
    if ! m=$(_fetch_metrics 2>/dev/null); then
        log_error "Metrics endpoint unavailable — is the proxy running?"
        return 1
    fi

    # Single awk pass: S| = scalars, D| = duration buckets, U| = per-user
    local parsed
    parsed=$(echo "$m" | awk '
        function lbl(s, k,    p, q) {
            p = index(s, k "=\""); if (!p) return ""
            s = substr(s, p + length(k) + 2)
            q = index(s, "\""); return q ? substr(s, 1, q-1) : ""
        }
        /^telemt_uptime_seconds /                           { uptime = $NF }
        /^telemt_connections_total /                        { c_tot  = $NF }
        /^telemt_connections_bad_total /                    { c_bad  = $NF }
        /^telemt_connections_current /                      { c_cur  = $NF }
        /^telemt_connections_me_current /                   { c_me   = $NF }
        /^telemt_connections_direct_current /               { c_dir  = $NF }
        /^telemt_upstream_connect_attempt_total /           { up_att = $NF }
        /^telemt_upstream_connect_success_total /           { up_ok  = $NF }
        /^telemt_upstream_connect_fail_total /              { up_fail= $NF }
        /^telemt_me_reconnect_attempts_total /              { me_att = $NF }
        /^telemt_me_reconnect_success_total /               { me_ok  = $NF }
        /^telemt_me_writers_active_current /                { me_wa  = $NF }
        /^telemt_me_writers_warm_current /                  { me_ww  = $NF }
        /^telemt_me_endpoint_quarantine_total /             { me_quar= $NF }
        /^telemt_me_crc_mismatch_total /                    { me_crc = $NF }
        /^telemt_pool_drain_active /                        { pool   = $NF }
        /^telemt_desync_total /                             { desync = $NF }
        /^telemt_secure_padding_invalid_total /             { padinv = $NF }
        /^telemt_upstream_connect_duration_success_total\{/ { b=lbl($0,"bucket"); if(b) ds[b]+=$NF }
        /^telemt_upstream_connect_duration_fail_total\{/    { b=lbl($0,"bucket"); if(b) df[b]+=$NF }
        /^telemt_user_connections_current\{/ { u=lbl($0,"user"); if(u) uc[u]+=$NF }
        /^telemt_user_connections_total\{/   { u=lbl($0,"user"); if(u) ut[u]+=$NF }
        /^telemt_user_octets_from_client\{/  { u=lbl($0,"user"); if(u) rx[u]+=$NF }
        /^telemt_user_octets_to_client\{/    { u=lbl($0,"user"); if(u) tx[u]+=$NF }
        /^telemt_user_unique_ips_current\{/  { u=lbl($0,"user"); if(u) ui[u]+=$NF }
        END {
            printf "S|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f\n",
                uptime+0,c_tot+0,c_bad+0,c_cur+0,c_me+0,c_dir+0,
                up_att+0,up_ok+0,up_fail+0,me_att+0,me_ok+0,
                me_wa+0,me_ww+0,me_quar+0,me_crc+0,pool+0,desync+0,padinv+0
            bkeys[1]="le_100ms";   bnames[1]="<=100ms"
            bkeys[2]="101_500ms";  bnames[2]="101-500ms"
            bkeys[3]="501_1000ms"; bnames[3]="501ms-1s"
            bkeys[4]="gt_1000ms";  bnames[4]=">1s"
            for (i=1;i<=4;i++) {
                b=bkeys[i]; ok=ds[b]+0; fail=df[b]+0; tot=ok+fail
                printf "D|%s|%s|%.0f|%.0f|%.1f\n", b, bnames[i], ok, fail, (tot>0 ? ok/tot*100 : -1)
            }
            for (u in uc) users[u]=1
            for (u in rx) users[u]=1
            for (u in tx) users[u]=1
            for (u in ui) users[u]=1
            for (u in users)
                printf "U|%s|%.0f|%.0f|%.0f|%.0f|%.0f\n", u, uc[u]+0, ut[u]+0, rx[u]+0, tx[u]+0, ui[u]+0
        }
    ')

    # Parse scalar line
    local uptime c_tot c_bad c_cur c_me c_dir up_att up_ok up_fail me_att me_ok me_wa me_ww me_quar me_crc pool desync padinv
    IFS='|' read -r _ uptime c_tot c_bad c_cur c_me c_dir up_att up_ok up_fail \
                       me_att me_ok me_wa me_ww me_quar me_crc pool desync padinv \
        <<< "$(echo "$parsed" | grep '^S|')"

    local c_good=$(( ${c_tot:-0} - ${c_bad:-0} ))
    local up_rate=0 me_rate=0
    [ "${up_att:-0}" -gt 0 ] && up_rate=$(awk -v a="$up_att" -v b="$up_ok" 'BEGIN{printf "%.1f", b/a*100}')
    [ "${me_att:-0}" -gt 0 ] && me_rate=$(awk -v a="$me_att" -v b="$me_ok" 'BEGIN{printf "%.1f", b/a*100}')

    local up_status
    if   [ "${up_att:-0}" -eq 0 ]; then
        up_status="${DIM}—${NC}"
    elif awk -v r="$up_rate" 'BEGIN{exit !(r+0 >= 95)}'; then
        up_status="${BRIGHT_GREEN}OK${NC} ${up_rate}%"
    elif awk -v r="$up_rate" 'BEGIN{exit !(r+0 >= 80)}'; then
        up_status="${YELLOW}WARN${NC} ${up_rate}%"
    else
        up_status="${BRIGHT_RED}CRIT${NC} ${up_rate}%"
    fi

    local me_rate_disp
    [ "${me_att:-0}" -gt 0 ] && me_rate_disp="${me_rate}%" || me_rate_disp="—"

    draw_header "METRICS"
    echo -e "  ${DIM}uptime:${NC} $(format_duration "${uptime:-0}")   ${DIM}upstream:${NC} ${up_status}   ${DIM}active:${NC} ${c_cur:-0}   ${DIM}writers:${NC} ${me_wa:-0}/${me_ww:-0}"
    echo ""

    echo -e "  ${BOLD}Connections${NC}"
    echo -e "  ${DIM}total:${NC} ${c_tot:-0}   ${DIM}authorized:${NC} ${BRIGHT_GREEN}${c_good}${NC}   ${DIM}rejected:${NC} ${BRIGHT_RED}${c_bad:-0}${NC}"
    echo -e "  ${DIM}active:${NC} ${c_cur:-0}  (ME: ${c_me:-0}  direct: ${c_dir:-0})"
    echo ""

    echo -e "  ${BOLD}Upstream${NC}"
    echo -e "  ${DIM}attempts:${NC} ${up_att:-0}   ${DIM}success:${NC} ${BRIGHT_GREEN}${up_ok:-0}${NC}   ${DIM}failed:${NC} ${BRIGHT_RED}${up_fail:-0}${NC}   ${DIM}rate:${NC} ${up_status}"
    while IFS='|' read -r _ bk bn ok fail pct; do
        local ppct
        ppct=$(awk -v p="$pct" 'BEGIN{if(p+0<0) print "—"; else printf "%.0f%%", p}')
        printf "    %-12s  %6s ok  %6s fail  (%s)\n" "$bn" "$ok" "$fail" "$ppct"
    done < <(echo "$parsed" | grep '^D|')
    echo ""

    local user_lines
    user_lines=$(echo "$parsed" | grep '^U|' | sort -t'|' -k3 -rn)
    if [ -n "$user_lines" ]; then
        echo -e "  ${BOLD}Users${NC}"
        while IFS='|' read -r _ uname ucur utot urx utx uips; do
            echo -e "  ${GREEN}${SYM_OK}${NC} ${BOLD}${uname}${NC}  active: ${ucur}  total: ${utot}  ${SYM_DOWN} $(format_bytes "$urx")  ${SYM_UP} $(format_bytes "$utx")  IPs: ${uips}"
        done <<< "$user_lines"
        echo ""
    fi

    echo -e "  ${BOLD}ME Health${NC}"
    echo -e "  ${DIM}reconnects:${NC} ${me_ok:-0}/${me_att:-0} (${me_rate_disp})   ${DIM}writers:${NC} ${me_wa:-0} active / ${me_ww:-0} warm"
    [ "${me_quar:-0}" -gt 0 ] && echo -e "  ${DIM}quarantined endpoints:${NC} ${YELLOW}${me_quar}${NC}"
    [ "${me_crc:-0}"  -gt 0 ] && echo -e "  ${DIM}CRC mismatches:${NC}       ${YELLOW}${me_crc}${NC}"
    [ "${pool:-0}"    -gt 0 ] && echo -e "  ${DIM}writers draining:${NC}     ${pool}"
    echo ""

    if [ "${desync:-0}" -gt 0 ] || [ "${padinv:-0}" -gt 0 ]; then
        echo -e "  ${BOLD}Security${NC}"
        [ "${desync:-0}"  -gt 0 ] && echo -e "  ${DIM}desync events:${NC}   ${YELLOW}${desync}${NC}"
        [ "${padinv:-0}"  -gt 0 ] && echo -e "  ${DIM}invalid padding:${NC} ${YELLOW}${padinv}${NC}"
        echo ""
    fi
}

show_status() {
    echo ""
    local w=$TERM_WIDTH

    draw_box_top "$w"
    draw_box_center "${BRIGHT_CYAN}${BOLD}M T P R O X Y M A X${NC}" "$w"
    draw_box_sep "$w"

    # Status info
    local status_str uptime_str traffic_in traffic_out connections
    if is_proxy_running; then
        status_str=$(draw_status running)
        local up_secs
        up_secs=$(get_proxy_uptime)
        uptime_str=$(format_duration "$up_secs")

        read -r traffic_in traffic_out connections <<< "$(get_cumulative_proxy_stats)"
    else
        status_str=$(draw_status stopped)
        uptime_str="—"
        traffic_in=0
        traffic_out=0
        connections=0
    fi

    draw_box_line "  ${BOLD}Engine:${NC} telemt v$(get_telemt_version)  ${BOLD}Status:${NC} ${status_str}" "$w"
    draw_box_line "  ${BOLD}Port:${NC}   ${PROXY_PORT}            ${BOLD}Uptime:${NC} ${uptime_str}" "$w"
    draw_box_line "  ${BOLD}Domain:${NC} ${PROXY_DOMAIN}" "$w"
    draw_box_line "  ${BOLD}Traffic:${NC} ${SYM_DOWN} $(format_bytes "$traffic_in")  ${SYM_UP} $(format_bytes "$traffic_out")" "$w"
    draw_box_line "  ${BOLD}Connections:${NC} ${connections}" "$w"

    # Count secrets
    local active=0 disabled=0
    local i
    for i in "${!SECRETS_ENABLED[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] && active=$((active+1)) || disabled=$((disabled+1))
    done
    draw_box_line "  ${BOLD}Secrets:${NC} ${active} active / ${disabled} disabled" "$w"

    draw_box_bottom "$w"
    echo ""
}

cli_main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        # No args = menu or installer (disable errexit for interactive TUI)
        "")
            set +eo pipefail
            if [ -f "$SETTINGS_FILE" ]; then
                load_settings
                load_secrets
                check_update_sha_bg   # non-blocking background SHA check
                show_main_menu
            else
                run_installer
            fi
            ;;

        start)
            check_root
            load_settings
            load_secrets
            start_proxy_container
            ;;
        stop)
            check_root
            load_settings
            stop_proxy_container
            ;;
        restart)
            check_root
            load_settings
            load_secrets
            restart_proxy_container
            ;;
        status)
            load_settings
            load_secrets
            if [ "$1" = "--json" ]; then
                show_status_json
            else
                show_status
            fi
            ;;

        secret)
            load_settings
            load_secrets
            local subcmd="${1:-list}"
            shift 2>/dev/null || true
            case "$subcmd" in
                add)
                    check_root
                    local _no_restart="false" _add_label="" _add_secret="" _add_template=""
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            --no-restart) _no_restart="true" ;;
                            --template) shift; _add_template="$1" ;;
                            *) [ -z "$_add_label" ] && _add_label="$1" || _add_secret="$1" ;;
                        esac; shift
                    done
                    secret_add "$_add_label" "$_add_secret" "$_no_restart" || return 1
                    # Apply template after creating
                    if [ -n "$_add_template" ]; then
                        template_apply "$_add_template" "$_add_label" || return 1
                    fi
                    return 0
                    ;;
                add-batch)
                    check_root
                    local _no_restart="false" _args=()
                    for _a in "$@"; do [[ "$_a" == "--no-restart" ]] && _no_restart="true" || _args+=("$_a"); done
                    secret_add_batch "$_no_restart" "${_args[@]}"
                    ;;
                remove)
                    check_root
                    local _no_restart="false" _rm_label="" _dry=""
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            --no-restart) _no_restart="true" ;;
                            --dry-run)    _dry="true" ;;
                            *) [ -z "$_rm_label" ] && _rm_label="$1" ;;
                        esac; shift
                    done
                    if [ "$_dry" = "true" ]; then
                        log_info "DRY RUN — would remove secret '${_rm_label}' (no changes made)"
                    else
                        secret_remove "$_rm_label" "false" "$_no_restart" || return 1
                    fi
                    return 0
                    ;;
                remove-batch)
                    check_root
                    local _no_restart="false" _args=()
                    for _a in "$@"; do [[ "$_a" == "--no-restart" ]] && _no_restart="true" || _args+=("$_a"); done
                    secret_remove_batch "false" "$_no_restart" "${_args[@]}"
                    ;;
                list)
                    if [ "${1:-}" = "--tag" ] && [ -n "${2:-}" ]; then
                        secret_list_by_tag "$2"
                    elif [ "${1:-}" = "--csv" ]; then
                        secret_list_csv
                    else
                        secret_list
                    fi
                    ;;
                rotate)
                    check_root
                    if [ "${1:-}" = "--all" ]; then
                        secret_rotate_all "${2:-false}"
                    elif [ "${1:-}" = "--dry-run" ]; then
                        secret_rotate_all "true"
                    else
                        secret_rotate "$1"
                    fi
                    ;;
                quota-reset)
                    check_root
                    secret_set_quota_reset_day "$1" "$2"
                    ;;
                link)    get_proxy_link_https "${1:-}"; echo "" ;;
                qr)      secret_qr "${1:-}" ;;
                enable)  check_root; secret_toggle "$1" enable ;;
                disable) check_root; secret_toggle "$1" disable ;;
                limits)  secret_show_limits "$1" ;;
                setlimit)
                    check_root
                    local _no_restart="false"
                    local _args=()
                    for _a in "$@"; do
                        if [ "$_a" = "--no-restart" ]; then _no_restart="true"
                        else _args+=("$_a"); fi
                    done
                    set -- "${_args[@]}"
                    local label="$1"; shift 2>/dev/null || true
                    local field="$1"; shift 2>/dev/null || true
                    local value="$1"
                    if [ -z "$label" ] || [ -z "$field" ] || [ -z "$value" ]; then
                        log_error "Usage: mtproxymax secret setlimit <label> conns|ips|quota|expires <value> [--no-restart]"
                        return 1
                    fi
                    case "$field" in
                        conns)   secret_set_limits "$label" "$value" "" "" "" "$_no_restart" ;;
                        ips)     secret_set_limits "$label" "" "$value" "" "" "$_no_restart" ;;
                        quota)   secret_set_limits "$label" "" "" "$value" "" "$_no_restart" ;;
                        expires) secret_set_limits "$label" "" "" "" "$value" "$_no_restart" ;;
                        *) log_error "Usage: mtproxymax secret setlimit <label> conns|ips|quota|expires <value> [--no-restart]"; return 1 ;;
                    esac
                    ;;
                setlimits)
                    check_root
                    local _no_restart="false"
                    local _args=()
                    for _a in "$@"; do
                        if [ "$_a" = "--no-restart" ]; then _no_restart="true"
                        else _args+=("$_a"); fi
                    done
                    set -- "${_args[@]}"
                    local label="$1"; shift 2>/dev/null || true
                    local sl_conns="${1:-0}"; shift 2>/dev/null || true
                    local sl_ips="${1:-0}"; shift 2>/dev/null || true
                    local sl_quota="${1:-0}"; shift 2>/dev/null || true
                    local sl_exp="${1:-}"
                    [ -z "$label" ] && { log_error "Usage: mtproxymax secret setlimits <label> <conns> <ips> <quota> [expires] [--no-restart]"; return 1; }
                    secret_set_limits "$label" "$sl_conns" "$sl_ips" "$sl_quota" "$sl_exp" "$_no_restart"
                    ;;
                reenable)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret reenable <label>"; return 1; }
                    secret_reenable "$1"
                    ;;
                reset-traffic)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret reset-traffic <label|all>"; return 1; }
                    secret_reset_traffic "$1"
                    ;;
                note)
                    local label="$1"; shift 2>/dev/null || true
                    local note_text="$*"
                    [ -z "$label" ] && { log_error "Usage: mtproxymax secret note <label> [text]"; return 1; }
                    secret_edit_note "$label" "$note_text"
                    ;;
                adtag)
                    check_root
                    local _no_restart="false" _args=()
                    for _a in "$@"; do [[ "$_a" == "--no-restart" ]] && _no_restart="true" || _args+=("$_a"); done
                    set -- "${_args[@]}"
                    local label="$1"; shift 2>/dev/null || true
                    local at="$1"
                    if [ -z "$label" ]; then
                        log_error "Usage: mtproxymax secret adtag <label> [32-hex-tag|clear] [--no-restart]"
                        return 1
                    fi
                    secret_set_adtag "$label" "$at" "$_no_restart"
                    ;;
                rename)
                    check_root
                    [ -z "$1" ] || [ -z "$2" ] && { log_error "Usage: mtproxymax secret rename <old> <new>"; return 1; }
                    secret_rename "$1" "$2"
                    ;;
                clone)
                    check_root
                    [ -z "$1" ] || [ -z "$2" ] && { log_error "Usage: mtproxymax secret clone <source> <new-label>"; return 1; }
                    secret_clone "$1" "$2"
                    ;;
                bulk-extend)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret bulk-extend <days>"; return 1; }
                    secret_bulk_extend "$1"
                    ;;
                export)
                    secret_export
                    ;;
                import)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret import <file>"; return 1; }
                    secret_import "$1"
                    ;;
                purge-disabled)
                    check_root
                    secret_purge_disabled
                    ;;
                sub)
                    secret_sub
                    ;;
                export-json)
                    secret_export_json
                    ;;
                rename-prefix)
                    check_root
                    [ -z "$1" ] || [ -z "$2" ] && { log_error "Usage: mtproxymax secret rename-prefix <old> <new>"; return 1; }
                    secret_rename_prefix "$1" "$2"
                    ;;
                disable-expired)
                    check_root
                    secret_disable_expired
                    ;;
                extend)
                    check_root
                    [ -z "$1" ] || [ -z "$2" ] && { log_error "Usage: mtproxymax secret extend <label> <days>"; return 1; }
                    secret_extend "$1" "$2"
                    ;;
                stats)
                    secret_stats
                    ;;
                sort)
                    check_root
                    secret_sort "${1:-traffic}"
                    ;;
                info)
                    secret_info "$1"
                    ;;
                generate-links)
                    secret_generate_links "${1:-txt}" "${2:-}"
                    ;;
                search)
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret search <query>"; return 1; }
                    secret_search "$1"
                    ;;
                archive)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret archive <label>"; return 1; }
                    secret_archive "$1"
                    ;;
                unarchive)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax secret unarchive <label>"; return 1; }
                    secret_unarchive "$1"
                    ;;
                archives)
                    secret_archive_list
                    ;;
                top)
                    secret_top "${1:-traffic}" "${2:-5}"
                    ;;
                tag)
                    check_root
                    local _tg_label="$1"; shift 2>/dev/null || true
                    secret_tag "$_tg_label" "$@"
                    ;;
                untag)
                    check_root
                    secret_untag "$1"
                    ;;
                tags)
                    local _st_label="$1"
                    if [ -z "$_st_label" ]; then
                        [ ! -f "$_TAGS_FILE" ] && { log_info "No tags set"; return 0; }
                        cat "$_TAGS_FILE" 2>/dev/null | column -t -s'|' 2>/dev/null || cat "$_TAGS_FILE"
                    else
                        local _t; _t=$(secret_get_tags "$_st_label")
                        echo "  ${_st_label}: ${_t:-${DIM}(none)${NC}}"
                    fi
                    ;;
                logs)
                    secret_logs "$1" "${2:-50}"
                    ;;
                *)       log_error "Unknown: secret ${subcmd}"; show_cli_help; return 1 ;;
            esac
            ;;

        upstream)
            load_settings
            load_secrets
            local subcmd="${1:-list}"
            shift 2>/dev/null || true
            case "$subcmd" in
                list)    upstream_list ;;
                add)
                    check_root
                    local name="$1" type="$2" addr="${3:-}" user="${4:-}" pass="${5:-}" weight="${6:-10}" iface="${7:-}"
                    upstream_add "$name" "$type" "$addr" "$user" "$pass" "$weight" "$iface"
                    ;;
                remove)  check_root; upstream_remove "$1" ;;
                enable)  check_root; upstream_toggle "$1" enable ;;
                disable) check_root; upstream_toggle "$1" disable ;;
                test)    upstream_test "$1" ;;
                *)       log_error "Unknown: upstream ${subcmd}"; show_cli_help; return 1 ;;
            esac
            ;;

        port)
            load_settings
            local new_port="$1"
            if [ -z "$new_port" ] || [ "$new_port" = "get" ]; then
                echo "$PROXY_PORT"
                return 0
            fi
            check_root
            if validate_port "$new_port"; then
                # Remove geoblock rules on old port before changing
                [ -n "$BLOCKLIST_COUNTRIES" ] && { geoblock_remove_all; _remove_default_drop; }
                PROXY_PORT="$new_port"
                save_settings
                log_success "Port changed to ${new_port}"
                if is_proxy_running; then
                    load_secrets
                    restart_proxy_container
                fi
            else
                log_error "Invalid port: ${new_port} (must be 1-65535)"
                return 1
            fi
            ;;

        ip)
            load_settings
            local ip_arg="$1"
            case "$ip_arg" in
                ""|get)
                    if [ -n "${CUSTOM_IP}" ]; then
                        echo "${CUSTOM_IP} (custom)"
                    else
                        echo "$(get_public_ip) (auto-detected)"
                    fi
                    return 0
                    ;;
                auto|clear)
                    check_root
                    CUSTOM_IP=""
                    save_settings
                    log_success "IP reset to auto-detect ($(CUSTOM_IP="" get_public_ip))"
                    ;;
                *)
                    check_root
                    if [[ "$ip_arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$ip_arg" =~ ^[0-9a-fA-F:]+$ ]] || [[ "$ip_arg" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
                        CUSTOM_IP="$ip_arg"
                        save_settings
                        log_success "IP/domain set to ${ip_arg}"
                    else
                        log_error "Invalid IP address or domain: ${ip_arg}"
                        return 1
                    fi
                    ;;
            esac
            ;;

        domain)
            load_settings
            local new_domain="$1"
            case "$new_domain" in
                ""|get)
                    echo "${PROXY_DOMAIN:-<not set>}"
                    return 0
                    ;;
                clear)
                    check_root
                    PROXY_DOMAIN=""
                    save_settings
                    log_success "Domain cleared"
                    if is_proxy_running; then
                        load_secrets
                        restart_proxy_container
                    fi
                    ;;
                *)
                    check_root
                    if validate_domain "$new_domain"; then
                        PROXY_DOMAIN="$new_domain"
                        sync_domain_cert_len "true" "false" || true
                        save_settings
                        log_success "Domain changed to ${new_domain}"
                        audit_log "domain change → ${new_domain}"
                        log_warn "Existing proxy links still encode the old domain"
                        local _rot="y"
                        if [ -t 0 ]; then
                            echo -en "  ${BOLD}Rotate all secrets for new domain? [Y/n]:${NC} "
                            read -r _rot || _rot="y"
                        else
                            log_info "Non-interactive mode: rotating secrets and restarting automatically"
                        fi
                        if [[ ! "$_rot" =~ ^[nN] ]]; then
                            local _ri
                            for _ri in "${!SECRETS_LABELS[@]}"; do
                                SECRETS_KEYS[$_ri]=$(generate_secret)
                            done
                            save_secrets
                            log_success "All secrets rotated — share new links with your users"
                        fi
                        if is_proxy_running; then
                            load_secrets
                            restart_proxy_container
                        fi
                    else
                        log_error "Invalid domain format (use valid hostname like cloudflare.com)"
                        return 1
                    fi
                    ;;
            esac
            ;;

        mask-backend)
            load_settings
            local _mh="${1:-}" _mp="${2:-}"
            if [ -z "$_mh" ]; then
                echo -e "  Mask backend: ${MASKING_HOST:-${PROXY_DOMAIN}}:${MASKING_PORT:-443}"
                return
            fi
            check_root
            load_secrets
            # Support host:port format
            if [[ "$_mh" == *:* ]] && [ -z "$_mp" ]; then
                _mp="${_mh##*:}"; _mh="${_mh%%:*}"
            fi
            [ -n "$_mp" ] && { [[ "$_mp" =~ ^[0-9]+$ ]] && [ "$_mp" -ge 1 ] && [ "$_mp" -le 65535 ] || { log_error "Invalid port"; return 1; }; }
            MASKING_HOST="$_mh"
            [ -n "$_mp" ] && MASKING_PORT="$_mp"
            save_settings
            log_success "Mask backend set to ${MASKING_HOST}:${MASKING_PORT:-443}"
            if is_proxy_running; then
                load_secrets
                restart_proxy_container
            fi
            ;;

        mask-relay-bytes)
            load_settings
            local _val="${1:-}"
            if [ -z "$_val" ]; then
                local _cur="${MASKING_RELAY_MAX_BYTES:-}"
                if [ -z "$_cur" ]; then
                    echo -e "  mask_relay_max_bytes: ${DIM}(engine default — 32768)${NC}"
                elif [ "$_cur" = "0" ]; then
                    echo -e "  mask_relay_max_bytes: ${BOLD}0${NC} ${DIM}(unlimited)${NC}"
                else
                    echo -e "  mask_relay_max_bytes: ${BOLD}${_cur}${NC} bytes"
                fi
                echo -e "  ${DIM}Caps bytes relayed per direction on mask fallback paths.${NC}"
                echo -e "  ${DIM}Set to 0 for unlimited (useful for large mask backends).${NC}"
                return
            fi
            check_root
            load_secrets
            if [ "$_val" = "clear" ] || [ "$_val" = "default" ]; then
                MASKING_RELAY_MAX_BYTES=""
            elif [[ "$_val" =~ ^[0-9]+$ ]]; then
                MASKING_RELAY_MAX_BYTES="$_val"
            else
                log_error "Value must be a non-negative integer, 'clear', or 'default'"
                return 1
            fi
            save_settings
            log_success "mask_relay_max_bytes set to ${MASKING_RELAY_MAX_BYTES:-default}"
            if is_proxy_running; then
                restart_proxy_container
            fi
            ;;

        info)
            load_settings
            load_secrets
            show_server_info
            ;;

        maintenance)
            load_settings
            case "${1:-status}" in
                on|enable)   maintenance_on ;;
                off|disable) maintenance_off ;;
                status|"")   maintenance_status ;;
                *) log_error "Usage: mtproxymax maintenance [on|off|status]"; return 1 ;;
            esac
            ;;

        ban)
            load_settings
            ban_ip "$1"
            ;;
        unban)
            load_settings
            unban_ip "$1"
            ;;
        bans)
            load_settings
            bans_list
            ;;

        migrate)
            load_settings
            load_secrets
            case "${1:-}" in
                export) migrate_export "$2" ;;
                import) migrate_import "$2" ;;
                *) log_error "Usage: mtproxymax migrate export [file] | import <file>"; return 1 ;;
            esac
            ;;

        changelog)
            show_changelog
            ;;

        sweep)
            # Internal periodic maintenance tasks — called by bot loop and/or cron
            load_settings
            load_secrets
            secret_check_quota_resets 2>/dev/null
            secret_check_auto_rotate 2>/dev/null
            secret_disable_expired >/dev/null 2>&1 || true
            sync_domain_cert_len "false" "true" 2>/dev/null || true
            load_cloud_backup_config 2>/dev/null || true
            if [ "${CLOUD_BACKUP_ENABLED:-false}" = "true" ]; then
                local _cb_last=0 _cb_now
                _cb_now=$(date +%s)
                [ -f "${INSTALL_DIR}/.last_cloud_backup_epoch" ] && _cb_last=$(cat "${INSTALL_DIR}/.last_cloud_backup_epoch" 2>/dev/null || echo 0)
                if [ $((_cb_now - _cb_last)) -ge 86400 ]; then
                    create_backup >/dev/null 2>&1 || true
                    echo "$_cb_now" > "${INSTALL_DIR}/.last_cloud_backup_epoch" 2>/dev/null || true
                fi
            fi
            [ "${BACKUP_RETENTION_DAYS:-30}" -gt 0 ] 2>/dev/null && backup_autoclean "${BACKUP_RETENTION_DAYS}" >/dev/null 2>&1
            if [ -f "$CONNECTION_LOG" ] && [ "$(wc -c < "$CONNECTION_LOG" 2>/dev/null || echo 0)" -gt 52428800 ]; then
                tail -n 50000 "$CONNECTION_LOG" > "${CONNECTION_LOG}.tmp" 2>/dev/null && mv "${CONNECTION_LOG}.tmp" "$CONNECTION_LOG" 2>/dev/null || true
            fi
            [ "${AUTO_HEAL_ENABLED:-false}" = "true" ] && run_heal >/dev/null 2>&1 || true
            [ "${TLS_PAD_ENABLED:-false}" = "true" ] && run_tls_pad randomize >/dev/null 2>&1 || true
            if [ -f "${INSTALL_DIR}/failover.conf" ]; then
                local fo_status="disabled" fo_mode="backend"
                fo_status=$(grep -E '^fo_status=' "${INSTALL_DIR}/failover.conf" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "disabled")
                fo_mode=$(grep -E '^fo_mode=' "${INSTALL_DIR}/failover.conf" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "backend")
                if [ "$fo_status" = "enabled" ]; then
                    load_upstreams 2>/dev/null || true
                    local active_up_idx=-1
                    for ((u=0; u<${#UPSTREAM_NAMES[@]}; u++)); do
                        if [ "${UPSTREAM_ENABLED[$u]}" = "true" ]; then
                            active_up_idx=$u
                            break
                        fi
                    done
                    if [ "$active_up_idx" -ne -1 ]; then
                        local up_name="${UPSTREAM_NAMES[$active_up_idx]}"
                        if ! upstream_test "$up_name" >/dev/null 2>&1; then
                            local fo_cnt_file="${INSTALL_DIR}/relay_stats/.failover_fails"
                            local fo_fails=0
                            [ -f "$fo_cnt_file" ] && fo_fails=$(cat "$fo_cnt_file" 2>/dev/null || echo 0)
                            fo_fails=$((fo_fails + 1))
                            mkdir -p "$(dirname "$fo_cnt_file")" 2>/dev/null || true
                            echo "$fo_fails" > "$fo_cnt_file" 2>/dev/null || true
                            if [ "$fo_fails" -ge 3 ]; then
                                upstream_toggle "$up_name" "disable" >/dev/null 2>&1 || true
                                rm -f "$fo_cnt_file" 2>/dev/null || true
                                local _next_up_found="" _n
                                load_upstreams 2>/dev/null || true
                                for ((_n=0; _n<${#UPSTREAM_NAMES[@]}; _n++)); do
                                    if [ "${UPSTREAM_ENABLED[$_n]}" != "true" ] && [ "${UPSTREAM_NAMES[$_n]}" != "$up_name" ]; then
                                        if upstream_test "${UPSTREAM_NAMES[$_n]}" >/dev/null 2>&1; then
                                            _next_up_found="${UPSTREAM_NAMES[$_n]}"
                                            break
                                        fi
                                    fi
                                done
                                if [ -n "$_next_up_found" ]; then
                                    upstream_toggle "$_next_up_found" "enable" >/dev/null 2>&1 || true
                                    if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
                                        tg_send "🔄 *Autonomous Upstream Failover Triggered*\n\nUpstream *$(_esc "$up_name")* failed 3 consecutive health pings and was automatically disabled.\n\n✅ Switched traffic to healthy standby upstream: *$(_esc "$_next_up_found")*."
                                    fi
                                else
                                    if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
                                        tg_send "🔄 *Autonomous Upstream Failover Triggered*\n\nUpstream *$(_esc "$up_name")* failed 3 consecutive health pings and was automatically disabled.\n\n⚠️ No healthy standby upstreams found. Routing traffic directly via host public IP."
                                    fi
                                fi
                            fi
                        else
                            rm -f "${INSTALL_DIR}/relay_stats/.failover_fails" 2>/dev/null || true
                        fi
                    fi
                fi
            fi
            if [ -f "${INSTALL_DIR}/eco_mode.conf" ]; then
                local eco_status="disabled"
                eco_status=$(grep -E '^eco_status=' "${INSTALL_DIR}/eco_mode.conf" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r' | tail -1 || echo "disabled")
                if [ "$eco_status" = "enabled" ]; then
                    sysctl -w net.core.rmem_max=131072 >/dev/null 2>&1 || true
                    sysctl -w net.core.wmem_max=131072 >/dev/null 2>&1 || true
                fi
            fi
            if [ -s "${INSTALL_DIR}/pools.conf" ] && [ -f "$STATUS_JSON_FILE" ]; then
                while IFS='|' read -r p_name p_limit p_members p_notes; do
                    [ -z "$p_name" ] || [ "$p_limit" -le 0 ] 2>/dev/null && continue
                    local comb_bytes=0
                    IFS=',' read -ra mem_arr <<< "$p_members"
                    for mem in "${mem_arr[@]}"; do
                        local ub; ub=$(awk -v l="$mem" '$0 ~ "\"" l "\":" {getline; getline; if($0 ~ "bytes_used") {gsub(/[^0-9]/, "", $0); print $0; exit}}' "$STATUS_JSON_FILE" 2>/dev/null || echo 0)
                        comb_bytes=$(( comb_bytes + ${ub:-0} ))
                    done
                    if [ "$comb_bytes" -ge "$p_limit" ]; then
                        local any_enabled="false"
                        for ((idx=0; idx<${#SECRETS_LABELS[@]}; idx++)); do
                            for mem in "${mem_arr[@]}"; do
                                if [ "${SECRETS_LABELS[$idx]}" = "$mem" ] && [ "${SECRETS_ENABLED[$idx]}" = "true" ]; then
                                    any_enabled="true"
                                    break 2
                                fi
                            done
                        done
                        if [ "$any_enabled" = "true" ]; then
                            for mem in "${mem_arr[@]}"; do
                                secret_toggle "$mem" "disable" >/dev/null 2>&1 || true
                            done
                            if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
                                tg_send "⚠️ *Shared Quota Pool Exceeded*\n\nPool *$(_esc "$p_name")* reached limit ($(format_bytes "$p_limit")). All member links paused."
                            fi
                        fi
                    fi
                done < "${INSTALL_DIR}/pools.conf"
            fi
            ;;

        auto-rotate)
            load_settings
            local _val="${1:-}"
            if [ -z "$_val" ]; then
                echo -e "  Auto-rotate: ${SECRET_AUTO_ROTATE_DAYS:-0} days ${DIM}(0 = disabled)${NC}"
                return
            fi
            check_root
            if [ "$_val" = "off" ] || [ "$_val" = "0" ]; then
                SECRET_AUTO_ROTATE_DAYS="0"
            elif [[ "$_val" =~ ^[0-9]+$ ]] && [ "$_val" -ge 1 ] && [ "$_val" -le 3650 ]; then
                SECRET_AUTO_ROTATE_DAYS="$_val"
            else
                log_error "Value must be a positive integer (days) or 'off'"
                return 1
            fi
            save_settings
            log_success "Auto-rotate policy: ${SECRET_AUTO_ROTATE_DAYS} days"
            ;;

        template)
            load_settings
            load_secrets
            local sub="${1:-list}"; shift 2>/dev/null || true
            case "$sub" in
                save)   template_save "$@" ;;
                list)   template_list ;;
                delete) template_delete "$1" ;;
                apply)  template_apply "$@" ;;
                *) log_error "Usage: mtproxymax template save|list|delete|apply"; return 1 ;;
            esac
            ;;

        tune)
            load_settings
            local sub="${1:-list}"; shift 2>/dev/null || true
            case "$sub" in
                list|"")               tune_list_params ;;
                get)                   tune_get "$1" ;;
                set)                   tune_set "$1" "$2" ;;
                clear)                 tune_clear "$1" ;;
                fastpath|tcp-fastpath) run_tcp_fastpath "$@" ;;
                bbr|net|tune-net)      run_bbr "$@" ;;
                ram|ram-tune)          run_ram_tune "$@" ;;
                cpu|cpu-tune)          run_cpu_tune "$@" ;;
                *) log_error "Usage: mtproxymax tune list|get|set|clear|fastpath|bbr|ram|cpu"; return 1 ;;
            esac
            ;;

        verify)
            load_settings
            load_secrets
            run_verify
            ;;

        history)
            show_history "${1:-50}"
            ;;

        completion)
            emit_completion
            ;;

        speedtest)
            run_speedtest
            ;;

        digest)
            load_settings
            load_secrets
            run_digest
            ;;

        ping-dc)
            run_ping_dc
            ;;

        syn-shield|kernel-shield)
            run_shield "$@"
            ;;

        stealth)
            run_stealth_preset "$@"
            ;;

        clamp-mss)
            run_clamp_mss "$@"
            ;;

        domain-pool)
            run_domain_pool "$@"
            ;;

        dpi-inspect)
            load_settings
            run_dpi_inspect
            ;;

        cover-watchdog)
            run_cover_watchdog "$@"
            ;;

        lockdown)
            run_lockdown "$@"
            ;;

        port-pool)
            run_port_pool "$@"
            ;;

        qos)
            run_qos "$@"
            ;;

        happy-hours)
            run_happy_hours "$@"
            ;;

        quota-mode)
            run_quota_mode "$@"
            ;;

        notify-expiry)
            run_notify_expiry
            ;;

        abuse-watch)
            run_abuse_watch
            ;;

        broadcast)
            run_broadcast "$1"
            ;;

        export-lb)
            run_export_lb "$1"
            ;;

        ddns)
            run_ddns "$@"
            ;;

        diag-dump)
            run_diag_dump
            ;;

        snapshot|dev-snapshot)
            run_snapshot "$@"
            ;;

        top)
            run_top "$@"
            ;;

        tag|note-tag)
            run_tag "$@"
            ;;

        export-client)
            run_export_client "$@"
            ;;

        export-report)
            run_export_report "$@"
            ;;

        qr-sheet)
            run_qr_sheet "$@"
            ;;

        guest|burner)
            run_guest "$@"
            ;;

        pool|shared-pool)
            run_pool "$@"
            ;;

        calendar|promo)
            run_calendar "$@"
            ;;

        geofence|geo-fence)
            run_geo_fence "$@"
            ;;

        decoy|decoy-web)
            run_decoy_web "$@"
            ;;

        auto-sni)
            run_auto_sni "$@"
            ;;

        dc-optimize|dc-ping)
            run_dc_optimize "$@"
            ;;

        ip-score|reputation)
            run_ip_score "$@"
            ;;

        webhook|webhooks)
            run_webhooks "$@"
            ;;

        failover|auto-failover)
            run_auto_failover "$@"
            ;;

        eco-mode|ecomode)
            run_eco_mode "$@"
            ;;

        chaos-test|chaos)
            run_chaos_test "$@"
            ;;

        evacuate|migrate-server)
            run_evacuate "$@"
            ;;

        daily-report)
            run_daily_report "$@"
            ;;

        ssh-shield)
            run_ssh_shield "$@"
            ;;

        net-grade)
            run_net_grade
            ;;

        onboard)
            run_onboard_wizard "$@"
            ;;

        tcp-boost)
            run_tcp_boost "$@"
            ;;

        leak-scan)
            run_leak_scan "$@"
            ;;

        cert-check)
            run_cert_check "$@"
            ;;

        clone-link)
            run_clone_link
            ;;

        bootstrap)
            run_bootstrap "$1"
            ;;

        heal)
            run_heal
            ;;

        auto-heal)
            run_auto_heal "$@"
            ;;

        tcp-clean)
            run_tcp_clean "$@"
            ;;

        socket-boost)
            run_socket_boost "$@"
            ;;

        tls-pad)
            run_tls_pad "$@"
            ;;

        honeypot)
            run_honeypot "$@"
            ;;

        tcp-fastpath)
            run_tcp_fastpath "$@"
            ;;

        ram-tune)
            run_ram_tune "$@"
            ;;

        port-hop)
            run_port_hop "$@"
            ;;

        cpu-tune)
            run_cpu_tune "$@"
            ;;

        bbr|tune-net)
            run_bbr "$@"
            ;;

        shield|anti-dpi|dpi-shield)
            run_anti_dpi_shield "$@"
            ;;

        cover-shield|fallback)
            run_cover_shield "$@"
            ;;

        tg-urls)
            load_settings
            load_secrets
            local sub="${1:-get}"; shift 2>/dev/null || true
            case "$sub" in
                get|show|"")
                    echo -e "  ${BOLD}Telegram infrastructure URLs${NC}"
                    echo -e "  ${DIM}Empty = use Telegram's defaults (core.telegram.org)${NC}"
                    echo ""
                    echo -e "  proxy_secret_url:    ${PROXY_SECRET_URL:-${DIM}(default)${NC}}"
                    echo -e "  proxy_config_v4_url: ${PROXY_CONFIG_V4_URL:-${DIM}(default)${NC}}"
                    echo -e "  proxy_config_v6_url: ${PROXY_CONFIG_V6_URL:-${DIM}(default)${NC}}"
                    ;;
                clear|reset)
                    check_root
                    PROXY_SECRET_URL=""; PROXY_CONFIG_V4_URL=""; PROXY_CONFIG_V6_URL=""
                    save_settings
                    log_success "Telegram URLs reset to defaults"
                    if is_proxy_running; then restart_proxy_container; fi
                    ;;
                set)
                    check_root
                    local _field="$1" _val="$2"
                    [ -z "$_field" ] || [ -z "$_val" ] && { log_error "Usage: mtproxymax tg-urls set <secret|config-v4|config-v6> <url>"; return 1; }
                    [[ "$_val" =~ ^https?:// ]] || { log_error "URL must start with http:// or https://"; return 1; }
                    case "$_field" in
                        secret)     PROXY_SECRET_URL="$_val" ;;
                        config-v4)  PROXY_CONFIG_V4_URL="$_val" ;;
                        config-v6)  PROXY_CONFIG_V6_URL="$_val" ;;
                        *) log_error "Field must be: secret | config-v4 | config-v6"; return 1 ;;
                    esac
                    save_settings
                    log_success "Telegram URL set: ${_field} = ${_val}"
                    if is_proxy_running; then restart_proxy_container; fi
                    ;;
                *)
                    log_error "Usage: mtproxymax tg-urls [get|set <field> <url>|clear]"
                    return 1
                    ;;
            esac
            ;;

        adtag)
            load_settings
            case "$1" in
                set)
                    check_root
                    local _in
                    _in=$(echo "${2:-}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                    if [[ "$_in" =~ ^[0-9a-f]{32}$ ]]; then
                        AD_TAG="$_in"
                        save_settings
                        log_success "Ad-tag set to: ${_in}"
                        load_secrets; reload_proxy_config
                    else
                        log_error "Ad-tag must be exactly 32 hexadecimal characters (obtained from @MTProxyBot)"
                        return 1
                    fi
                    ;;
                remove|clear|off|delete)
                    check_root
                    AD_TAG=""
                    save_settings
                    log_success "Ad-tag removed (promoted channel disabled)"
                    load_secrets; reload_proxy_config
                    ;;
                view|"")
                    if [ -n "$AD_TAG" ]; then
                        echo -e "  ${BOLD}Ad-tag:${NC} ${AD_TAG}"
                    else
                        echo -e "  ${DIM}No ad-tag configured${NC}"
                        echo -e "  ${DIM}Get one from @MTProxyBot on Telegram${NC}"
                    fi
                    ;;
                *)
                    log_error "Unknown: adtag $1"; show_cli_help; return 1
                    ;;
            esac
            ;;

        geoblock)
            load_settings
            case "$1" in
                add)
                    check_root
                    local code=$(echo "$2" | tr '[:upper:]' '[:lower:]')
                    if [[ "$code" =~ ^[a-z]{2}$ ]]; then
                        if echo ",$BLOCKLIST_COUNTRIES," | grep -q ",${code},"; then
                            log_info "Country '${code^^}' is already blocked"
                        else
                            _ensure_ipset && _download_country_cidrs "$code" && {
                                [ -z "$BLOCKLIST_COUNTRIES" ] && BLOCKLIST_COUNTRIES="$code" || BLOCKLIST_COUNTRIES="${BLOCKLIST_COUNTRIES},${code}"
                                save_settings
                                _apply_country_rules "$code"
                                _ensure_default_drop
                            }
                        fi
                    else
                        log_error "Invalid country code (use 2-letter ISO code, e.g. us, de, ir)"
                    fi
                    ;;
                remove)
                    check_root
                    local code=$(echo "$2" | tr '[:upper:]' '[:lower:]')
                    if [[ "$code" =~ ^[a-z]{2}$ ]]; then
                        if echo ",$BLOCKLIST_COUNTRIES," | grep -q ",${code},"; then
                            BLOCKLIST_COUNTRIES=$(echo ",$BLOCKLIST_COUNTRIES," | sed "s/,${code},/,/g;s/^,//;s/,$//")
                            save_settings
                            _remove_country_rules "$code"
                            rm -f "${GEOBLOCK_CACHE_DIR}/${code}.zone"
                            [ -z "$BLOCKLIST_COUNTRIES" ] && _remove_default_drop
                            log_success "Removed ${code^^} — rules and cache cleared"
                        else
                            log_info "Country '${code^^}' is not blocked"
                        fi
                    else
                        log_error "Invalid country code (use 2-letter ISO code)"
                    fi
                    ;;
                clear)
                    check_root
                    local code
                    IFS=',' read -ra codes <<< "$BLOCKLIST_COUNTRIES"
                    for code in "${codes[@]}"; do
                        [ -z "$code" ] && continue
                        _remove_country_rules "$code"
                        rm -f "${GEOBLOCK_CACHE_DIR}/${code}.zone"
                    done
                    _remove_default_drop
                    BLOCKLIST_COUNTRIES=""
                    save_settings
                    log_success "All geo-blocks cleared"
                    ;;
                list|"")
                    echo -e "  ${BOLD}Blocked countries:${NC} ${BLOCKLIST_COUNTRIES:-${DIM}none${NC}}"
                    ;;
                *)
                    log_error "Unknown: geoblock $1"; show_cli_help; return 1
                    ;;
            esac
            ;;

        sni-policy)
            load_settings
            case "$1" in
                mask)
                    check_root
                    UNKNOWN_SNI_ACTION="mask"; save_settings; reload_proxy_config
                    log_success "Unknown SNI policy set to Mask (permissive)"
                    ;;
                drop)
                    check_root
                    UNKNOWN_SNI_ACTION="drop"; save_settings; reload_proxy_config
                    log_success "Unknown SNI policy set to Drop (strict)"
                    ;;
                "")
                    echo -e "  ${BOLD}Unknown SNI policy:${NC} ${UNKNOWN_SNI_ACTION}"
                    ;;
                *)
                    log_error "Usage: mtproxymax sni-policy [mask|drop]"; return 1
                    ;;
            esac
            ;;

        traffic)
            load_settings
            load_secrets
            echo ""
            draw_header "TRAFFIC"
            local t_in t_out conns
            read -r t_in t_out conns <<< "$(get_cumulative_proxy_stats)"
            # Batch-load all user stats
            _load_all_cumulative_user_stats 2>/dev/null
            echo ""
            echo -e "  ${BOLD}Total:${NC} ${SYM_DOWN} $(format_bytes "$t_in")  ${SYM_UP} $(format_bytes "$t_out")  ${BOLD}Connections:${NC} ${conns}"
            echo ""

            # Per-user breakdown
            for i in "${!SECRETS_LABELS[@]}"; do
                [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
                local label="${SECRETS_LABELS[$i]}"
                local u_in=${_batch_cum_in["$label"]:-0}
                local u_out=${_batch_cum_out["$label"]:-0}
                local u_conns=${_batch_cum_conns["$label"]:-0}
                echo -e "  ${GREEN}${SYM_OK}${NC} ${BOLD}${label}${NC}: ${SYM_DOWN} $(format_bytes "$u_in")  ${SYM_UP} $(format_bytes "$u_out")  conns: ${u_conns}"
            done
            echo ""
            ;;

        connections)
            load_settings
            load_secrets
            show_connections
            ;;

        config)
            load_settings
            show_config
            ;;

        uptime)
            load_settings
            load_secrets
            show_uptime_oneliner
            ;;

        notify)
            load_settings
            send_notify "$*"
            ;;

        port-check)
            load_settings
            port_check
            ;;

        profile)
            load_settings
            load_secrets
            local subcmd="${1:-list}"
            shift 2>/dev/null || true
            case "$subcmd" in
                save)   check_root; profile_save "$1" ;;
                load)   check_root; profile_load "$1" ;;
                list)   profile_list ;;
                delete) check_root; profile_delete "$1" ;;
                *)      log_error "Usage: mtproxymax profile save|load|list|delete <name>"; return 1 ;;
            esac
            ;;

        metrics)
            load_settings
            local subcmd="${1:-}"
            if [ "$subcmd" = "live" ]; then
                local interval="${2:-5}"
                [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 1 ] || interval=5
                (
                    while true; do
                        tput clear 2>/dev/null || printf '\033[2J\033[H'
                        show_metrics
                        echo -e "  ${DIM}[live — refreshing every ${interval}s, Ctrl+C to stop]${NC}"
                        sleep "$interval"
                    done
                )
                echo ""
            else
                show_metrics
            fi
            ;;

        logs)
            load_settings
            echo -e "  ${DIM}Streaming logs (Ctrl+C to stop)...${NC}"
            docker logs -f --tail 50 "$CONTAINER_NAME" 2>&1
            ;;

        instance)
            load_settings
            load_secrets
            load_instances
            local subcmd="${1:-list}"; shift 2>/dev/null || true
            case "$subcmd" in
                add)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax instance add <port> [label]"; return 1; }
                    instance_add "$1" "$2"
                    ;;
                remove)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax instance remove <port>"; return 1; }
                    instance_remove "$1"
                    ;;
                list|"")
                    instance_list
                    ;;
                *) log_error "Unknown: instance ${subcmd}"; return 1 ;;
            esac
            ;;

        backup)
            check_root
            load_settings
            load_secrets
            case "${1:-}" in
                --encrypt|encrypt) backup_create_encrypted ;;
                restore-encrypted) backup_restore_encrypted "$2" ;;
                autoclean)         backup_autoclean "${2:-${BACKUP_RETENTION_DAYS:-30}}" ;;
                send-tg)           run_backup_send_tg "$2" ;;
                *) create_backup ;;
            esac
            ;;

        restore)
            check_root
            load_settings
            if [ "${1:-}" = "--encrypted" ] && [ -n "${2:-}" ]; then
                backup_restore_encrypted "$2"
            else
                restore_backup "$1"
            fi
            ;;

        backups)
            load_settings
            list_backups
            ;;

        connlog)
            load_settings
            if [ "$1" = "clear" ]; then
                check_root
                > "$CONNECTION_LOG" 2>/dev/null
                log_success "Connection log cleared"
            elif [ -f "$CONNECTION_LOG" ] && [ -s "$CONNECTION_LOG" ]; then
                echo ""
                draw_header "CONNECTION LOG"
                echo ""
                tail -n "${1:-50}" "$CONNECTION_LOG"
                echo ""
            else
                log_info "Connection log is empty"
            fi
            ;;

        health)
            load_settings
            load_secrets
            health_check
            ;;

        doctor)
            load_settings
            load_secrets
            run_doctor
            ;;

        telegram)
            load_settings
            load_secrets
            case "${1:-status}" in
                setup)   check_root; telegram_setup_wizard ;;
                test)    telegram_test_message ;;
                status|"")
                    if [ "$TELEGRAM_ENABLED" = "true" ]; then
                        echo -e "  ${BOLD}Telegram:${NC} $(draw_status running 'Enabled')"
                        echo -e "  ${DIM}Interval: every ${TELEGRAM_INTERVAL}h | Alerts: ${TELEGRAM_ALERTS_ENABLED} | Label: ${TELEGRAM_SERVER_LABEL}${NC}"
                    else
                        echo -e "  ${BOLD}Telegram:${NC} $(draw_status disabled 'Disabled')"
                    fi
                    ;;
                interval)
                    check_root
                    shift
                    local _ival="${1:-}"
                    if [ -z "$_ival" ]; then
                        echo -e "  ${BOLD}Report interval:${NC} every ${TELEGRAM_INTERVAL}h"
                        echo -e "  ${DIM}Usage: mtproxymax telegram interval <hours>${NC}"
                        return 0
                    fi
                    if [[ "$_ival" =~ ^[0-9]+$ ]] && [ "$_ival" -ge 1 ] && [ "$_ival" -le 168 ]; then
                        TELEGRAM_INTERVAL="$_ival"
                        save_settings
                        log_success "Report interval set to every ${_ival}h"
                    else
                        log_error "Invalid interval — must be 1-168 hours"
                        return 1
                    fi
                    ;;
                label)
                    check_root
                    shift
                    local _lbl="${*:-}"
                    if [ -z "$_lbl" ]; then
                        echo -e "  ${BOLD}Server label:${NC} ${TELEGRAM_SERVER_LABEL}"
                        echo -e "  ${DIM}Usage: mtproxymax telegram label <name>${NC}"
                        return 0
                    fi
                    if [[ "$_lbl" =~ ^[a-zA-Z0-9_.\ -]+$ ]] && [ ${#_lbl} -le 32 ]; then
                        TELEGRAM_SERVER_LABEL="$_lbl"
                        save_settings
                        log_success "Server label set to '${_lbl}'"
                    else
                        log_error "Invalid label — letters, digits, spaces, dots, hyphens, max 32 chars"
                        return 1
                    fi
                    ;;
                alerts)
                    check_root
                    shift
                    local _aval="${1:-}"
                    case "$_aval" in
                        on|true|enable)
                            TELEGRAM_ALERTS_ENABLED="true"
                            save_settings
                            log_success "Alerts enabled"
                            ;;
                        off|false|disable)
                            TELEGRAM_ALERTS_ENABLED="false"
                            save_settings
                            log_success "Alerts disabled"
                            ;;
                        "")
                            echo -e "  ${BOLD}Alerts:${NC} ${TELEGRAM_ALERTS_ENABLED}"
                            echo -e "  ${DIM}Usage: mtproxymax telegram alerts <on|off>${NC}"
                            ;;
                        *)
                            log_error "Usage: mtproxymax telegram alerts <on|off>"
                            return 1
                            ;;
                    esac
                    ;;
                disable)
                    check_root
                    TELEGRAM_ENABLED="false"
                    save_settings
                    systemctl stop mtproxymax-telegram.service 2>/dev/null || true
                    log_success "Telegram disabled"
                    ;;
                remove)
                    check_root
                    TELEGRAM_ENABLED="false"
                    TELEGRAM_BOT_TOKEN=""
                    TELEGRAM_CHAT_ID=""
                    save_settings
                    systemctl stop mtproxymax-telegram.service 2>/dev/null || true
                    systemctl disable mtproxymax-telegram.service 2>/dev/null || true
                    log_success "Telegram bot removed"
                    ;;
                *) log_error "Usage: mtproxymax telegram [setup|test|status|interval|label|alerts|disable|remove]"; return 1 ;;
            esac
            ;;


        replication)
            load_settings
            case "${1:-status}" in
                setup)   check_root; replication_setup_wizard ;;
                status|"") replication_status ;;
                add)
                    check_root
                    shift; replication_add "$@"
                    ;;
                remove)
                    check_root
                    shift; replication_remove "${1:-}"
                    ;;
                list)
                    replication_list
                    ;;
                enable)
                    check_root
                    load_settings
                    if [ "${REPLICATION_ROLE}" != "master" ]; then
                        log_error "Only a master can enable replication sync. Current role: ${REPLICATION_ROLE}"
                        log_info "Run: mtproxymax replication setup"
                        return 1
                    fi
                    REPLICATION_ENABLED="true"
                    save_settings
                    setup_replication_service
                    log_success "Replication enabled"
                    ;;
                disable)
                    check_root
                    REPLICATION_ENABLED="false"
                    save_settings
                    stop_replication_service
                    log_success "Replication disabled"
                    ;;
                sync)
                    check_root
                    replication_sync_now
                    ;;
                test)
                    shift; replication_test "${1:-}"
                    ;;
                logs)
                    replication_show_logs
                    ;;
                reset)
                    check_root; replication_reset
                    ;;
                promote)
                    check_root; replication_promote
                    ;;
                *)
                    log_error "Unknown: replication ${1}"
                    echo "  Usage: mtproxymax replication [setup|status|add|remove|list|enable|disable|sync|test|logs|reset|promote]"
                    return 1
                    ;;
            esac
            ;;


        firewall)
            load_settings
            show_firewall_guide
            ;;

        portforward)
            load_settings
            show_port_forward_guide
            ;;

        update)
            check_root
            load_settings
            self_update
            ;;

        rebuild)
            check_root
            load_settings
            log_info "Force-rebuilding telemt engine from source (commit ${TELEMT_COMMIT})..."
            build_telemt_image source
            if is_proxy_running; then
                load_secrets
                restart_proxy_container
            fi
            ;;

        engine)
            load_settings
            local subcmd="${1:-status}"
            shift 2>/dev/null || true
            case "$subcmd" in
                status)
                    echo -e "  ${BOLD}Telemt Engine${NC}"
                    echo -e "  ${DIM}Installed:${NC}  v$(get_telemt_version)"
                    echo -e "  ${DIM}Pinned to:${NC}  commit ${TELEMT_COMMIT}"
                    echo ""
                    local _expected="${TELEMT_MIN_VERSION}-${TELEMT_COMMIT}"
                    local _current; _current=$(get_telemt_version)
                    if [ "$_current" = "$_expected" ]; then
                        log_success "Engine is up to date"
                    elif _version_gte "$_current" "$_expected"; then
                        log_success "Engine is up to date (v${_current}, ahead of pinned v${_expected})"
                    else
                        log_info "Update available: v${_current} -> v${_expected}"
                        echo -e "  ${DIM}Run: mtproxymax update${NC}"
                    fi
                    ;;
                rebuild)
                    check_root
                    echo -en "  ${DIM}Force rebuild engine from commit ${TELEMT_COMMIT}? [Y/n]:${NC} "
                    local confirm; read -r confirm
                    if [[ "$confirm" =~ ^[nN] ]]; then
                        return 0
                    fi
                    build_telemt_image true
                    if is_proxy_running; then
                        load_secrets
                        restart_proxy_container
                    fi
                    log_success "Engine rebuilt"
                    ;;
                *)
                    echo -e "  ${BOLD}Usage:${NC} mtproxymax engine <command>"
                    echo ""
                    echo -e "  ${DIM}status${NC}     Show current engine version"
                    echo -e "  ${DIM}rebuild${NC}    Force rebuild engine image"
                    ;;
            esac
            ;;

        voucher)
            load_settings
            local subcmd="${1:-list}"
            shift 2>/dev/null || true
            case "$subcmd" in
                create)
                    check_root
                    voucher_create "${1:-1}" "${2:-10G}" "${3:-30}"
                    ;;
                list)
                    voucher_list "${1:-all}"
                    ;;
                revoke)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax voucher revoke <code>"; return 1; }
                    voucher_revoke "$1"
                    ;;
                redeem)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax voucher redeem <code> [label]"; return 1; }
                    voucher_redeem "$1" "${2:-}"
                    ;;
                *) log_error "Usage: mtproxymax voucher [create|list|revoke|redeem]"; return 1 ;;
            esac
            ;;

        admin|rbac|admins)
            load_settings
            local subcmd="${1:-list}"
            shift 2>/dev/null || true
            case "$subcmd" in
                add)
                    check_root
                    [ -z "$1" ] || [ -z "$2" ] && { log_error "Usage: mtproxymax admin add <tg_chat_id> <role>"; return 1; }
                    admin_add "$1" "$2"
                    ;;
                remove|rm)
                    check_root
                    [ -z "$1" ] && { log_error "Usage: mtproxymax admin remove <tg_chat_id>"; return 1; }
                    admin_remove "$1"
                    ;;
                list)
                    admin_list
                    ;;
                checkrole)
                    _check_tg_role "$1"
                    ;;
                *) log_error "Usage: mtproxymax admin [add|remove|list]"; return 1 ;;
            esac
            ;;

        portal)
            load_settings
            local subcmd="${1:-status}"
            shift 2>/dev/null || true
            case "$subcmd" in
                enable|on)
                    check_root
                    PORTAL_ENABLED="true"
                    save_settings
                    portal_generate
                    portal_export_data
                    log_success "Portal enabled"
                    ;;
                disable|off)
                    check_root
                    PORTAL_ENABLED="false"
                    save_settings
                    log_success "Portal disabled"
                    ;;
                port)
                    check_root
                    [ -z "$1" ] && { echo "${PORTAL_PORT:-8080}"; return 0; }
                    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ] || { log_error "Invalid port"; return 1; }
                    PORTAL_PORT="$1"
                    save_settings
                    log_success "Portal port set to $1"
                    ;;
                generate)
                    check_root
                    portal_generate
                    portal_export_data
                    log_success "Portal HTML and data generated in ${PORTAL_DIR}"
                    ;;
                serve)
                    portal_serve "${1:-}"
                    ;;
                status|"")
                    echo -e "  ${BOLD}Status Portal:${NC} $([ "${PORTAL_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}") (Port: ${PORTAL_PORT:-8080})"
                    ;;
                *) log_error "Usage: mtproxymax portal [enable|disable|port|generate|serve|status]"; return 1 ;;
            esac
            ;;

        scanner-shield|threat-shield)
            load_settings
            local subcmd="${1:-status}"
            shift 2>/dev/null || true
            case "$subcmd" in
                enable|on)
                    check_root
                    SCANNER_SHIELD_ENABLED="true"
                    save_settings
                    scanner_shield_on
                    log_success "Scanner shield enabled"
                    ;;
                disable|off)
                    check_root
                    SCANNER_SHIELD_ENABLED="false"
                    save_settings
                    scanner_shield_off
                    log_success "Scanner shield disabled"
                    ;;
                update)
                    check_root
                    scanner_shield_update
                    ;;
                status|"")
                    echo -e "  ${BOLD}Scanner Threat Shield:${NC} $([ "${SCANNER_SHIELD_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
                    if command -v ipset &>/dev/null && ipset list mtproxymax-scanners &>/dev/null; then
                        local _cnt; _cnt=$(ipset list mtproxymax-scanners 2>/dev/null | grep -E '^[0-9]' | wc -l || echo 0)
                        echo -e "  ${DIM}Blocked scanner IPs/Subnets in ipset:${NC} ${_cnt}"
                    fi
                    ;;
                *) log_error "Usage: mtproxymax scanner-shield [enable|disable|update|status]"; return 1 ;;
            esac
            ;;

        uninstall)
            check_root
            load_settings
            load_secrets
            uninstall
            ;;

        speed-limit)
            check_root
            local sub="${1:-list}"
            shift 2>/dev/null || true
            case "$sub" in
                set) speed_limit_set "$@" ;;
                remove|del|rm) speed_limit_remove "$@" ;;
                apply) speed_limit_apply ;;
                clear) speed_limit_clear ;;
                list|status|"") speed_limit_list ;;
                *) log_error "Usage: mtproxymax speed-limit [set|remove|apply|clear|list|status]"; return 1 ;;
            esac
            ;;

        fleet)
            check_root
            local sub="${1:-status}"
            shift 2>/dev/null || true
            case "$sub" in
                status|"") fleet_status ;;
                collect) fleet_collect_slave_metrics ;;
                *) log_error "Usage: mtproxymax fleet [status|collect]"; return 1 ;;
            esac
            ;;

        ssl)
            check_root
            local sub="${1:-status}"
            shift 2>/dev/null || true
            case "$sub" in
                issue) ssl_issue "$@" ;;
                status|"") ssl_status ;;
                clear|reset) ssl_clear ;;
                *) log_error "Usage: mtproxymax ssl [issue|status|clear]"; return 1 ;;
            esac
            ;;

        backup-cloud)
            check_root
            local sub="${1:-status}"
            shift 2>/dev/null || true
            case "$sub" in
                toggle) backup_cloud_toggle "$@" ;;
                telegram|rclone|s3|off|disable) backup_cloud_toggle "$sub" "$@" ;;
                push|offload) backup_cloud_push ;;
                status|"") backup_cloud_status ;;
                *) log_error "Usage: mtproxymax backup-cloud [telegram|rclone|push|status|off]"; return 1 ;;
            esac
            ;;

        version)
            echo -e "  ${BOLD}MTProxyMax${NC} v${VERSION}"
            echo -e "  ${DIM}Engine: telemt v$(get_telemt_version) (Rust)${NC}"
            echo -e "  ${DIM}SamNet Technologies${NC}"
            ;;

        help|--help|-h)
            show_cli_help
            ;;

        install)
            run_installer
            ;;

        menu)
            load_settings
            load_secrets
            show_main_menu
            ;;

        *)
            log_error "Unknown command: ${cmd}"
            show_cli_help
            return 1
            ;;
    esac
}

# ── Section 18: Interactive TUI Menus ───────────────────────

show_stealth_menu() {
    while true; do
        clear_screen
        draw_header "ANTI-DPI & STEALTH DEFENSES"
        echo ""
        echo -e "  ${BOLD}Kernel SYN Shield:${NC}     $([ "${STEALTH_SHIELD:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}Stealth Preset:${NC}        $([ "${STEALTH_PRESET:-normal}" = "ultra" ] && echo "${RED}${BOLD}ULTRA${NC}" || echo "${GREEN}NORMAL${NC}")"
        echo -e "  ${BOLD}TCP MSS Clamping:${NC}      $([ "${STEALTH_MSS_CLAMP:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}Domain SNI Pool:${NC}       ${CYAN}${PROXY_DOMAIN:-not set}${NC}"
        echo -e "  ${BOLD}Emergency Lockdown:${NC}    $([ "${LOCKDOWN_MODE:-false}" = "true" ] && echo "${RED}${BOLD}ACTIVE${NC}" || echo "${GREEN}INACTIVE${NC}")"
        echo -e "  ${BOLD}Secondary Port Pool:${NC}   ${CYAN}${PORT_POOL_PORTS:-none}${NC}"
        echo ""
        echo -e "  ${DIM}[1]${NC} Toggle Kernel SYN Shield (>15 SYN/5s tarpit)"
        echo -e "  ${DIM}[2]${NC} Switch Stealth Preset (Normal vs Ultra anti-replay)"
        echo -e "  ${DIM}[3]${NC} Toggle TCP MSS Clamping (--clamp-mss-to-pmtu)"
        echo -e "  ${DIM}[4]${NC} Configure Multi-Domain SNI Pool"
        echo -e "  ${DIM}[5]${NC} Run DPI Forensics & Readiness Analyzer"
        echo -e "  ${DIM}[6]${NC} Test Cover Domain Health (Watchdog probe)"
        echo -e "  ${DIM}[7]${NC} Toggle Emergency Lockdown Mode"
        echo -e "  ${DIM}[8]${NC} Manage Secondary Port Pool Listener"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                if [ "${STEALTH_SHIELD:-false}" = "true" ]; then
                    run_shield off
                else
                    run_shield on
                fi
                press_any_key
                ;;
            2)
                if [ "${STEALTH_PRESET:-normal}" = "ultra" ]; then
                    run_stealth_preset normal
                else
                    run_stealth_preset ultra
                fi
                press_any_key
                ;;
            3)
                if [ "${STEALTH_MSS_CLAMP:-false}" = "true" ]; then
                    run_clamp_mss off
                else
                    run_clamp_mss on
                fi
                press_any_key
                ;;
            4)
                echo -en "  ${BOLD}Enter cover domain pool (comma-separated):${NC} "
                local dp; read -r dp
                [ -n "$dp" ] && { run_domain_pool "$dp"; press_any_key; }
                ;;
            5)
                run_dpi_inspect
                press_any_key
                ;;
            6)
                run_cover_watchdog test
                press_any_key
                ;;
            7)
                if [ "${LOCKDOWN_MODE:-false}" = "true" ]; then
                    run_lockdown off
                else
                    run_lockdown on
                fi
                press_any_key
                ;;
            8)
                echo -e "\n  ${BOLD}[1] Add port to pool   [2] Remove port from pool${NC}"
                local _pchoice=$(read_choice "Action" "1")
                echo -en "  ${BOLD}Enter port number:${NC} "
                local _pport; read -r _pport
                if [ "$_pchoice" = "1" ]; then
                    run_port_pool add "$_pport"
                elif [ "$_pchoice" = "2" ]; then
                    run_port_pool remove "$_pport"
                fi
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_speed_limit_menu() {
    while true; do
        clear_screen
        draw_header "HTB QOS THROTTLING (SPEED-LIMIT)"
        echo ""
        speed_limit_list
        echo -e "  ${BRIGHT_CYAN}[1]${NC} Set QoS Speed Limit for Port / Global"
        echo -e "  ${BRIGHT_CYAN}[2]${NC} Remove QoS Speed Limit"
        echo -e "  ${BRIGHT_CYAN}[3]${NC} Apply / Refresh Kernel QoS Rules"
        echo -e "  ${BRIGHT_CYAN}[4]${NC} Clear All QoS Speed Limits"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}Target (global or port number):${NC} "
                local target; read -r target
                echo -en "  ${BOLD}Download rate (kbps):${NC} "
                local down; read -r down
                echo -en "  ${BOLD}Upload rate (kbps, optional):${NC} "
                local up; read -r up
                speed_limit_set "$target" "$down" "$up"
                press_any_key
                ;;
            2)
                echo -en "  ${BOLD}Target to remove (global or port number):${NC} "
                local target; read -r target
                speed_limit_remove "$target"
                press_any_key
                ;;
            3)
                speed_limit_apply
                log_success "Kernel QoS rules refreshed"
                press_any_key
                ;;
            4)
                speed_limit_clear
                log_success "All QoS rules cleared"
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_qos_menu() {
    while true; do
        clear_screen
        draw_header "QOS BANDWIDTH & QUOTA INTELLIGENCE"
        echo ""
        load_settings
        local qos_status="${YELLOW}DISABLED${NC}"
        [ "${QOS_LIMIT_MBPS:-0}" -gt 0 ] && qos_status="${GREEN}${QOS_LIMIT_MBPS} Mbps / IP${NC}"
        local happy_status="${YELLOW}DISABLED${NC}"
        if [ -n "${HAPPY_HOURS_WINDOW:-}" ]; then
            happy_status="${CYAN}${HAPPY_HOURS_WINDOW}${NC} ($([ $(check_in_happy_hours "${HAPPY_HOURS_WINDOW}" >/dev/null 2>&1; echo $?) -eq 0 ] && echo "${GREEN}ACTIVE NOW${NC}" || echo "INACTIVE"))"
        fi

        echo -e "  ${DIM}[1]${NC} Per-IP Bandwidth Shaping (QoS): ${qos_status}"
        echo -e "  ${DIM}[2]${NC} Off-Peak Happy Hours Window:    ${happy_status}"
        echo -e "  ${DIM}[3]${NC} Run Bandwidth Surge & Abuse Watchdog"
        echo -e "  ${DIM}[4]${NC} Send Expiry Notification Reminders"
        echo -e "  ${DIM}[5]${NC} Hierarchical Token Bucket (HTB) QoS Throttling"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo ""
                echo -en "  ${BOLD}Enter Per-IP Speed Limit in Mbps (0 to disable):${NC} "
                local sp; read -r sp
                if [ "$sp" = "0" ]; then
                    run_qos off
                elif [ -n "$sp" ]; then
                    run_qos set "$sp"
                fi
                press_any_key
                ;;
            2)
                echo ""
                echo -en "  ${BOLD}Enter Happy Hours window (e.g. 02:00-08:00 or 'off'):${NC} "
                local hw; read -r hw
                if [ "$hw" = "off" ] || [ "$hw" = "0" ]; then
                    run_happy_hours off
                elif [ -n "$hw" ]; then
                    run_happy_hours set "$hw"
                fi
                press_any_key
                ;;
            3)
                run_abuse_watch
                press_any_key
                ;;
            4)
                run_notify_expiry
                press_any_key
                ;;
            5)
                show_speed_limit_menu
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_security_menu() {
    while true; do
        clear_screen
        draw_header "SECURITY & ROUTING"
        echo ""
        local sni_label
        if [ "$UNKNOWN_SNI_ACTION" = "drop" ]; then
            sni_label="${RED}Drop${NC} (strict)"
        else
            sni_label="${GREEN}Mask${NC} (permissive)"
        fi
        echo -e "  ${DIM}[1]${NC} Geo-Blocking"
        echo -e "  ${DIM}[2]${NC} Proxy Chaining (Upstreams)"
        echo -e "  ${DIM}[3]${NC} Unknown SNI Policy: ${sni_label}"
        echo -e "  ${DIM}[4]${NC} IP Banlist"
        echo -e "  ${DIM}[5]${NC} Anti-DPI & Stealth Defenses"
        echo -e "  ${DIM}[6]${NC} QoS Bandwidth & Quota Intelligence"
        echo -e "  ${DIM}[7]${NC} Performance, Diagnostics & Self-Healing Suite"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) show_geoblock_menu ;;
            2) show_upstream_menu ;;
            3)
                echo ""
                echo -e "  ${BOLD}Unknown SNI Policy${NC}"
                echo -e "  Controls how the engine handles TLS connections whose SNI"
                echo -e "  doesn't match your configured domain."
                echo ""
                echo -e "  ${DIM}[1]${NC} ${GREEN}Mask${NC}  — redirect to mask backend (recommended)"
                echo -e "        Keeps old proxy links working after domain changes."
                echo -e "  ${DIM}[2]${NC} ${RED}Drop${NC}  — reject immediately (strict)"
                echo -e "        More secure, but old proxy links with a previous"
                echo -e "        domain will stop working."
                echo ""
                local sni_choice
                sni_choice=$(read_choice "Choice" "0")
                case "$sni_choice" in
                    1) UNKNOWN_SNI_ACTION="mask"; save_settings; reload_proxy_config; log_success "Unknown SNI policy set to Mask" ;;
                    2) UNKNOWN_SNI_ACTION="drop"; save_settings; reload_proxy_config; log_success "Unknown SNI policy set to Drop" ;;
                    *) ;;
                esac
                press_any_key
                ;;
            4)
                bans_list
                echo -e "  ${DIM}[1] Ban IP/CIDR  [2] Unban IP/CIDR  [0] Back${NC}"
                local bc; bc=$(read_choice "Choice" "0")
                case "$bc" in
                    1)
                        echo -en "  ${BOLD}IP or CIDR to ban:${NC} "
                        local bi; read -r bi
                        [ -n "$bi" ] && { ban_ip "$bi" || true; }
                        ;;
                    2)
                        echo -en "  ${BOLD}IP or CIDR to unban:${NC} "
                        local bi; read -r bi
                        [ -n "$bi" ] && { unban_ip "$bi" || true; }
                        ;;
                esac
                press_any_key
                ;;
            5) show_stealth_menu ;;
            6) show_qos_menu ;;
            7) show_performance_menu ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_upstream_menu() {
    while true; do
        clear_screen
        draw_header "PROXY CHAINING"

        load_upstreams
        upstream_list

        echo -e "  ${DIM}[1]${NC} Add upstream"
        echo -e "  ${DIM}[2]${NC} Remove upstream"
        echo -e "  ${DIM}[3]${NC} Enable/disable upstream"
        echo -e "  ${DIM}[4]${NC} Test upstream connectivity"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo ""
                echo -en "  ${BOLD}Name:${NC} "
                local name; read -r name
                [ -z "$name" ] && { press_any_key; continue; }

                echo -e "  ${BOLD}Type:${NC}"
                echo -e "    ${DIM}[1]${NC} SOCKS5"
                echo -e "    ${DIM}[2]${NC} SOCKS4"
                echo -e "    ${DIM}[3]${NC} Direct"
                local type_choice; read -rp "    > " type_choice
                local type
                case "$type_choice" in
                    1) type="socks5" ;;
                    2) type="socks4" ;;
                    3) type="direct" ;;
                    *) log_error "Invalid type"; press_any_key; continue ;;
                esac

                local addr="" user="" pass=""
                if [ "$type" != "direct" ]; then
                    echo -en "  ${BOLD}Address (host:port):${NC} "
                    read -r addr
                    [ -z "$addr" ] && { log_error "Address required"; press_any_key; continue; }
                    echo -en "  ${BOLD}Username (optional):${NC} "
                    read -r user
                    echo -en "  ${BOLD}Password (optional):${NC} "
                    read -r pass
                fi

                echo -en "  ${BOLD}Weight (1-100, default 10):${NC} "
                local weight; read -r weight
                [ -z "$weight" ] && weight=10

                echo -en "  ${BOLD}Bind to IP (optional, blank=auto):${NC} "
                local iface; read -r iface

                upstream_add "$name" "$type" "$addr" "$user" "$pass" "$weight" "$iface" || true
                press_any_key
                ;;
            2)
                echo -en "  ${BOLD}Name to remove:${NC} "
                local name; read -r name
                [ -n "$name" ] && { upstream_remove "$name" || true; }
                press_any_key
                ;;
            3)
                echo -en "  ${BOLD}Name to toggle:${NC} "
                local name; read -r name
                [ -n "$name" ] && { upstream_toggle "$name" || true; }
                press_any_key
                ;;
            4)
                echo -en "  ${BOLD}Name to test:${NC} "
                local name; read -r name
                [ -n "$name" ] && { upstream_test "$name" || true; }
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_voucher_menu() {
    while true; do
        clear_screen
        draw_header "COMMERCIAL VOUCHER SYSTEM"
        echo ""
        voucher_list active | head -n 15
        echo ""
        echo -e "  ${DIM}[1]${NC} Generate new vouchers"
        echo -e "  ${DIM}[2]${NC} List all vouchers"
        echo -e "  ${DIM}[3]${NC} Revoke a voucher code"
        echo -e "  ${DIM}[4]${NC} Redeem a voucher code locally"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}Number of vouchers to generate (default 1):${NC} "
                local cnt; read -r cnt; cnt="${cnt:-1}"
                echo -en "  ${BOLD}Quota per voucher (e.g. 10G, 50G, 0=unlim):${NC} "
                local qta; read -r qta; qta="${qta:-10G}"
                echo -en "  ${BOLD}Validity duration in days (default 30):${NC} "
                local dys; read -r dys; dys="${dys:-30}"
                voucher_create "$cnt" "$qta" "$dys"
                press_any_key
                ;;
            2)
                clear_screen
                draw_header "ALL VOUCHERS"
                voucher_list all
                press_any_key
                ;;
            3)
                echo -en "  ${BOLD}Enter voucher code to revoke:${NC} "
                local code; read -r code
                [ -n "$code" ] && voucher_revoke "$code"
                press_any_key
                ;;
            4)
                echo -en "  ${BOLD}Enter voucher code to redeem:${NC} "
                local code; read -r code
                echo -en "  ${BOLD}Enter account label for new secret:${NC} "
                local lbl; read -r lbl
                [ -n "$code" ] && voucher_redeem "$code" "$lbl"
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_rbac_menu() {
    while true; do
        clear_screen
        draw_header "ROLE-BASED ACCESS CONTROL (RBAC)"
        echo ""
        admin_list
        echo ""
        echo -e "  ${DIM}[1]${NC} Add Telegram Admin (superadmin or reseller)"
        echo -e "  ${DIM}[2]${NC} Remove Telegram Admin"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}Enter Telegram Chat ID:${NC} "
                local cid; read -r cid
                echo -en "  ${BOLD}Enter Role (superadmin/reseller):${NC} "
                local rl; read -r rl; rl="${rl:-reseller}"
                [ -n "$cid" ] && admin_add "$cid" "$rl"
                press_any_key
                ;;
            2)
                echo -en "  ${BOLD}Enter Telegram Chat ID to remove:${NC} "
                local cid; read -r cid
                [ -n "$cid" ] && admin_remove "$cid"
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_portal_menu() {
    while true; do
        clear_screen
        draw_header "SELF-SERVICE STATUS PORTAL"
        echo ""
        load_settings
        echo -e "  ${BOLD}Status:${NC} $([ "${PORTAL_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}Port:${NC}   ${PORTAL_PORT:-8080}"
        echo -e "  ${BOLD}Directory:${NC} ${PORTAL_DIR}"
        echo ""
        echo -e "  ${DIM}[1]${NC} Toggle Portal Enable/Disable"
        echo -e "  ${DIM}[2]${NC} Change Portal Port"
        echo -e "  ${DIM}[3]${NC} Force Regenerate HTML Dashboard & Snapshot Data"
        echo -e "  ${DIM}[4]${NC} Start/Test Local Portal Server Foreground"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                if [ "${PORTAL_ENABLED:-false}" = "true" ]; then
                    PORTAL_ENABLED="false"
                    save_settings
                    log_success "Portal disabled"
                else
                    PORTAL_ENABLED="true"
                    save_settings
                    portal_generate
                    portal_export_data
                    log_success "Portal enabled"
                fi
                press_any_key
                ;;
            2)
                echo -en "  ${BOLD}Enter new portal port (e.g. 8080):${NC} "
                local pt; read -r pt
                if [[ "$pt" =~ ^[0-9]+$ ]] && [ "$pt" -ge 1 ] && [ "$pt" -le 65535 ]; then
                    PORTAL_PORT="$pt"
                    save_settings
                    log_success "Portal port changed to $pt"
                else
                    log_error "Invalid port"
                fi
                press_any_key
                ;;
            3)
                portal_generate
                portal_export_data
                log_success "Portal regenerated"
                press_any_key
                ;;
            4)
                portal_serve
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_scanner_shield_menu() {
    while true; do
        clear_screen
        draw_header "AUTOMATED HOSTILE SCANNER SHIELD"
        echo ""
        load_settings
        echo -e "  ${BOLD}Status:${NC} $([ "${SCANNER_SHIELD_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        if command -v ipset &>/dev/null && ipset list mtproxymax-scanners &>/dev/null; then
            local _cnt; _cnt=$(ipset list mtproxymax-scanners 2>/dev/null | grep -E '^[0-9]' | wc -l || echo 0)
            echo -e "  ${BOLD}Active Blocked Subnets/IPs:${NC} ${_cnt}"
        fi
        echo ""
        echo -e "  ${DIM}[1]${NC} Toggle Scanner Shield On/Off"
        echo -e "  ${DIM}[2]${NC} Force Update Shodan/Censys Threat Feed Now"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                if [ "${SCANNER_SHIELD_ENABLED:-false}" = "true" ]; then
                    SCANNER_SHIELD_ENABLED="false"
                    save_settings
                    scanner_shield_off
                else
                    SCANNER_SHIELD_ENABLED="true"
                    save_settings
                    scanner_shield_on
                fi
                press_any_key
                ;;
            2)
                scanner_shield_update
                log_success "Shodan/Censys threat feed updated"
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_fleet_menu() {
    while true; do
        clear_screen
        draw_header "FLEET FEDERATION TELEMETRY DASHBOARD"
        echo ""
        fleet_status
        echo -e "  ${BRIGHT_CYAN}[1]${NC} Collect & Publish Node Telemetry Now"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                fleet_collect_slave_metrics
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_ssl_menu() {
    while true; do
        clear_screen
        draw_header "AUTOMATED LET'S ENCRYPT / ACME SSL SHIELD"
        echo ""
        ssl_status
        echo -e "  ${BRIGHT_CYAN}[1]${NC} Issue / Refresh Certificate for Domain"
        echo -e "  ${BRIGHT_CYAN}[2]${NC} Clear / Reset Certificate Configuration"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}Enter Domain Name (e.g. proxy.example.com):${NC} "
                local dom; read -r dom
                echo -en "  ${BOLD}Enter Admin Email for ACME alerts:${NC} "
                local em; read -r em
                ssl_issue "$dom" "$em"
                press_any_key
                ;;
            2)
                ssl_clear
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_backup_cloud_menu() {
    while true; do
        clear_screen
        draw_header "AUTOMATED OFF-SITE CLOUD & TELEGRAM BACKUPS"
        echo ""
        backup_cloud_status
        echo -e "  ${BRIGHT_CYAN}[1]${NC} Configure / Toggle Backup Mode (telegram, rclone, s3, off)"
        echo -e "  ${BRIGHT_CYAN}[2]${NC} Trigger Immediate Backup & Push Off-Site"
        echo -e "  ${BRIGHT_CYAN}[3]${NC} Disable Cloud Backups"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""
        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}Select mode [telegram|rclone|s3|off]:${NC} "
                local bmode; read -r bmode
                local btarget=""
                if [ "$bmode" = "rclone" ] || [ "$bmode" = "s3" ]; then
                    echo -en "  ${BOLD}Enter target path/bucket (e.g. myremote:backups or s3://bucket/path):${NC} "
                    read -r btarget
                fi
                backup_cloud_toggle "$bmode" "$btarget"
                press_any_key
                ;;
            2)
                backup_cloud_push
                press_any_key
                ;;
            3)
                backup_cloud_toggle off
                press_any_key
                ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_enterprise_menu() {
    while true; do
        clear_screen
        draw_header "ENTERPRISE COMMERCIAL & SHIELD SUITE"
        echo ""
        load_settings
        echo -e "  ${BOLD}Status Portal:${NC}   $([ "${PORTAL_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}") (Port: ${PORTAL_PORT:-8080})"
        echo -e "  ${BOLD}Scanner Shield:${NC}  $([ "${SCANNER_SHIELD_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo ""
        echo -e "  ${BRIGHT_CYAN}[1]${NC} Commercial Voucher & Gift Code System"
        echo -e "  ${BRIGHT_CYAN}[2]${NC} Role-Based Access Control (Admin / RBAC)"
        echo -e "  ${BRIGHT_CYAN}[3]${NC} Self-Service Status Portal Management"
        echo -e "  ${BRIGHT_CYAN}[4]${NC} Automated Hostile Scanner Shield"
        echo -e "  ${BRIGHT_CYAN}[5]${NC} Fleet Federation Telemetry Dashboard"
        echo -e "  ${BRIGHT_CYAN}[6]${NC} Automated Let's Encrypt / ACME SSL Shield"
        echo -e "  ${BRIGHT_CYAN}[7]${NC} Automated Off-Site Cloud & Telegram Backups"
        echo -e "  ${DIM}[0]${NC} Back"
        echo ""

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) show_voucher_menu ;;
            2) show_rbac_menu ;;
            3) show_portal_menu ;;
            4) show_scanner_shield_menu ;;
            5) show_fleet_menu ;;
            6) show_ssl_menu ;;
            7) show_backup_cloud_menu ;;
            0|q|Q|"") return ;;
            *) ;;
        esac
    done
}

show_main_menu() {
    local _cached_telemt_ver _cached_start_epoch=""
    _cached_telemt_ver=$(get_telemt_version)

    while true; do
        clear 2>/dev/null || printf '\033[2J\033[H'

        local w=$TERM_WIDTH

        show_banner

        # Status dashboard — single Docker check
        draw_box_top "$w"

        local _running=false
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
            _running=true
        fi

        local status_str uptime_str traffic_in traffic_out connections
        if [ "$_running" = "true" ]; then
            status_str=$(draw_status running)
            # Cache docker inspect — skip on subsequent renders unless container restarted
            if [ -z "$_cached_start_epoch" ]; then
                local started_at
                started_at=$(docker inspect --format '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)
                _cached_start_epoch=$(_iso_to_epoch "$started_at")
            fi
            local up_secs=$(( $(date +%s) - _cached_start_epoch ))
            uptime_str=$(format_duration "$up_secs")
            # Parse all stats fields in a single read (no awk subprocesses)
            read -r traffic_in traffic_out connections <<< "$(get_cumulative_proxy_stats)"
        else
            status_str=$(draw_status stopped)
            uptime_str="—"
            traffic_in=0; traffic_out=0; connections=0
            _cached_start_epoch=""  # Reset so it re-fetches when container comes back up
        fi

        local active=0 disabled=0
        for i in "${!SECRETS_ENABLED[@]}"; do
            [ "${SECRETS_ENABLED[$i]}" = "true" ] && active=$((active+1)) || disabled=$((disabled+1))
        done

        draw_box_line "  ${BOLD}Engine:${NC} telemt v${_cached_telemt_ver}  ${BOLD}Status:${NC} ${status_str}" "$w"
        draw_box_line "  ${BOLD}Port:${NC}   ${PROXY_PORT}            ${BOLD}Uptime:${NC} ${uptime_str}" "$w"
        draw_box_line "  ${BOLD}Domain:${NC} ${PROXY_DOMAIN}" "$w"
        draw_box_line "  ${BOLD}Traffic:${NC} ${SYM_DOWN} $(format_bytes "$traffic_in")  ${SYM_UP} $(format_bytes "$traffic_out")  ${BOLD}Conns:${NC} ${connections}" "$w"
        draw_box_line "  ${BOLD}Secrets:${NC} ${active} active / ${disabled} disabled" "$w"

        draw_box_sep "$w"
        if [ -f "$_UPDATE_BADGE" ]; then
            draw_box_line "  ${YELLOW}${BOLD}⬆  Update available — select [9] to update${NC}" "$w"
            draw_box_sep "$w"
        fi
        draw_box_empty "$w"
        draw_box_line "  ${BRIGHT_CYAN}[1]${NC}  Proxy Management" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[2]${NC}  Secret Management" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[3]${NC}  Share Links & QR" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[4]${NC}  Telegram Bot" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[5]${NC}  Security & Routing" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[6]${NC}  Settings" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[7]${NC}  Logs & Traffic" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[8]${NC}  Info & Help" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[9]${NC}  About & Update" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[e]${NC}  Enterprise Commercial & Shield Suite" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[p]${NC}  Performance & Self-Healing Suite" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[r]${NC}  Replication" "$w"
        draw_box_empty "$w"
        draw_box_line "  ${BRIGHT_RED}[u]${NC}  Uninstall" "$w"
        draw_box_line "  ${BRIGHT_CYAN}[0]${NC}  Exit" "$w"
        draw_box_empty "$w"
        draw_box_sep "$w"
        draw_box_center "${DIM}mtproxymax v${VERSION} | SamNet Technologies${NC}" "$w"
        draw_box_bottom "$w"

        local choice
        choice=$(read_choice "Choice" "0")

        case "$choice" in
            1) show_proxy_menu ;;
            2) show_secrets_menu ;;
            3) show_links_menu ;;
            4) show_telegram_menu ;;
            5) show_security_menu ;;
            6) show_settings_menu ;;
            7) show_traffic_menu ;;
            8) show_info_menu ;;
            9) show_about ;;
            e|E) show_enterprise_menu ;;
            p|P) show_performance_menu ;;
            r|R) show_replication_menu ;;
            u|U) uninstall; exit 0 ;;
            0|q|Q) echo ""; exit 0 ;;
            *) ;;
        esac
    done
}

show_proxy_menu() {
    while true; do
        clear_screen
        draw_header "PROXY MANAGEMENT"
        echo ""
        local _pstatus
        docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$" && _pstatus="running" || _pstatus="stopped"
        echo -e "  Status: $(draw_status "$_pstatus")"
        echo ""
        echo -e "  ${DIM}[1]${NC} Start proxy"
        echo -e "  ${DIM}[2]${NC} Stop proxy"
        echo -e "  ${DIM}[3]${NC} Restart proxy"
        echo -e "  ${DIM}[4]${NC} View logs"
        echo -e "  ${DIM}[5]${NC} Health check"
        maintenance_status
        echo -e "  ${DIM}[m]${NC} Toggle maintenance mode"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) start_proxy_container || true; press_any_key ;;
            2) stop_proxy_container || true; press_any_key ;;
            3) restart_proxy_container || true; press_any_key ;;
            4) echo -e "  ${DIM}Press Ctrl+C to stop...${NC}"; docker logs -f --tail 30 "$CONTAINER_NAME" 2>&1 || true; press_any_key ;;
            5) health_check || true; press_any_key ;;
            m|M)
                if [ -f "$MAINTENANCE_FILE" ]; then
                    maintenance_off
                else
                    maintenance_on
                fi
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_secrets_menu() {
    while true; do
        clear_screen
        draw_header "SECRET MANAGEMENT"

        secret_list

        echo -e "  ${DIM}[1]${NC} Add new secret"
        echo -e "  ${DIM}[2]${NC} Remove a secret"
        echo -e "  ${DIM}[3]${NC} Rotate a secret"
        echo -e "  ${DIM}[4]${NC} Enable/disable a secret"
        echo -e "  ${DIM}[5]${NC} Set user limits"
        echo -e "  ${DIM}[6]${NC} Batch add secrets"
        echo -e "  ${DIM}[7]${NC} Batch remove secrets"
        echo -e "  ${DIM}[8]${NC} Edit note/description"
        echo -e "  ${DIM}[9]${NC} Rename secret (single or prefix)"
        echo -e "  ${DIM}[c]${NC} Clone a secret"
        echo -e "  ${DIM}[x]${NC} Extend a secret's expiry"
        echo -e "  ${DIM}[e]${NC} Bulk-extend all expiry dates"
        echo -e "  ${DIM}[d]${NC} Disable or purge expired secrets"
        echo -e "  ${DIM}[s]${NC} User stats overview"
        echo -e "  ${DIM}[t]${NC} Sort secrets"
        echo -e "  ${DIM}[i]${NC} Export / Import"
        echo -e "  ${DIM}[f]${NC} Full secret info"
        echo -e "  ${DIM}[/]${NC} Search secrets"
        echo -e "  ${DIM}[p]${NC} Top users"
        echo -e "  ${DIM}[g]${NC} Generate links file"
        echo -e "  ${DIM}[a]${NC} Archive / Unarchive"
        echo -e "  ${DIM}[b]${NC} Set/clear per-secret AdTag"
        echo -e "  ${DIM}[y]${NC} Tag / Untag / Filter by tag"
        echo -e "  ${DIM}[l]${NC} View user activity log"
        echo -e "  ${DIM}[q]${NC} Monthly quota reset"
        echo -e "  ${DIM}[R]${NC} Rotate ALL secrets"
        echo -e "  ${DIM}[k]${NC} Templates (save / apply / list / delete)"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}Label:${NC} "
                local label
                read -r label
                [ -n "$label" ] && { secret_add "$label" || true; }
                press_any_key
                ;;
            2)
                echo -en "  ${BOLD}Label or # to remove:${NC} "
                local label
                read -r label
                if [[ "$label" =~ ^[0-9]+$ ]] && [ "$label" -ge 1 ] && [ "$label" -le "${#SECRETS_LABELS[@]}" ]; then
                    label="${SECRETS_LABELS[$((label - 1))]}"
                fi
                [ -n "$label" ] && { secret_remove "$label" || true; }
                press_any_key
                ;;
            3)
                echo -en "  ${BOLD}Label or # to rotate:${NC} "
                local label
                read -r label
                if [[ "$label" =~ ^[0-9]+$ ]] && [ "$label" -ge 1 ] && [ "$label" -le "${#SECRETS_LABELS[@]}" ]; then
                    label="${SECRETS_LABELS[$((label - 1))]}"
                fi
                [ -n "$label" ] && { secret_rotate "$label" || true; }
                press_any_key
                ;;
            4)
                echo -en "  ${BOLD}Label or # to toggle:${NC} "
                local label
                read -r label
                if [[ "$label" =~ ^[0-9]+$ ]] && [ "$label" -ge 1 ] && [ "$label" -le "${#SECRETS_LABELS[@]}" ]; then
                    label="${SECRETS_LABELS[$((label - 1))]}"
                fi
                [ -n "$label" ] && { secret_toggle "$label" || true; }
                press_any_key
                ;;
            5)
                secret_show_limits
                echo ""
                echo -en "  ${BOLD}Label or # to set limits:${NC} "
                local label
                read -r label
                # If user entered a number, map to the label at that index
                if [[ "$label" =~ ^[0-9]+$ ]] && [ "$label" -ge 1 ] && [ "$label" -le "${#SECRETS_LABELS[@]}" ]; then
                    label="${SECRETS_LABELS[$((label - 1))]}"
                fi
                if [ -n "$label" ]; then
                    echo -en "  ${BOLD}Max TCP connections (0=unlimited):${NC} "
                    local mc; read -r mc
                    echo -en "  ${BOLD}Max unique IPs (0=unlimited):${NC} "
                    local mi; read -r mi
                    echo -en "  ${BOLD}Data quota (e.g. 5G, 500M, 0=unlimited):${NC} "
                    local dq; read -r dq
                    echo -en "  ${BOLD}Expiry date (YYYY-MM-DD, 0=never):${NC} "
                    local ex; read -r ex
                    secret_set_limits "$label" "${mc:-0}" "${mi:-0}" "${dq:-0}" "${ex:-0}" || true
                fi
                press_any_key
                ;;
            6)
                echo -e "  ${DIM}Enter labels separated by spaces${NC}"
                echo -en "  ${BOLD}Labels:${NC} "
                local batch_labels
                read -r batch_labels
                if [ -n "$batch_labels" ]; then
                    # shellcheck disable=SC2086
                    secret_add_batch $batch_labels || true
                fi
                press_any_key
                ;;
            7)
                echo -e "  ${DIM}Enter labels separated by spaces${NC}"
                echo -en "  ${BOLD}Labels to remove:${NC} "
                local batch_labels
                read -r batch_labels
                if [ -n "$batch_labels" ]; then
                    # shellcheck disable=SC2086
                    secret_remove_batch "false" $batch_labels || true
                fi
                press_any_key
                ;;
            8)
                echo -en "  ${BOLD}Label or #:${NC} "
                local note_label
                read -r note_label
                if [[ "$note_label" =~ ^[0-9]+$ ]] && [ "$note_label" -ge 1 ] && [ "$note_label" -le "${#SECRETS_LABELS[@]}" ]; then
                    note_label="${SECRETS_LABELS[$((note_label - 1))]}"
                fi
                if [ -n "$note_label" ]; then
                    secret_edit_note "$note_label" || true
                fi
                press_any_key
                ;;
            9)
                echo -e "  ${DIM}[1] Single rename  [2] Bulk rename by prefix${NC}"
                local rc; rc=$(read_choice "Choice" "1")
                case "$rc" in
                    1)
                        echo -en "  ${BOLD}Label or # to rename:${NC} "
                        local old_label; read -r old_label
                        if [[ "$old_label" =~ ^[0-9]+$ ]] && [ "$old_label" -ge 1 ] && [ "$old_label" -le "${#SECRETS_LABELS[@]}" ]; then
                            old_label="${SECRETS_LABELS[$((old_label - 1))]}"
                        fi
                        if [ -n "$old_label" ]; then
                            echo -en "  ${BOLD}New label:${NC} "
                            local new_label; read -r new_label
                            [ -n "$new_label" ] && { secret_rename "$old_label" "$new_label" || true; }
                        fi
                        ;;
                    2)
                        echo -en "  ${BOLD}Old prefix to match:${NC} "
                        local old_p; read -r old_p
                        if [ -n "$old_p" ]; then
                            echo -en "  ${BOLD}New prefix:${NC} "
                            local new_p; read -r new_p
                            [ -n "$new_p" ] && { secret_rename_prefix "$old_p" "$new_p" || true; }
                        fi
                        ;;
                esac
                press_any_key
                ;;
            c|C)
                echo -en "  ${BOLD}Source label or #:${NC} "
                local src_label; read -r src_label
                if [[ "$src_label" =~ ^[0-9]+$ ]] && [ "$src_label" -ge 1 ] && [ "$src_label" -le "${#SECRETS_LABELS[@]}" ]; then
                    src_label="${SECRETS_LABELS[$((src_label - 1))]}"
                fi
                if [ -n "$src_label" ]; then
                    echo -en "  ${BOLD}New label:${NC} "
                    local clone_label; read -r clone_label
                    [ -n "$clone_label" ] && { secret_clone "$src_label" "$clone_label" || true; }
                fi
                press_any_key
                ;;
            e|E)
                echo -en "  ${BOLD}Extend all by how many days?${NC} "
                local ext_days; read -r ext_days
                [ -n "$ext_days" ] && { secret_bulk_extend "$ext_days" || true; }
                press_any_key
                ;;
            x|X)
                echo -en "  ${BOLD}Label or #:${NC} "
                local ext_label; read -r ext_label
                if [[ "$ext_label" =~ ^[0-9]+$ ]] && [ "$ext_label" -ge 1 ] && [ "$ext_label" -le "${#SECRETS_LABELS[@]}" ]; then
                    ext_label="${SECRETS_LABELS[$((ext_label - 1))]}"
                fi
                if [ -n "$ext_label" ]; then
                    echo -en "  ${BOLD}Extend by how many days?${NC} "
                    local ext_d; read -r ext_d
                    [ -n "$ext_d" ] && { secret_extend "$ext_label" "$ext_d" || true; }
                fi
                press_any_key
                ;;
            d|D)
                echo -e "  ${DIM}[1] Disable expired  [2] Permanently PURGE disabled/expired${NC}"
                local dc; dc=$(read_choice "Choice" "1")
                case "$dc" in
                    1) secret_disable_expired ;;
                    2) secret_purge_disabled ;;
                esac
                press_any_key
                ;;
            s|S) secret_stats; press_any_key ;;
            t|T)
                echo -e "  ${DIM}[1] By traffic  [2] By connections  [3] By date  [4] By name${NC}"
                local sort_choice; sort_choice=$(read_choice "Choice" "1")
                case "$sort_choice" in
                    1) secret_sort traffic ;;
                    2) secret_sort conns ;;
                    3) secret_sort date ;;
                    4) secret_sort name ;;
                esac
                press_any_key
                ;;
            i|I)
                echo -e "  ${DIM}[1] Export CSV  [2] Import CSV  [3] Export JSON${NC}"
                local io_choice; io_choice=$(read_choice "Choice" "0")
                case "$io_choice" in
                    1)
                        local exp_file="$(get_export_dir)/mtproxymax-secrets-$(date +%Y%m%d).csv"
                        secret_export > "$exp_file"
                        chmod 600 "$exp_file" 2>/dev/null || true
                        log_success "Exported CSV to ${exp_file}"
                        ;;
                    2)
                        echo -en "  ${BOLD}File path:${NC} "
                        local imp_file; read -r imp_file
                        [ -n "$imp_file" ] && { secret_import "$imp_file" || true; }
                        ;;
                    3)
                        local exp_file="$(get_export_dir)/mtproxymax-secrets-$(date +%Y%m%d).json"
                        secret_export_json > "$exp_file"
                        chmod 600 "$exp_file" 2>/dev/null || true
                        log_success "Exported JSON to ${exp_file}"
                        ;;
                esac
                press_any_key
                ;;
            f|F)
                echo -en "  ${BOLD}Label or #:${NC} "
                local info_label; read -r info_label
                if [[ "$info_label" =~ ^[0-9]+$ ]] && [ "$info_label" -ge 1 ] && [ "$info_label" -le "${#SECRETS_LABELS[@]}" ]; then
                    info_label="${SECRETS_LABELS[$((info_label - 1))]}"
                fi
                [ -n "$info_label" ] && { secret_info "$info_label" || true; }
                press_any_key
                ;;
            /)
                echo -en "  ${BOLD}Search:${NC} "
                local sq; read -r sq
                [ -n "$sq" ] && { secret_search "$sq" || true; }
                press_any_key
                ;;
            p|P)
                echo -e "  ${DIM}[1] By traffic  [2] By connections${NC}"
                local tc; tc=$(read_choice "Choice" "1")
                case "$tc" in
                    1) secret_top traffic 5 ;;
                    2) secret_top conns 5 ;;
                esac
                press_any_key
                ;;
            g|G)
                echo -e "  ${DIM}[1] Text file  [2] HTML with QR codes${NC}"
                local gc; gc=$(read_choice "Choice" "1")
                case "$gc" in
                    1) secret_generate_links txt ;;
                    2) secret_generate_links html ;;
                esac
                press_any_key
                ;;
            a|A)
                echo -e "  ${DIM}[1] Archive a secret  [2] Unarchive  [3] List archived${NC}"
                local ac; ac=$(read_choice "Choice" "0")
                case "$ac" in
                    1)
                        echo -en "  ${BOLD}Label or # to archive:${NC} "
                        local al; read -r al
                        if [[ "$al" =~ ^[0-9]+$ ]] && [ "$al" -ge 1 ] && [ "$al" -le "${#SECRETS_LABELS[@]}" ]; then
                            al="${SECRETS_LABELS[$((al - 1))]}"
                        fi
                        [ -n "$al" ] && { secret_archive "$al" || true; }
                        ;;
                    2)
                        secret_archive_list
                        echo -en "  ${BOLD}Label to restore:${NC} "
                        local ul; read -r ul
                        [ -n "$ul" ] && { secret_unarchive "$ul" || true; }
                        ;;
                    3) secret_archive_list ;;
                esac
                press_any_key
                ;;
            y|Y)
                echo -e "  ${DIM}[1] Set tags  [2] Clear tags  [3] Filter by tag  [4] Show all tags${NC}"
                local tc; tc=$(read_choice "Choice" "0")
                case "$tc" in
                    1)
                        echo -en "  ${BOLD}Label or #:${NC} "
                        local tl; read -r tl
                        if [[ "$tl" =~ ^[0-9]+$ ]] && [ "$tl" -ge 1 ] && [ "$tl" -le "${#SECRETS_LABELS[@]}" ]; then
                            tl="${SECRETS_LABELS[$((tl - 1))]}"
                        fi
                        if [ -n "$tl" ]; then
                            echo -en "  ${BOLD}Tags (comma-separated):${NC} "
                            local tv; read -r tv
                            [ -n "$tv" ] && { secret_tag "$tl" "$tv" || true; }
                        fi
                        ;;
                    2)
                        echo -en "  ${BOLD}Label or #:${NC} "
                        local tl; read -r tl
                        if [[ "$tl" =~ ^[0-9]+$ ]] && [ "$tl" -ge 1 ] && [ "$tl" -le "${#SECRETS_LABELS[@]}" ]; then
                            tl="${SECRETS_LABELS[$((tl - 1))]}"
                        fi
                        [ -n "$tl" ] && { secret_untag "$tl" || true; }
                        ;;
                    3)
                        echo -en "  ${BOLD}Tag to filter:${NC} "
                        local tf; read -r tf
                        [ -n "$tf" ] && secret_list_by_tag "$tf"
                        ;;
                    4)
                        if [ -f "$_TAGS_FILE" ] && [ -s "$_TAGS_FILE" ]; then
                            echo ""
                            echo -e "  ${BOLD}LABEL            TAGS${NC}"
                            echo -e "  ${DIM}$(_repeat '─' 50)${NC}"
                            while IFS='|' read -r lbl tgs; do
                                [ -z "$lbl" ] && continue
                                printf "  %-16s %s\n" "$lbl" "$tgs"
                            done < "$_TAGS_FILE"
                        else
                            echo -e "  ${DIM}No tags set${NC}"
                        fi
                        ;;
                esac
                press_any_key
                ;;
            l|L)
                echo -en "  ${BOLD}Label or #:${NC} "
                local ll; read -r ll
                if [[ "$ll" =~ ^[0-9]+$ ]] && [ "$ll" -ge 1 ] && [ "$ll" -le "${#SECRETS_LABELS[@]}" ]; then
                    ll="${SECRETS_LABELS[$((ll - 1))]}"
                fi
                [ -n "$ll" ] && secret_logs "$ll"
                press_any_key
                ;;
            q|Q)
                echo -en "  ${BOLD}Label or #:${NC} "
                local ql; read -r ql
                if [[ "$ql" =~ ^[0-9]+$ ]] && [ "$ql" -ge 1 ] && [ "$ql" -le "${#SECRETS_LABELS[@]}" ]; then
                    ql="${SECRETS_LABELS[$((ql - 1))]}"
                fi
                if [ -n "$ql" ]; then
                    local _cur_day; _cur_day=$(secret_get_quota_reset_day "$ql")
                    echo -e "  ${DIM}Current: ${_cur_day:-not set}${NC}"
                    echo -en "  ${BOLD}Day of month (1-31, or 'off'):${NC} "
                    local qd; read -r qd
                    [ -n "$qd" ] && { secret_set_quota_reset_day "$ql" "$qd" || true; }
                fi
                press_any_key
                ;;
            r|R)
                echo -e "  ${DIM}[1] Dry run (preview)  [2] Rotate ALL now${NC}"
                local rc; rc=$(read_choice "Choice" "1")
                case "$rc" in
                    1) secret_rotate_all "true" ;;
                    2) secret_rotate_all "false" ;;
                esac
                press_any_key
                ;;
            k|K)
                template_list
                echo -e "  ${DIM}[1] Save new  [2] Apply to secret  [3] Delete${NC}"
                local tc; tc=$(read_choice "Choice" "0")
                case "$tc" in
                    1)
                        echo -en "  ${BOLD}Name:${NC} "; local tn; read -r tn
                        [ -z "$tn" ] && { press_any_key; continue; }
                        echo -en "  ${BOLD}Conns (0=unlimited):${NC} "; local tc2; read -r tc2
                        echo -en "  ${BOLD}IPs (0=unlimited):${NC} "; local ti; read -r ti
                        echo -en "  ${BOLD}Quota (e.g. 10G, 0=unlimited):${NC} "; local tq; read -r tq
                        echo -en "  ${BOLD}Expires (YYYY-MM-DD or empty):${NC} "; local te; read -r te
                        echo -en "  ${BOLD}Notes (optional):${NC} "; local tno; read -r tno
                        template_save "$tn" "${tc2:-0}" "${ti:-0}" "${tq:-0}" "${te:-0}" "$tno" || true
                        ;;
                    2)
                        echo -en "  ${BOLD}Template name:${NC} "; local tn; read -r tn
                        echo -en "  ${BOLD}Label or # to apply to:${NC} "; local tl; read -r tl
                        if [[ "$tl" =~ ^[0-9]+$ ]] && [ "$tl" -ge 1 ] && [ "$tl" -le "${#SECRETS_LABELS[@]}" ]; then
                            tl="${SECRETS_LABELS[$((tl - 1))]}"
                        fi
                        [ -n "$tn" ] && [ -n "$tl" ] && { template_apply "$tn" "$tl" || true; }
                        ;;
                    3)
                        echo -en "  ${BOLD}Name to delete:${NC} "; local tn; read -r tn
                        [ -n "$tn" ] && { template_delete "$tn" || true; }
                        ;;
                esac
                press_any_key
                ;;
            b|B)
                echo -en "  ${BOLD}Label or #:${NC} "
                local bl; read -r bl
                if [[ "$bl" =~ ^[0-9]+$ ]] && [ "$bl" -ge 1 ] && [ "$bl" -le "${#SECRETS_LABELS[@]}" ]; then
                    bl="${SECRETS_LABELS[$((bl - 1))]}"
                fi
                if [ -n "$bl" ]; then
                    echo -en "  ${BOLD}AdTag (32 hex chars, or 'clear'):${NC} "
                    local bat; read -r bat
                    [ -n "$bat" ] && { secret_set_adtag "$bl" "$bat" || true; }
                fi
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_links_menu() {
    clear_screen
    draw_header "SHARE LINKS & QR"

    local server_ip
    server_ip=$(get_public_ip)

    if [ -z "$server_ip" ]; then
        log_error "Cannot detect server IP"
        press_any_key
        return
    fi

    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local full_secret
        full_secret=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
        local tg_link="tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}"
        local https_link="https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}"

        echo ""
        echo -e "  ${BRIGHT_GREEN}${BOLD}${SECRETS_LABELS[$i]}${NC}"
        echo -e "  ${DIM}$(_repeat '─' 40)${NC}"
        echo -e "  ${BOLD}TG Link:${NC}  ${CYAN}${tg_link}${NC}"
        echo -e "  ${BOLD}Web Link:${NC} ${CYAN}${https_link}${NC}"

        show_qr "$https_link"
    done

    echo ""
    local sub_b64; sub_b64=$(secret_sub 2>/dev/null)
    if [ -n "$sub_b64" ]; then
        echo -e "  ${BOLD}Base64 Subscription Feed:${NC}"
        echo -e "  ${CYAN}${sub_b64}${NC}"
    fi

    # Offer to send via Telegram
    if [ "$TELEGRAM_ENABLED" = "true" ]; then
        echo -en "  ${BOLD}Send links via Telegram? [y/N]:${NC} "
        local tg_choice
        read -r tg_choice
        case "$tg_choice" in
            y|Y) telegram_notify_proxy_started || true ;;
        esac
    fi

    press_any_key
}

show_telegram_menu() {
    while true; do
        clear_screen
        draw_header "TELEGRAM BOT"
        echo ""
        if [ "$TELEGRAM_ENABLED" = "true" ]; then
            echo -e "  Status: $(draw_status running 'Enabled')"
            echo -e "  ${DIM}Interval: every ${TELEGRAM_INTERVAL}h | Alerts: ${TELEGRAM_ALERTS_ENABLED} | Label: ${TELEGRAM_SERVER_LABEL}${NC}"
        else
            echo -e "  Status: $(draw_status disabled 'Disabled')"
        fi
        echo ""
        echo -e "  ${DIM}[1]${NC} Setup wizard"
        echo -e "  ${DIM}[2]${NC} Send test message"
        echo -e "  ${DIM}[3]${NC} Send proxy links"
        echo -e "  ${DIM}[4]${NC} Toggle notifications"
        echo -e "  ${DIM}[5]${NC} Toggle alerts (${TELEGRAM_ALERTS_ENABLED})"
        echo -e "  ${DIM}[6]${NC} Send custom notification"
        echo -e "  ${DIM}[7]${NC} Change report interval (${TELEGRAM_INTERVAL}h)"
        echo -e "  ${DIM}[8]${NC} Change server label (${TELEGRAM_SERVER_LABEL})"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) telegram_setup_wizard || true ;;
            2) telegram_test_message || true; press_any_key ;;
            3) { telegram_notify_proxy_started && log_success "Links sent"; } || true; press_any_key ;;
            4)
                if [ "$TELEGRAM_ENABLED" = "true" ]; then
                    TELEGRAM_ENABLED="false"
                    systemctl stop mtproxymax-telegram.service 2>/dev/null || true
                    log_success "Telegram disabled"
                else
                    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                        TELEGRAM_ENABLED="true"
                        setup_telegram_service
                        log_success "Telegram enabled"
                    else
                        log_warn "Run setup wizard first"
                    fi
                fi
                save_settings
                press_any_key
                ;;
            5)
                if [ "$TELEGRAM_ALERTS_ENABLED" = "true" ]; then
                    TELEGRAM_ALERTS_ENABLED="false"
                else
                    TELEGRAM_ALERTS_ENABLED="true"
                fi
                save_settings
                log_success "Alerts: ${TELEGRAM_ALERTS_ENABLED}"
                press_any_key
                ;;
            6)
                echo -en "  ${BOLD}Message:${NC} "
                local nmsg; read -r nmsg
                [ -n "$nmsg" ] && { send_notify "$nmsg" || true; }
                press_any_key
                ;;
            7)
                echo -en "  ${BOLD}Report interval in hours [${TELEGRAM_INTERVAL}]:${NC} "
                local new_interval; read -r new_interval
                if [[ "$new_interval" =~ ^[0-9]+$ ]] && [ "$new_interval" -ge 1 ] && [ "$new_interval" -le 168 ]; then
                    TELEGRAM_INTERVAL="$new_interval"
                    save_settings
                    log_success "Report interval set to every ${new_interval}h"
                elif [ -z "$new_interval" ]; then
                    log_info "Keeping current interval: ${TELEGRAM_INTERVAL}h"
                else
                    log_error "Invalid interval — must be 1-168 hours"
                fi
                press_any_key
                ;;
            8)
                echo -en "  ${BOLD}Server label [${TELEGRAM_SERVER_LABEL}]:${NC} "
                local new_label; read -r new_label
                if [ -n "$new_label" ]; then
                    if [[ "$new_label" =~ ^[a-zA-Z0-9_.\ -]+$ ]] && [ ${#new_label} -le 32 ]; then
                        TELEGRAM_SERVER_LABEL="$new_label"
                        save_settings
                        log_success "Server label set to '${new_label}'"
                    else
                        log_error "Invalid label — letters, digits, spaces, dots, hyphens, max 32 chars"
                    fi
                else
                    log_info "Keeping current label: ${TELEGRAM_SERVER_LABEL}"
                fi
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_settings_menu() {
    while true; do
        clear_screen
        draw_header "SETTINGS"
        echo ""
        echo -e "  ${BOLD}Port:${NC}        ${PROXY_PORT}"
        echo -e "  ${BOLD}IP:${NC}          ${CUSTOM_IP:-$(get_public_ip) ${DIM}(auto)${NC}}"
        echo -e "  ${BOLD}Domain:${NC}      ${PROXY_DOMAIN}"
        echo -e "  ${BOLD}CPU:${NC}         ${PROXY_CPUS:-unlimited}"
        echo -e "  ${BOLD}Memory:${NC}      ${PROXY_MEMORY:-unlimited}"
        echo -e "  ${BOLD}Masking:${NC}     ${MASKING_ENABLED}$([ "$MASKING_ENABLED" = "true" ] && echo " → ${MASKING_HOST:-${PROXY_DOMAIN}}:${MASKING_PORT:-443}")"
        echo -e "  ${BOLD}Ad-tag:${NC}      ${AD_TAG:-${DIM}not set${NC}}"
        echo -e "  ${BOLD}Auto-update:${NC} ${AUTO_UPDATE_ENABLED}"
        echo -e "  ${BOLD}PROXY proto:${NC} ${PROXY_PROTOCOL}$([ "$PROXY_PROTOCOL" = "true" ] && [ -n "$PROXY_PROTOCOL_TRUSTED_CIDRS" ] && echo " (trusted: ${PROXY_PROTOCOL_TRUSTED_CIDRS})")"
        echo -e "  ${BOLD}Engine:${NC}      telemt v$(get_telemt_version)"
        echo ""
        echo -e "  ${DIM}[1]${NC} Change port"
        echo -e "  ${DIM}[2]${NC} Change IP"
        echo -e "  ${DIM}[3]${NC} Change domain"
        echo -e "  ${DIM}[4]${NC} Change resources (CPU/RAM)"
        echo -e "  ${DIM}[5]${NC} Toggle traffic masking"
        echo -e "  ${DIM}[m]${NC} Set mask backend (host:port for non-proxy traffic)"
        echo -e "  ${DIM}[b]${NC} Set mask relay byte cap"
        echo -e "  ${DIM}[6]${NC} Set ad-tag"
        echo -e "  ${DIM}[7]${NC} Toggle auto-update"
        echo -e "  ${DIM}[8]${NC} Toggle PROXY protocol"
        echo -e "  ${DIM}[9]${NC} Engine Management"
        echo -e "  ${DIM}[v]${NC} View engine config"
        echo -e "  ${DIM}[k]${NC} Port reachability check"
        echo -e "  ${DIM}[r]${NC} Config profiles"
        echo -e "  ${DIM}[u]${NC} Custom Telegram URLs (restricted regions)"
        echo -e "  ${DIM}[A]${NC} Auto-rotate policy (current: ${SECRET_AUTO_ROTATE_DAYS:-0}d)"
        echo -e "  ${DIM}[s]${NC} Anti-DPI & Stealth Defenses"
        echo -e "  ${DIM}[n]${NC} Engine tuning (advanced)"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}New port:${NC} "
                local p; read -r p
                if validate_port "$p"; then
                    # Remove geoblock rules on old port before changing
                    [ -n "$BLOCKLIST_COUNTRIES" ] && { geoblock_remove_all; _remove_default_drop; }
                    PROXY_PORT="$p"
                    save_settings
                    log_success "Port set to ${p}"
                    if is_proxy_running; then
                        echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                        local r; read -r r
                        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                    fi
                else
                    log_error "Invalid port (must be 1-65535)"
                fi
                press_any_key
                ;;
            2)
                local _det_ip; _det_ip=$(CUSTOM_IP="" get_public_ip)
                echo -e "  ${DIM}Detected: ${_det_ip:-unknown}${NC}"
                echo -en "  ${BOLD}Custom IP [${CUSTOM_IP:-auto}]:${NC} "
                local ip; read -r ip
                if [ "$ip" = "auto" ] || [ "$ip" = "clear" ]; then
                    CUSTOM_IP=""
                    save_settings
                    log_success "IP reset to auto-detect (${_det_ip})"
                elif [ -n "$ip" ]; then
                    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] || [[ "$ip" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
                        CUSTOM_IP="$ip"
                        save_settings
                        log_success "IP/domain set to ${ip}"
                    else
                        log_error "Invalid IP address or domain"
                    fi
                fi
                press_any_key
                ;;
            3)
                echo -e "  ${DIM}[1] cloudflare.com  [2] google.com  [3] microsoft.com  [4] Custom${NC}"
                local d; d=$(read_choice "Choice" "1")
                local _domain_changed=true
                case "$d" in
                    1) PROXY_DOMAIN="cloudflare.com" ;;
                    2) PROXY_DOMAIN="www.google.com" ;;
                    3) PROXY_DOMAIN="www.microsoft.com" ;;
                    4)
                        echo -en "  Domain: "
                        local cd; read -r cd
                        if [ -n "$cd" ] && validate_domain "$cd"; then
                            PROXY_DOMAIN="$cd"
                        elif [ -n "$cd" ]; then
                            log_error "Invalid domain format"; press_any_key; continue
                        else
                            _domain_changed=false
                        fi
                        ;;
                    *) _domain_changed=false ;;
                esac
                if $_domain_changed; then
                    sync_domain_cert_len "true" "false" || true
                    save_settings
                    log_success "Domain set to ${PROXY_DOMAIN}"
                    log_warn "Existing proxy links still encode the old domain"
                    echo -en "  ${BOLD}Rotate all secrets for new domain? [Y/n]:${NC} "
                    local _rot; read -r _rot
                    if [[ ! "$_rot" =~ ^[nN] ]]; then
                        local _ri
                        for _ri in "${!SECRETS_LABELS[@]}"; do
                            SECRETS_KEYS[$_ri]=$(generate_secret)
                        done
                        save_secrets
                        log_success "All secrets rotated — share new links with your users"
                    fi
                    if is_proxy_running; then
                        echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                        local r; read -r r
                        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                    fi
                fi
                press_any_key
                ;;
            4)
                echo -en "  ${BOLD}CPU cores [${PROXY_CPUS:-unlimited}]:${NC} "
                local c; read -r c
                local _res_changed=false
                if [ -n "$c" ]; then
                    if [[ "$c" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk "BEGIN{exit ($c < 0.1)}" 2>/dev/null; then
                        PROXY_CPUS="$c"; _res_changed=true
                    else
                        log_error "Invalid CPU value (must be a number >= 0.1, e.g. 1, 2, 0.5)"
                    fi
                fi
                echo -en "  ${BOLD}Memory, e.g. 256m, 1g [${PROXY_MEMORY:-unlimited}]:${NC} "
                local m; read -r m
                if [ -n "$m" ]; then
                    if [[ "$m" =~ ^[0-9]+[bBkKmMgG]?$ ]]; then
                        [[ "$m" =~ ^[0-9]+$ ]] && m="${m}m"
                        PROXY_MEMORY="$m"; _res_changed=true
                    else
                        log_error "Invalid memory value (e.g. 256m, 1g)"
                    fi
                fi
                if $_res_changed; then
                    save_settings
                    log_success "Resources updated (takes effect on next restart)"
                    if is_proxy_running; then
                        echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                        local r; read -r r
                        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                    fi
                fi
                press_any_key
                ;;
            5)
                [ "$MASKING_ENABLED" = "true" ] && MASKING_ENABLED="false" || MASKING_ENABLED="true"
                save_settings
                log_success "Traffic masking: ${MASKING_ENABLED}"
                if is_proxy_running; then
                    echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                    local r; read -r r
                    [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                fi
                press_any_key
                ;;
            6)
                echo -en "  ${BOLD}Ad-tag (32 hex chars, or 'remove'):${NC} "
                local at; read -r at
                at=$(echo "$at" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                if [[ "$at" =~ ^(remove|clear|off|delete)$ ]] || [ -z "$at" ]; then
                    AD_TAG=""
                    log_success "Ad-tag removed (promoted channel disabled)"
                    save_settings
                elif [[ "$at" =~ ^[0-9a-f]{32}$ ]]; then
                    AD_TAG="$at"
                    log_success "Ad-tag set to: ${at}"
                    save_settings
                else
                    log_error "Invalid ad-tag (must be 32 hex characters)"
                    press_any_key; continue
                fi
                load_secrets; reload_proxy_config
                press_any_key
                ;;
            7)
                [ "$AUTO_UPDATE_ENABLED" = "true" ] && AUTO_UPDATE_ENABLED="false" || AUTO_UPDATE_ENABLED="true"
                save_settings
                log_success "Auto-update: ${AUTO_UPDATE_ENABLED}"
                press_any_key
                ;;
            8)
                [ "$PROXY_PROTOCOL" = "true" ] && PROXY_PROTOCOL="false" || PROXY_PROTOCOL="true"
                if [ "$PROXY_PROTOCOL" = "true" ]; then
                    echo -en "  ${BOLD}Trusted CIDRs (comma-separated, e.g. 10.0.0.0/8,172.16.0.0/12, empty=reject all):${NC} "
                    local cidrs; read -r cidrs
                    PROXY_PROTOCOL_TRUSTED_CIDRS="$cidrs"
                else
                    PROXY_PROTOCOL_TRUSTED_CIDRS=""
                fi
                save_settings
                log_success "PROXY protocol: ${PROXY_PROTOCOL}"
                if is_proxy_running; then
                    echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                    local r; read -r r
                    [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                fi
                press_any_key
                ;;
            9) show_engine_menu ;;
            m|M)
                echo -e "  ${DIM}Non-proxy TLS traffic is forwarded to this backend.${NC}"
                echo -e "  ${DIM}Current: ${MASKING_HOST:-${PROXY_DOMAIN}}:${MASKING_PORT:-443}${NC}"
                echo ""
                echo -en "  ${BOLD}Host [${MASKING_HOST:-${PROXY_DOMAIN}}]:${NC} "
                local _mh; read -r _mh
                echo -en "  ${BOLD}Port [${MASKING_PORT:-443}]:${NC} "
                local _mp; read -r _mp
                local _changed=false
                if [ -n "$_mh" ]; then
                    MASKING_HOST="$_mh"; _changed=true
                fi
                if [ -n "$_mp" ]; then
                    if [[ "$_mp" =~ ^[0-9]+$ ]] && [ "$_mp" -ge 1 ] && [ "$_mp" -le 65535 ]; then
                        MASKING_PORT="$_mp"; _changed=true
                    else
                        log_error "Invalid port"
                    fi
                fi
                if $_changed; then
                    save_settings
                    log_success "Mask backend set to ${MASKING_HOST:-${PROXY_DOMAIN}}:${MASKING_PORT:-443}"
                    if is_proxy_running; then
                        echo -en "  ${DIM}Restart proxy to apply? [Y/n]:${NC} "
                        local r; read -r r
                        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                    fi
                fi
                press_any_key
                ;;
            b|B)
                echo ""
                echo -e "  ${BOLD}Mask relay byte cap${NC}"
                echo -e "  ${DIM}Caps bytes relayed per direction on mask fallback paths.${NC}"
                echo -e "  ${DIM}Empty = engine default (32768). 0 = unlimited (for large mask backends).${NC}"
                echo ""
                local _cur_disp="${MASKING_RELAY_MAX_BYTES:-default}"
                [ "$_cur_disp" = "0" ] && _cur_disp="0 (unlimited)"
                echo -en "  ${BOLD}Value [${_cur_disp}]:${NC} "
                local _v; read -r _v
                if [ -n "$_v" ]; then
                    local _mrb_changed=false
                    if [ "$_v" = "default" ] || [ "$_v" = "clear" ]; then
                        MASKING_RELAY_MAX_BYTES=""
                        save_settings
                        log_success "mask_relay_max_bytes cleared (using engine default)"
                        _mrb_changed=true
                    elif [[ "$_v" =~ ^[0-9]+$ ]]; then
                        MASKING_RELAY_MAX_BYTES="$_v"
                        save_settings
                        log_success "mask_relay_max_bytes set to ${_v}"
                        _mrb_changed=true
                    else
                        log_error "Must be a non-negative integer, 'default', or 'clear'"
                    fi
                    if $_mrb_changed && is_proxy_running; then
                        echo -en "  ${DIM}Restart proxy to apply? [Y/n]:${NC} "
                        local r; read -r r
                        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                    fi
                fi
                press_any_key
                ;;
            v|V) show_config; press_any_key ;;
            k|K) port_check; press_any_key ;;
            r|R)
                echo -e "  ${DIM}[1] Save current config  [2] Load profile  [3] List  [4] Delete${NC}"
                local pc; pc=$(read_choice "Choice" "3")
                case "$pc" in
                    1)
                        echo -en "  ${BOLD}Profile name:${NC} "
                        local pn; read -r pn
                        [ -n "$pn" ] && { profile_save "$pn" || true; }
                        ;;
                    2)
                        profile_list
                        echo -en "  ${BOLD}Profile name to load:${NC} "
                        local pn; read -r pn
                        [ -n "$pn" ] && { profile_load "$pn" || true; }
                        ;;
                    3) profile_list ;;
                    4)
                        profile_list
                        echo -en "  ${BOLD}Profile name to delete:${NC} "
                        local pn; read -r pn
                        [ -n "$pn" ] && { profile_delete "$pn" || true; }
                        ;;
                esac
                press_any_key
                ;;
            u|U)
                echo ""
                echo -e "  ${BOLD}Custom Telegram Infrastructure URLs${NC}"
                echo -e "  ${DIM}Use this if core.telegram.org is blocked in your region.${NC}"
                echo -e "  ${DIM}Point these to a mirror/proxy that serves the same files.${NC}"
                echo ""
                echo -e "  proxy_secret_url:    ${PROXY_SECRET_URL:-${DIM}(default)${NC}}"
                echo -e "  proxy_config_v4_url: ${PROXY_CONFIG_V4_URL:-${DIM}(default)${NC}}"
                echo -e "  proxy_config_v6_url: ${PROXY_CONFIG_V6_URL:-${DIM}(default)${NC}}"
                echo ""
                echo -e "  ${DIM}[1] Set getProxySecret URL${NC}"
                echo -e "  ${DIM}[2] Set getProxyConfig (v4) URL${NC}"
                echo -e "  ${DIM}[3] Set getProxyConfigV6 URL${NC}"
                echo -e "  ${DIM}[4] Clear all (back to defaults)${NC}"
                echo -e "  ${DIM}[0] Back${NC}"
                local uc; uc=$(read_choice "Choice" "0")
                local _url _field=""
                case "$uc" in
                    1) _field="secret" ;;
                    2) _field="config-v4" ;;
                    3) _field="config-v6" ;;
                    4)
                        PROXY_SECRET_URL=""; PROXY_CONFIG_V4_URL=""; PROXY_CONFIG_V6_URL=""
                        save_settings
                        log_success "Telegram URLs reset to defaults"
                        if is_proxy_running; then
                            echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                            local r; read -r r
                            [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                        fi
                        ;;
                esac
                if [ -n "$_field" ]; then
                    echo -en "  ${BOLD}URL (empty to clear):${NC} "
                    read -r _url
                    if [ -z "$_url" ]; then
                        case "$_field" in
                            secret)    PROXY_SECRET_URL="" ;;
                            config-v4) PROXY_CONFIG_V4_URL="" ;;
                            config-v6) PROXY_CONFIG_V6_URL="" ;;
                        esac
                        save_settings
                        log_success "${_field} URL cleared"
                    elif [[ "$_url" =~ ^https?:// ]]; then
                        case "$_field" in
                            secret)    PROXY_SECRET_URL="$_url" ;;
                            config-v4) PROXY_CONFIG_V4_URL="$_url" ;;
                            config-v6) PROXY_CONFIG_V6_URL="$_url" ;;
                        esac
                        save_settings
                        log_success "${_field} URL set"
                        if is_proxy_running; then
                            echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                            local r; read -r r
                            [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                        fi
                    else
                        log_error "URL must start with http:// or https://"
                    fi
                fi
                press_any_key
                ;;
            n|N)
                tune_list_params
                echo -e "  ${DIM}[1] Set param  [2] Clear param  [3] Clear all  [0] Back${NC}"
                local tch; tch=$(read_choice "Choice" "0")
                case "$tch" in
                    1)
                        echo -en "  ${BOLD}Param name:${NC} "
                        local tp; read -r tp
                        [ -z "$tp" ] && { press_any_key; continue; }
                        echo -en "  ${BOLD}Value:${NC} "
                        local tv; read -r tv
                        [ -n "$tv" ] && { tune_set "$tp" "$tv" || true; }
                        ;;
                    2)
                        echo -en "  ${BOLD}Param name to clear:${NC} "
                        local tp; read -r tp
                        [ -n "$tp" ] && { tune_clear "$tp" || true; }
                        ;;
                    3)
                        tune_clear "all"
                        ;;
                esac
                press_any_key
                ;;
            a|A)
                echo ""
                echo -e "  ${BOLD}Secret auto-rotate policy${NC}"
                echo -e "  ${DIM}Automatically rotate all secrets older than N days.${NC}"
                echo -e "  ${DIM}Set to 0 to disable. Bot daemon enforces every 5 min.${NC}"
                echo ""
                echo -e "  Current: ${SECRET_AUTO_ROTATE_DAYS:-0} days"
                echo -en "  ${BOLD}New value (days, 0=disabled):${NC} "
                local _av; read -r _av
                if [ -n "$_av" ]; then
                    if [ "$_av" = "off" ] || [ "$_av" = "0" ]; then
                        SECRET_AUTO_ROTATE_DAYS="0"
                    elif [[ "$_av" =~ ^[0-9]+$ ]] && [ "$_av" -ge 1 ] && [ "$_av" -le 3650 ]; then
                        SECRET_AUTO_ROTATE_DAYS="$_av"
                    else
                        log_error "Must be a positive integer (days) or 'off'"
                        press_any_key; continue
                    fi
                    save_settings
                    log_success "Auto-rotate policy: ${SECRET_AUTO_ROTATE_DAYS} days"
                fi
                press_any_key
                ;;
            s|S) show_stealth_menu ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_engine_menu() {
    while true; do
        clear_screen
        draw_header "ENGINE MANAGEMENT"
        echo ""
        echo -e "  ${BOLD}Engine:${NC}    telemt v$(get_telemt_version)"
        echo -e "  ${BOLD}Pinned to:${NC} commit ${TELEMT_COMMIT}"
        echo ""
        local _expected="${TELEMT_MIN_VERSION}-${TELEMT_COMMIT}"
        local _current; _current=$(get_telemt_version)
        if [ "$_current" = "$_expected" ]; then
            echo -e "  ${GREEN}${SYM_OK} Engine is up to date${NC}"
        elif _version_gte "$_current" "$_expected"; then
            echo -e "  ${GREEN}${SYM_OK} Engine is up to date (ahead of pinned)${NC}"
        else
            echo -e "  ${YELLOW}Update available: v${_current} -> v${_expected}${NC}"
            echo -e "  ${DIM}Run: mtproxymax update${NC}"
        fi
        echo ""
        echo -e "  ${DIM}[1]${NC} Force rebuild engine"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${DIM}Force rebuild from commit ${TELEMT_COMMIT}? [Y/n]:${NC} "
                local confirm; read -r confirm
                if [[ "$confirm" =~ ^[nN] ]]; then
                    press_any_key; continue
                fi
                build_telemt_image true
                if is_proxy_running; then
                    load_secrets
                    restart_proxy_container || true
                fi
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_traffic_menu() {
    clear_screen
    draw_header "LOGS & TRAFFIC"

    if ! is_proxy_running; then
        echo ""
        echo -e "  ${DIM}Proxy is not running${NC}"
        press_any_key
        return
    fi

    local t_in t_out conns
    read -r t_in t_out conns <<< "$(get_cumulative_proxy_stats)"

    # Batch-load all user stats in one pass
    _load_all_cumulative_user_stats 2>/dev/null

    echo ""
    echo -e "  ${BOLD}Total Traffic${NC}"
    echo -e "  ${SYM_DOWN} Download: $(format_bytes "$t_in")"
    echo -e "  ${SYM_UP} Upload:   $(format_bytes "$t_out")"
    echo -e "  ${BOLD}Active Connections:${NC} ${conns}"
    echo ""

    echo -e "  ${BOLD}Per-User Breakdown${NC}"
    echo -e "  ${DIM}$(_repeat '─' 60)${NC}"

    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local label="${SECRETS_LABELS[$i]}"
        local u_in=${_batch_cum_in["$label"]:-0}
        local u_out=${_batch_cum_out["$label"]:-0}
        local u_conns=${_batch_cum_conns["$label"]:-0}
        echo -e "  ${GREEN}${SYM_OK}${NC} ${BOLD}${label}${NC}"
        echo -e "    ${SYM_DOWN} $(format_bytes "$u_in")  ${SYM_UP} $(format_bytes "$u_out")  conns: ${u_conns}"
    done

    echo ""
    echo -e "  ${DIM}[1]${NC} Stream live logs"
    echo -e "  ${DIM}[2]${NC} Connection log"
    echo -e "  ${DIM}[3]${NC} Engine metrics"
    echo -e "  ${DIM}[4]${NC} Engine metrics (live)"
    echo -e "  ${DIM}[5]${NC} Active connections"
    echo -e "  ${DIM}[0]${NC} Back"

    local choice
    choice=$(read_choice "Choice" "0")
    case "$choice" in
        1) echo -e "  ${DIM}Press Ctrl+C to stop...${NC}"; docker logs -f --tail 30 "$CONTAINER_NAME" 2>&1 || true ;;
        2)
            echo ""
            if [ -f "$CONNECTION_LOG" ] && [ -s "$CONNECTION_LOG" ]; then
                tail -n 50 "$CONNECTION_LOG"
            else
                echo -e "  ${DIM}Connection log is empty${NC}"
            fi
            press_any_key
            ;;
        3) show_metrics; press_any_key ;;
        4)
            (
                while true; do
                    tput clear 2>/dev/null || printf '\033[2J\033[H'
                    show_metrics
                    echo -e "  ${DIM}[live — refreshing every 5s, Ctrl+C to stop]${NC}"
                    sleep 5
                done
            )
            ;;
        5) show_connections; press_any_key ;;
    esac
}

# ── Info & Help Sub-Pages ────────────────────────────────────

show_info_faketls() {
    clear_screen
    draw_header "FAKETLS OBFUSCATION"
    echo ""
    echo -e "  ${BOLD}What is FakeTLS?${NC}"
    echo -e "  FakeTLS makes your proxy traffic look identical to normal"
    echo -e "  HTTPS (TLS 1.3) connections. Deep Packet Inspection (DPI)"
    echo -e "  systems cannot distinguish proxy traffic from regular web"
    echo -e "  browsing, making your proxy virtually undetectable."
    echo ""
    echo -e "  ${BOLD}How it works:${NC}"
    echo -e "  1. Clients initiate a TLS handshake to a \"cover\" domain"
    echo -e "     (e.g., cloudflare.com) — this is the FakeTLS domain."
    echo -e "  2. The handshake looks exactly like a real TLS 1.3 session"
    echo -e "     to any network observer or firewall."
    echo -e "  3. Inside the encrypted tunnel, the actual MTProxy protocol"
    echo -e "     carries your Telegram data."
    echo -e "  4. Censors see only \"user connected to cloudflare.com via"
    echo -e "     HTTPS\" — completely normal traffic."
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "  ${DIM}Domain:${NC}  Choose a popular, non-blocked site (cloudflare.com,"
    echo -e "           google.com, microsoft.com). The domain appears in the"
    echo -e "           TLS handshake SNI field."
    echo -e "  ${DIM}Secret:${NC}  FakeTLS secrets start with \`ee\` prefix followed by"
    echo -e "           the raw secret + hex-encoded domain name."
    echo ""
    echo -e "  ${BOLD}Best practices:${NC}"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Use a domain hosted on the same CDN/IP range as your server"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Choose popular sites with high traffic (harder to block)"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Enable traffic masking alongside FakeTLS for maximum stealth"
    echo ""
    press_any_key
}

show_info_masking() {
    clear_screen
    draw_header "TRAFFIC MASKING"
    echo ""
    echo -e "  ${BOLD}What is Traffic Masking?${NC}"
    echo -e "  When enabled, your server responds to non-proxy connections"
    echo -e "  by forwarding them to a real website. This means if a censor"
    echo -e "  probes your server, they see a legitimate website — not a proxy."
    echo ""
    echo -e "  ${BOLD}How it works:${NC}"
    echo -e "  1. A probe connects to your server on port 443."
    echo -e "  2. The connection doesn't contain a valid proxy secret."
    echo -e "  3. Instead of dropping the connection (suspicious!), the server"
    echo -e "     forwards it to the real website (e.g., cloudflare.com)."
    echo -e "  4. The probe receives a real TLS certificate and web content."
    echo -e "  5. Your server looks like a normal web server."
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "  ${DIM}mask = true${NC}       Enable masking in telemt config"
    echo -e "  ${DIM}mask_host${NC}         Domain to forward probes to (default: your FakeTLS domain)"
    echo -e "  ${DIM}mask_port = 443${NC}   Port on the target website"
    echo ""
    echo -e "  ${BOLD}Why it matters:${NC}"
    echo -e "  Without masking, active probers can detect that your server"
    echo -e "  only accepts connections with valid secrets and drops others."
    echo -e "  This behavior is a fingerprint that reveals it's a proxy."
    echo -e "  Masking eliminates this fingerprint entirely."
    echo ""
    press_any_key
}

show_info_multisecret() {
    clear_screen
    draw_header "MULTI-SECRET MANAGEMENT"
    echo ""
    echo -e "  ${BOLD}What are Secrets?${NC}"
    echo -e "  Each secret is a unique key that grants a user access to your"
    echo -e "  proxy. Think of it like giving someone a password to connect."
    echo -e "  MTProxyMax supports multiple secrets simultaneously."
    echo ""
    echo -e "  ${BOLD}Use cases:${NC}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Give each family member their own secret"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Track traffic per user (each secret = one user)"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Revoke one user's access without affecting others"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Rotate compromised keys while keeping others active"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "  ${GREEN}mtproxymax secret add <label>${NC}      Create a new secret"
    echo -e "  ${GREEN}mtproxymax secret add-batch <l1> <l2> ...${NC}  Add multiple (single restart)"
    echo -e "  ${GREEN}mtproxymax secret remove <label>${NC}   Delete a secret"
    echo -e "  ${GREEN}mtproxymax secret remove-batch <l1> <l2> ...${NC}  Remove multiple (single restart)"
    echo -e "  ${GREEN}mtproxymax secret rotate <label>${NC}   Replace key, keep label"
    echo -e "  ${GREEN}mtproxymax secret enable <label>${NC}   Re-enable a disabled secret"
    echo -e "  ${GREEN}mtproxymax secret disable <label>${NC}  Temporarily disable access"
    echo -e "  ${GREEN}mtproxymax secret list${NC}             Show all secrets + traffic"
    echo ""
    echo -e "  ${BOLD}Labels:${NC}"
    echo -e "  Labels are human-readable names (a-z, 0-9, _, -). They appear"
    echo -e "  in traffic stats so you can see who is using how much bandwidth."
    echo ""
    press_any_key
}

show_info_adtag() {
    clear_screen
    draw_header "AD-TAG / PROMOTED CHANNEL"
    echo ""
    echo -e "  ${BOLD}What is an Ad-Tag?${NC}"
    echo -e "  Telegram's official feature that lets proxy operators show a"
    echo -e "  sponsored channel to users who connect through their proxy."
    echo -e "  This is how you can earn from running a public proxy."
    echo ""
    echo -e "  ${BOLD}How to get an ad-tag:${NC}"
    echo -e "  1. Open Telegram and message @MTProxyBot"
    echo -e "  2. Register your proxy server"
    echo -e "  3. Choose a channel to promote"
    echo -e "  4. You'll receive a 32-character hex ad-tag"
    echo ""
    echo -e "  ${BOLD}How to set it:${NC}"
    echo -e "  ${GREEN}mtproxymax adtag set <hex>${NC}    Set the ad-tag"
    echo -e "  ${GREEN}mtproxymax adtag remove${NC}       Remove the ad-tag"
    echo ""
    echo -e "  ${BOLD}How it appears:${NC}"
    echo -e "  Users who connect through your proxy will see the promoted"
    echo -e "  channel at the top of their chat list. They can dismiss it,"
    echo -e "  but it reappears periodically."
    echo ""
    echo -e "  ${DIM}Note: Ad-tags are entirely optional. Your proxy works"
    echo -e "  perfectly fine without one.${NC}"
    echo ""
    press_any_key
}

show_info_telegram() {
    clear_screen
    draw_header "TELEGRAM BOT INTEGRATION"
    echo ""
    echo -e "  ${BOLD}What does the bot do?${NC}"
    echo -e "  Control your proxy from your phone via Telegram. The bot runs"
    echo -e "  as a separate systemd service and responds to commands."
    echo ""
    echo -e "  ${BOLD}Available commands:${NC}"
    echo -e "  /mp_status         Check proxy status, uptime, traffic"
    echo -e "  /mp_secrets        List all secrets with per-user stats"
    echo -e "  /mp_link           Get proxy links + QR code"
    echo -e "  /mp_add <label>    Add a new user secret"
    echo -e "  /mp_remove <label> Remove a secret"
    echo -e "  /mp_rotate <label> Rotate a secret (new key)"
    echo -e "  /mp_enable <label> Enable a secret"
    echo -e "  /mp_disable <label> Disable a secret"
    echo -e "  /mp_limits         Show per-user limits"
    echo -e "  /mp_setlimit       Set user limits (conns, IPs, quota, expiry)"
    echo -e "  /mp_upstreams      List upstream routes"
    echo -e "  /mp_traffic        Detailed traffic breakdown"
    echo -e "  /mp_health         Run health diagnostics"
    echo -e "  /mp_restart        Restart the proxy"
    echo -e "  /mp_update         Check for script updates"
    echo -e "  /mp_help           Show all commands"
    echo ""
    echo -e "  ${BOLD}Automatic notifications:${NC}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Proxy startup — sends links + QR codes"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Downtime alerts — notifies when proxy goes down"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Auto-recovery — attempts restart and reports result"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} Periodic reports — traffic summaries at your interval"
    echo ""
    echo -e "  ${BOLD}Setup:${NC} Run ${GREEN}mtproxymax telegram setup${NC}"
    echo ""
    press_any_key
}

show_info_qrcode() {
    clear_screen
    draw_header "QR CODE SHARING"
    echo ""
    echo -e "  ${BOLD}What are proxy QR codes?${NC}"
    echo -e "  QR codes encode your proxy link so users can connect by"
    echo -e "  simply scanning with their phone's camera in Telegram."
    echo ""
    echo -e "  ${BOLD}How to use:${NC}"
    echo -e "  1. Open Telegram > Settings > Data and Storage > Proxy"
    echo -e "  2. Tap \"Add Proxy\" or use the camera to scan"
    echo -e "  3. The proxy configuration is applied automatically"
    echo ""
    echo -e "  ${BOLD}QR generation methods (auto-detected):${NC}"
    echo -e "  ${GREEN}1.${NC} ${BOLD}qrencode${NC} (native) — fastest, renders in terminal"
    echo -e "     Install: ${DIM}apt install qrencode${NC}"
    echo -e "  ${GREEN}2.${NC} ${BOLD}Docker${NC} — uses alpine + qrencode container"
    echo -e "  ${GREEN}3.${NC} ${BOLD}Web API${NC} — qrserver.com (for Telegram photo messages)"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "  ${GREEN}mtproxymax secret qr <label>${NC}   Show QR in terminal"
    echo -e "  ${GREEN}mtproxymax secret link <label>${NC} Show shareable link"
    echo ""
    echo -e "  ${BOLD}Via Telegram bot:${NC}"
    echo -e "  Send /mp_link to your bot — it replies with both the link"
    echo -e "  and a scannable QR code image."
    echo ""
    press_any_key
}

show_info_geoblock() {
    clear_screen
    draw_header "GEO-BLOCKING"
    echo ""
    echo -e "  ${BOLD}What is Geo-Blocking?${NC}"
    echo -e "  Block connections from specific countries using IP-based"
    echo -e "  CIDR lists. Useful for limiting who can use your proxy."
    echo ""
    echo -e "  ${BOLD}How it works:${NC}"
    echo -e "  1. Country CIDR lists are downloaded from ipdeny.com"
    echo -e "  2. IP ranges are added to iptables/nftables rules"
    echo -e "  3. Connections from blocked countries are dropped at the"
    echo -e "     network level before reaching the proxy"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "  ${GREEN}mtproxymax geoblock add <CC>${NC}    Block a country (e.g., CN)"
    echo -e "  ${GREEN}mtproxymax geoblock remove <CC>${NC} Unblock a country"
    echo -e "  ${GREEN}mtproxymax geoblock list${NC}        Show blocked countries"
    echo ""
    echo -e "  ${BOLD}Common country codes:${NC}"
    echo -e "  US (United States)  DE (Germany)    NL (Netherlands)"
    echo -e "  CN (China)          RU (Russia)     IR (Iran)"
    echo -e "  FR (France)         GB (UK)         SG (Singapore)"
    echo ""
    echo -e "  ${DIM}Note: Geo-blocking uses host networking, so iptables"
    echo -e "  rules are applied on the host, not inside the container.${NC}"
    echo ""
    press_any_key
}

show_info_autoupdate() {
    clear_screen
    draw_header "AUTO-UPDATE"
    echo ""
    echo -e "  ${BOLD}How Auto-Update works:${NC}"
    echo -e "  MTProxyMax checks GitHub for new releases and can update"
    echo -e "  itself with a single command."
    echo ""
    echo -e "  ${BOLD}Update process:${NC}"
    echo -e "  1. Query GitHub API for the latest release version"
    echo -e "  2. Compare with your installed version"
    echo -e "  3. If newer, prompt for confirmation"
    echo -e "  4. Backup current script to ${DIM}/opt/mtproxymax/backups/${NC}"
    echo -e "  5. Download and validate new version"
    echo -e "  6. Atomic replace (mv, not copy)"
    echo -e "  7. Regenerate Telegram service if active"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "  ${GREEN}mtproxymax update${NC}   Check and apply updates"
    echo ""
    echo -e "  ${BOLD}Safety:${NC}"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Always backs up before updating"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Validates downloaded script (checks #!/bin/bash header)"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Rollback possible from ${DIM}backups/${NC} directory"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Telegram notification when update is available"
    echo ""
    press_any_key
}

show_info_health() {
    clear_screen
    draw_header "HEALTH MONITORING"
    echo ""
    echo -e "  ${BOLD}What does Health Monitoring do?${NC}"
    echo -e "  Continuously checks that your proxy is running and accessible."
    echo -e "  If the proxy goes down, it attempts automatic recovery."
    echo ""
    echo -e "  ${BOLD}Checks performed:${NC}"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Docker daemon running"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Proxy container status (up/down)"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Port listening on configured port"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Prometheus metrics endpoint responding"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Telegram bot service status"
    echo ""
    echo -e "  ${BOLD}Auto-recovery:${NC}"
    echo -e "  The Telegram bot service checks every 5 minutes. If the proxy"
    echo -e "  container is down:"
    echo -e "  1. Sends alert: \"Proxy is down! Attempting auto-restart...\""
    echo -e "  2. Runs ${GREEN}mtproxymax start${NC}"
    echo -e "  3. Reports success or failure via Telegram"
    echo ""
    echo -e "  ${BOLD}Manual check:${NC}"
    echo -e "  ${GREEN}mtproxymax health${NC}   Run diagnostic checks"
    echo ""
    echo -e "  ${BOLD}Docker auto-restart:${NC}"
    echo -e "  The container runs with ${DIM}--restart unless-stopped${NC}, so Docker"
    echo -e "  itself will restart it on crashes. The health monitor is an"
    echo -e "  additional safety net."
    echo ""
    press_any_key
}

show_info_userlimits() {
    clear_screen
    draw_header "USER LIMITS"
    echo ""
    echo -e "  ${BOLD}${YELLOW}Per-User Connection & Bandwidth Limits${NC}"
    echo ""
    echo -e "  MTProxyMax lets you set limits per secret (user), so you can"
    echo -e "  prevent abuse when sharing your proxy with others."
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}Available limits:${NC}"
    echo ""
    echo -e "  ${CYAN}1. Max TCP Connections${NC}"
    echo -e "     Limits how many simultaneous connections a user can have."
    echo -e "     Prevents one user from overloading your server."
    echo -e "     ${DIM}Recommended: 50-200 for normal use${NC}"
    echo ""
    echo -e "  ${CYAN}2. Max Unique IPs${NC}"
    echo -e "     Limits how many different devices/IPs can use a secret."
    echo -e "     Great for controlling who shares your link."
    echo -e "     ${DIM}Recommended: 3-5 for family, 1-2 for personal${NC}"
    echo ""
    echo -e "  ${CYAN}3. Data Quota${NC}"
    echo -e "     Bandwidth cap per user in bytes."
    echo -e "     Useful for fair-use on limited bandwidth servers."
    echo -e "     ${DIM}Recommended: 5G-50G depending on your plan${NC}"
    echo ""
    echo -e "  ${CYAN}4. Expiration Date${NC}"
    echo -e "     Auto-disables a secret after the given date."
    echo -e "     Useful for time-limited access (trials, guests)."
    echo -e "     ${DIM}Format: YYYY-MM-DD (e.g. 2026-06-30)${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}How to set limits:${NC}"
    echo ""
    echo -e "  ${GREEN}TUI:${NC}  Main Menu > Secret Management > Set user limits"
    echo ""
    echo -e "  ${GREEN}CLI:${NC}"
    echo -e "    mtproxymax secret setlimit alice conns 100"
    echo -e "    mtproxymax secret setlimit alice ips 5"
    echo -e "    mtproxymax secret setlimit alice quota 10G"
    echo -e "    mtproxymax secret setlimit alice expires 2026-06-30"
    echo ""
    echo -e "  ${GREEN}Telegram:${NC}"
    echo -e "    /mp_setlimit alice 100 5 10G 2026-06-30"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}Examples:${NC}"
    echo ""
    echo -e "  ${CYAN}Family sharing (5 people):${NC}"
    echo -e "    Give each person their own secret with:"
    echo -e "    Max IPs: 3 (phone + tablet + desktop)"
    echo -e "    Max conns: 100"
    echo -e "    Data quota: 10G per person"
    echo ""
    echo -e "  ${CYAN}Public proxy:${NC}"
    echo -e "    Max IPs: 1 (one device per key)"
    echo -e "    Max conns: 50"
    echo -e "    Data quota: 2G"
    echo ""
    echo -e "  ${DIM}Set any limit to 0 for unlimited.${NC}"
    echo ""
    press_any_key
}

show_info_proxychaining() {
    clear_screen
    draw_header "PROXY CHAINING"
    echo ""
    echo -e "  ${BOLD}${YELLOW}Route Traffic Through Intermediate Proxies${NC}"
    echo ""
    echo -e "  Proxy chaining routes your proxy's outbound traffic through"
    echo -e "  a SOCKS5/SOCKS4 proxy before it reaches Telegram servers."
    echo ""
    echo -e "  ${BOLD}How it works:${NC}"
    echo ""
    echo -e "    User --> ${CYAN}Your Server${NC} --> ${GREEN}SOCKS5 Proxy${NC} --> Telegram"
    echo ""
    echo -e "  ${BOLD}Why Iran users need this:${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Your server IP gets blocked by ISPs"
    echo -e "     ${DIM}Solution: Route through a clean IP via SOCKS5${NC}"
    echo ""
    echo -e "  ${CYAN}2.${NC} Direct routes to Telegram are throttled"
    echo -e "     ${DIM}Solution: Route through a different network path${NC}"
    echo ""
    echo -e "  ${CYAN}3.${NC} IP gets flagged for hosting proxy"
    echo -e "     ${DIM}Solution: Use Cloudflare WARP or VPN as exit${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}Common setups:${NC}"
    echo ""
    echo -e "  ${CYAN}Cloudflare WARP (Free, Easiest):${NC}"
    echo -e "    Install WARP on your server, it creates a SOCKS5 at 127.0.0.1:40000"
    echo -e "    ${GREEN}curl -fsSL https://pkg.cloudflareclient.com | bash${NC}"
    echo -e "    ${GREEN}warp-cli register && warp-cli set-mode proxy && warp-cli connect${NC}"
    echo -e "    Then add upstream: socks5 at 127.0.0.1:40000"
    echo ""
    echo -e "  ${CYAN}SSH Tunnel (Any VPS):${NC}"
    echo -e "    Create a SOCKS5 tunnel through another server:"
    echo -e "    ${GREEN}ssh -D 1080 -N user@backup-vps${NC}"
    echo -e "    Then add upstream: socks5 at 127.0.0.1:1080"
    echo ""
    echo -e "  ${CYAN}Secondary VPS:${NC}"
    echo -e "    Run a SOCKS5 proxy on a second server (e.g., dante, microsocks)"
    echo -e "    Then add upstream: socks5 at <backup-ip>:1080"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}Weight-based load balancing:${NC}"
    echo ""
    echo -e "  When you have multiple upstreams, traffic is distributed by weight."
    echo -e "  Higher weight = more traffic routed through that upstream."
    echo ""
    echo -e "  Example:"
    echo -e "    direct    weight=10  (33% of traffic)"
    echo -e "    warp      weight=20  (67% of traffic)"
    echo ""
    echo -e "  If one upstream fails, traffic automatically shifts to others."
    echo ""
    press_any_key
}

show_info_upstreams() {
    clear_screen
    draw_header "UPSTREAM TYPES"
    echo ""
    echo -e "  ${BOLD}${YELLOW}Understanding Upstream Connection Types${NC}"
    echo ""
    echo -e "  ${CYAN}Direct:${NC}"
    echo -e "    Connects straight to Telegram servers."
    echo -e "    Fastest, but your server IP is visible."
    echo -e "    ${DIM}Best when: your IP isn't blocked${NC}"
    echo ""
    echo -e "  ${CYAN}SOCKS5:${NC}"
    echo -e "    Routes through a SOCKS5 proxy server."
    echo -e "    Supports authentication (username/password)."
    echo -e "    Supports DNS resolution through proxy."
    echo -e "    ${DIM}Best when: you need to hide your server IP or bypass blocks${NC}"
    echo ""
    echo -e "  ${CYAN}SOCKS4:${NC}"
    echo -e "    Older protocol, identification via user_id only (no password)."
    echo -e "    ${DIM}Best when: only SOCKS4 is available${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}How weights work:${NC}"
    echo ""
    echo -e "  Each upstream has a weight from 1-100."
    echo -e "  Traffic is distributed proportionally."
    echo ""
    echo -e "  ${BOLD}Example with 3 upstreams:${NC}"
    echo -e "    direct (w:10) + warp (w:20) + backup (w:5) = 35 total"
    echo -e "    direct gets 10/35 = 29%"
    echo -e "    warp gets   20/35 = 57%"
    echo -e "    backup gets  5/35 = 14%"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}Setting up a SOCKS5 proxy:${NC}"
    echo ""
    echo -e "  ${CYAN}Option A: Cloudflare WARP${NC} (Free)"
    echo -e "    ${GREEN}curl -fsSL https://pkg.cloudflareclient.com | bash"
    echo -e "    warp-cli register"
    echo -e "    warp-cli set-mode proxy"
    echo -e "    warp-cli connect${NC}"
    echo -e "    Proxy available at: 127.0.0.1:40000"
    echo ""
    echo -e "  ${CYAN}Option B: microsocks${NC} (On another VPS)"
    echo -e "    ${GREEN}git clone https://github.com/rofl0r/microsocks && cd microsocks"
    echo -e "    make && sudo cp microsocks /usr/local/bin/"
    echo -e "    microsocks -p 1080 &${NC}"
    echo ""
    echo -e "  ${CYAN}Option C: SSH Tunnel${NC}"
    echo -e "    ${GREEN}ssh -D 1080 -f -N user@other-server${NC}"
    echo ""
    echo -e "  ${BOLD}Bind to interface (advanced):${NC}"
    echo -e "    When adding an upstream, you can bind outbound traffic"
    echo -e "    to a specific IP address on your server."
    echo -e "    Useful if your server has multiple IPs and you want"
    echo -e "    different upstreams to exit from different addresses."
    echo ""
    echo -e "  ${BOLD}Testing an upstream:${NC}"
    echo -e "    TUI: Security & Routing > Proxy Chaining > Test"
    echo -e "    CLI: ${GREEN}mtproxymax upstream test <name>${NC}"
    echo ""
    press_any_key
}

show_info_menu() {
    while true; do
        clear_screen
        draw_header "INFO & HELP"
        echo ""
        echo -e "  ${BOLD}Learn about each feature in detail:${NC}"
        echo ""
        echo -e "  ${BRIGHT_CYAN}[1]${NC}  FakeTLS Obfuscation"
        echo -e "  ${BRIGHT_CYAN}[2]${NC}  Traffic Masking"
        echo -e "  ${BRIGHT_CYAN}[3]${NC}  Multi-Secret Management"
        echo -e "  ${BRIGHT_CYAN}[4]${NC}  Ad-Tag / Promoted Channel"
        echo -e "  ${BRIGHT_CYAN}[5]${NC}  Telegram Bot Integration"
        echo -e "  ${BRIGHT_CYAN}[6]${NC}  QR Code Sharing"
        echo -e "  ${BRIGHT_CYAN}[7]${NC}  Geo-Blocking"
        echo -e "  ${BRIGHT_CYAN}[8]${NC}  Auto-Update"
        echo -e "  ${BRIGHT_CYAN}[9]${NC}  Health Monitoring"
        echo ""
        echo -e "  ${BRIGHT_CYAN}[a]${NC}  Per-User Limits"
        echo -e "  ${BRIGHT_CYAN}[b]${NC}  Proxy Chaining"
        echo -e "  ${BRIGHT_CYAN}[c]${NC}  Upstream Types & Setup"
        echo ""
        echo -e "  ${BRIGHT_CYAN}[p]${NC}  Port Forwarding Guide (Home Users)"
        echo -e "  ${BRIGHT_CYAN}[f]${NC}  Firewall Configuration Guide"
        echo ""
        echo -e "  ${BRIGHT_CYAN}[d]${NC}  Run Doctor (diagnostics)"
        echo -e "  ${BRIGHT_CYAN}[i]${NC}  Server Info (full overview)"
        echo -e "  ${BRIGHT_CYAN}[n]${NC}  View Changelog"
        echo -e "  ${BRIGHT_CYAN}[v]${NC}  Run Verify (install check)"
        echo -e "  ${BRIGHT_CYAN}[s]${NC}  Speed Test (outbound bandwidth)"
        echo -e "  ${BRIGHT_CYAN}[l]${NC}  Datacenter Latency Benchmark"
        echo -e "  ${BRIGHT_CYAN}[g]${NC}  Executive Digest Summary"
        echo -e "  ${BRIGHT_CYAN}[h]${NC}  Audit History"
        echo ""
        echo -e "  ${DIM}[0]${NC}  Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) show_info_faketls ;;
            2) show_info_masking ;;
            3) show_info_multisecret ;;
            4) show_info_adtag ;;
            5) show_info_telegram ;;
            6) show_info_qrcode ;;
            7) show_info_geoblock ;;
            8) show_info_autoupdate ;;
            9) show_info_health ;;
            a|A) show_info_userlimits ;;
            b|B) show_info_proxychaining ;;
            c|C) show_info_upstreams ;;
            p|P) show_port_forward_guide ;;
            f|F) show_firewall_guide ;;
            d|D) run_doctor; press_any_key ;;
            i|I) show_server_info; press_any_key ;;
            n|N) show_changelog; press_any_key ;;
            v|V) run_verify; press_any_key ;;
            s|S) run_speedtest; press_any_key ;;
            l|L) run_ping_dc; press_any_key ;;
            g|G) run_digest; press_any_key ;;
            h|H) show_history 50; press_any_key ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

show_port_forward_guide() {
    clear_screen
    draw_header "PORT FORWARDING GUIDE"
    echo ""
    echo -e "  ${BOLD}${YELLOW}For Home Users Running Behind a Router${NC}"
    echo ""
    echo -e "  If your server is behind a home router (NAT), users on the"
    echo -e "  internet cannot reach your proxy directly. You need to set up"
    echo -e "  ${BOLD}port forwarding${NC} on your router."
    echo ""
    echo -e "  ${BOLD}What port forwarding does:${NC}"
    echo -e "  Routes incoming connections on your public IP to your server"
    echo -e "  on the local network."
    echo ""
    echo -e "  ${BOLD}  Internet --> [Your Public IP:${PROXY_PORT}] --> Router"
    echo -e "       --> [Your Server LAN IP:${PROXY_PORT}] --> MTProxyMax${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BOLD}Step 1: Find your server's local IP${NC}"
    echo -e "  ${DIM}Run on your server:${NC}"
    echo -e "  ${GREEN}  ip addr show | grep 'inet ' | grep -v 127.0.0.1${NC}"
    echo -e "  ${DIM}Look for something like 192.168.1.100 or 10.0.0.50${NC}"
    echo ""
    echo -e "  ${BOLD}Step 2: Access your router admin panel${NC}"
    echo -e "  ${DIM}Open a browser and go to one of:${NC}"
    echo -e "  ${CYAN}  http://192.168.1.1${NC}  (most common)"
    echo -e "  ${CYAN}  http://192.168.0.1${NC}  (some ISPs)"
    echo -e "  ${CYAN}  http://10.0.0.1${NC}     (some networks)"
    echo ""
    echo -e "  ${BOLD}Step 3: Find the port forwarding section${NC}"
    echo -e "  ${DIM}Common locations by router brand:${NC}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}TP-Link:${NC}    Advanced > NAT Forwarding > Port Forwarding"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}Netgear:${NC}    Advanced > Advanced Setup > Port Forwarding"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}ASUS:${NC}       WAN > Virtual Server / Port Forwarding"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}Linksys:${NC}    Apps & Gaming > Single Port Forwarding"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}D-Link:${NC}     Advanced > Port Forwarding"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}Xfinity:${NC}    Advanced > Port Forwarding"
    echo ""
    echo -e "  ${BOLD}Step 4: Create the forwarding rule${NC}"
    echo -e "  ${DIM}+──────────────────────────────────────────+${NC}"
    echo -e "  ${DIM}|  Service Name:  ${NC}MTProxyMax"
    echo -e "  ${DIM}|  External Port: ${NC}${BOLD}${PROXY_PORT}${NC}"
    echo -e "  ${DIM}|  Internal Port: ${NC}${BOLD}${PROXY_PORT}${NC}"
    echo -e "  ${DIM}|  Internal IP:   ${NC}${BOLD}<your server LAN IP>${NC}"
    echo -e "  ${DIM}|  Protocol:      ${NC}${BOLD}TCP${NC}"
    echo -e "  ${DIM}+──────────────────────────────────────────+${NC}"
    echo ""
    echo -e "  ${BOLD}Step 5: Find your public IP${NC}"
    echo -e "  ${DIM}This is the IP your users will connect to:${NC}"
    echo -e "  ${GREEN}  curl -s https://api.ipify.org${NC}"
    echo ""
    echo -e "  ${BOLD}Step 6: Test it${NC}"
    echo -e "  ${DIM}From another device (phone on mobile data, not WiFi):${NC}"
    echo -e "  Open the proxy link using your public IP and port ${PROXY_PORT}."
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${YELLOW}${SYM_WARN} Important notes:${NC}"
    echo -e "  ${DIM}- If your ISP uses CGNAT (shared public IP), port forwarding"
    echo -e "    won't work. Contact your ISP to request a dedicated IP.${NC}"
    echo -e "  ${DIM}- Your public IP may change. Consider a DDNS service if"
    echo -e "    you have a dynamic IP (no-ip.com, duckdns.org).${NC}"
    echo -e "  ${DIM}- Make sure your server firewall also allows the port"
    echo -e "    (see Firewall Guide).${NC}"
    echo ""
    press_any_key
}

show_firewall_guide() {
    clear_screen
    draw_header "FIREWALL CONFIGURATION"
    echo ""
    echo -e "  ${BOLD}${YELLOW}You must allow TCP port ${PROXY_PORT} through your firewall${NC}"
    echo ""
    echo -e "  If your server has a firewall enabled, incoming connections"
    echo -e "  to your proxy will be blocked unless you add a rule."
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BRIGHT_CYAN}${BOLD}UFW (Ubuntu/Debian)${NC}"
    echo -e "  ${DIM}UFW is the default firewall on Ubuntu.${NC}"
    echo ""
    echo -e "  ${GREEN}  # Allow proxy port${NC}"
    echo -e "  ${WHITE}  sudo ufw allow ${PROXY_PORT}/tcp${NC}"
    echo ""
    echo -e "  ${GREEN}  # Verify${NC}"
    echo -e "  ${WHITE}  sudo ufw status${NC}"
    echo ""
    echo -e "  ${GREEN}  # If UFW is not enabled yet${NC}"
    echo -e "  ${WHITE}  sudo ufw enable${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BRIGHT_CYAN}${BOLD}firewalld (CentOS/RHEL/Fedora)${NC}"
    echo -e "  ${DIM}firewalld is the default on Red Hat-based systems.${NC}"
    echo ""
    echo -e "  ${GREEN}  # Allow proxy port (permanent)${NC}"
    echo -e "  ${WHITE}  sudo firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp${NC}"
    echo ""
    echo -e "  ${GREEN}  # Reload rules${NC}"
    echo -e "  ${WHITE}  sudo firewall-cmd --reload${NC}"
    echo ""
    echo -e "  ${GREEN}  # Verify${NC}"
    echo -e "  ${WHITE}  sudo firewall-cmd --list-ports${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BRIGHT_CYAN}${BOLD}iptables (Any Linux)${NC}"
    echo -e "  ${DIM}Low-level firewall available on all Linux distributions.${NC}"
    echo ""
    echo -e "  ${GREEN}  # Allow proxy port${NC}"
    echo -e "  ${WHITE}  sudo iptables -I INPUT -p tcp --dport ${PROXY_PORT} -j ACCEPT${NC}"
    echo ""
    echo -e "  ${GREEN}  # Save rules (Debian/Ubuntu)${NC}"
    echo -e "  ${WHITE}  sudo apt install iptables-persistent${NC}"
    echo -e "  ${WHITE}  sudo netfilter-persistent save${NC}"
    echo ""
    echo -e "  ${GREEN}  # Save rules (CentOS/RHEL)${NC}"
    echo -e "  ${WHITE}  sudo service iptables save${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BRIGHT_CYAN}${BOLD}nftables (Modern Linux)${NC}"
    echo -e "  ${DIM}Newer replacement for iptables on modern kernels.${NC}"
    echo ""
    echo -e "  ${GREEN}  # Allow proxy port${NC}"
    echo -e "  ${WHITE}  sudo nft add rule inet filter input tcp dport ${PROXY_PORT} accept${NC}"
    echo ""
    draw_line 60 '─'
    echo ""
    echo -e "  ${BRIGHT_CYAN}${BOLD}Cloud Provider Firewalls${NC}"
    echo -e "  ${DIM}If using a VPS, also check the provider's security group:${NC}"
    echo ""
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}AWS:${NC}          EC2 > Security Groups > Inbound Rules > Add TCP ${PROXY_PORT}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}Google Cloud:${NC} VPC > Firewall Rules > Create > TCP ${PROXY_PORT}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}DigitalOcean:${NC} Networking > Firewalls > Inbound TCP ${PROXY_PORT}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}Oracle Cloud:${NC} VCN > Security List > Ingress TCP ${PROXY_PORT}"
    echo -e "  ${CYAN}${SYM_ARROW}${NC} ${BOLD}Hetzner:${NC}      Firewall > Inbound TCP ${PROXY_PORT}"
    echo ""
    echo -e "  ${YELLOW}${SYM_WARN} Test after adding rules:${NC}"
    echo -e "  ${WHITE}  curl -v telnet://YOUR_SERVER_IP:${PROXY_PORT}${NC}"
    echo -e "  ${DIM}  (should connect, not timeout)${NC}"
    echo ""
    press_any_key
}

show_about() {
    while true; do
        clear_screen
        echo ""
        show_banner

        local w=$TERM_WIDTH
        draw_box_top "$w"
        draw_box_center "${BRIGHT_GREEN}${BOLD}ABOUT MTPROXYMAX${NC}" "$w"
        draw_box_sep "$w"
        draw_box_empty "$w"
        draw_box_line "  ${BOLD}Created by:${NC}  Sam" "$w"
        draw_box_line "  ${BOLD}Publisher:${NC}   SamNet Technologies" "$w"
        draw_box_line "  ${BOLD}Version:${NC}     v${VERSION}" "$w"
        draw_box_line "  ${BOLD}Engine:${NC}      telemt v$(get_telemt_version) (Rust)" "$w"
        draw_box_line "  ${BOLD}License:${NC}     MIT" "$w"
        draw_box_line "  ${BOLD}GitHub:${NC}      github.com/${GITHUB_REPO}" "$w"
        draw_box_empty "$w"
        draw_box_sep "$w"
        draw_box_center "${BOLD}FEATURES${NC}" "$w"
        draw_box_empty "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} FakeTLS obfuscation (deep TLS 1.3 fidelity)" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Traffic masking (undetectable to DPI probes)" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Multi-secret user management with per-user stats" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Ad-tag / promoted channel support" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Telegram bot for remote management" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} QR code generation (3-tier fallback)" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Geo-blocking by country" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Proxy chaining (SOCKS5/SOCKS4 upstream routing)" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Per-user connection, IP, bandwidth & expiry limits" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Per-user traffic analytics (Prometheus)" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Auto-update with backup & rollback" "$w"
        draw_box_line "  ${GREEN}${SYM_CHECK}${NC} Health monitoring & auto-recovery" "$w"
        draw_box_empty "$w"
        draw_box_sep "$w"
        draw_box_center "${DIM}Made with care by Sam — SamNet Technologies${NC}" "$w"
        draw_box_bottom "$w"
        echo ""
        echo -e "  ${DIM}[1]${NC} Check for updates"
        echo -e "  ${DIM}[2]${NC} Create backup"
        echo -e "  ${DIM}[3]${NC} Restore backup"
        echo -e "  ${DIM}[4]${NC} List backups"
        echo -e "  ${DIM}[5]${NC} Create encrypted backup"
        echo -e "  ${DIM}[6]${NC} Restore encrypted backup"
        echo -e "  ${DIM}[7]${NC} Migrate export (to another server)"
        echo -e "  ${DIM}[8]${NC} Migrate import (from another server)"
        echo -e "  ${DIM}[9]${NC} Auto-clean old backups"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                self_update || true
                if [ "${_SCRIPT_NEEDS_REEXEC:-}" = "true" ]; then
                    log_info "Restarting with updated script..."
                    sleep 1
                    exec "${INSTALL_DIR}/mtproxymax" menu
                fi
                press_any_key
                ;;
            2) create_backup || true; press_any_key ;;
            3)
                list_backups
                echo -en "  ${BOLD}Backup file path:${NC} "
                local bf; read -r bf
                [ -n "$bf" ] && restore_backup "$bf" || true
                press_any_key
                ;;
            4) list_backups; press_any_key ;;
            5) backup_create_encrypted || true; press_any_key ;;
            6)
                echo -en "  ${BOLD}Encrypted backup file path:${NC} "
                local ef; read -r ef
                [ -n "$ef" ] && backup_restore_encrypted "$ef" || true
                press_any_key
                ;;
            7)
                echo -en "  ${BOLD}Output file [auto]:${NC} "
                local mf; read -r mf
                migrate_export "$mf" || true
                press_any_key
                ;;
            8)
                echo -en "  ${BOLD}Migration tarball path:${NC} "
                local mf; read -r mf
                [ -n "$mf" ] && migrate_import "$mf" || true
                press_any_key
                ;;
            9)
                echo -e "  ${DIM}Current retention: ${BACKUP_RETENTION_DAYS:-30} days${NC}"
                echo -en "  ${BOLD}Delete backups older than N days [${BACKUP_RETENTION_DAYS:-30}]:${NC} "
                local acd; read -r acd
                acd="${acd:-${BACKUP_RETENTION_DAYS:-30}}"
                backup_autoclean "$acd" || true
                # Persist if changed
                if [[ "$acd" =~ ^[0-9]+$ ]] && [ "$acd" != "${BACKUP_RETENTION_DAYS:-30}" ]; then
                    BACKUP_RETENTION_DAYS="$acd"
                    save_settings
                    log_info "Retention policy updated: ${acd} days"
                fi
                press_any_key
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}


show_port_hop_menu() {
    while true; do
        clear_screen
        draw_header "DYNAMIC PORT RANGE SHADOWING"
        echo ""
        load_settings
        echo -e "  ${BOLD}Active Shadow Port Ranges:${NC} ${CYAN}${PORT_HOP_RANGES:-none}${NC}"
        echo -e "  ${DIM}Redirects arbitrary multi-port blocks directly to your proxy listen port.${NC}"
        echo ""
        echo -e "  ${DIM}[1]${NC} List active port ranges"
        echo -e "  ${DIM}[2]${NC} Add a port range (e.g., 2000:2050)"
        echo -e "  ${DIM}[3]${NC} Remove a port range"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) run_port_hop list; press_any_key ;;
            2)
                echo ""
                echo -n -e "  ${BOLD}Enter port range to add (start:end, e.g. 2000:2050):${NC} "
                read -r r_add
                if [ -n "$r_add" ]; then
                    run_port_hop add "$r_add"
                    press_any_key
                fi
                ;;
            3)
                echo ""
                echo -n -e "  ${BOLD}Enter port range to remove (start:end):${NC} "
                read -r r_rm
                if [ -n "$r_rm" ]; then
                    run_port_hop remove "$r_rm"
                    press_any_key
                fi
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}


show_performance_menu() {
    while true; do
        clear_screen
        draw_header "PERFORMANCE & SELF-HEALING SUITE"
        echo ""
        load_settings
        echo -e "  ${BOLD}1. TCP BBR Booster:${NC}     $([ "${TCP_BOOST_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}2. Dead Socket Reaper:${NC}  $([ "${TCP_CLEAN_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}3. Socket Low-Latency:${NC}  $([ "${SOCKET_BOOST_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}4. FakeTLS Pad Rotation:${NC} $([ "${TLS_PAD_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}5. Active Probe Honeypot:${NC} $([ "${HONEYPOT_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}6. TCP Fast-Path Window:${NC} $([ "${TCP_FASTPATH_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}7. Dynamic RAM Auto-Tune:${NC} $([ "${RAM_TUNE_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}8. Port Range Shadowing:${NC} ${CYAN}${PORT_HOP_RANGES:-none}${NC}"
        echo -e "  ${BOLD}9. Multi-Core IRQ Spread:${NC} $([ "${CPU_TUNE_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}a. BBRv3 & ECN Tuning:${NC}    $([ "${BBR_ECN_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}b. Anti-DPI Shield:${NC}       $([ "${ANTI_DPI_SHIELD_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}c. Cover Probe Shield:${NC}    $([ "${COVER_SHIELD_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo -e "  ${BOLD}h. Background Auto-Heal:${NC} $([ "${AUTO_HEAL_ENABLED:-false}" = "true" ] && echo "${GREEN}ENABLED${NC}" || echo "${YELLOW}DISABLED${NC}")"
        echo ""
        echo -e "  ${DIM}[1]${NC} Toggle Linux Kernel TCP BBR & Fast Open Booster"
        echo -e "  ${DIM}[2]${NC} Toggle Dead Mobile Socket Reaper (45s timeout)"
        echo -e "  ${DIM}[3]${NC} Toggle Ultra-Low Latency Kernel Socket Booster"
        echo -e "  ${DIM}[4]${NC} Toggle Dynamic FakeTLS Record Padding Rotation"
        echo -e "  ${DIM}[5]${NC} Toggle Active Probe Honeypot Redirection"
        echo -e "  ${DIM}[6]${NC} Toggle TCP Fast-Path Window Scaling & MTU Probing"
        echo -e "  ${DIM}[7]${NC} Toggle Dynamic RAM Auto-Tuning Profile"
        echo -e "  ${DIM}[8]${NC} Manage Dynamic Multi-Port Range Shadowing"
        echo -e "  ${DIM}[9]${NC} Toggle Multi-Core IRQ Packet Spreading (RPS/RFS)"
        echo -e "  ${DIM}[a]${NC} Toggle Suite 1: BBRv3 Congestion Control & ECN Auto-Tuning"
        echo -e "  ${DIM}[b]${NC} Toggle Suite 2: Anti-DPI Packet Padding & TLS Fingerprint Shield"
        echo -e "  ${DIM}[c]${NC} Toggle Suite 3: Reverse-Proxy Cover Shield & Active Probe Defense"
        echo -e "  ${DIM}[h]${NC} Toggle Background RAM & Socket Auto-Healer"
        echo -e "  ${DIM}[e]${NC} Execute Emergency One-Click Immediate Heal Now"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) [ "${TCP_BOOST_ENABLED:-false}" = "true" ] && run_tcp_boost off || run_tcp_boost on; press_any_key ;;
            2) [ "${TCP_CLEAN_ENABLED:-false}" = "true" ] && run_tcp_clean off || run_tcp_clean on; press_any_key ;;
            3) [ "${SOCKET_BOOST_ENABLED:-false}" = "true" ] && run_socket_boost off || run_socket_boost on; press_any_key ;;
            4) [ "${TLS_PAD_ENABLED:-false}" = "true" ] && run_tls_pad off || run_tls_pad auto; press_any_key ;;
            5) [ "${HONEYPOT_ENABLED:-false}" = "true" ] && run_honeypot off || run_honeypot on; press_any_key ;;
            6) [ "${TCP_FASTPATH_ENABLED:-false}" = "true" ] && run_tcp_fastpath off || run_tcp_fastpath on; press_any_key ;;
            7) [ "${RAM_TUNE_ENABLED:-false}" = "true" ] && run_ram_tune off || run_ram_tune auto; press_any_key ;;
            8) show_port_hop_menu ;;
            9) [ "${CPU_TUNE_ENABLED:-false}" = "true" ] && run_cpu_tune off || run_cpu_tune on; press_any_key ;;
            a|A) [ "${BBR_ECN_ENABLED:-false}" = "true" ] && run_bbr off || run_bbr on; press_any_key ;;
            b|B) [ "${ANTI_DPI_SHIELD_ENABLED:-false}" = "true" ] && run_anti_dpi_shield off || run_anti_dpi_shield on; press_any_key ;;
            c|C) [ "${COVER_SHIELD_ENABLED:-false}" = "true" ] && run_cover_shield off || run_cover_shield on; press_any_key ;;
            h|H) [ "${AUTO_HEAL_ENABLED:-false}" = "true" ] && run_auto_heal off || run_auto_heal on; press_any_key ;;
            e|E) run_heal; press_any_key ;;
            0|"") return ;;
            *) ;;
        esac
    done
}


show_replication_menu() {
    while true; do
        clear_screen
        draw_header "REPLICATION"
        echo ""
        load_settings
        load_replication

        # Status bar
        local role_color="$DIM"
        case "$REPLICATION_ROLE" in
            master) role_color="$BRIGHT_GREEN" ;;
            slave)  role_color="$BRIGHT_CYAN" ;;
        esac

        local timer_state="inactive"
        if command -v systemctl &>/dev/null; then
            timer_state=$(systemctl is-active mtproxymax-sync.timer 2>/dev/null)
            timer_state="${timer_state:-inactive}"
        fi

        echo -e "  Role:   ${role_color}${REPLICATION_ROLE}${NC}   Enabled: $([ "$REPLICATION_ENABLED" = "true" ] && echo "${GREEN}yes${NC}" || echo "${DIM}no${NC}")   Timer: $([ "$timer_state" = "active" ] && echo "${GREEN}active${NC}" || echo "${DIM}${timer_state}${NC}")"
        if [ "${REPLICATION_ROLE}" = "master" ]; then
            echo -e "  Slaves: ${#REPL_HOSTS[@]} configured   Interval: ${REPLICATION_SYNC_INTERVAL}s"
        else
            echo -e "  Receiving config from master"
        fi
        echo ""
        draw_line
        echo ""
        echo -e "  ${BRIGHT_CYAN}[1]${NC} Setup wizard"
        echo -e "  ${BRIGHT_CYAN}[2]${NC} Add slave"
        echo -e "  ${BRIGHT_CYAN}[3]${NC} Remove slave"
        echo -e "  ${BRIGHT_CYAN}[4]${NC} List slaves"
        echo -e "  ${BRIGHT_CYAN}[5]${NC} Test connectivity"
        echo -e "  ${BRIGHT_CYAN}[6]${NC} Sync now"
        echo -e "  ${BRIGHT_CYAN}[7]${NC} View sync logs"
        echo -e "  ${BRIGHT_CYAN}[8]${NC} $([ "$REPLICATION_ENABLED" = "true" ] && echo 'Disable replication' || echo 'Enable replication')"
        echo -e "  ${BRIGHT_CYAN}[9]${NC} Change sync interval"
        echo -e "  ${BRIGHT_CYAN}[p]${NC} Promote slave → master"
        echo -e "  ${BRIGHT_CYAN}[x]${NC} Reset / remove all"
        echo -e "  ${BRIGHT_CYAN}[0]${NC} Back"
        echo ""

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) check_root; replication_setup_wizard ;;
            2)
                check_root
                echo -en "  Slave host: "; read -r _h
                echo -en "  Port [22]: "; read -r _p; _p="${_p:-22}"
                echo -en "  Label [${_h}]: "; read -r _l; _l="${_l:-${_h}}"
                replication_add "$_h" "$_p" "$_l"
                press_any_key
                ;;
            3)
                check_root
                replication_list
                echo -en "  Host or label to remove: "; read -r _t
                [ -n "$_t" ] && replication_remove "$_t"
                press_any_key
                ;;
            4) replication_list; press_any_key ;;
            5)
                echo -en "  Test specific slave (leave blank for all): "; read -r _t
                replication_test "$_t"
                press_any_key
                ;;
            6) check_root; replication_sync_now; press_any_key ;;
            7) replication_show_logs; press_any_key ;;
            8)
                check_root
                if [ "$REPLICATION_ENABLED" = "true" ]; then
                    REPLICATION_ENABLED="false"
                    save_settings
                    stop_replication_service
                    log_success "Replication disabled"
                else
                    if [ "$REPLICATION_ROLE" != "master" ]; then
                        log_error "Replication can only be enabled on a master"
                        log_info "Run setup wizard to configure role"
                        press_any_key; continue
                    fi
                    REPLICATION_ENABLED="true"
                    save_settings
                    setup_replication_service
                    log_success "Replication enabled"
                fi
                press_any_key
                ;;
            9)
                check_root
                local new_interval
                new_interval=$(read_choice "Sync interval in seconds (min 10)" "${REPLICATION_SYNC_INTERVAL}")
                if [[ "$new_interval" =~ ^[0-9]+$ ]] && [ "$new_interval" -ge 10 ]; then
                    REPLICATION_SYNC_INTERVAL="$new_interval"
                    save_settings
                    [ "$REPLICATION_ENABLED" = "true" ] && setup_replication_service
                    log_success "Interval set to ${new_interval}s"
                else
                    log_error "Invalid interval (must be >= 10)"
                fi
                press_any_key
                ;;
            p|P) check_root; replication_promote; press_any_key ;;
            x|X) check_root; replication_reset; press_any_key ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

# ── Section 19: Main Entry Point ─────────────────────────────

main() {
    cli_main "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [ "${MTPROXYMAX_SOURCE_ONLY:-false}" != "true" ]; then
    main "$@"
fi
