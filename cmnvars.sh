#!/bin/sh
# *****************************************************************
# cmnvars.sh - common environment variables
# *****************************************************************
# NOTE: All scripts to set the environment must call this script at
#       the end.

# Set the version numbers
export OWBLDVER=20
export OWBLDVERSTR=2.0
export OWBLDVERTOOL=1300

# Subdirectory to be used for building OW build tools
if [ -z "$OWOBJDIR" ]; then export OWOBJDIR=binbuild; fi

# Set environment variables
# Set up default path information variable
if [ -z "$OWDEFPATH" ]; then
    export OWDEFPATH="$PATH":
    if [ -n "$INCLUDE" ]; then export OWDEFINCLUDE=$INCLUDE; fi
    if [ -n "$WATCOM" ]; then export OWDEFWATCOM=$WATCOM; fi
fi
export PATH="$OWROOT/build/$OWOBJDIR:$OWROOT/build:$OWDEFPATH"
if [ -n "$OWDEFINCLUDE" ]; then export INCLUDE=$OWDEFINCLUDE; fi
if [ -n "$OWDEFWATCOM" ]; then export WATCOM=$OWDEFWATCOM; fi

# Set OWTOOLSVER from the selected compiler, not a stale preprocessor
# output from an earlier build. A failed probe is a failed bootstrap:
# reporting "version=0" would hide a broken compiler behind later stages.
# This file is sourced by POSIX build scripts (so 'return' is deliberate).
export OWTOOLSVER=0
rm -f ./getversi.gc ./getversi.sh
case "$OWTOOLS" in
    WATCOM)
        printf 'export OWTOOLSVER=__WATCOMC__\n' > ./getversi.gc || return $?
        if wcc386 -p ./getversi.gc > ./getversi.sh; then
            :
        else
            rc=$?
            rm -f ./getversi.gc ./getversi.sh
            return "$rc"
        fi
        ;;
    CLANG)
        printf 'export OWTOOLSVER=__clang_major__\n' > ./getversi.gc || return $?
        compiler=${OWCLANG:-clang}
        if "$compiler" -x c -E ./getversi.gc -o ./getversi.sh; then
            :
        else
            rc=$?
            rm -f ./getversi.gc ./getversi.sh
            return "$rc"
        fi
        ;;
    GCC)
        printf 'export OWTOOLSVER=__GNUC__\n' > ./getversi.gc || return $?
        if gcc -x c -E ./getversi.gc -o ./getversi.sh; then
            :
        else
            rc=$?
            rm -f ./getversi.gc ./getversi.sh
            return "$rc"
        fi
        ;;
    VISUALC)
        CC=cl
        CXX=cl
        printf 'export OWTOOLSVER=_MSC_VER\n' > ./getversi.gc || return $?
        if cl -nologo -EP ./getversi.gc > ./getversi.bat; then
            :
        else
            rc=$?
            rm -f ./getversi.gc ./getversi.bat
            return "$rc"
        fi
        ;;
    *)
        printf 'OpenWatcom: unknown host compiler kind OWTOOLS=%s\n' "$OWTOOLS" >&2
        return 2
        ;;
esac

if [ "$OWTOOLS" != "VISUALC" ]; then
    if [ ! -s ./getversi.sh ]; then
        printf '%s\n' 'OpenWatcom: host compiler version probe produced no output' >&2
        rm -f ./getversi.gc ./getversi.sh
        return 1
    fi
    . ./getversi.sh || {
        rc=$?
        rm -f ./getversi.gc ./getversi.sh
        return "$rc"
    }
    case "$OWTOOLSVER" in
        ''|0|*[!0-9]*)
            printf 'OpenWatcom: unrecognized host compiler version: %s\n' "$OWTOOLSVER" >&2
            rm -f ./getversi.gc ./getversi.sh
            return 1
            ;;
    esac
fi
rm -f ./getversi.gc ./getversi.sh

printf 'Open Watcom build environment (%s version=%s)\n' "$OWTOOLS" "$OWTOOLSVER"
