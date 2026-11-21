#!/bin/sh
#
# Script to build the Open Watcom tools on Github CI/CD Pipelines
# using the host platform's native C/C++ compiler.
#
# Expects
#   - POSIX tools
#   - correct setup for all OW build environment variables
#

bootutil_proc()
{
    # Bootstrapping is repeatable: a second invocation must not fail just
    # because the build directories already exist. No compiler/linker run
    # is treated as successful merely because a later command succeeded.
    mkdir -p "$OWROOT/build/$OWOBJDIR" ||
        return $?
    mkdir -p "$OWROOT/bld/wmake/$OWOBJDIR" ||
        return $?
    cd "$OWROOT/bld/wmake/$OWOBJDIR" ||
        return $?

    if [ "$OWTOOLS" = "WATCOM" ]; then
        if [ "$OWTESTBOOT" = "1" ]; then
            wmake -m -f ../wmake EXTRADEF=-DTESTBOOT
        else
            wmake -m -f ../wmake
        fi
    else
        case "$(uname -s)" in
            Darwin) host_target=-D__OSX__ ;;
            *) host_target=-D__LINUX__ ;;
        esac
        # The first-stage POSIX makefile invokes $(CC), not OWCLANG.
        # Select the same host compiler used by cmnvars.sh when CLANG
        # is requested; never silently fall back to the platform cc.
        if [ "$OWTOOLS" = "CLANG" ]; then
            host_cc=$OWCLANG
            [ -n "$host_cc" ] || host_cc=clang
            if ! command -v "$host_cc" >/dev/null 2>&1; then
                printf 'OpenWatcom: selected host Clang not found: %s\n' "$host_cc" >&2
                return 127
            fi
            set -- "CC=$host_cc"
        else
            set --
        fi
        # Host make is required only to compile the first wmake.
        host_make=${OWHOSTMAKE:-make}
        if ! command -v "$host_make" >/dev/null 2>&1; then
            printf 'OpenWatcom: POSIX bootstrap make not found: %s\n' "$host_make" >&2
            return 127
        fi
        if [ "$OWTESTBOOT" = "1" ]; then
            "$host_make" -f ../posmake "TARGETDEF=$host_target" "$@" EXTRADEF=-DTESTBOOT
        else
            "$host_make" -f ../posmake "TARGETDEF=$host_target" "$@"
        fi
    fi
    RC=$?
    [ "$RC" -eq 0 ] || return "$RC"

    # Do not use a different wmake via the inherited PATH.
    if [ ! -x "$OWROOT/build/$OWOBJDIR/wmake" ]; then
        printf 'OpenWatcom: bootstrap did not produce local wmake: %s\n' "$OWROOT/build/$OWOBJDIR/wmake" >&2
        return 127
    fi
    mkdir -p "$OWROOT/bld/builder/$OWOBJDIR" ||
        return $?
    cd "$OWROOT/bld/builder/$OWOBJDIR" ||
        return $?
    if [ "$OWTOOLS" = "CLANG" ]; then
        # preboot defaults to cc as well; keep the host compiler
        # consistent through both bootstrap utilities.
        "$OWROOT/build/$OWOBJDIR/wmake" -f ../preboot \
            "CL=$host_cc -g -O2 -o\$(name_exe)"
    else
        "$OWROOT/build/$OWOBJDIR/wmake" -f ../preboot
    fi
}

# All later stages require the locally bootstrapped builder and wmake.
# cmnvars.sh prepends their directory to PATH for builder subcommands.
run_builder()
{
    local_builder="$OWROOT/build/$OWOBJDIR/builder"
    if [ ! -x "$local_builder" ]; then
        printf 'OpenWatcom: local builder not executable: %s\n' "$local_builder" >&2
        return 127
    fi
    if [ "$OWTOOLS" != "WATCOM" ] &&
       [ ! -x "$OWROOT/build/$OWOBJDIR/wmake" ]; then
        printf 'OpenWatcom: local wmake not executable: %s\n' "$OWROOT/build/$OWOBJDIR/wmake" >&2
        return 127
    fi
    "$local_builder" "$@"
}

build_proc()
{
    RC=0
    if [ -z "${OWROOT:-}" ] || [ ! -f "$OWROOT/cmnvars.sh" ]; then
        printf '%s\n' 'OpenWatcom: OWROOT/cmnvars.sh is required' >&2
        return 2
    fi
    export OWGHOSTSCRIPTPATH=:

    . "$OWROOT/cmnvars.sh" || return $?
    export OWVERBOSE=1
    cd "$OWROOT/bld" || return $?

    case "$OWBUILD_STAGE" in
        boot)
            bootutil_proc
            RC=$?
            if [ "$RC" -eq 0 ]; then
                if [ -z "${OWDOCTARGET:-}" ]; then
                    cd "$OWROOT/bld" || return $?
                    run_builder boot
                    RC=$?
                else
                    # Stop on the FIRST failed document bootstrap.
                    # The previous loop silently reported only the last
                    # command's status, concealing costly intermediate failures.
                    for section in watcom builder whpcvt bmp2eps; do
                        cd "$OWROOT/bld/$section" || {
                            RC=$?
                            break
                        }
                        run_builder boot
                        RC=$?
                        [ "$RC" -eq 0 ] || break
                    done
                fi
            fi
            ;;
        build)
            run_builder rel
            RC=$?
            ;;
        tests)
            cd "$OWTESTTARGET" || return $?
            run_builder -i test
            RC=$?
            # The log is diagnostic: a successful cat never overrides a
            # failed test; a missing log cannot erase the builder status.
            if [ -f result.log ]; then
                cat result.log
                log_rc=$?
                if [ "$RC" -eq 0 ]; then RC=$log_rc; fi
            fi
            ;;
        docs)
            run_builder docs "$OWDOCTARGET"
            RC=$?
            ;;
        inst)
            run_builder install "$OWINSTTARGET"
            RC=$?
            ;;
        *)
            printf 'OpenWatcom: unsupported OWBUILD_STAGE: %s\n' "$OWBUILD_STAGE" >&2
            RC=2
            ;;
    esac
    cd "$OWROOT" || return $?
    return "$RC"
}

if [ "${OWDEBUG:-}" = "1" ]; then
    env | sort
fi
build_proc "$@"
