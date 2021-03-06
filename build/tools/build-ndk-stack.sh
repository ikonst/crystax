#!/bin/bash
#
# Copyright (C) 2011, 2013 The Android Open Source Project
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
# This script is used to rebuild the host 'ndk-stack' tool from the
# sources under sources/host-tools/ndk-stack.
#
# Note: The tool is installed under prebuilt/$HOST_TAG/bin/ndk-stack
#       by default.
#
PROGDIR=$(dirname $0)
. $PROGDIR/prebuilt-common.sh

PROGRAM_PARAMETERS=""
PROGRAM_DESCRIPTION=\
"This script is used to rebuild the host ndk-stack binary program."

register_jobs_option

OUT_DIR=/tmp/ndk-$USER
OPTION_OUT_DIR=
register_option "--out-dir=<path>" do_out_dir  "Specify build directory" "$OUT_DIR"
do_out_dir() { OPTION_OUT_DIR=$1; }

NDK_DIR=$ANDROID_NDK_ROOT
register_var_option "--ndk-dir=<path>" NDK_DIR "Place binary in NDK installation path"

GNUMAKE=
register_var_option "--make=<path>" GNUMAKE "Specify GNU Make program"

DEBUG=
register_var_option "--debug" DEBUG "Build debug version"

PACKAGE_DIR=
register_var_option "--package-dir=<path>" PACKAGE_DIR "Archive binary into specific directory"

register_canadian_option
register_try64_option

extract_parameters "$@"

fix_option OUT_DIR "$OPTION_OUT_DIR" "out directory"
setup_default_log_file $OUT_DIR/build.log
OUT_DIR=$OUT_DIR/host/ndk-stack

#
# Try cached package
#
set_cache_host_tag
ARCHIVE=ndk-stack-$CACHE_HOST_TAG.tar.bz2
if [ "$PACKAGE_DIR" ]; then
    # will exit if cached package found
    try_cached_package "$PACKAGE_DIR" "$ARCHIVE"
fi

#
# Rebuild from scratch
#

prepare_host_build

prepare_canadian_toolchain $OUT_DIR

OUT=$NDK_DIR/$(get_host_exec_name ndk-stack)

# GNU Make
if [ -z "$GNUMAKE" ]; then
    GNUMAKE=make
    log "Auto-config: --make=$GNUMAKE"
fi

if [ "$PACKAGE_DIR" ]; then
    mkdir -p "$PACKAGE_DIR"
    fail_panic "Could not create package directory: $PACKAGE_DIR"
fi

PROGNAME=ndk-stack
if [ "$MINGW" = "yes" ]; then
    PROGNAME=$PROGNAME.exe
fi

# Create output directory
mkdir -p $(dirname $OUT)
if [ $? != 0 ]; then
    echo "ERROR: Could not create output directory: $(dirname $OUT)"
    exit 1
fi

SRCDIR=$ANDROID_NDK_ROOT/sources/host-tools/ndk-stack

CFLAGS="$HOST_CFLAGS"
if [ -n "$DEBUG" ]; then
    CFLAGS=$CFLAGS" -O0 -g"
else
    CFLAGS=$CFLAGS" -O2 -s"
fi
LDFLAGS="$HOST_LDFLAGS"

# Let's roll
export CFLAGS=$HOST_CFLAGS" -O2 -s"
export LDFLAGS=$HOST_LDFLAGS
run $GNUMAKE -C $SRCDIR -f $SRCDIR/GNUMakefile \
    -B -j$NUM_JOBS \
    PROGNAME="$OUT" \
    OUT_DIR="$OUT_DIR" \
    CC="$CXX" CXX="$CXX" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    STRIP="$STRIP" \
    DEBUG=$DEBUG

if [ $? != 0 ]; then
    echo "ERROR: Could not build host program!"
    exit 1
fi

if [ "$PACKAGE_DIR" ]; then
    assert_cache_host_tag
    SUBDIR=$(get_host_exec_name ndk-stack $HOST_TAG)
    dump "Packaging: $ARCHIVE"
    pack_archive "$PACKAGE_DIR/$ARCHIVE" "$NDK_DIR" "$SUBDIR"
    fail_panic "Could not create package: $PACKAGE_DIR/$ARCHIVE from $OUT"
    cache_package "$PACKAGE_DIR" "$ARCHIVE"
fi

if [ -z "$OPTION_OUT_DIR" ]; then
    log "Cleaning up..."
    rm -rf $OUT_DIR
    dir=`dirname $OUT_DIR`
    while true; do
        rmdir $dir >/dev/null 2>&1 || break
        dir=`dirname $dir`
    done
else
    log "Don't forget to clean up: $OUT_DIR"
fi

log "Done!"
exit 0
