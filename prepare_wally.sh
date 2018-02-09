#!/bin/bash

set -e

if [ "$(uname -s)" == "Darwin" ]; then
    OSX=true
else
    #FIXME: for osx assume installed in a pre-script or manually until we install cordova non-globally
    yarn global add cordova@8.0.0
fi

# Prevent cordova prompting us to opt-in to telemetry on first use
cordova telemetry off >/dev/null 2>&1

APPDIR=$PWD
APPNAME=$(grep '<name>' config.xml www/config.xml 2>/dev/null | cut -d">" -f2 | cut -d"<" -f1)
READLINK=readlink
if which greadlink; then
    READLINK=greadlink
elif [ -n "$OSX" ]; then
    echo "greadlink missing! Try brew install coreutils."
    exit 1
fi

if [ -z "$JAVA_HOME" ]; then
    export JAVA_HOME=$JAVA7_HOME
fi
if [ -z "$OSX" ]; then
    # Require JAVA_HOME and ANDROID_NDK on Linux only, where we can't build for iOS
    echo ${JAVA_HOME:?}
    echo ${ANDROID_NDK:?}
else
    JAVA_HOME=""
    ANDROID_NDK=""
fi
echo ${APPNAME:?}

cd libwally-core

if [ -z "$OSX" ]; then
    source ./tools/android_helpers.sh

    all_archs=$(android_get_arch_list)
    if [ -n "$1" ]; then
        all_archs="$1"
    fi
fi

echo '============================================================'
echo 'Initialising build for architecture(s):'
echo $all_archs
echo '============================================================'
tools/cleanup.sh
tools/autogen.sh

configure_opts="--disable-dependency-tracking --disable-swig-python"
if [ -z "$OSX" ]; then
    configure_opts="$configure_opts --enable-swig-java"
else
    configure_opts="$configure_opts --disable-swig-java"
fi

for arch in $all_archs; do
    if [ -z "$ANDROID_NDK" ]; then
        continue
    fi

    echo '============================================================'
    echo Building $arch
    echo '============================================================'
    # Use API level 14 for non-64 bit targets for better device coverage
    api="14"
    if [[ $arch == *"64"* ]]; then
        api="21"
    fi

    rm -rf ./toolchain >/dev/null 2>&1
    if [ -n "$OSX" ]; then
        android_build_wally $arch $PWD/toolchain $api $configure_opts || continue
    else
        android_build_wally $arch $PWD/toolchain $api $configure_opts
    fi
    JNI_LIBDIR="src/wrap_js/cordovaplugin/jniLibs/$arch"
    mkdir -p $JNI_LIBDIR
    toolchain/bin/*-strip -o $JNI_LIBDIR/libwallycore.so src/.libs/libwallycore.so
done

./configure $configure_opts
make clean
cd src
make cordova-wrappers
cd ../..

if [ -n "$OSX" ]; then
    cordova prepare ios
    cordova plugin add $APPDIR/libwally-core/src/wrap_js/cordovaplugin --nosave
else
    cordova plugin add $APPDIR/libwally-core/src/wrap_js/cordovaplugin --nosave
fi

# Put files required by GA webfiles into place:
mkdir -p plugins/cordova-plugin-wally/build/Release
touch plugins/cordova-plugin-wally/build/Release/wallycore.js  # mock wallycore which is nodejs-only
cd plugins/cordova-plugin-wally
yarn add base64-js
cd ../..
