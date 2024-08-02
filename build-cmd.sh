#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

OGG_SOURCE_DIR="libogg"
OGG_VERSION="$(sed -n "s/^AC_INIT(\[libogg\],\[\(.*\)\]\,\[ogg-dev@xiph.org\])/\1/p" "$OGG_SOURCE_DIR/configure.ac")"

VORBIS_SOURCE_DIR="libvorbis"
VORBIS_VERSION="$(sed -n "s/^AC_INIT(\[libvorbis\],\[\(.*\)\]\,\[vorbis-dev@xiph.org\])/\1/p" "$VORBIS_SOURCE_DIR/configure.ac")"

top="$(pwd)"
stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${OGG_VERSION}-${VORBIS_VERSION}.${build}" > "${stage}/VERSION.txt"

apply_patch()
{
    local patch="$1"
    local path="$2"
    echo "Applying $patch..."
    git apply --check --directory="$path" "$patch" && git apply --directory="$path" "$patch"
}

apply_patch "patches/libvorbis/0001-vendored-ogg-build.patch" "libvorbis"

# setup staging dirs
mkdir -p "$stage/include/"
mkdir -p "$stage/lib/debug"
mkdir -p "$stage/lib/release"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        pushd "$OGG_SOURCE_DIR"
            mkdir -p "build_debug"
            pushd "build_debug"
                cmake .. -G "Ninja Multi-Config" -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/ogg_debug"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                cmake .. -G "Ninja Multi-Config" -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/ogg_release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd
        popd

        # copy ogg libs
        cp ${stage}/ogg_debug/lib/ogg.lib ${stage}/lib/debug/libogg.lib
        cp ${stage}/ogg_release/lib/ogg.lib ${stage}/lib/release/libogg.lib

        # copy ogg headers
        cp -a $stage/ogg_release/include/* $stage/include/

        pushd "$VORBIS_SOURCE_DIR"
            mkdir -p "build_debug"
            pushd "build_debug"
                cmake .. -G "Ninja Multi-Config" \
                    -DOGG_LIBRARIES="$(cygpath -m $stage)/lib/debug/libogg.lib" \
                    -DOGG_INCLUDE_DIRS="$(cygpath -m $stage)/include" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/vorbis_debug"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                cmake .. -G "Ninja Multi-Config" \
                    -DOGG_LIBRARIES="$(cygpath -m $stage)/lib/release/libogg.lib" \
                    -DOGG_INCLUDE_DIRS="$(cygpath -m $stage)/include" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/vorbis_release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd
        popd

        # copy vorbis libs
        cp ${stage}/vorbis_debug/lib/vorbis.lib ${stage}/lib/debug/libvorbis.lib
        cp ${stage}/vorbis_debug/lib/vorbisenc.lib ${stage}/lib/debug/libvorbisenc.lib
        cp ${stage}/vorbis_debug/lib/vorbisfile.lib ${stage}/lib/debug/libvorbisfile.lib
        cp ${stage}/vorbis_release/lib/vorbis.lib ${stage}/lib/release/libvorbis.lib
        cp ${stage}/vorbis_release/lib/vorbisenc.lib ${stage}/lib/release/libvorbisenc.lib
        cp ${stage}/vorbis_release/lib/vorbisfile.lib ${stage}/lib/release/libvorbisfile.lib

        # copy vorbis headers
        cp -a $stage/vorbis_release/include/* $stage/include/
    ;;
    darwin*)
        # Setup build flags
        opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"
        plainopts="$(remove_cxxstd $opts)"

        pushd "$OGG_SOURCE_DIR"
            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$plainopts" \
                cmake .. -GNinja -DCMAKE_BUILD_TYPE="Release" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/ogg_release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # mkdir -p "build_release_arm64"
            # pushd "build_release_arm64"
            #     CFLAGS="$C_OPTS_ARM64" \
            #     LDFLAGS="$LINK_OPTS_ARM64" \
            #     cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
            #         -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
            #         -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
            #         -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
            #         -DCMAKE_MACOSX_RPATH=YES \
            #         -DCMAKE_INSTALL_PREFIX="$stage/ogg_release_arm64"

            #     cmake --build . --config Release
            #     cmake --install . --config Release

            #     # conditionally run unit tests
            #     if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            #         ctest -C Release
            #     fi
            # popd

            # # create fat libraries
            # lipo -create ${stage}/ogg_release_x86/lib/libogg.a ${stage}/ogg_release_arm64/lib/libogg.a -output ${stage}/lib/release/libogg.a

            # copy files
            cp -a ${stage}/ogg_release_x86/lib/libogg.a ${stage}/lib/release/libogg.a
            cp -a $stage/ogg_release_x86/include/* $stage/include/
        popd

        pushd "$VORBIS_SOURCE_DIR"
            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$plainopts" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
                    -DOGG_LIBRARIES="${stage}/lib/release/libogg.a" -DOGG_INCLUDE_DIRS="$stage/include" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/vorbis_release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # mkdir -p "build_release_arm64"
            # pushd "build_release_arm64"
            #     CFLAGS="$C_OPTS_ARM64" \
            #     LDFLAGS="$LINK_OPTS_ARM64" \
            #     cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
            #         -DOGG_LIBRARIES="${stage}/lib/release/libogg.a" -DOGG_INCLUDE_DIRS="$stage/include" \
            #         -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
            #         -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
            #         -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
            #         -DCMAKE_MACOSX_RPATH=YES \
            #         -DCMAKE_INSTALL_PREFIX="$stage/vorbis_release_arm64"

            #     cmake --build . --config Release
            #     cmake --install . --config Release

            #     # conditionally run unit tests
            #     if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            #        ctest -C Release
            #     fi
            # popd

            # # create fat libraries
            # lipo -create ${stage}/vorbis_release_x86/lib/libvorbis.a ${stage}/vorbis_release_arm64/lib/libvorbis.a -output ${stage}/lib/release/libvorbis.a
            # lipo -create ${stage}/vorbis_release_x86/lib/libvorbisenc.a ${stage}/vorbis_release_arm64/lib/libvorbisenc.a -output ${stage}/lib/release/libvorbisenc.a
            # lipo -create ${stage}/vorbis_release_x86/lib/libvorbisfile.a ${stage}/vorbis_release_arm64/lib/libvorbisfile.a -output ${stage}/lib/release/libvorbisfile.a

            # copy headers
            cp -a $stage/vorbis_release_x86/lib/libvorbis.a $stage/lib/release/libvorbis.a
            cp -a $stage/vorbis_release_x86/lib/libvorbisenc.a $stage/lib/release/libvorbisenc.a
            cp -a $stage/vorbis_release_x86/lib/libvorbisfile.a $stage/lib/release/libvorbisfile.a
            cp -a $stage/vorbis_release_x86/include/* $stage/include/
        popd
     ;;
    linux*)
        # Default target per autobuild build --address-size
        opts="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE"
        plainopts="$(remove_cxxstd $opts)"

        pushd "$OGG_SOURCE_DIR"
            mkdir -p "build"
            pushd "build"
                CFLAGS="$plainopts" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_INSTALL_PREFIX="$stage/ogg_release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                   ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/ogg_release/lib/*.a ${stage}/lib/release/

            # copy headers
            cp -a ${stage}/ogg_release/include/* ${stage}/include/
        popd
        
        pushd "$VORBIS_SOURCE_DIR"
            mkdir -p "build"
            pushd "build"
                CFLAGS="$plainopts" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_INSTALL_PREFIX="$stage/vorbis_release" \
                    -DOGG_LIBRARIES="$stage/lib/release/libogg.a" \
                    -DOGG_INCLUDE_DIRS="$stage/include"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                   ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/vorbis_release/lib/*.a ${stage}/lib/release/

            # copy headers
            cp -a ${stage}/vorbis_release/include/* ${stage}/include/
        popd
    ;;
esac

mkdir -p "$stage/LICENSES"
cp $OGG_SOURCE_DIR/COPYING "$stage/LICENSES/ogg-vorbis.txt"
