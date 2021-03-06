#!/bin/bash
#
# Copyright (C) 2010, 2012, 2013 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This script is used to build an NDK release package *from* scratch !!
# While handy, this is *not* the best way to generate NDK release packages.
# See docs/DEVELOPMENT.TXT for details.
#

. `dirname $0`/prebuilt-common.sh

PROGRAM_PARAMETERS="<toolchain-src-dir>"
PROGRAM_DESCRIPTION=\
"This script is used to generate an NDK release package from scratch.

This process is EXTREMELY LONG and consists in the following steps:

  - downloading toolchain sources from the Internet
  - patching them appropriately (if needed)
  - rebuilding the toolchain binaries for the host system
  - rebuilding the platforms and samples directories from ../development/ndk
  - packaging everything into a host-specific archive

This can take several hours on a dual-core machine, even assuming a very
nice Internet connection and plenty of RAM and disk space.

Note that on Linux, if you have the 'mingw32' package installed, the script
will also automatically generate a windows release package. You can prevent
that by using the --systems option.

IMPORTANT:
        If you intend to package NDK releases often, please read the
        file named docs/DEVELOPMENT.TXT which provides ways to do that
        more quickly, by preparing toolchain binary tarballs that can be
        reused for each package operation. This will save you hours of
        your time compared to using this script!
"

force_32bit_binaries

# The default release name (use today's date)
RELEASE=`date +%Y%m%d`
register_var_option "--release=<name>" RELEASE "Specify release name"

# The package prefix
PREFIX=android-ndk
register_var_option "--prefix=<name>" PREFIX "Specify package prefix"

# Find the location of the platforms root directory
DEVELOPMENT_ROOT=`dirname $ANDROID_NDK_ROOT`/development/ndk
register_var_option "--development=<path>" DEVELOPMENT_ROOT "Path to development/ndk directory"

# Default location for final packages
OUT_DIR=/tmp/ndk-$USER
OPTION_OUT_DIR=
register_option "--out-dir=<path>" do_out_dir "Path to output directory" "$OUT_DIR"
do_out_dir() { OPTION_OUT_DIR=$1; }

# Force the build
FORCE=no
register_var_option "--force" FORCE "Force build (do not ask initial question)"

# Use --incremental to implement incremental release builds.
# This is only useful to debug this script or the ones it calls.
INCREMENTAL=no
register_var_option "--incremental" INCREMENTAL "Enable incremental packaging (debug only)."

DARWIN_SSH=
if [ "$HOST_OS" = "linux" ] ; then
register_var_option "--darwin-ssh=<hostname>" DARWIN_SSH "Specify Darwin hostname to ssh to for the build."
fi

# Determine the host platforms we can build for.
# This is the current host platform, and eventually windows if
# we are on Linux and have the mingw32 compiler installed and
# in our path.
#
HOST_SYSTEMS="$HOST_TAG32"

MINGW_GCC=
CANADIAN_DARWIN_BUILD=no
if [ "$HOST_TAG" == "linux-x86" ] ; then
    find_mingw_toolchain
    if [ -n "$MINGW_GCC" ] ; then
        HOST_SYSTEMS="$HOST_SYSTEMS,windows"
    fi
    # If darwin toolchain exist, build darwin too
    if [ -z "$DARWIN_SSH" -a -f "${DARWIN_TOOLCHAIN}-gcc" ]; then
        HOST_SYSTEMS="$HOST_SYSTEMS,darwin-x86"
        CANADIAN_DARWIN_BUILD=yes
    fi
fi
if [ -n "$DARWIN_SSH" -a "$HOST_SYSTEMS" = "${HOST_SYSTEMS%darwin-x86*}" ]; then
    HOST_SYSTEMS="$HOST_SYSTEMS,darwin-x86"
fi

register_var_option "--systems=<list>" HOST_SYSTEMS "List of host systems to build for"

ALSO_64_FLAG=
register_option "--also-64" do_ALSO_64 "Also build 64-bit host toolchain"
do_ALSO_64 () { ALSO_64_FLAG="--also-64"; }

TOOLCHAIN_SRCDIR=
register_var_option "--toolchain-src-dir=<path>" TOOLCHAIN_SRCDIR "Use toolchain sources from <path>"

extract_parameters "$@"

# check if HOST_SYSTEMS contains only permitted values
check_host_systems ()
{
    #echo "HOST_SYSTEMS    = $HOST_SYSTEMS"
    #echo "DEFAULT_SYSTEMS = $DEFAULT_SYSTEMS"
    local hs=$(commas_to_spaces $HOST_SYSTEMS)
    local sys=""
    local good=""
    local defsys=""
    for sys in $hs ; do 
        good=""
        for defsys in $DEFAULT_SYSTEMS ; do
            if [ $sys = $defsys ] ; then
                good="yes"
                break
            fi
        done
        if [ "$good" != "yes" ] ; then
            echo "ERROR: Unsupported host system: $sys"
            exit 1
        fi
    done
}

check_host_systems

# Check if windows is specified than mingw must be present
if [ "$HOST_SYSTEMS" != "${HOST_SYSTEMS%windows*}" ] ; then
    if [ -z "$MINGW_GCC" ]; then
        echo "ERROR: Can't find mingw tool with --systems=$HOST_SYSTEMS"
        exit 1
    fi
fi

fix_option OUT_DIR "$OPTION_OUT_DIR" "out directory"
setup_default_log_file $OUT_DIR/build.log

HOST_SYSTEMS_FLAGS="--systems=$HOST_SYSTEMS"
if [ -z "$CANADIAN_DARWIN_BUILD" ]; then
    # Filter out darwin-x86 in $HOST_SYSTEMS_FLAGS, because
    # 1) On linux, cross-compiling is done via "--darwin-ssh".  Keeping darwin-x86 in --systems list
    #    actually disable --darwin-ssh later on.
    # 2) On MacOSX, darwin-x86 is the default, no need to be explicit.
    #
    HOST_SYSTEMS_FLAGS=$(echo "$HOST_SYSTEMS_FLAGS" | sed -e 's/darwin-x86//')
fi
[ "$HOST_SYSTEMS_FLAGS" = "--systems=" ] && HOST_SYSTEMS_FLAGS=""

set_parameters ()
{
    TOOLCHAIN_SRCDIR="$1"

    # Check source directory
    #
    if [ -z "$TOOLCHAIN_SRCDIR" ] ; then
        echo "ERROR: Missing source directory parameter. See --help for details."
        exit 1
    fi

    if [ ! -d "$TOOLCHAIN_SRCDIR/gcc" ] ; then
        echo "ERROR: Source directory does not contain gcc sources: $TOOLCHAIN_SRCDIR"
        exit 1
    fi

    log "Using source directory: $TOOLCHAIN_SRCDIR"
}

set_parameters $PARAMETERS

# Print a warning and ask the user if he really wants to do that !
#
if [ "$FORCE" = "no" -a "$INCREMENTAL" = "no" ] ; then
    echo "IMPORTANT WARNING !!"
    echo ""
    echo "This script is used to generate an NDK release package from scratch"
    echo "for the following host platforms: $HOST_SYSTEMS"
    echo ""
    echo "This process is EXTREMELY LONG and may take SEVERAL HOURS on a dual-core"
    echo "machine. If you plan to do that often, please read docs/DEVELOPMENT.TXT"
    echo "that provides instructions on how to do that more easily."
    echo ""
    echo "Are you sure you want to do that [y/N] "
    read YESNO
    case "$YESNO" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Aborting !"
            exit 0
    esac
fi

#
# Timestamp management
TIMESTAMP_DIR="$OUT_DIR/timestamps"
mkdir -p "$TIMESTAMP_DIR"
if [ "$INCREMENTAL" = "no" ] ; then
    run rm -rf "$TIMESTAMP_DIR/*"
fi

timestamp_set ()
{
    mkdir -p $TIMESTAMP_DIR
    touch "$TIMESTAMP_DIR/$1"
}

timestamp_clear ()
{
    rm -f "$TIMESTAMP_DIR/$1"
}

timestamp_check ()
{
    if [ -f "$TIMESTAMP_DIR/$1" ] ; then
        return 1
    else
        return 0
    fi
}

# $1 - list of systems names
repack_64_packages ()
{
    local systems=$(commas_to_spaces ${1#"--systems="})
    local repack_dir="$OUT_DIR/tmp/repack"
    local sys
    local short_sys
    local pkg32_name
    local pkg32_name
    local pkg64_name
    local tools64_name
    local pkg_base
    dump "Will repack 64-bit packages for systems: $systems"
    for sys in $systems ; do
        case "$sys" in
            linux-x86|darwin-x86)
                short_sys=$sys
                pkg_ext="tar.bz2"
                ;;
            windows)
                pkg_ext="zip"
                sys=windows-x86
                short_sys=windows
                ;;
            *)
                echo "Unknown system to repack 64-bit packages: $sys"
                exit 1
        esac
        #
        echo "Repacking $sys packages"
        pkg32_name=`ls $OUT_DIR/android-ndk-*-$sys.$pkg_ext`
        pkg32_name=${pkg32_name#"$OUT_DIR/"}
        pkg64_name=${pkg32_name/"-x86"/"-x86_64"}
        tools64_name=${pkg32_name/"-x86"/"-x86-64bit-tools"}
        pkg_base=${pkg32_name%"-$sys.$pkg_ext"}
        #echo "pkg32_name:   $pkg32_name"
        #echo "pkg64_name:   $pkg64_name"
        #echo "tools64_name: $tools64_name"
        #echo "pkg_base:     $pkg_base"
        run mkdir "$repack_dir"
        unpack_archive "$OUT_DIR/$pkg32_name" "$repack_dir"
        run rm -rf "$repack_dir/$pkg_base/prebuilt/common"
        run rm -rf "$repack_dir/$pkg_base/prebuilt/$short_sys"
        find "$repack_dir/$pkg_base/toolchains" -type d -name prebuilt | xargs rm -rf
        unpack_archive "$OUT_DIR/$tools64_name" "$repack_dir"
        run rm "$OUT_DIR/$tools64_name"
        pack_archive "$OUT_DIR/$pkg64_name" "$repack_dir"
        run rm -rf "$repack_dir"
    done
}

# Step 1, If needed, download toolchain sources into a temporary directory
if [ -n "$TOOLCHAIN_SRCDIR" ] ; then
    dump "Using toolchain source directory: $TOOLCHAIN_SRCDIR"
    timestamp_set   toolchain-download-sources
else
    if timestamp_check toolchain-download-sources; then
        dump "Downloading toolchain sources..."
        TOOLCHAIN_SRCDIR="$OUT_DIR/toolchain-src"
        log "Using toolchain source directory: $TOOLCHAIN_SRCDIR"
        run $ANDROID_NDK_ROOT/build/tools/download-toolchain-sources.sh "$TOOLCHAIN_SRCDIR"
        if [ "$?" != 0 ] ; then
            dump "ERROR: Could not download toolchain sources"
            exit 1
        fi
        timestamp_set   toolchain-download-sources
        timestamp_clear build-prebuilts
        timestamp_clear build-host-prebuilts
        timestamp_clear build-darwin-prebuilts
        timestamp_clear build-mingw-prebuilts
    fi
fi

# Step 2, build the host toolchain binaries and package them
PREBUILT_DIR="$OUT_DIR/prebuilt"
if timestamp_check build-prebuilts; then
    FLAGS=""
    if [ "$VERBOSE" = "yes" ] ; then
        FLAGS=$FLAGS" --verbose"
    fi
    if [ "$DRY_RUN" = "yes" ] ; then
        FLAGS=$FLAGS" --dry-run"
    fi
    if [ -n "$XCODE_PATH" ]; then
        FLAGS=$FLAGS" --xcode=$XCODE_PATH"
    fi
    if [ -n "$OPTION_OUT_DIR" ]; then
        FLAGS=$FLAGS" --out-dir=$OUT_DIR"
    fi
    if timestamp_check build-host-prebuilts; then
        dump "Building host toolchain binaries..."
        run $ANDROID_NDK_ROOT/build/tools/rebuild-all-prebuilt.sh $FLAGS --package-dir="$PREBUILT_DIR" $ALSO_64_FLAG "$HOST_SYSTEMS_FLAGS" "$TOOLCHAIN_SRCDIR"
        fail_panic "Can't build $HOST_SYSTEMS binaries."
        timestamp_set build-host-prebuilts
    fi
    if [ -n "$DARWIN_SSH" ] ; then
        if timestamp_check build-darwin-prebuilts; then
            dump "Building Darwin prebuilts through ssh to $DARWIN_SSH..."
            run $ANDROID_NDK_ROOT/build/tools/rebuild-all-prebuilt.sh $FLAGS --package-dir="$PREBUILT_DIR" --darwin-ssh="$DARWIN_SSH" "$TOOLCHAIN_SRCDIR"
            fail_panic "Can't build Darwin binaries!"
            timestamp_set build-darwin-prebuilts
        fi
    fi
    timestamp_set build-prebuilts
    timestamp_clear make-packages
fi

# Step 3, package a release with everything
if timestamp_check make-packages; then
    SEPARATE_64=
    if [ -n "$ALSO_64_FLAG" ] ; then
        SEPARATE_64="--separate-64"
    fi
    dump "Generating NDK release packages"
    run $ANDROID_NDK_ROOT/build/tools/package-release.sh --release=$RELEASE --prefix=$PREFIX --out-dir="$OUT_DIR" --prebuilt-dir="$PREBUILT_DIR" "$HOST_SYSTEMS_FLAGS" --development-root="$DEVELOPMENT_ROOT" $SEPARATE_64
    if [ $? != 0 ] ; then
        dump "ERROR: Can't generate proper release packages."
        exit 1
    fi
    if [ -n "$ALSO_64_FLAG" ] ; then
        repack_64_packages "$HOST_SYSTEMS_FLAGS"
    fi
    timestamp_set make-packages
fi

dump "All clear. Good work! See $OUT_DIR"
