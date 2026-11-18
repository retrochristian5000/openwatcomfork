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
        if [ "$OWTESTBOOT" = "1" ]; then
            make -f ../posmake "TARGETDEF=$host_target" EXTRADEF=-DTESTBOOT
        else
            make -f ../posmake "TARGETDEF=$host_target"
        fi
    fi
    RC=$?
    [ "$RC" -eq 0 ] || return "$RC"

    mkdir -p "$OWROOT/bld/builder/$OWOBJDIR" ||
        return $?
    cd "$OWROOT/bld/builder/$OWOBJDIR" ||
        return $?
    "$OWROOT/build/$OWOBJDIR/wmake" -f ../preboot
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
                    builder boot
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
                        builder boot
                        RC=$?
                        [ "$RC" -eq 0 ] || break
                    done
                fi
            fi
            ;;
        build)
            builder rel
            RC=$?
            ;;
        tests)
            cd "$OWTESTTARGET" || return $?
            builder -i test
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
            builder docs "$OWDOCTARGET"
            RC=$?
            ;;
        inst)
            builder install "$OWINSTTARGET"
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
