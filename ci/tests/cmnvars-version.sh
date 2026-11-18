#!/bin/sh
# Compiler-version preflight: stub the compiler, never compile real code.
set -eu
root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ow-cmnvars-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 3 15

mkdir -p "$tmp/root/build/binbuild" "$tmp/root/build" "$tmp/bin" "$tmp/cwd"
cat > "$tmp/bin/clang" <<'SH'
#!/bin/sh
out=
prev=
for arg do
    if [ "$prev" = -o ]; then out=$arg; break; fi
    prev=$arg
done
[ -n "$out" ] || exit 99
case "${OW_MOCK_MODE:-}" in
    good) printf '# mock compiler preprocessor\nexport OWTOOLSVER=19\n' > "$out" ;;
    badvalue) printf 'export OWTOOLSVER=not_a_number\n' > "$out" ;;
    empty) : > "$out" ;;
    fail) exit 73 ;;
    *) exit 77 ;;
esac
SH
chmod +x "$tmp/bin/clang"

export OWROOT="$tmp/root"
export OWOBJDIR=binbuild
export OWTOOLS=CLANG
export OWCLANG="$tmp/bin/clang"
export OWDEFPATH="$PATH"
export INCLUDE=
export WATCOM=
export OWDEFINCLUDE=
export OWDEFWATCOM=

cd "$tmp/cwd" || exit 1

check_code() {
    wanted=$1
    shift
    got=0
    "$@" > "$tmp/output" 2>&1 || got=$?
    if [ "$got" -ne "$wanted" ]; then
        printf 'cmnvars: expected exit %s, got %s\n' "$wanted" "$got" >&2
        cat "$tmp/output" >&2
        exit 1
    fi
}

export OW_MOCK_MODE=good
check_code 0 sh -c '. "$1"; [ "$OWTOOLSVER" = 19 ]' sh "$root/cmnvars.sh"
[ ! -e ./getversi.gc ] && [ ! -e ./getversi.sh ]

# Even a previously generated successful file cannot mask a failed
# compiler during the next bootstrap attempt.
printf 'export OWTOOLSVER=99\n' > ./getversi.sh
export OW_MOCK_MODE=fail
check_code 73 sh -c '. "$1"' sh "$root/cmnvars.sh"
[ ! -e ./getversi.gc ] && [ ! -e ./getversi.sh ]

export OW_MOCK_MODE=empty
check_code 1 sh -c '. "$1"' sh "$root/cmnvars.sh"
export OW_MOCK_MODE=badvalue
check_code 1 sh -c '. "$1"' sh "$root/cmnvars.sh"
[ ! -e ./getversi.gc ] && [ ! -e ./getversi.sh ]

# Invalid compiler selection is a clear configuration failure.
export OWTOOLS=NOT_A_COMPILER
check_code 2 sh -c '. "$1"' sh "$root/cmnvars.sh"

printf '%s\n' 'OpenWatcom compiler-version preflight: all mocked checks passed'
