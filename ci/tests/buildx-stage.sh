#!/bin/sh
# Host-only, mocked regression for OpenWatcom's POSIX CI driver.
# No compiler/bootstrap run, no downloaded toolchain or real objects.
set -eu

root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ow-buildx-stage.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 3 15

fake="$tmp/root"
mock="$tmp/bin"
mkdir -p "$fake/bld" "$mock"
for sub in wmake builder watcom whpcvt bmp2eps; do
    mkdir -p "$fake/bld/$sub"
done
cat > "$fake/cmnvars.sh" <<'SH'
# Deliberately minimal, to avoid needing host OpenWatcom tools.
: "${OWROOT:?}"
: "${OWOBJDIR:?}"
SH
cat > "$mock/builder" <<'SH'
#!/bin/sh
printf 'builder %s @ %s\n' "$*" "$PWD" >> "$OW_MOCK_LOG"
if [ "${OW_MOCK_FAIL_CMD:-}" = "$*" ]; then exit 17; fi
if [ -n "${OW_MOCK_FAIL_DIRECTORY:-}" ] &&
   [ "$PWD" = "$OW_MOCK_FAIL_DIRECTORY" ]; then exit 23; fi
exit 0
SH
cat > "$mock/make" <<'SH'
#!/bin/sh
printf 'make %s\n' "$*" >> "$OW_MOCK_LOG"
if [ "${OW_MOCK_FAIL_MAKE:-0}" = 1 ]; then exit 19; fi
mkdir -p "$OWROOT/build/$OWOBJDIR"
cat > "$OWROOT/build/$OWOBJDIR/wmake" <<'WMAKE'
#!/bin/sh
printf 'wmake %s\n' "$*" >> "$OW_MOCK_LOG"
if [ "${OW_MOCK_FAIL_WMAKE:-0}" = 1 ]; then exit 21; fi
exit 0
WMAKE
chmod +x "$OWROOT/build/$OWOBJDIR/wmake"
exit 0
SH
chmod +x "$mock/builder" "$mock/make"

export OWROOT="$fake"
export OWOBJDIR=binbuild
export OWTOOLS=CLANG
export OWTESTBOOT=0
export OWTESTTARGET="$fake/bld"
export OWDOCTARGET=
export OWINSTTARGET=
export OW_MOCK_LOG="$tmp/commands"
export PATH="$mock:$PATH"
: > "$OW_MOCK_LOG"

expect_status() {
    expected=$1
    shift
    actual=0
    "$@" > "$tmp/last-output" 2>&1 || actual=$?
    if [ "$actual" -ne "$expected" ]; then
        printf 'Expected exit %s, got %s for:' "$expected" "$actual" >&2
        printf ' %s' "$@" >&2
        printf '\n' >&2
        cat "$tmp/last-output" >&2
        exit 1
    fi
}

# Never accept a mistyped stage as a successful no-op.
export OWBUILD_STAGE=unknown
expect_status 2 sh "$root/ci/buildx.sh"
grep -q 'unsupported OWBUILD_STAGE' "$tmp/last-output"

# Builder failure must survive successful printing of result.log.
export OWBUILD_STAGE=tests
printf 'mock tests returned failure\n' > "$OWTESTTARGET/result.log"
export OW_MOCK_FAIL_CMD='-i test'
expect_status 17 sh "$root/ci/buildx.sh"
grep -q 'mock tests returned failure' "$tmp/last-output"
unset OW_MOCK_FAIL_CMD
expect_status 0 sh "$root/ci/buildx.sh"

# A successful test without an optional log is not a spurious failure.
rm "$OWTESTTARGET/result.log"
expect_status 0 sh "$root/ci/buildx.sh"

# Build, documentation and installation failure codes propagate.
export OWBUILD_STAGE=build
export OW_MOCK_FAIL_CMD=rel
expect_status 17 sh "$root/ci/buildx.sh"
unset OW_MOCK_FAIL_CMD
expect_status 0 sh "$root/ci/buildx.sh"
export OWBUILD_STAGE=docs
export OWDOCTARGET=guide
export OW_MOCK_FAIL_CMD='docs guide'
expect_status 17 sh "$root/ci/buildx.sh"
unset OW_MOCK_FAIL_CMD
export OWBUILD_STAGE=inst
export OWINSTTARGET=rel
export OW_MOCK_FAIL_CMD='install rel'
expect_status 17 sh "$root/ci/buildx.sh"
unset OW_MOCK_FAIL_CMD

# Bootstrap must fail if make or preboot wmake failed.
export OWBUILD_STAGE=boot
export OWDOCTARGET=
export OW_MOCK_FAIL_MAKE=1
expect_status 19 sh "$root/ci/buildx.sh"
unset OW_MOCK_FAIL_MAKE
export OW_MOCK_FAIL_WMAKE=1
expect_status 21 sh "$root/ci/buildx.sh"
unset OW_MOCK_FAIL_WMAKE

# Repeating bootstrap works even with existing output directories.
expect_status 0 sh "$root/ci/buildx.sh"
expect_status 0 sh "$root/ci/buildx.sh"

# Documentation-specific boot must stop on the FIRST failed subtree,
# not report success because the final builder boot happened to pass.
: > "$OW_MOCK_LOG"
export OWDOCTARGET=docwin
export OW_MOCK_FAIL_DIRECTORY="$fake/bld/builder"
expect_status 23 sh "$root/ci/buildx.sh"
grep -q "builder boot @ $fake/bld/watcom" "$OW_MOCK_LOG"
grep -q "builder boot @ $fake/bld/builder" "$OW_MOCK_LOG"
if grep -q "builder boot @ $fake/bld/whpcvt" "$OW_MOCK_LOG"; then
    printf 'Later document bootstrap ran after a failure\n' >&2
    exit 1
fi
unset OW_MOCK_FAIL_DIRECTORY

# Missing root provenance cannot be treated as a successful bootstrap.
unset OWROOT
export OWBUILD_STAGE=build
expect_status 2 sh "$root/ci/buildx.sh"

printf '%s\n' 'OpenWatcom CI stage propagation: all mocked checks passed'
