#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x

# make errors fatal
set -e

# complain about unreferenced environment variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$top/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

MESHOPT_SOURCE_DIR="meshoptimizer"

pushd "$MESHOPT_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
            plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

            mkdir -p "build"
            pushd "build"
                cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"
                cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config Release
            popd

            mkdir -p "$stage/lib/release"
            mv "$stage/lib/meshoptimizer.lib" \
                "$stage/lib/release/meshoptimizer.lib"

            mkdir -p "$stage/include/meshoptimizer"
            mv "$stage/include/meshoptimizer.h" \
                "$stage/include/meshoptimizer/meshoptimizer.h"

            rm -r "$stage/lib/cmake"
        ;;

        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$opts" \
                    LDFLAGS="$ld_opts" \
                    cmake -G Ninja .. \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_BUILD_TYPE=Release \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_INSTALL_INCLUDEDIR="$stage/include/meshoptimizer" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}

                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release
                popd
            done

            lipo -create -output "$stage/lib/release/libmeshoptimizer.a" "$stage/lib/release/x86_64/libmeshoptimizer.a" "$stage/lib/release/arm64/libmeshoptimizer.a"
        ;;

        linux*)
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            mkdir -p "build"
            pushd "build"
                cmake -G Ninja .. \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_CXX_FLAGS="$plainopts" \
                    -DCMAKE_INSTALL_PREFIX:STRING="${stage}"

                cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config Release
            popd

            mkdir -p "$stage/lib/release"
            mv "$stage/lib/libmeshoptimizer.a" \
                "$stage/lib/release/libmeshoptimizer.a"

            mkdir -p "$stage/include/meshoptimizer"
            mv "$stage/include/meshoptimizer.h" \
                "$stage/include/meshoptimizer/meshoptimizer.h"

            rm -r "$stage/lib/cmake"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp -a LICENSE.md "$stage/LICENSES/meshoptimizer.txt"
popd

#mkdir -p "$stage"/docs/meshoptimizer/
#cp -a README.Linden "$stage"/docs/meshoptimizer/
