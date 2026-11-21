#!/bin/sh
# Host-only, mocked macOS entrypoint regression; no compiler build or SDK access.
set -eu
root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ow-macos-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 3 15

fake="$tmp/openwatcom"
mock="$tmp/bin"
mkdir -p "$fake/ci" "$mock" "$tmp/sdk"
cp "$root/ci/macos-bootstrap.sh" "$fake/ci/macos-bootstrap.sh"
: > "$fake/cmnvars.sh"
cat > "$fake/ci/buildx.sh" <<'BUILD'
#!/bin/sh
set -eu
printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$OWBUILD_STAGE" "$OWTOOLS" "$OWOBJDIR" "$OWCLANG" \
    "$OWHOSTMAKE" "$OWROOT" "$OWRELROOT" >> "$OW_TEST_LOG"
[ "${OW_TEST_FAIL_STAGE:-}" != "$OWBUILD_STAGE" ] || exit 42
if [ "$OWBUILD_STAGE" = build ] && [ "${OW_TEST_SKIP_RELEASE:-0}" != 1 ]; then
    case "$(uname -m)" in
        arm64|aarch64) out=armo64 ;;
        x86_64) out=bino64 ;;
        *) exit 3 ;;
    esac
    mkdir -p "$OWRELROOT/$out" "$OWRELROOT/h" "$OWRELROOT/lib286/dos"
    for tool in wcc wcc386 wlink; do
        printf '#!/bin/sh\nexit 0\n' > "$OWRELROOT/$out/$tool"
        chmod 700 "$OWRELROOT/$out/$tool"
    done
fi
BUILD
cat > "$mock/uname" <<'UNAME'
#!/bin/sh
case "$1" in
    -s) printf '%s\n' "${OW_TEST_PLATFORM:-Darwin}" ;;
    -m) printf '%s\n' "${OW_TEST_ARCH:-arm64}" ;;
    *) exit 4 ;;
esac
UNAME
cat > "$mock/xcrun" <<'XCRUN'
#!/bin/sh
case "$*" in
    '--sdk macosx --show-sdk-path')
        [ "${OW_TEST_SDK_FAIL:-0}" != 1 ] || exit 5
        printf '%s\n' "$OW_TEST_SDK" ;;
    '--sdk macosx --find clang')
        [ "${OW_TEST_CLANG_FAIL:-0}" != 1 ] || exit 6
        printf '%s\n' "$OW_TEST_CLANG" ;;
    *) exit 7 ;;
esac
XCRUN
cat > "$mock/clang" <<'CLANG'
#!/bin/sh
[ "$1" = --version ] || exit 8
printf '%s\n' 'Apple clang version (mocked)'
CLANG
cat > "$mock/make" <<'MAKE'
#!/bin/sh
exit 0
MAKE
chmod 700 "$mock/uname" "$mock/xcrun" "$mock/clang" "$mock/make"
OW_TEST_SDK="$tmp/sdk"
OW_TEST_CLANG="$mock/clang"
OW_TEST_LOG="$tmp/stages"
PATH="$mock:$PATH"
export OW_TEST_SDK OW_TEST_CLANG OW_TEST_LOG PATH
unset OWROOT OWRELROOT OWCLANG OWHOSTMAKE OWTOOLS OWOBJDIR SDKROOT OW_TEST_FAIL_STAGE
unset OW_TEST_SDK_FAIL OW_TEST_CLANG_FAIL OW_TEST_SKIP_RELEASE

check_status() {
    expected=$1
    shift
    status=0
    "$@" > "$tmp/output" 2>&1 || status=$?
    if [ "$status" -ne "$expected" ]; then
        printf 'macOS bootstrap test: expected %s, got %s\n' "$expected" "$status" >&2
        cat "$tmp/output" >&2
        exit 1
    fi
}

: > "$OW_TEST_LOG"
check_status 0 sh "$fake/ci/macos-bootstrap.sh" --check
[ ! -s "$OW_TEST_LOG" ] || exit 1
grep -F 'native host=arm64 release=armo64' "$tmp/output" >/dev/null
check_status 0 sh "$fake/ci/macos-bootstrap.sh"
test "$(wc -l < "$OW_TEST_LOG" | tr -d ' ')" -eq 2
grep -F 'boot|CLANG|binbuild|' "$OW_TEST_LOG" >/dev/null
grep -F 'build|CLANG|binbuild|' "$OW_TEST_LOG" >/dev/null
test -x "$fake/rel/armo64/wcc" && test -x "$fake/rel/armo64/wlink"

# Explicit compiler/make overrides and SDKROOT stay intact.
: > "$OW_TEST_LOG"
export OWCLANG="$mock/clang" OWHOSTMAKE="$mock/make" SDKROOT="$tmp/sdk"
export DEVELOPER_DIR="$tmp/developer" OWOBJDIR=macbuild
check_status 0 sh "$fake/ci/macos-bootstrap.sh" --check
[ ! -s "$OW_TEST_LOG" ] || exit 1
[ "$DEVELOPER_DIR" = "$tmp/developer" ] && [ "$SDKROOT" = "$tmp/sdk" ]
check_status 0 sh "$fake/ci/macos-bootstrap.sh" --build
grep -F "boot|CLANG|macbuild|$mock/clang|$mock/make|$fake|$fake/rel" "$OW_TEST_LOG" >/dev/null
unset OWCLANG OWHOSTMAKE SDKROOT DEVELOPER_DIR OWOBJDIR

# Intel-hosted native binaries must use their own directory.
OW_TEST_ARCH=x86_64
export OW_TEST_ARCH
check_status 0 sh "$fake/ci/macos-bootstrap.sh" --build
test -x "$fake/rel/bino64/wcc386"
unset OW_TEST_ARCH

# Invalid platform, SDK, compiler and architecture must fail before a build.
: > "$OW_TEST_LOG"
export OW_TEST_PLATFORM=Linux
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --build
unset OW_TEST_PLATFORM
export OW_TEST_ARCH=mips
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --build
unset OW_TEST_ARCH
export OW_TEST_SDK_FAIL=1
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --build
unset OW_TEST_SDK_FAIL
export OW_TEST_CLANG_FAIL=1
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --build
unset OW_TEST_CLANG_FAIL
[ ! -s "$OW_TEST_LOG" ] || exit 1

# Release failures and partial outputs cannot be reported as success.
rm -rf "$fake/rel"
export OW_TEST_FAIL_STAGE=boot
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --build
[ "$(wc -l < "$OW_TEST_LOG" | tr -d ' ')" -eq 1 ]
unset OW_TEST_FAIL_STAGE
: > "$OW_TEST_LOG"
export OW_TEST_SKIP_RELEASE=1
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --build
grep -F 'release headers rel/h missing' "$tmp/output" >/dev/null
unset OW_TEST_SKIP_RELEASE

check_status 0 sh "$fake/ci/macos-bootstrap.sh" --help
check_status 1 sh "$fake/ci/macos-bootstrap.sh" --invalid
printf '%s\n' 'OpenWatcom macOS bootstrap: all mocked checks passed'
