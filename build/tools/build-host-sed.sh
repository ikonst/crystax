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
# Build the host version of the sed executable and place it
# at the right location

PROGDIR=$(dirname $0)
. $PROGDIR/prebuilt-common.sh

PROGRAM_PARAMETERS=""
PROGRAM_DESCRIPTION=\
"Rebuild the host sed tool used by the NDK."

register_try64_option
register_canadian_option
register_jobs_option

NDK_DIR=$ANDROID_NDK_ROOT
register_var_option "--ndk-dir=<path>" NDK_DIR "Specify NDK install directory"

PACKAGE_DIR=
register_var_option "--package-dir=<path>" PACKAGE_DIR "Archive to package directory"

OUT_DIR=/tmp/ndk-$USER
OPTION_OUT_DIR=
register_option "--out-dir=<path>" do_out_dir "Specify path to build out directory" "$OUT_DIR"
do_out_dir() { OPTION_OUT_DIR=$1; }

GNUMAKE=make
register_var_option "--make=<path>" GNUMAKE "Specify GNU Make program"

extract_parameters "$@"
fix_option OUT_DIR "$OPTION_OUT_DIR" "out directory"
setup_default_log_file $OUT_DIR/build.log
OUT_DIR=$OUT_DIR/host/sed

#
# Try cached package
#
set_cache_host_tag
ARCHIVE=ndk-sed-$CACHE_HOST_TAG.tar.bz2
if [ "$PACKAGE_DIR" ]; then
    # will exit if cached package found
    try_cached_package "$PACKAGE_DIR" "$ARCHIVE"
fi

#
# Rebuild from scratch
#

SUBDIR=$(get_prebuilt_host_exec sed)
OUT=$NDK_DIR/$(get_prebuilt_host_exec sed)

SED_VERSION=4.2.1
SED_SRCDIR=$ANDROID_NDK_ROOT/sources/host-tools/sed-$SED_VERSION
if [ ! -d "$SED_SRCDIR" ]; then
    echo "ERROR: Can't find sed-$SED_VERSION source tree: $SED_SRCDIR"
    exit 1
fi

log "Using sources from: $SED_SRCDIR"

prepare_host_build

log "Configuring the build"
mkdir -p $OUT_DIR && rm -rf $OUT_DIR/*
prepare_canadian_toolchain $OUT_DIR
cd $OUT_DIR &&
CFLAGS=$HOST_CFLAGS" -O2 -s" &&
LDFLAGS=$HOST_LDFLAGS" -O2 -s" &&
export CC CFLAGS LDFLAGS &&
run $SED_SRCDIR/configure \
    --disable-nls \
    --disable-rpath \
    --disable-i18n \
    --disable-acl \
    --host=$ABI_CONFIGURE_HOST \
    --build=$ABI_CONFIGURE_BUILD
fail_panic "Failed to configure the sed-$SED_VERSION build!"

log "Building sed (lib/ and sed/ only)"
run $GNUMAKE -j $NUM_JOBS -C lib
run $GNUMAKE -j $NUM_JOBS -C sed
fail_panic "Failed to build the sed-$SED_VERSION executable!"

log "Copying executable to prebuilt location"
run mkdir -p $(dirname "$OUT") && cp sed/$(get_host_exec_name sed) $OUT
fail_panic "Could not copy executable to: $OUT"

if [ "$PACKAGE_DIR" ]; then
    assert_cache_host_tag
    dump "Packaging: $ARCHIVE"
    mkdir -p "$PACKAGE_DIR" &&
    pack_archive "$PACKAGE_DIR/$ARCHIVE" "$NDK_DIR" "$SUBDIR"
    fail_panic "Could not package archive: $PACKAGE_DIR/$ARCHIVE"
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
    log "Don't forget to cleanup: $OUT_DIR"
fi

log "Done."

