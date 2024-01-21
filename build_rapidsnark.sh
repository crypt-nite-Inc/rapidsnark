#!/usr/bin/env bash
set -eu

# for another architectures, check https://github.com/leetal/ios-cmake
declare -a -r platforms=('IOS' 'IOS_SIMULATOR')

declare -r working_dir='.'
declare -r output="$working_dir/../frameworks"
declare -r ios_simulator_prover_package_dir="package_ios_simulator"
declare -r ios_prover_package_dir="package_ios"



declare -r libz_source="$working_dir/source/zlib"
declare -r libz_include="$working_dir/source/zlib-include"
declare -r lvdb_source="$working_dir/source/leveldb-mcpe"
declare -r lvdb_include="$working_dir/source/leveldb-mcpe/include"

# ########## ########## ########## ########## ########## ########## ########## #

# $1: platform
# $2: lib_name
function stop() {
    open .
    echo '========== ========== ========== ========== =========='
    echo "Building $2 for $1 ..."
    echo '========== ========== ========== ========== =========='
    echo 'Todo List:'

    echo '- Open Xcode project'
    echo '- Select target OS version'
    if [[ $1 == 'OS64' ]]; then
        echo '- Add a development team in "Build Settings" tab'
    elif [[ $1 == 'SIMULATORARM64' ]]; then
        echo '- Remove excluded architectures for arm64 iOS simulators in "Build Settings" tab'
    fi
    echo ''
    echo 'Press any key to continue ...'
    read -r
}

# $1: platform
# $2: prefix
function mv_built_lib() {
    declare -r dst_dir=$output/$2-$1
    if [[ -e $dst_dir ]]; then rm -rf "$dst_dir"; fi
    case $1 in
    'OS64')
        mv Release-iphoneos "$dst_dir"
        ;;
    'MAC' | 'MAC_ARM64' | 'MAC_UNIVERSAL')
        mv Release "$dst_dir"
        ;;
    'SIMULATOR64' | 'SIMULATORARM64')
        mv Release-iphonesimulator "$dst_dir"
        ;;
    *)
        exit 1
        ;;
    esac
}

# ########## ########## ########## ########## ########## ########## ########## #

function prepare() {
    make clean
    #if [[ -e $working_dir ]]; then rm -rf $working_dir; fi
    mkdir -p $output
    rm -fr  $output/* $working_dir/build_prover_ios_simulator $working_dir/package_ios_simulator \
     $working_dir/depends/gmp/package_*
}

function build_gmp() {
  echo '========== ========== ========== ========== ========== =========='
  echo "initing gmp lib source"
  git submodule init
  git submodule update
  echo '========== ========== ========== ========== ========== =========='
  echo "Building library for gimp for iOS"
  $working_dir/build_gmp.sh ios
  echo '========== ========== ========== ========== ========== =========='
  echo "Building library for gimp for iOS Simulator"
  $working_dir/build_gmp.sh ios_simulator
  
}

function build_rapidsnark() {
  echo '========== ========== ========== ========== ========== =========='
  echo "Building library for rapidsnark for iOS"
  ios_prover_build_dir=$working_dir/build_prover_ios
  mkdir -p $ios_prover_build_dir $ios_prover_package_dir && cd $ios_prover_build_dir
  cmake .. --fresh  -GXcode -DTARGET_PLATFORM=IOS -DCMAKE_INSTALL_PREFIX=../$ios_prover_package_dir
  xcodebuild -destination 'generic/platform=iOS' -scheme rapidsnarkStatic -project rapidsnark.xcodeproj -configuration Debug
  # need to adjust the ARCHS if building on intel macs
  xcodebuild  -destination 'generic/platform=iOS' ARCHS=arm64 -project rapidsnark.xcodeproj  -target install -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO
  cd ../
  
  echo '========== ========== ========== ========== ========== =========='
  echo "Building library for rapidsnark for iOS Simulator"
  ios_simulator_prover_build_dir=$working_dir/build_prover_ios_simulator
  mkdir -p $ios_simulator_prover_build_dir $ios_simulator_prover_package_dir && cd $ios_simulator_prover_build_dir
  cmake .. --fresh -GXcode -DTARGET_PLATFORM=IOS_SIMULATOR -DCMAKE_INSTALL_PREFIX=../$ios_simulator_prover_package_dir -DUSE_ASM=NO
  xcodebuild ARCHS=arm64  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -scheme rapidsnarkStatic -project rapidsnark.xcodeproj 
  # need to adjust the ARCHS if building on intel macs
  xcodebuild  ARCHS=arm64  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -project rapidsnark.xcodeproj  -target install -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO
  cd ../
}


function make_framework() {

    xcodebuild -create-xcframework \
        -library $working_dir/$ios_prover_package_dir/lib/libfq.a \
        -library $working_dir/$ios_simulator_prover_package_dir/lib/libfq.a \
        -output $output/libfq.xcframework
    xcodebuild -create-xcframework \
        -library $working_dir/$ios_prover_package_dir/lib/libfr.a \
        -library $working_dir/$ios_simulator_prover_package_dir/lib/libfr.a \
        -output $working_dir/$output/libfr.xcframework
    xcodebuild -create-xcframework \
        -library $working_dir/$ios_prover_package_dir/lib/libgmp.a \
        -library $working_dir/$ios_simulator_prover_package_dir/lib/libgmp.a \
        -output $output/libgmp.xcframework
    xcodebuild -create-xcframework \
        -library $working_dir/$ios_prover_package_dir/lib/librapidsnark.a \
        -headers $working_dir/$ios_prover_package_dir/include \
        -library $working_dir/$ios_simulator_prover_package_dir/lib/librapidsnark.a \
        -output $output/librapidsnark.xcframework
    
}

# ########## ########## ########## ########## ########## ########## ########## #

prepare
build_gmp
build_rapidsnark
make_framework

open $output