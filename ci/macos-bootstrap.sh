#!/bin/sh
# Native macOS entrypoint for the existing OpenWatcom POSIX CI stages.
# Do not replace the local wmake/builder bootstrap or force an SDK version.
set -eu

fail() { printf 'OpenWatcom macOS: %s\n' "$*" >&2; exit 1; }

case "${1:---build}" in
    --build) mode=build ;;
    --check) mode=check ;;
    -h|--help)
        printf '%s\n' 'Usage: sh ci/macos-bootstrap.sh [--check|--build]'
        printf '%s\n' '  --check  Validate native Apple tools and OpenWatcom paths only'
        printf '%s\n' '  --build  Bootstrap local wmake/builder, then the OpenWatcom release (default)'
        exit 0 ;;
    *) fail 'expected --check, --build or --help' ;;
esac
[ "$#" -le 1 ] || fail 'too many arguments'

[ "$(uname -s)" = Darwin ] || fail 'this entrypoint requires macOS (Darwin)'
root=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || fail 'cannot resolve source root'
case "$root" in
    *' '*|*'='*) fail 'source path contains a space or =, unsupported by the upstream build' ;;
esac
[ -f "$root/ci/buildx.sh" ] && [ -f "$root/cmnvars.sh" ] ||
    fail 'OpenWatcom source tree is incomplete'

case "$(uname -m)" in
    arm64|aarch64) host_release=armo64 ;;
    x86_64) host_release=bino64 ;;
    *) fail 'unsupported native macOS architecture (expected arm64 or x86_64)' ;;
esac

case "${OWTOOLS:-CLANG}" in
    CLANG) ;;
    *) fail 'macOS helper supports OWTOOLS=CLANG only' ;;
esac

OWOBJDIR=${OWOBJDIR:-binbuild}
case "$OWOBJDIR" in
    ''|.|..|*[!a-zA-Z0-9_-]*) fail 'OWOBJDIR must be a simple directory name' ;;
esac

if [ -n "${OWROOT:-}" ] && [ "$OWROOT" != "$root" ]; then
    fail 'OWROOT differs from this source tree'
fi
if [ -n "${OWRELROOT:-}" ] && [ "$OWRELROOT" != "$root/rel" ]; then
    fail 'OWRELROOT differs from this source tree release path'
fi

command -v xcrun >/dev/null 2>&1 ||
    fail 'Apple Command Line Tools not found; install with xcode-select --install'
macos_sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null) ||
    fail 'no usable macOS SDK; check the active Xcode/Command Line Tools with xcode-select -p'
[ -n "$macos_sdk" ] && [ -d "$macos_sdk" ] ||
    fail 'the active macOS SDK directory does not exist'
if [ -n "${SDKROOT:-}" ] && [ ! -d "$SDKROOT" ]; then
    fail 'SDKROOT was explicitly set to a nonexistent directory'
fi

if [ -n "${OWCLANG:-}" ]; then
    selected_clang=$OWCLANG
else
    selected_clang=$(xcrun --sdk macosx --find clang 2>/dev/null) ||
        fail 'Apple Clang not found; verify Xcode Command Line Tools installation'
fi
selected_clang=$(command -v "$selected_clang") || fail 'selected Clang is not on PATH'
case "$selected_clang" in
    /*) ;;
    *) fail 'selected Clang must resolve to an absolute path' ;;
esac
case "$selected_clang" in
    *' '*|*'='*) fail 'Clang path contains a space or =, unsupported by the upstream build' ;;
esac
[ -x "$selected_clang" ] || fail 'selected Clang is not executable'
"$selected_clang" --version >/dev/null 2>&1 || fail 'selected Clang cannot run'

if [ -n "${OWHOSTMAKE:-}" ]; then
    selected_make=$OWHOSTMAKE
else
    selected_make=$(command -v make) || fail 'POSIX make not found (required to bootstrap wmake)'
fi
selected_make=$(command -v "$selected_make") || fail 'selected POSIX make is not on PATH'
case "$selected_make" in
    /*) ;;
    *) fail 'selected POSIX make must resolve to an absolute path' ;;
esac
[ -x "$selected_make" ] || fail 'selected POSIX make is not executable'

printf 'OpenWatcom macOS: native host=%s release=%s\n' "$(uname -m)" "$host_release"
printf 'OpenWatcom macOS: Apple SDK=%s (not overriding SDKROOT)\n' "$macos_sdk"
printf 'OpenWatcom macOS: Clang=%s\n' "$selected_clang"
printf 'OpenWatcom macOS: host make=%s (first wmake bootstrap only)\n' "$selected_make"
[ "$mode" = check ] && exit 0

OWROOT=$root
OWRELROOT=$root/rel
OWTOOLS=CLANG
OWCLANG=$selected_clang
OWHOSTMAKE=$selected_make
OWTESTBOOT=${OWTESTBOOT:-0}
OWDOCBUILD=${OWDOCBUILD:-0}
OWNOWGML=${OWNOWGML:-1}
OWGUINOBUILD=${OWGUINOBUILD:-1}
PATH="${OWCLANG%/*}:$PATH"
export OWROOT OWRELROOT OWTOOLS OWCLANG OWHOSTMAKE OWOBJDIR
export OWTESTBOOT OWDOCBUILD OWNOWGML OWGUINOBUILD PATH

cd "$OWROOT" || fail 'cannot enter source root'
for stage in boot build; do
    printf 'OpenWatcom macOS: running stage %s\n' "$stage"
    OWBUILD_STAGE=$stage
    export OWBUILD_STAGE
    sh "$OWROOT/ci/buildx.sh" || fail "stage $stage failed"
done

native_bin="$OWRELROOT/$host_release"
[ -d "$OWRELROOT/h" ] || fail 'release headers rel/h missing'
[ -d "$OWRELROOT/lib286/dos" ] || fail '16-bit DOS libraries rel/lib286/dos missing'
for tool in wcc wcc386 wlink; do
    [ -x "$native_bin/$tool" ] || fail "missing native release tool: $native_bin/$tool"
done
printf 'OpenWatcom macOS: native release ready at %s\n' "$native_bin"
