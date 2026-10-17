#!/bin/bash
# Exercise image acquisition without Docker, networking, or sourcing the manager.
set -euo pipefail
repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
eval "$(sed -n '/^build_telemt_image() {$/,/^# Get installed telemt version/p' "$repo/mtproxymax.sh" | sed '$d')"
eval "$(sed -n '/^TELEMT_MIN_VERSION=/p; /^TELEMT_COMMIT=/p; /^DOCKER_IMAGE_BASE=/p; /^REGISTRY_IMAGE=/p' "$repo/mtproxymax.sh")"
version="${TELEMT_MIN_VERSION}-${TELEMT_COMMIT}"
INSTALL_DIR="$tmp/install"
declare -a _TEMP_FILES=()
log_info() { :; }
log_warn() { :; }
log_success() { :; }
log_error() { :; }
docker() {
    printf '%s\n' "$*" >> "$tmp/calls"
    case "$1" in
        image) return "$cached" ;;
        pull) return "$pull_result" ;;
        tag) return "$tag_result" ;;
        build)
            cp "${@: -1}/Dockerfile" "$tmp/Dockerfile"
            return "$build_result" ;;
        *) echo "Unexpected Docker operation: $*" >&2; return 99 ;;
    esac
}
reset_case() {
    cached=1 pull_result=1 tag_result=0 build_result=0
    mkdir -p "$INSTALL_DIR"
    printf 'previous\n' > "$INSTALL_DIR/.telemt_version"
    : > "$tmp/calls"
}
assert_marker() { test "$(cat "$INSTALL_DIR/.telemt_version")" = "$1"; }
assert_no_latest_pull() { ! grep -q "pull ${REGISTRY_IMAGE}:latest" "$tmp/calls"; }

reset_case
cached=0
build_telemt_image
test "$(wc -l < "$tmp/calls")" -eq 1
assert_marker previous

reset_case
pull_result=0
build_telemt_image
grep -q "pull ${REGISTRY_IMAGE}:${version}" "$tmp/calls"
! grep -q '^build ' "$tmp/calls"
assert_marker "$version"

reset_case
build_telemt_image
assert_no_latest_pull
grep -q "^build --build-arg TELEMT_COMMIT=${TELEMT_COMMIT} " "$tmp/calls"
assert_marker "$version"
grep -Fq 'RUN git checkout --detach "${TELEMT_COMMIT}" && test "$(git rev-parse HEAD)" = "${TELEMT_COMMIT}"' "$tmp/Dockerfile"
grep -Fq 'cargo build --release --locked' "$tmp/Dockerfile"

reset_case
cached=0 pull_result=0
build_telemt_image source
! grep -Eq '^(image|pull) ' "$tmp/calls"
grep -q '^build ' "$tmp/calls"
assert_marker "$version"

reset_case
cached=0 pull_result=0
build_telemt_image true
! grep -q '^image ' "$tmp/calls"
assert_marker "$version"

reset_case
build_result=1
if build_telemt_image; then echo 'FAIL: build failure accepted'; exit 1; fi
assert_marker previous
! grep -q '^tag ' "$tmp/calls"
assert_no_latest_pull

reset_case
pull_result=0 tag_result=1
if build_telemt_image; then echo 'FAIL: tag failure accepted'; exit 1; fi
assert_marker previous

# Execute the generated build command with failed cargo and a stale output file.
# A failed compile must never reach strip/cp, even if an old binary exists.
command_text=$(sed -n '/^RUN cargo build/,/^    cp /p' "$tmp/Dockerfile")
command_text=${command_text#RUN }
cargo() { return 1; }
strip() { touch "$tmp/stripped"; }
cp() { touch "$tmp/copied"; }
if eval "$command_text"; then echo 'FAIL: cargo failure masked'; exit 1; fi
test ! -e "$tmp/stripped"
test ! -e "$tmp/copied"
echo 'PASS: engine cache, exact pull, pinned fallback, source/force, build/tag failures, cargo failure propagation'
