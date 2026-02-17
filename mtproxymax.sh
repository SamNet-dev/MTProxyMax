#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  MTProxyMax v1.0 — The Ultimate Telegram Proxy Manager
#  Copyright (c) 2026 SamNet Technologies
#  https://github.com/SamNet-dev/MTProxyMax
#
#  Engine: telemt 3.x (Rust+Tokio) — https://github.com/telemt/telemt
#  License: MIT
# ═══════════════════════════════════════════════════════════════
set -eo pipefail
export LC_NUMERIC=C

# ── Section 1: Initialization ────────────────────────────────
VERSION="1.0.0"
SCRIPT_NAME="mtproxymax"
INSTALL_DIR="/opt/mtproxymax"
CONFIG_DIR="${INSTALL_DIR}/mtproxy"
SETTINGS_FILE="${INSTALL_DIR}/settings.conf"
SECRETS_FILE="${INSTALL_DIR}/secrets.conf"
STATS_DIR="${INSTALL_DIR}/relay_stats"
UPSTREAMS_FILE="${INSTALL_DIR}/upstreams.conf"
BACKUP_DIR="${INSTALL_DIR}/backups"
CONTAINER_NAME="mtproxymax"
DOCKER_IMAGE_BASE="mtproxymax-telemt"
TELEMT_REPO="telemt/telemt"
TELEMT_MIN_VERSION="3.0.0"
TELEMT_COMMIT="43990c9"  # Pinned: ME fixes + Prometheus metrics (post-v3.0.0)
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
PROXY_CPUS="1"
PROXY_MEMORY="256m"
AD_TAG=""
BLOCKLIST_COUNTRIES=""
MASKING_ENABLED="true"
MASKING_HOST=""
MASKING_PORT=443
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_INTERVAL=6
TELEGRAM_ALERTS_ENABLED="true"
TELEGRAM_SERVER_LABEL="MTProxyMax"
AUTO_UPDATE_ENABLED="true"

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
    printf -v str '%*s' "$count" ''
    printf '%s' "${str// /$char}"
}

# Draw a horizontal line
draw_line() {
    local width="${1:-$TERM_WIDTH}" char="${2:-$BOX_H}" color="${3:-$DIM}"
    echo -e "${color}$(_repeat "$char" "$width")${NC}"
}

# Draw top border of a box
draw_box_top() {
    local width="${1:-$TERM_WIDTH}"
    local inner=$((width - 2))
    echo -e "${CYAN}${BOX_TL}$(_repeat "$BOX_H" "$inner")${BOX_TR}${NC}"
}

# Draw bottom border of a box
draw_box_bottom() {
    local width="${1:-$TERM_WIDTH}"
    local inner=$((width - 2))
    echo -e "${CYAN}${BOX_BL}$(_repeat "$BOX_H" "$inner")${BOX_BR}${NC}"
}

# Draw separator in a box
draw_box_sep() {
    local width="${1:-$TERM_WIDTH}"
    local inner=$((width - 2))
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

# Draw a progress bar
draw_progress() {
    local current="$1" total="$2" width="${3:-20}" label="${4:-}"
    local filled empty pct
    if [ "$total" -gt 0 ] 2>/dev/null; then
        pct=$(( (current * 100) / total ))
        filled=$(( (current * width) / total ))
    else
        pct=0
        filled=0
    fi
    [ "$filled" -gt "$width" ] && filled=$width
    empty=$((width - filled))

    local bar_color="$GREEN"
    [ "$pct" -ge 70 ] && bar_color="$YELLOW"
    [ "$pct" -ge 90 ] && bar_color="$RED"

    local bar="${bar_color}$(_repeat '█' "$filled")${DIM}$(_repeat '░' "$empty")${NC}"
    if [ -n "$label" ]; then
        echo -e "  ${label} [${bar}] ${pct}%"
    else
        echo -e "  [${bar}] ${pct}%"
    fi
}

# Draw a sparkline from array of values
draw_sparkline() {
    local -a values=("$@")
    local chars=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    local max=0
    for v in "${values[@]}"; do
        [ "$v" -gt "$max" ] 2>/dev/null && max=$v
    done
    [ "$max" -eq 0 ] && max=1

    local result=""
    for v in "${values[@]}"; do
        local idx=$(( (v * 7) / max ))
        [ "$idx" -gt 7 ] && idx=7
        result+="${chars[$idx]}"
    done
    echo -e "${BRIGHT_CYAN}${result}${NC}"
}

# Prompt for menu choice with retro styling
read_choice() {
    local prompt="${1:-choice}"
    local default="${2:-}"
    echo -en "\n  ${DIM}Enter ${prompt,,}${NC}" >&2
    [ -n "$default" ] && echo -en " ${DIM}[${default}]${NC}" >&2
    echo -en "${DIM}:${NC} " >&2
    local choice
    read -r choice
    [ -z "$choice" ] && choice="$default"
    echo "$choice"
}

# Typing effect for retro banner
typing_effect() {
    local text="$1" delay="${2:-0.01}"
    local i
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep "$delay" 2>/dev/null || true
    done
    echo ""
}

# Press any key prompt
press_any_key() {
    echo ""
    echo -en "  ${DIM}Press any key to continue...${NC}"
    read -rsn1
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
    else
        echo "$(awk -v b="$bytes" 'BEGIN {printf "%.2f", b/1073741824}') GB"
    fi
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

# Format large numbers
format_number() {
    local num=$1
    [ -z "$num" ] || [ "$num" = "0" ] && { echo "0"; return; }
    if [ "$num" -ge 1000000 ] 2>/dev/null; then
        echo "$(awk -v n="$num" 'BEGIN {printf "%.1f", n/1000000}')M"
    elif [ "$num" -ge 1000 ] 2>/dev/null; then
        echo "$(awk -v n="$num" 'BEGIN {printf "%.1f", n/1000}')K"
    else
        echo "$num"
    fi
}

# Escape markdown special characters
escape_md() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//\*/\\*}"
    text="${text//_/\\_}"
    text="${text//\`/\\\`}"
    text="${text//\[/\\[}"
    text="${text//\]/\\]}"
    echo "$text"
}

# Get public IP address
_PUBLIC_IP_CACHE=""
_PUBLIC_IP_CACHE_AGE=0

get_public_ip() {
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
        B)        awk -v n="$num" 'BEGIN {printf "%d", n}' ;;
        K|KB)     awk -v n="$num" 'BEGIN {printf "%d", n * 1024}' ;;
        M|MB)     awk -v n="$num" 'BEGIN {printf "%d", n * 1048576}' ;;
        G|GB)     awk -v n="$num" 'BEGIN {printf "%d", n * 1073741824}' ;;
        T|TB)     awk -v n="$num" 'BEGIN {printf "%d", n * 1099511627776}' ;;
        *)        echo "0"; return 1 ;;
    esac
}

# Compare version strings (returns 0 if $1 >= $2)
version_gte() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# Validate a domain name (reject TOML/shell-unsafe characters)
validate_domain() {
    local d="$1"
    [ -z "$d" ] && return 1
    # Only allow valid hostname chars: letters, digits, dots, hyphens
    [[ "$d" =~ ^[a-zA-Z0-9.-]+$ ]] && [[ "$d" =~ \. ]]
}

# ── Section 5: Settings Persistence ──────────────────────────

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

# Ad-Tag (from @MTProxyBot)
AD_TAG='${AD_TAG}'

# Geo-Blocking
BLOCKLIST_COUNTRIES='${BLOCKLIST_COUNTRIES}'

# Traffic Masking
MASKING_ENABLED='${MASKING_ENABLED}'
MASKING_HOST='${MASKING_HOST}'
MASKING_PORT='${MASKING_PORT}'

# Telegram Integration
TELEGRAM_ENABLED='${TELEGRAM_ENABLED}'
TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'
TELEGRAM_CHAT_ID='${TELEGRAM_CHAT_ID}'
TELEGRAM_INTERVAL='${TELEGRAM_INTERVAL}'
TELEGRAM_ALERTS_ENABLED='${TELEGRAM_ALERTS_ENABLED}'
TELEGRAM_SERVER_LABEL='${TELEGRAM_SERVER_LABEL}'

# Auto-Update
AUTO_UPDATE_ENABLED='${AUTO_UPDATE_ENABLED}'
SETTINGS_EOF

    chmod 600 "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
}

load_settings() {
    [ -f "$SETTINGS_FILE" ] || return 0

    # Safe whitelist-based parsing (no source/eval)
    while IFS= read -r line; do
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
            PROXY_PORT|PROXY_METRICS_PORT|PROXY_DOMAIN|PROXY_CONCURRENCY|\
            PROXY_CPUS|PROXY_MEMORY|AD_TAG|BLOCKLIST_COUNTRIES|\
            MASKING_ENABLED|MASKING_HOST|MASKING_PORT|\
            TELEGRAM_ENABLED|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|\
            TELEGRAM_INTERVAL|TELEGRAM_ALERTS_ENABLED|TELEGRAM_SERVER_LABEL|\
            AUTO_UPDATE_ENABLED)
                printf -v "$key" '%s' "$val"
                ;;
        esac
    done < "$SETTINGS_FILE"

    # Post-load validation for numeric fields
    [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_PORT" -ge 1 ] && [ "$PROXY_PORT" -le 65535 ] || PROXY_PORT=443
    [[ "$PROXY_METRICS_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_METRICS_PORT" -ge 1 ] && [ "$PROXY_METRICS_PORT" -le 65535 ] || PROXY_METRICS_PORT=9090
    [[ "$MASKING_PORT" =~ ^[0-9]+$ ]] && [ "$MASKING_PORT" -ge 1 ] && [ "$MASKING_PORT" -le 65535 ] || MASKING_PORT=443
    [[ "$PROXY_CONCURRENCY" =~ ^[0-9]+$ ]] || PROXY_CONCURRENCY=8192
    [[ "$TELEGRAM_INTERVAL" =~ ^[0-9]+$ ]] || TELEGRAM_INTERVAL=6
    [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]] || TELEGRAM_CHAT_ID=""
}

# Save secrets database
save_secrets() {
    mkdir -p "$INSTALL_DIR"

    local tmp
    tmp=$(_mktemp) || { log_error "Cannot create temp file"; return 1; }

    echo "# MTProxyMax Secrets Database — v${VERSION}" > "$tmp"
    echo "# Format: LABEL|SECRET|CREATED_TS|ENABLED|MAX_CONNS|MAX_IPS|QUOTA_BYTES|EXPIRES" >> "$tmp"
    echo "# DO NOT EDIT MANUALLY — use 'mtproxymax secret' commands" >> "$tmp"

    if [ ${#SECRETS_LABELS[@]} -gt 0 ]; then
        local i
        for i in "${!SECRETS_LABELS[@]}"; do
            echo "${SECRETS_LABELS[$i]}|${SECRETS_KEYS[$i]}|${SECRETS_CREATED[$i]}|${SECRETS_ENABLED[$i]}|${SECRETS_MAX_CONNS[$i]:-0}|${SECRETS_MAX_IPS[$i]:-0}|${SECRETS_QUOTA[$i]:-0}|${SECRETS_EXPIRES[$i]:-0}" >> "$tmp"
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

    if [ -f "$SECRETS_FILE" ]; then
        while IFS='|' read -r label secret created enabled max_conns max_ips quota expires; do
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

    while IFS='|' read -r name type addr user pass weight iface enabled; do
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
            if command -v dnf &>/dev/null; then
                dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null ||
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                dnf install -y docker-ce docker-ce-cli containerd.io
            else
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
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
    local version="3.0.0-${commit}"

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

    cat > "${build_dir}/Dockerfile" << 'DOCKERFILE_EOF'
FROM rust:1-bookworm AS builder
ARG TELEMT_REPO
ARG TELEMT_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*
RUN git clone "https://github.com/${TELEMT_REPO}.git" /build
WORKDIR /build
RUN git checkout "${TELEMT_COMMIT}"
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
        --build-arg "TELEMT_REPO=${TELEMT_REPO}" \
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

# Check if telemt has a newer release available
check_telemt_update() {
    local current
    current=$(get_telemt_version)
    # Strip commit suffix for comparison (3.0.0-43990c9 → 3.0.0)
    local current_base="${current%%-*}"
    local latest
    latest=$(curl -sL --max-time 10 \
        "https://api.github.com/repos/${TELEMT_REPO}/releases/latest" \
        2>/dev/null | grep '"tag_name"' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^"]*')

    # Only notify if release is strictly newer than our base version
    if [ -n "$latest" ] && [ "$latest" != "$current_base" ] && version_gte "$latest" "$current_base"; then
        echo "$latest"
        return 0
    fi
    return 1
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
    local domain_hex
    domain_hex=$(domain_to_hex "$domain")
    echo "ee${raw_secret}${domain_hex}"
}

# Generate telemt config.toml
generate_telemt_config() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    local domain="${PROXY_DOMAIN:-cloudflare.com}"
    local mask_enabled="${MASKING_ENABLED:-true}"
    local mask_host="${MASKING_HOST:-$domain}"
    local mask_port="${MASKING_PORT:-443}"
    local ad_tag="${AD_TAG:-}"
    local port="${PROXY_PORT:-443}"
    local metrics_port="${PROXY_METRICS_PORT:-9090}"

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

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = [$(get_enabled_labels_quoted)]
# public_host = ""
# public_port = ${port}

[server]
port = ${port}
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"
metrics_port = ${metrics_port}
metrics_whitelist = ["127.0.0.1", "::1"]

[timeouts]
client_handshake = 15
tg_connect = 10
client_keepalive = 60
client_ack = 300

[censorship]
tls_domain = "${domain}"
mask = ${mask_enabled}
mask_port = ${mask_port}
$([ "$mask_enabled" = "true" ] && [ -n "$mask_host" ] && echo "mask_host = \"${mask_host}\"")
fake_cert_len = 2048
# Note: geo-blocking is enforced at the host firewall level (iptables/nftables),
# not via telemt config. See: mtproxymax info -> Geo-Blocking

[access]
replay_check_len = 65536
replay_window_secs = 1800
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
    local has_conns=false has_ips=false has_quota=false has_expires=false
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        [ "${SECRETS_MAX_CONNS[$i]:-0}" != "0" ] && has_conns=true
        [ "${SECRETS_MAX_IPS[$i]:-0}" != "0" ] && has_ips=true
        [ "${SECRETS_QUOTA[$i]:-0}" != "0" ] && has_quota=true
        [ "${SECRETS_EXPIRES[$i]:-0}" != "0" ] && has_expires=true
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

    if $has_quota; then
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

    # Append enabled upstream entries
    for i in "${!UPSTREAM_NAMES[@]}"; do
        [ "${UPSTREAM_ENABLED[$i]}" = "true" ] || continue
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

    chmod 644 "$tmp"
    mv "$tmp" "${CONFIG_DIR}/config.toml"
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
    _METRICS_CACHE=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
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

# ── Section 8: Secret Management ─────────────────────────────

# Add a new secret
secret_add() {
    local label="$1" custom_secret="${2:-}"

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

    # Save
    save_secrets

    # Restart if running (run_proxy_container regenerates config)
    if is_proxy_running; then
        restart_proxy_container
    fi

    local full_secret
    full_secret=$(build_faketls_secret "$raw_secret")
    local server_ip
    server_ip=$(get_public_ip)

    log_success "Secret '${label}' created"
    echo ""
    echo -e "  ${BOLD}Proxy Link:${NC}"
    echo -e "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    echo ""
    echo -e "  ${BOLD}Web Link:${NC}"
    echo -e "  ${CYAN}https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    echo ""
}

# Remove a secret
secret_remove() {
    local label="$1" force="${2:-false}"

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
    local -a new_max_conns=() new_max_ips=() new_quota=() new_expires=()
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
    done
    SECRETS_LABELS=("${new_labels[@]}")
    SECRETS_KEYS=("${new_keys[@]}")
    SECRETS_CREATED=("${new_created[@]}")
    SECRETS_ENABLED=("${new_enabled[@]}")
    SECRETS_MAX_CONNS=("${new_max_conns[@]}")
    SECRETS_MAX_IPS=("${new_max_ips[@]}")
    SECRETS_QUOTA=("${new_quota[@]}")
    SECRETS_EXPIRES=("${new_expires[@]}")

    save_secrets

    if is_proxy_running; then
        restart_proxy_container
    fi

    log_success "Secret '${label}' removed"
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
            status_icon="${RED}${SYM_OK}${NC}"
            status_text="${RED}disabled${NC}"
        fi

        # Format creation date
        local created_fmt
        created_fmt=$(date -d "@${created}" '+%Y-%m-%d' 2>/dev/null || date -r "$created" '+%Y-%m-%d' 2>/dev/null || echo "unknown")

        # Get per-user traffic
        local user_stats traffic_in_fmt traffic_out_fmt
        user_stats=$(get_user_stats "$label" 2>/dev/null)
        local u_in u_out
        u_in=$(echo "$user_stats" | awk '{print $1}')
        u_out=$(echo "$user_stats" | awk '{print $2}')
        traffic_in_fmt=$(format_bytes "${u_in:-0}")
        traffic_out_fmt=$(format_bytes "${u_out:-0}")

        printf "  %-4s %-16s ${status_icon} %-8b %-10s %-12s %-12s\n" \
            "$((i+1))" "$label" "$status_text" "$created_fmt" "$traffic_in_fmt" "$traffic_out_fmt"
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

    if is_proxy_running; then
        restart_proxy_container
    fi

    local full_secret
    full_secret=$(build_faketls_secret "$new_secret")
    local server_ip
    server_ip=$(get_public_ip)

    log_success "Secret '${label}' rotated"
    echo ""
    echo -e "  ${BOLD}New Proxy Link:${NC}"
    echo -e "  ${CYAN}tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}${NC}"
    echo ""

    # Notify via Telegram if enabled
    if [ "$TELEGRAM_ENABLED" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local msg="🔄 *Secret Rotated*\n\nLabel: \`${label}\`\n\n🔗 New link:\n\`tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}\`"
        telegram_send_message "$msg" &>/dev/null &
    fi
}

# Enable/disable a secret
secret_toggle() {
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

    if is_proxy_running; then
        restart_proxy_container
    fi

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
    local label="$1" max_conns="${2:-}" max_ips="${3:-}" quota="${4:-}" expires="${5:-}"

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

    if is_proxy_running; then
        restart_proxy_container
    fi

    log_success "Limits updated for '${label}'"
    secret_show_limits "$label"
}

# Show limits for a secret
secret_show_limits() {
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
    printf "  ${BOLD}%-4s %-18s %-8s %-24s %-8s %-10s${NC}\n" "#" "NAME" "TYPE" "ADDRESS" "WEIGHT" "STATUS"
    echo -e "  ${DIM}$(_repeat '─' 76)${NC}"

    local i
    for i in "${!UPSTREAM_NAMES[@]}"; do
        local name="${UPSTREAM_NAMES[$i]}"
        local type="${UPSTREAM_TYPES[$i]}"
        local addr="${UPSTREAM_ADDRS[$i]}"
        local weight="${UPSTREAM_WEIGHTS[$i]}"
        local iface="${UPSTREAM_IFACES[$i]}"
        local enabled="${UPSTREAM_ENABLED[$i]}"
        local status_icon addr_fmt

        [ -z "$addr" ] && addr_fmt="${DIM}—${NC}" || addr_fmt="$addr"
        [ -n "$iface" ] && addr_fmt="${addr_fmt} ${DIM}(${iface})${NC}"

        if [ "$enabled" = "true" ]; then
            status_icon="${GREEN}${SYM_OK} active${NC}"
        else
            status_icon="${RED}${SYM_CROSS} disabled${NC}"
        fi

        printf "  %-4s %-18s %-8s %-24b %-8s %-10b\n" \
            "$((i+1))" "$name" "$type" "$addr_fmt" "$weight" "$status_icon"
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

    local proxy_url
    local proxy_user="${UPSTREAM_USERS[$idx]}"
    local proxy_pass="${UPSTREAM_PASSES[$idx]}"

    if [ "$type" = "socks4" ] && [ -n "$proxy_user" ]; then
        # SOCKS4 uses user_id only (no password)
        proxy_url="socks4://${proxy_user}@${addr}"
    elif [ -n "$proxy_user" ] && [ -n "$proxy_pass" ]; then
        proxy_url="${type}://${proxy_user}:${proxy_pass}@${addr}"
    elif [ -n "$proxy_user" ]; then
        proxy_url="${type}://${proxy_user}@${addr}"
    else
        proxy_url="${type}://${addr}"
    fi

    # socks5 -> socks5h for remote DNS resolution
    proxy_url="${proxy_url/socks5:\/\//socks5h:\/\/}"

    local result
    if result=$(curl -sf --max-time 15 "${iface_opt[@]}" -x "$proxy_url" https://api.ipify.org 2>/dev/null) && [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_success "${type} proxy OK — Exit IP: ${result}"
    else
        log_error "${type} proxy at ${addr} failed"
        return 1
    fi
}

# ── Section 9: Container Management ─────────────────────────

is_proxy_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$" || return 1
    return 0
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

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --network host \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        --cpus "${PROXY_CPUS}" \
        --memory "${PROXY_MEMORY}" \
        --memory-swap "${PROXY_MEMORY}" \
        -v "${CONFIG_DIR}/config.toml:/etc/telemt.toml:ro" \
        "$(get_docker_image)" /etc/telemt.toml \
        &>/dev/null || {
            log_error "Failed to start container"
            return 1
        }

    # Wait for startup
    sleep 2

    if is_proxy_running; then
        log_success "Proxy is running on port ${PROXY_PORT}"
        traffic_tracking_setup
        geoblock_reapply_all

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
        if docker stop --timeout 10 "$CONTAINER_NAME" 2>/dev/null; then
            traffic_tracking_teardown
            log_success "Proxy stopped"
        else
            log_error "Failed to stop proxy"
            return 1
        fi
    else
        log_info "Proxy is not running"
    fi
}

start_proxy_container() {
    if is_proxy_running; then
        log_info "Proxy is already running"
        return 0
    fi

    # Always recreate container to ensure settings (port, memory, cpus) are current
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    run_proxy_container
}

restart_proxy_container() {
    stop_proxy_container 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    run_proxy_container
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
    start_epoch=$(date -d "${started_at}" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    [ "$start_epoch" -gt 0 ] 2>/dev/null && echo $((now_epoch - start_epoch)) || echo "0"
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
    elif docker run --rm -e QR_DATA="$link" alpine:latest sh -c 'apk add --no-cache qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$QR_DATA"' 2>/dev/null | sed 's/^/  /'; then
        :
    else
        echo ""
        echo -e "  ${YELLOW}QR code not available (install qrencode for QR support)${NC}"
        echo -e "  ${DIM}Install: apt install qrencode${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}Share this link:${NC}"
    echo -e "  ${CYAN}${link}${NC}"
    echo ""
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

    # Add iptables DROP rule if not already present
    if ! iptables -C INPUT -m set --match-set "$setname" src \
        -p tcp --dport "$PROXY_PORT" \
        -m comment --comment "$GEOBLOCK_COMMENT" -j DROP 2>/dev/null; then
        iptables -I INPUT -m set --match-set "$setname" src \
            -p tcp --dport "$PROXY_PORT" \
            -m comment --comment "$GEOBLOCK_COMMENT" -j DROP
    fi

    log_success "Geo-blocking active for ${code^^} (port ${PROXY_PORT})"
}

# Remove iptables rules and ipset for one country
_remove_country_rules() {
    local code="$1"
    local setname="${GEOBLOCK_IPSET_PREFIX}${code}"

    # Remove iptables rule
    iptables -D INPUT -m set --match-set "$setname" src \
        -p tcp --dport "$PROXY_PORT" \
        -m comment --comment "$GEOBLOCK_COMMENT" -j DROP 2>/dev/null || true

    # Destroy ipset
    ipset destroy "$setname" 2>/dev/null || true
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
}

# Remove ALL mtproxymax geoblock rules (called on uninstall)
geoblock_remove_all() {
    # Remove all tagged iptables rules
    if command -v iptables &>/dev/null; then
        iptables-save 2>/dev/null | grep -- "--comment ${GEOBLOCK_COMMENT}" | \
            sed 's/^-A/-D/' | while IFS= read -r rule; do
                iptables $rule 2>/dev/null || true
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

build_blocklist_config() {
    [ -z "$BLOCKLIST_COUNTRIES" ] && return
    geoblock_reapply_all
}

show_geoblock_menu() {
    while true; do
        clear_screen
        draw_header "GEO-BLOCKING"
        echo ""
        echo -e "  ${BOLD}Current blocklist:${NC} ${BLOCKLIST_COUNTRIES:-${DIM}none${NC}}"
        echo ""
        echo -e "  ${DIM}[1]${NC} Add country"
        echo -e "  ${DIM}[2]${NC} Remove country"
        echo -e "  ${DIM}[3]${NC} Clear all"
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
                        log_info "Country '${code}' is already blocked"
                    else
                        _ensure_ipset && _download_country_cidrs "$code" && {
                            [ -z "$BLOCKLIST_COUNTRIES" ] && BLOCKLIST_COUNTRIES="$code" || BLOCKLIST_COUNTRIES="${BLOCKLIST_COUNTRIES},${code}"
                            save_settings
                            _apply_country_rules "$code"
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
                        log_success "Removed ${rm_code^^} — rules and cache cleared"
                    else
                        log_info "Country '${rm_code}' is not in the blocklist"
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
                BLOCKLIST_COUNTRIES=""
                save_settings
                log_success "All geo-blocks cleared"
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

    echo ""
}

auto_recover() {
    if ! is_proxy_running; then
        log_warn "Proxy is down, attempting auto-recovery..."
        start_proxy_container
    fi
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
            log_warn "Another update is already running."
            return 1
        fi
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

    # Regenerate + restart Telegram bot service if script was updated
    if [ "$_script_updated" = true ] && [ "${TELEGRAM_ENABLED:-}" = "true" ]; then
        log_info "Regenerating Telegram bot service..."
        telegram_generate_service_script
        if command -v systemctl &>/dev/null; then
            systemctl restart mtproxymax-telegram.service 2>/dev/null \
                && log_success "Telegram bot service restarted" \
                || log_warn "Telegram restart failed — run: systemctl restart mtproxymax-telegram.service"
        fi
    fi

    # Telemt engine update check
    echo ""
    local _telemt_latest
    _telemt_latest=$(check_telemt_update 2>/dev/null) && {
        local _telemt_cur
        _telemt_cur=$(get_telemt_version)
        log_info "Telemt engine update available: v${_telemt_cur} -> v${_telemt_latest}"
        echo -en "  ${BOLD}Update telemt engine? [y/N]:${NC} "
        local _tconfirm; read -r _tconfirm
        if [ "$_tconfirm" = "y" ] || [ "$_tconfirm" = "Y" ]; then
            build_telemt_image true
            if is_proxy_running; then
                load_secrets
                restart_proxy_container
            fi
        fi
    } || {
        local _tver; _tver=$(get_telemt_version)
        if [ "$_tver" = "unknown" ]; then
            log_warn "Telemt version unknown — try rebuilding with: mtproxymax rebuild"
        else
            log_success "Telemt engine is up to date (v${_tver})"
        fi
    }
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
        2>/dev/null)
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
        >/dev/null 2>&1
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
    response=$(curl -s --max-time 10 -K "$_cfg" 2>/dev/null)
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
        chat_id=$(echo "$response" | grep -oE '"chat"\s*:\s*\{[^}]*"id"\s*:\s*(-?[0-9]+)' | head -1 | grep -oE '-?[0-9]+$')
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

    # Build message with all enabled secrets
    local msg="📱 *MTProxy Started*\n\n"
    local i
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local full_secret
        full_secret=$(build_faketls_secret "${SECRETS_KEYS[$i]}")
        local tg_link="tg://proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}"
        local https_link="https://t.me/proxy?server=${server_ip}&port=${PROXY_PORT}&secret=${full_secret}"
        msg+="🏷 *${SECRETS_LABELS[$i]}*\n"
        msg+="🔗 \`${tg_link}\`\n"
        msg+="🌐 ${https_link}\n\n"
    done

    msg+="📊 Port: ${PROXY_PORT} | Domain: ${PROXY_DOMAIN}\n"
    msg+="_Share the QR code below with users who need access._"

    telegram_send_message "$msg"

    # Send QR for first enabled secret
    for i in "${!SECRETS_LABELS[@]}"; do
        [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
        local https_link
        https_link=$(get_proxy_link_https "${SECRETS_LABELS[$i]}")
        local qr_url
        qr_url=$(generate_qr_url "$https_link")
        telegram_send_photo "$qr_url" "📱 *MTProxy QR Code* — Scan in Telegram to connect"
        break
    done
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
    response=$(curl -s --max-time 10 -K "$_cfg" 2>/dev/null)
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
                PROXY_CPUS|PROXY_MEMORY|MASKING_ENABLED|MASKING_HOST|MASKING_PORT|\
                AD_TAG|BLOCKLIST_COUNTRIES|AUTO_UPDATE_ENABLED|\
                TELEGRAM_ENABLED|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|\
                TELEGRAM_INTERVAL|TELEGRAM_SERVER_LABEL|TELEGRAM_ALERTS_ENABLED)
                    printf -v "$key" '%s' "$val" ;;
            esac
        fi
    done < "$SETTINGS_FILE"
}

# IP cache (refreshed every 5 minutes)
_TG_IP_CACHE=""
_TG_IP_CACHE_AGE=0
get_cached_ip() {
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

# Minimal Telegram send
tg_send() {
    local msg
    msg=$(printf '%b' "$1")   # expand literal \n to real newlines
    local label="${TELEGRAM_SERVER_LABEL:-MTProxyMax}"
    local _ip; _ip=$(get_cached_ip)
    [ -n "$_ip" ] && msg="[$(_esc "$label") | ${_ip}] ${msg}" || msg="[$(_esc "$label")] ${msg}"
    local _cfg=$(mktemp /tmp/.mtproxymax-tg.XXXXXX)
    chmod 600 "$_cfg"
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN" > "$_cfg"
    curl -s --max-time 10 -X POST -K "$_cfg" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null 2>&1
    rm -f "$_cfg"
}

tg_send_photo() {
    local photo="$1" caption="${2:-}"
    local _cfg=$(mktemp /tmp/.mtproxymax-tg.XXXXXX)
    chmod 600 "$_cfg"
    printf 'url = "https://api.telegram.org/bot%s/sendPhoto"\n' "$TELEGRAM_BOT_TOKEN" > "$_cfg"
    curl -s --max-time 15 -X POST -K "$_cfg" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "photo=${photo}" \
        --data-urlencode "caption=[$(_esc "${TELEGRAM_SERVER_LABEL:-MTProxyMax}")] ${caption}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null 2>&1
    rm -f "$_cfg"
}

# Escape Markdown special chars in labels for Telegram
_esc() { local t="$1"; t="${t//_/\\_}"; t="${t//\*/\\*}"; t="${t//\`/\\\`}"; echo "$t"; }

format_bytes() {
    local b=$1; [[ "$b" =~ ^[0-9]+$ ]] || b=0
    [ "$b" -lt 1024 ] 2>/dev/null && echo "${b} B" && return
    [ "$b" -lt 1048576 ] 2>/dev/null && echo "$(awk -v b=$b 'BEGIN{printf "%.1f",b/1024}') KB" && return
    [ "$b" -lt 1073741824 ] 2>/dev/null && echo "$(awk -v b=$b 'BEGIN{printf "%.2f",b/1048576}') MB" && return
    echo "$(awk -v b=$b 'BEGIN{printf "%.2f",b/1073741824}') GB"
}

format_duration() {
    local s=$1; [[ "$s" =~ ^[0-9]+$ ]] || s=0
    local d=$((s/86400)) h=$(((s%86400)/3600)) m=$(((s%3600)/60))
    [ "$d" -gt 0 ] && echo "${d}d ${h}h ${m}m" && return
    [ "$h" -gt 0 ] && echo "${h}h ${m}m" && return
    echo "${m}m"
}

is_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^mtproxymax$"
}

get_stats() {
    local m=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
    [ -z "$m" ] && echo "0 0 0" && return
    local i=$(echo "$m"|awk '/^telemt_user_octets_to_client\{/{s+=$NF}END{printf "%.0f",s}')
    local o=$(echo "$m"|awk '/^telemt_user_octets_from_client\{/{s+=$NF}END{printf "%.0f",s}')
    local c=$(echo "$m"|awk '/^telemt_user_connections_current\{/{s+=$NF}END{printf "%.0f",s}')
    echo "${i:-0} ${o:-0} ${c:-0}"
}

get_uptime() {
    local sa=$(docker inspect --format '{{.State.StartedAt}}' mtproxymax 2>/dev/null)
    [ -z "$sa" ] && echo 0 && return
    local se=$(date -d "$sa" +%s 2>/dev/null || echo 0)
    echo $(( $(date +%s) - se ))
}

get_user_stats_tg() {
    local user="$1" m="${2:-}"
    [ -z "$m" ] && m=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
    [ -z "$m" ] && echo "0 0 0" && return
    local i=$(echo "$m"|awk -v u="$user" '$0 ~ "^telemt_user_octets_to_client\\{.*user=\"" u "\"" {print $NF}')
    local o=$(echo "$m"|awk -v u="$user" '$0 ~ "^telemt_user_octets_from_client\\{.*user=\"" u "\"" {print $NF}')
    local c=$(echo "$m"|awk -v u="$user" '$0 ~ "^telemt_user_connections_current\\{.*user=\"" u "\"" {print $NF}')
    echo "${i:-0} ${o:-0} ${c:-0}"
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
    local _tmp=$(mktemp "${_tdir}/.traffic.XXXXXX" 2>/dev/null) || return
    chmod 600 "$_tmp"
    echo "${_cum_in}|${_cum_out}" > "$_tmp"
    mv "$_tmp" "$TRAFFIC_FILE" 2>/dev/null || { rm -f "$_tmp"; return; }
    _tmp=$(mktemp "${_tdir}/.traffic.XXXXXX" 2>/dev/null) || return
    chmod 600 "$_tmp"
    for _ul in "${!_cum_user_in[@]}"; do
        echo "${_ul}|${_cum_user_in[$_ul]}|${_cum_user_out[$_ul]}" >> "$_tmp"
    done
    mv "$_tmp" "$USER_TRAFFIC_FILE" 2>/dev/null || rm -f "$_tmp"
}

update_traffic() {
    # Fetch metrics once for both global and per-user stats
    local _metrics
    _metrics=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
    local cur_in cur_out
    if [ -n "$_metrics" ]; then
        cur_in=$(echo "$_metrics"|awk '/^telemt_user_octets_to_client\{/{s+=$NF}END{printf "%.0f",s}')
        cur_out=$(echo "$_metrics"|awk '/^telemt_user_octets_from_client\{/{s+=$NF}END{printf "%.0f",s}')
    fi
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

    # Per-user delta tracking (reuse already-fetched metrics)
    while IFS='|' read -r label secret created enabled _mc _mi _q _ex; do
        [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue
        [ "$enabled" != "true" ] && continue
        local us=$(get_user_stats_tg "$label" "$_metrics")
        local ui=$(echo "$us"|awk '{print $1}')
        local uo=$(echo "$us"|awk '{print $2}')
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

get_cum_traffic() { echo "${_cum_in:-0} ${_cum_out:-0}"; }
get_cum_user_traffic() { echo "${_cum_user_in[$1]:-0} ${_cum_user_out[$1]:-0}"; }

process_commands() {
    local offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo "0")
    [[ "$offset" =~ ^[0-9]+$ ]] || offset="0"
    local _cfg=$(mktemp /tmp/.mtproxymax-tg.XXXXXX)
    chmod 600 "$_cfg"
    printf 'url = "https://api.telegram.org/bot%s/getUpdates?offset=%s&timeout=1"\n' "$TELEGRAM_BOT_TOKEN" "$offset" > "$_cfg"
    local updates
    updates=$(curl -s --max-time 15 -K "$_cfg" 2>/dev/null)
    rm -f "$_cfg"
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
except: pass
" 2>/dev/null | while IFS=$'\t' read -r _uid _cid _txt; do
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
        _cid=$(echo "$updates" | grep -oE '"chat"\s*:\s*\{[^}]*"id"\s*:\s*-?[0-9]+' | tail -1 | grep -oE '-?[0-9]+$')
        [ -n "$_text" ] && [ -n "$_cid" ] && [ "$_cid" = "$TELEGRAM_CHAT_ID" ] && {
            _new_offset=${_new_offset:-0}
            _process_cmd "$_new_offset" "$_cid" "$_text"
        }
    fi
}

_process_cmd() {
    local update_id="$1" chat_id="$2" text="$3"
    echo "$((update_id + 1))" > "$OFFSET_FILE"

    # Only respond to our chat
    [ "$chat_id" != "$TELEGRAM_CHAT_ID" ] && return

    case "$text" in
        /mp_status|/mp_status@*)
            load_tg_settings
            if ! is_running; then
                tg_send "📱 *MTProxy Status*\n\n🔴 Status: Stopped"
                return
            fi
            local stats=$(get_stats)
            local conns=$(echo "$stats"|awk '{print $3}')
            local up=$(get_uptime)
            local cum=$(get_cum_traffic)
            local ct_in=$(echo "$cum"|awk '{print $1}')
            local ct_out=$(echo "$cum"|awk '{print $2}')
            tg_send "📱 *MTProxy Status*\n\n🟢 Status: Running\n⏱ Uptime: $(format_duration $up)\n👥 Connections: ${conns}\n📊 Traffic: ↓ $(format_bytes $ct_in) ↑ $(format_bytes $ct_out)\n🔗 Port: ${PROXY_PORT} | Domain: ${PROXY_DOMAIN}"
            ;;
        /mp_secrets|/mp_secrets@*)
            load_tg_settings
            [ ! -f "$SECRETS_FILE" ] && tg_send "📋 No secrets configured." && return
            local msg="📋 *Secrets*\n\n"
            local _sec_metrics
            _sec_metrics=$(curl -s --max-time 2 "http://127.0.0.1:${PROXY_METRICS_PORT:-9090}/metrics" 2>/dev/null)
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex; do
                [[ "$label" =~ ^# ]] && continue
                [ -z "$secret" ] && continue
                local icon="🟢"; [ "$enabled" != "true" ] && icon="🔴"
                local us=$(get_user_stats_tg "$label" "$_sec_metrics")
                local uc=$(echo "$us"|awk '{print $3}')
                local cum_u=$(get_cum_user_traffic "$label")
                local cui=$(echo "$cum_u"|awk '{print $1}')
                local cuo=$(echo "$cum_u"|awk '{print $2}')
                msg+="${icon} *$(_esc "$label")* — ${uc} conn | ↓$(format_bytes $cui) ↑$(format_bytes $cuo)\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            ;;
        /mp_link|/mp_link@*)
            load_tg_settings
            local ip; ip=$(get_cached_ip)
            [ -z "$ip" ] && tg_send "❌ Cannot detect server IP" && return
            local msg="🔗 *Proxy Links*\n\n"
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex; do
                [[ "$label" =~ ^# ]] && continue
                [ -z "$secret" ] && continue
                [ "$enabled" != "true" ] && continue
                local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
                local fs="ee${secret}${dh}"
                msg+="🏷 *$(_esc "$label")*\n\`tg://proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs}\`\n\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            # Send QR for first
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex; do
                [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue; [ "$enabled" != "true" ] && continue
                local dh=$(domain_to_hex "${PROXY_DOMAIN:-cloudflare.com}")
                local fs="ee${secret}${dh}"
                local hl="https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs}"
                local el=$(printf '%s' "$hl" | sed 's/&/%26/g;s/?/%3F/g;s/=/%3D/g;s/:/%3A/g;s|/|%2F|g')
                tg_send_photo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${el}" "📱 Scan in Telegram"
                break
            done < "$SECRETS_FILE"
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
                tg_send "✅ Secret *$(_esc "$label")* created!\n\n🔗 \`tg://proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs}\`\n\n🌐 https://t.me/proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs}"
            else
                tg_send "❌ Failed to add secret '$(_esc "$label")' (may already exist)"
            fi
            ;;
        /mp_remove\ *|/mp_remove@*\ *)
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
                tg_send "✅ Secret *$(_esc "$label")* removed"
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
                tg_send "🔄 Secret *$(_esc "$label")* rotated!\n\n🔗 New link:\n\`tg://proxy?server=${ip}&port=${PROXY_PORT}&secret=${fs}\`"
            else
                tg_send "❌ Secret '$(_esc "$label")' not found"
            fi
            ;;
        /mp_restart|/mp_restart@*)
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
            local cum=$(get_cum_traffic)
            local ct_in=$(echo "$cum"|awk '{print $1}')
            local ct_out=$(echo "$cum"|awk '{print $2}')
            local stats=$(get_stats)
            local conns=$(echo "$stats"|awk '{print $3}')
            local msg="📊 *Traffic Report*\n\n"
            msg+="Total: ↓ $(format_bytes $ct_in) ↑ $(format_bytes $ct_out)\n"
            msg+="Active connections: ${conns}\n\n"
            while IFS='|' read -r label secret created enabled _mc _mi _q _ex; do
                [[ "$label" =~ ^# ]] && continue; [ -z "$secret" ] && continue
                [ "$enabled" != "true" ] && continue
                local cum_u=$(get_cum_user_traffic "$label")
                local cui=$(echo "$cum_u"|awk '{print $1}')
                local cuo=$(echo "$cum_u"|awk '{print $2}')
                msg+="👤 *$(_esc "$label")*: ↓ $(format_bytes $cui) ↑ $(format_bytes $cuo)\n"
            done < "$SECRETS_FILE"
            tg_send "$msg"
            ;;
        /mp_update|/mp_update@*)
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
            while IFS='|' read -r label secret created enabled max_conns max_ips quota expires; do
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
        /mp_help|/mp_help@*)
            tg_send "📋 *MTProxyMax Commands*\n\n/mp\\_status — Proxy status\n/mp\\_secrets — List secrets\n/mp\\_link — Get proxy links + QR\n/mp\\_add <label> — Add secret\n/mp\\_remove <label> — Remove secret\n/mp\\_rotate <label> — Rotate secret\n/mp\\_enable <label> — Enable secret\n/mp\\_disable <label> — Disable secret\n/mp\\_limits — Show user limits\n/mp\\_setlimit — Set user limits\n/mp\\_upstreams — List upstreams\n/mp\\_traffic — Traffic report\n/mp\\_health — Health check\n/mp\\_restart — Restart proxy\n/mp\\_update — Check for updates\n/mp\\_help — This help"
            ;;
    esac
}

# Cleanup trap for temp files
trap 'rm -f /tmp/.mtproxymax-tg.* 2>/dev/null' EXIT

# Main loop
echo "$$" > "$PID_FILE"
mkdir -p "$(dirname "$OFFSET_FILE")"
load_tg_settings
load_traffic

_last_report=0
_report_interval=$(( ${TELEGRAM_INTERVAL:-6} * 3600 ))
_last_health=0
_last_traffic_update=0

while true; do
    load_tg_settings
    _report_interval=$(( ${TELEGRAM_INTERVAL:-6} * 3600 ))
    [ "$TELEGRAM_ENABLED" != "true" ] && sleep 30 && continue

    # Process bot commands
    process_commands 2>/dev/null

    # Update traffic counters every 60 seconds
    _now=$(date +%s)
    if [ $((_now - _last_traffic_update)) -ge 60 ] && is_running; then
        _last_traffic_update=$_now
        update_traffic 2>/dev/null
    fi

    # Health check every 5 minutes
    if [ $((_now - _last_health)) -ge 300 ]; then
        _last_health=$_now
        if [ "$TELEGRAM_ALERTS_ENABLED" = "true" ] && ! is_running; then
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
            stats=$(get_stats)
            conns=$(echo "$stats"|awk '{print $3}')
            up=$(get_uptime)
            cum=$(get_cum_traffic)
            ct_in=$(echo "$cum"|awk '{print $1}')
            ct_out=$(echo "$cum"|awk '{print $2}')
            tg_send "📊 *Periodic Report*\n\n🟢 Running | ⏱ $(format_duration $up)\n👥 Connections: ${conns}\n📊 ↓ $(format_bytes $ct_in) ↑ $(format_bytes $ct_out)"
        fi
    fi

    sleep 30
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
            if [[ "$adtag_input" =~ ^[0-9a-fA-F]{32}$ ]]; then
                AD_TAG="$adtag_input"
            else
                log_warn "Invalid ad-tag (must be 32 hex characters), skipping"
            fi
            ;;
    esac

    # Resource limits
    echo ""
    echo -e "  ${BOLD}Resource limits${NC}"
    echo -en "  ${DIM}Enter CPU cores [1]:${NC} "
    local cpu_input
    read -r cpu_input
    if [ -n "$cpu_input" ]; then
        if [[ "$cpu_input" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            # Ensure minimum 0.1 CPU
            if awk "BEGIN{exit ($cpu_input < 0.1)}" 2>/dev/null; then
                PROXY_CPUS="$cpu_input"
            else
                log_warn "CPU must be at least 0.1, keeping ${PROXY_CPUS:-1}"
            fi
        else
            log_warn "Invalid CPU value (must be a number, e.g. 1, 2, 0.5), keeping ${PROXY_CPUS:-1}"
        fi
    fi

    echo -en "  ${DIM}Enter memory limit [256m]:${NC} "
    local mem_input
    read -r mem_input
    if [ -n "$mem_input" ]; then
        if [[ "$mem_input" =~ ^[0-9]+[bBkKmMgG]?$ ]]; then
            # Default bare numbers to megabytes
            [[ "$mem_input" =~ ^[0-9]+$ ]] && mem_input="${mem_input}m"
            PROXY_MEMORY="$mem_input"
        else
            log_warn "Invalid memory value (e.g. 256m, 1g), keeping ${PROXY_MEMORY:-256m}"
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
    draw_box_center "${BOLD}COMMANDS${NC}" "$w"
    draw_box_empty "$w"
    draw_box_line "  ${GREEN}mtproxymax${NC}              Open management menu" "$w"
    draw_box_line "  ${GREEN}mtproxymax status${NC}       Show proxy status" "$w"
    draw_box_line "  ${GREEN}mtproxymax secret add${NC}   Add a new user" "$w"
    draw_box_line "  ${GREEN}mtproxymax help${NC}         Show all commands" "$w"
    draw_box_empty "$w"
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

    log_info "Removing container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log_info "Removing Docker image..."
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${DOCKER_IMAGE_BASE}:" | xargs -r docker rmi 2>/dev/null || true
    # Clean up dangling build cache from Rust compilation
    docker builder prune -f 2>/dev/null || true

    log_info "Removing files..."
    rm -rf "$INSTALL_DIR"
    rm -f /usr/local/bin/mtproxymax

    echo ""
    log_success "MTProxyMax has been fully uninstalled"
    echo ""
}

# ── Section 17: CLI Dispatcher ──────────────────────────────

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
    echo -e "    ${GREEN}secret remove${NC} <label>   Remove a secret"
    echo -e "    ${GREEN}secret list${NC}             List all secrets"
    echo -e "    ${GREEN}secret rotate${NC} <label>   Rotate a secret"
    echo -e "    ${GREEN}secret link${NC} [label]     Show proxy link"
    echo -e "    ${GREEN}secret qr${NC} [label]       Show QR code"
    echo -e "    ${GREEN}secret enable${NC} <label>   Enable a secret"
    echo -e "    ${GREEN}secret disable${NC} <label>  Disable a secret"
    echo -e "    ${GREEN}secret limits${NC} [label]   Show user limits"
    echo -e "    ${GREEN}secret setlimit${NC} <label> conns|ips|quota|expires <value>"
    echo -e "    ${GREEN}secret setlimits${NC} <label> <conns> <ips> <quota> [expires]"
    echo ""
    echo -e "  ${BOLD}Upstream Routing:${NC}"
    echo -e "    ${GREEN}upstream list${NC}                  List upstreams"
    echo -e "    ${GREEN}upstream add${NC} <name> <type> <addr> [user] [pass] [weight] [iface]"
    echo -e "    ${GREEN}upstream remove${NC} <name>      Remove upstream"
    echo -e "    ${GREEN}upstream enable${NC} <name>      Enable upstream"
    echo -e "    ${GREEN}upstream disable${NC} <name>     Disable upstream"
    echo -e "    ${GREEN}upstream test${NC} <name>        Test connectivity"
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "    ${GREEN}port${NC} [get|<number>]       Show or change proxy port"
    echo -e "    ${GREEN}domain${NC} [get|clear|<host>] Show, clear, or change FakeTLS domain"
    echo -e "    ${GREEN}adtag${NC} [set <hex>|remove|view] Manage ad-tag"
    echo -e "    ${GREEN}geoblock${NC} [add|remove|list|clear] Manage geo-blocking"
    echo ""
    echo -e "  ${BOLD}Monitoring:${NC}"
    echo -e "    ${GREEN}traffic${NC}                 Show traffic stats"
    echo -e "    ${GREEN}logs${NC}                    Stream container logs"
    echo -e "    ${GREEN}health${NC}                  Run health diagnostics"
    echo ""
    echo -e "  ${BOLD}Telegram:${NC}"
    echo -e "    ${GREEN}telegram setup${NC}          Run Telegram bot wizard"
    echo -e "    ${GREEN}telegram status${NC}         Show Telegram bot status"
    echo -e "    ${GREEN}telegram test${NC}           Send test message"
    echo -e "    ${GREEN}telegram disable${NC}        Disable Telegram"
    echo -e "    ${GREEN}telegram remove${NC}         Remove Telegram bot"
    echo ""
    echo -e "  ${BOLD}Info & Help:${NC}"
    echo -e "    ${GREEN}info${NC}                    Open feature info guide"
    echo -e "    ${GREEN}firewall${NC}                Show firewall setup guide"
    echo -e "    ${GREEN}portforward${NC}             Show port forwarding guide"
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

        local stats
        stats=$(get_proxy_stats)
        traffic_in=$(echo "$stats" | awk '{print $1}')
        traffic_out=$(echo "$stats" | awk '{print $2}')
        connections=$(echo "$stats" | awk '{print $3}')
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
            show_status
            ;;

        secret)
            load_settings
            load_secrets
            local subcmd="${1:-list}"
            shift 2>/dev/null || true
            case "$subcmd" in
                add)     check_root; secret_add "$1" "${2:-}" ;;
                remove)  check_root; secret_remove "$1" ;;
                list)    secret_list ;;
                rotate)  check_root; secret_rotate "$1" ;;
                link)    get_proxy_link_https "${1:-}"; echo "" ;;
                qr)      local link; link=$(get_proxy_link_https "${1:-}") && show_qr "$link" ;;
                enable)  check_root; secret_toggle "$1" enable ;;
                disable) check_root; secret_toggle "$1" disable ;;
                limits)  secret_show_limits "$1" ;;
                setlimit)
                    check_root
                    local label="$1"; shift 2>/dev/null || true
                    local field="$1"; shift 2>/dev/null || true
                    local value="$1"
                    if [ -z "$label" ] || [ -z "$field" ] || [ -z "$value" ]; then
                        log_error "Usage: mtproxymax secret setlimit <label> conns|ips|quota|expires <value>"
                        return 1
                    fi
                    case "$field" in
                        conns)   secret_set_limits "$label" "$value" "" "" "" ;;
                        ips)     secret_set_limits "$label" "" "$value" "" "" ;;
                        quota)   secret_set_limits "$label" "" "" "$value" "" ;;
                        expires) secret_set_limits "$label" "" "" "" "$value" ;;
                        *) log_error "Usage: mtproxymax secret setlimit <label> conns|ips|quota|expires <value>"; return 1 ;;
                    esac
                    ;;
                setlimits)
                    check_root
                    local label="$1"; shift 2>/dev/null || true
                    local sl_conns="${1:-0}"; shift 2>/dev/null || true
                    local sl_ips="${1:-0}"; shift 2>/dev/null || true
                    local sl_quota="${1:-0}"; shift 2>/dev/null || true
                    local sl_exp="${1:-}"
                    [ -z "$label" ] && { log_error "Usage: mtproxymax secret setlimits <label> <conns> <ips> <quota> [expires]"; return 1; }
                    secret_set_limits "$label" "$sl_conns" "$sl_ips" "$sl_quota" "$sl_exp"
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
                        save_settings
                        log_success "Domain changed to ${new_domain}"
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

        adtag)
            load_settings
            case "$1" in
                set)
                    check_root
                    if [[ "$2" =~ ^[0-9a-fA-F]{32}$ ]]; then
                        AD_TAG="$2"
                        save_settings
                        log_success "Ad-tag set"
                        is_proxy_running && { load_secrets; restart_proxy_container; }
                    else
                        log_error "Ad-tag must be 32 hex characters"
                        return 1
                    fi
                    ;;
                remove)
                    check_root
                    AD_TAG=""
                    save_settings
                    log_success "Ad-tag removed"
                    is_proxy_running && { load_secrets; restart_proxy_container; }
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

        traffic)
            load_settings
            load_secrets
            echo ""
            draw_header "TRAFFIC"
            local stats
            stats=$(get_proxy_stats)
            local t_in t_out conns
            t_in=$(echo "$stats" | awk '{print $1}')
            t_out=$(echo "$stats" | awk '{print $2}')
            conns=$(echo "$stats" | awk '{print $3}')
            echo ""
            echo -e "  ${BOLD}Total:${NC} ${SYM_DOWN} $(format_bytes "$t_in")  ${SYM_UP} $(format_bytes "$t_out")  ${BOLD}Connections:${NC} ${conns}"
            echo ""

            # Per-user breakdown
            for i in "${!SECRETS_LABELS[@]}"; do
                [ "${SECRETS_ENABLED[$i]}" = "true" ] || continue
                local u_stats
                u_stats=$(get_user_stats "${SECRETS_LABELS[$i]}")
                local u_in u_out u_conns
                u_in=$(echo "$u_stats" | awk '{print $1}')
                u_out=$(echo "$u_stats" | awk '{print $2}')
                u_conns=$(echo "$u_stats" | awk '{print $3}')
                echo -e "  ${GREEN}${SYM_OK}${NC} ${BOLD}${SECRETS_LABELS[$i]}${NC}: ${SYM_DOWN} $(format_bytes "$u_in")  ${SYM_UP} $(format_bytes "$u_out")  conns: ${u_conns}"
            done
            echo ""
            ;;

        logs)
            load_settings
            echo -e "  ${DIM}Streaming logs (Ctrl+C to stop)...${NC}"
            docker logs -f --tail 50 "$CONTAINER_NAME" 2>&1
            ;;

        health)
            load_settings
            load_secrets
            health_check
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
                        echo -e "  ${DIM}Interval: every ${TELEGRAM_INTERVAL}h | Alerts: ${TELEGRAM_ALERTS_ENABLED}${NC}"
                    else
                        echo -e "  ${BOLD}Telegram:${NC} $(draw_status disabled 'Disabled')"
                    fi
                    ;;
                disable)
                    check_root
                    TELEGRAM_ENABLED="false"
                    save_settings
                    systemctl stop mtproxymax-telegram.service 2>/dev/null
                    log_success "Telegram disabled"
                    ;;
                remove)
                    check_root
                    TELEGRAM_ENABLED="false"
                    TELEGRAM_BOT_TOKEN=""
                    TELEGRAM_CHAT_ID=""
                    save_settings
                    systemctl stop mtproxymax-telegram.service 2>/dev/null
                    systemctl disable mtproxymax-telegram.service 2>/dev/null
                    log_success "Telegram bot removed"
                    ;;
                *) log_error "Usage: mtproxymax telegram [setup|test|status|disable|remove]"; return 1 ;;
            esac
            ;;

        info)
            load_settings
            show_info_menu
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
            build_telemt_image true
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
                    echo -e "  ${DIM}Repo:${NC}       https://github.com/${TELEMT_REPO}"
                    echo ""
                    log_info "Checking latest commits..."
                    local head_sha head_msg
                    head_sha=$(curl -sL --max-time 10 \
                        "https://api.github.com/repos/${TELEMT_REPO}/commits/main" 2>/dev/null \
                        | grep '"sha"' | head -1 | cut -d'"' -f4)
                    head_msg=$(curl -sL --max-time 10 \
                        "https://api.github.com/repos/${TELEMT_REPO}/commits/main" 2>/dev/null \
                        | grep '"message"' | head -1 | cut -d'"' -f4)
                    if [ -n "$head_sha" ]; then
                        local head_short="${head_sha:0:7}"
                        if [ "$head_short" = "${TELEMT_COMMIT:0:7}" ]; then
                            log_success "You are on the latest commit"
                        else
                            echo -e "  ${YELLOW}Latest on main:${NC} ${head_short} — ${head_msg}"
                            echo -e "  ${DIM}To update: mtproxymax engine switch ${head_short}${NC}"
                        fi
                    else
                        log_warn "Could not reach GitHub API"
                    fi
                    ;;
                switch)
                    check_root
                    local new_commit="$1"
                    if [ -z "$new_commit" ]; then
                        log_error "Usage: mtproxymax engine switch <commit-hash>"
                        log_info "Example: mtproxymax engine switch 43990c9"
                        return 1
                    fi
                    # Validate commit exists on the repo
                    log_info "Verifying commit ${new_commit}..."
                    local verify
                    verify=$(curl -sL --max-time 10 \
                        "https://api.github.com/repos/${TELEMT_REPO}/commits/${new_commit}" 2>/dev/null \
                        | grep '"sha"' | head -1 | cut -d'"' -f4)
                    if [ -z "$verify" ]; then
                        log_error "Commit '${new_commit}' not found on ${TELEMT_REPO}"
                        return 1
                    fi
                    local verify_short="${verify:0:7}"
                    log_info "Switching engine to commit ${verify_short}..."
                    TELEMT_COMMIT="${verify_short}"
                    # Remove old image so build_telemt_image creates a new one
                    docker rmi "${DOCKER_IMAGE_BASE}:$(get_telemt_version)" 2>/dev/null || true
                    mkdir -p "$INSTALL_DIR"
                    echo "3.0.0-${verify_short}" > "${INSTALL_DIR}/.telemt_version"
                    build_telemt_image true
                    if is_proxy_running; then
                        load_secrets
                        restart_proxy_container
                    fi
                    log_success "Engine switched to commit ${verify_short}"
                    log_info "To make this permanent, update TELEMT_COMMIT in the script"
                    ;;
                latest)
                    check_root
                    log_info "Fetching latest commit from main..."
                    local latest_sha
                    latest_sha=$(curl -sL --max-time 10 \
                        "https://api.github.com/repos/${TELEMT_REPO}/commits/main" 2>/dev/null \
                        | grep '"sha"' | head -1 | cut -d'"' -f4)
                    if [ -z "$latest_sha" ]; then
                        log_error "Cannot reach GitHub API"
                        return 1
                    fi
                    local latest_short="${latest_sha:0:7}"
                    if [ "$latest_short" = "${TELEMT_COMMIT:0:7}" ]; then
                        log_success "Already on the latest commit (${latest_short})"
                        return 0
                    fi
                    log_info "Switching to latest: ${latest_short}..."
                    TELEMT_COMMIT="${latest_short}"
                    docker rmi "${DOCKER_IMAGE_BASE}:$(get_telemt_version)" 2>/dev/null || true
                    mkdir -p "$INSTALL_DIR"
                    echo "3.0.0-${latest_short}" > "${INSTALL_DIR}/.telemt_version"
                    build_telemt_image true
                    if is_proxy_running; then
                        load_secrets
                        restart_proxy_container
                    fi
                    log_success "Engine updated to latest commit (${latest_short})"
                    ;;
                *)
                    echo -e "  ${BOLD}Usage:${NC} mtproxymax engine <command>"
                    echo ""
                    echo -e "  ${DIM}status${NC}            Show current engine version and check for updates"
                    echo -e "  ${DIM}switch <commit>${NC}   Switch to a specific commit"
                    echo -e "  ${DIM}latest${NC}            Switch to the latest commit on main"
                    ;;
            esac
            ;;

        uninstall)
            check_root
            load_settings
            load_secrets
            uninstall
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

show_security_menu() {
    while true; do
        clear_screen
        draw_header "SECURITY & ROUTING"
        echo ""
        echo -e "  ${DIM}[1]${NC} Geo-Blocking"
        echo -e "  ${DIM}[2]${NC} Proxy Chaining (Upstreams)"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) show_geoblock_menu ;;
            2) show_upstream_menu ;;
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
                _cached_start_epoch=$(date -d "${started_at}" +%s 2>/dev/null || echo "0")
            fi
            local up_secs=$(( $(date +%s) - _cached_start_epoch ))
            uptime_str=$(format_duration "$up_secs")
            # Parse all stats fields in a single read (no awk subprocesses)
            read -r traffic_in traffic_out connections < <(get_proxy_stats)
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
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) start_proxy_container || true; press_any_key ;;
            2) stop_proxy_container || true; press_any_key ;;
            3) restart_proxy_container || true; press_any_key ;;
            4) echo -e "  ${DIM}Press Ctrl+C to stop...${NC}"; docker logs -f --tail 30 "$CONTAINER_NAME" 2>&1 || true; press_any_key ;;
            5) health_check || true; press_any_key ;;
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
                echo -en "  ${BOLD}Label to remove:${NC} "
                local label
                read -r label
                [ -n "$label" ] && { secret_remove "$label" || true; }
                press_any_key
                ;;
            3)
                echo -en "  ${BOLD}Label to rotate:${NC} "
                local label
                read -r label
                [ -n "$label" ] && { secret_rotate "$label" || true; }
                press_any_key
                ;;
            4)
                echo -en "  ${BOLD}Label to toggle:${NC} "
                local label
                read -r label
                [ -n "$label" ] && { secret_toggle "$label" || true; }
                press_any_key
                ;;
            5)
                secret_show_limits
                echo ""
                echo -en "  ${BOLD}Label to set limits:${NC} "
                local label
                read -r label
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
            echo -e "  ${DIM}Interval: every ${TELEGRAM_INTERVAL}h | Alerts: ${TELEGRAM_ALERTS_ENABLED}${NC}"
        else
            echo -e "  Status: $(draw_status disabled 'Disabled')"
        fi
        echo ""
        echo -e "  ${DIM}[1]${NC} Setup wizard"
        echo -e "  ${DIM}[2]${NC} Send test message"
        echo -e "  ${DIM}[3]${NC} Send proxy links"
        echo -e "  ${DIM}[4]${NC} Toggle notifications"
        echo -e "  ${DIM}[5]${NC} Toggle alerts"
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
                    systemctl stop mtproxymax-telegram.service 2>/dev/null
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
        echo -e "  ${BOLD}Domain:${NC}      ${PROXY_DOMAIN}"
        echo -e "  ${BOLD}CPU:${NC}         ${PROXY_CPUS} cores"
        echo -e "  ${BOLD}Memory:${NC}      ${PROXY_MEMORY}"
        echo -e "  ${BOLD}Masking:${NC}     ${MASKING_ENABLED}"
        echo -e "  ${BOLD}Ad-tag:${NC}      ${AD_TAG:-${DIM}not set${NC}}"
        echo -e "  ${BOLD}Auto-update:${NC} ${AUTO_UPDATE_ENABLED}"
        echo -e "  ${BOLD}Engine:${NC}      telemt v$(get_telemt_version)"
        echo ""
        echo -e "  ${DIM}[1]${NC} Change port"
        echo -e "  ${DIM}[2]${NC} Change domain"
        echo -e "  ${DIM}[3]${NC} Change resources (CPU/RAM)"
        echo -e "  ${DIM}[4]${NC} Toggle traffic masking"
        echo -e "  ${DIM}[5]${NC} Set ad-tag"
        echo -e "  ${DIM}[6]${NC} Toggle auto-update"
        echo -e "  ${DIM}[7]${NC} Engine Management"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                echo -en "  ${BOLD}New port:${NC} "
                local p; read -r p
                if validate_port "$p"; then
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
                    save_settings
                    log_success "Domain set to ${PROXY_DOMAIN}"
                    if is_proxy_running; then
                        echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                        local r; read -r r
                        [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                    fi
                fi
                press_any_key
                ;;
            3)
                echo -en "  ${BOLD}CPU cores [${PROXY_CPUS}]:${NC} "
                local c; read -r c
                local _res_changed=false
                if [ -n "$c" ]; then
                    if [[ "$c" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk "BEGIN{exit ($c < 0.1)}" 2>/dev/null; then
                        PROXY_CPUS="$c"; _res_changed=true
                    else
                        log_error "Invalid CPU value (must be a number >= 0.1, e.g. 1, 2, 0.5)"
                    fi
                fi
                echo -en "  ${BOLD}Memory [${PROXY_MEMORY}]:${NC} "
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
            4)
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
            5)
                echo -en "  ${BOLD}Ad-tag (32 hex chars, or 'remove'):${NC} "
                local at; read -r at
                if [ "$at" = "remove" ]; then
                    AD_TAG=""
                    log_success "Ad-tag removed"
                    save_settings
                elif [[ "$at" =~ ^[0-9a-fA-F]{32}$ ]]; then
                    AD_TAG="$at"
                    log_success "Ad-tag set"
                    save_settings
                else
                    log_error "Invalid ad-tag (must be 32 hex characters)"
                    press_any_key; continue
                fi
                if is_proxy_running; then
                    echo -en "  ${DIM}Restart proxy now? [Y/n]:${NC} "
                    local r; read -r r
                    [[ ! "$r" =~ ^[nN] ]] && { load_secrets; restart_proxy_container || true; }
                fi
                press_any_key
                ;;
            6)
                [ "$AUTO_UPDATE_ENABLED" = "true" ] && AUTO_UPDATE_ENABLED="false" || AUTO_UPDATE_ENABLED="true"
                save_settings
                log_success "Auto-update: ${AUTO_UPDATE_ENABLED}"
                press_any_key
                ;;
            7) show_engine_menu ;;
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
        echo -e "  ${BOLD}Repo:${NC}      ${DIM}github.com/${TELEMT_REPO}${NC}"
        echo ""
        echo -e "  ${DIM}[1]${NC} Check for new commits"
        echo -e "  ${DIM}[2]${NC} Update to latest commit"
        echo -e "  ${DIM}[3]${NC} Switch to specific commit"
        echo -e "  ${DIM}[4]${NC} Force rebuild current"
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1)
                log_info "Checking latest commit on main..."
                local head_info
                head_info=$(curl -sL --max-time 10 \
                    "https://api.github.com/repos/${TELEMT_REPO}/commits/main" 2>/dev/null)
                local head_sha head_msg
                head_sha=$(echo "$head_info" | grep '"sha"' | head -1 | cut -d'"' -f4)
                head_msg=$(echo "$head_info" | grep '"message"' | head -1 | cut -d'"' -f4)
                if [ -n "$head_sha" ]; then
                    local head_short="${head_sha:0:7}"
                    echo ""
                    echo -e "  ${BOLD}Latest:${NC}  ${head_short} — ${head_msg}"
                    echo -e "  ${BOLD}Current:${NC} ${TELEMT_COMMIT}"
                    echo ""
                    if [ "$head_short" = "${TELEMT_COMMIT:0:7}" ]; then
                        log_success "You are on the latest commit"
                    else
                        echo -e "  ${YELLOW}New commit available!${NC}"
                        echo -e "  ${DIM}Use option [2] to update${NC}"
                    fi
                else
                    log_error "Could not reach GitHub API"
                fi
                press_any_key
                ;;
            2)
                log_info "Fetching latest commit from main..."
                local latest_sha
                latest_sha=$(curl -sL --max-time 10 \
                    "https://api.github.com/repos/${TELEMT_REPO}/commits/main" 2>/dev/null \
                    | grep '"sha"' | head -1 | cut -d'"' -f4)
                if [ -z "$latest_sha" ]; then
                    log_error "Cannot reach GitHub API"
                    press_any_key; continue
                fi
                local latest_short="${latest_sha:0:7}"
                if [ "$latest_short" = "${TELEMT_COMMIT:0:7}" ]; then
                    log_success "Already on the latest commit (${latest_short})"
                    press_any_key; continue
                fi
                echo -e "  ${BOLD}Update engine to commit ${latest_short}?${NC}"
                echo -en "  ${DIM}This will rebuild and restart the proxy [Y/n]:${NC} "
                local confirm; read -r confirm
                if [[ "$confirm" =~ ^[nN] ]]; then
                    press_any_key; continue
                fi
                TELEMT_COMMIT="${latest_short}"
                docker rmi "${DOCKER_IMAGE_BASE}:$(get_telemt_version)" 2>/dev/null || true
                mkdir -p "$INSTALL_DIR"
                echo "3.0.0-${latest_short}" > "${INSTALL_DIR}/.telemt_version"
                build_telemt_image true
                if is_proxy_running; then
                    load_secrets
                    restart_proxy_container || true
                fi
                log_success "Engine updated to commit ${latest_short}"
                press_any_key
                ;;
            3)
                echo -en "  ${BOLD}Enter commit hash:${NC} "
                local new_commit; read -r new_commit
                if [ -z "$new_commit" ]; then
                    press_any_key; continue
                fi
                log_info "Verifying commit ${new_commit}..."
                local verify
                verify=$(curl -sL --max-time 10 \
                    "https://api.github.com/repos/${TELEMT_REPO}/commits/${new_commit}" 2>/dev/null \
                    | grep '"sha"' | head -1 | cut -d'"' -f4)
                if [ -z "$verify" ]; then
                    log_error "Commit '${new_commit}' not found on ${TELEMT_REPO}"
                    press_any_key; continue
                fi
                local verify_short="${verify:0:7}"
                echo -e "  ${BOLD}Switch engine to commit ${verify_short}?${NC}"
                echo -en "  ${DIM}This will rebuild and restart the proxy [Y/n]:${NC} "
                local confirm; read -r confirm
                if [[ "$confirm" =~ ^[nN] ]]; then
                    press_any_key; continue
                fi
                TELEMT_COMMIT="${verify_short}"
                docker rmi "${DOCKER_IMAGE_BASE}:$(get_telemt_version)" 2>/dev/null || true
                mkdir -p "$INSTALL_DIR"
                echo "3.0.0-${verify_short}" > "${INSTALL_DIR}/.telemt_version"
                build_telemt_image true
                if is_proxy_running; then
                    load_secrets
                    restart_proxy_container || true
                fi
                log_success "Engine switched to commit ${verify_short}"
                press_any_key
                ;;
            4)
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

    local stats
    stats=$(get_proxy_stats)
    local t_in t_out conns
    t_in=$(echo "$stats" | awk '{print $1}')
    t_out=$(echo "$stats" | awk '{print $2}')
    conns=$(echo "$stats" | awk '{print $3}')

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
        local u_stats
        u_stats=$(get_user_stats "${SECRETS_LABELS[$i]}")
        local u_in u_out u_conns
        u_in=$(echo "$u_stats" | awk '{print $1}')
        u_out=$(echo "$u_stats" | awk '{print $2}')
        u_conns=$(echo "$u_stats" | awk '{print $3}')
        echo -e "  ${GREEN}${SYM_OK}${NC} ${BOLD}${SECRETS_LABELS[$i]}${NC}"
        echo -e "    ${SYM_DOWN} $(format_bytes "$u_in")  ${SYM_UP} $(format_bytes "$u_out")  conns: ${u_conns}"
    done

    echo ""
    echo -e "  ${DIM}[1]${NC} Stream live logs"
    echo -e "  ${DIM}[0]${NC} Back"

    local choice
    choice=$(read_choice "Choice" "0")
    case "$choice" in
        1) echo -e "  ${DIM}Press Ctrl+C to stop...${NC}"; docker logs -f --tail 30 "$CONTAINER_NAME" 2>&1 || true ;;
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
    echo -e "  ${GREEN}mtproxymax secret remove <label>${NC}   Delete a secret"
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
        echo -e "  ${DIM}[0]${NC} Back"

        local choice
        choice=$(read_choice "Choice" "0")
        case "$choice" in
            1) self_update || true; press_any_key ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

# ── Section 19: Main Entry Point ─────────────────────────────

main() {
    cli_main "$@"
}

main "$@"
