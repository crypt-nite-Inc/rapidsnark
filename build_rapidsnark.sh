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
    rm -fr  $output/* $working_dir/build_prover_ios* $working_dir/package_ios* \
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
  xcodebuild  -destination 'generic/platform=iOS' -project rapidsnark.xcodeproj  -target install -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO
  cd ../
  
  echo '========== ========== ========== ========== ========== =========='
  echo "Building library for rapidsnark for iOS Simulator"
  build_for_ios_simulator
}

function build_for_ios_simulator()
{
  include_dirs=()
  pkg_dirs=()
	#for ARCH in "arm64" "x86_64"; do
  
	for ARCH in "arm64" "x86_64"; do
		
		BUILD_DIR="${working_dir}/build_prover_ios_simulator_${ARCH}"
		PACKAGE_DIR="${ios_simulator_prover_package_dir}_${ARCH}"
    pkg_dirs+=("${PACKAGE_DIR}")
    include_dirs+=("${PACKAGE_DIR}/include")
    
		if [ -d "$PACKAGE_DIR" ]; then
			echo "iPhone Simulator ${ARCH} package is built already. See $PACKAGE_DIR. Skip building this ARCH."
			continue
		fi

		rm -rf "$BUILD_DIR"
		mkdir -p "$BUILD_DIR" "$PACKAGE_DIR"
		cd "$BUILD_DIR"

    cmake .. --fresh -GXcode -DTARGET_PLATFORM=IOS_SIMULATOR_${ARCH} -DCMAKE_INSTALL_PREFIX=../$PACKAGE_DIR -DUSE_ASM=NO
    xcodebuild -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -scheme rapidsnarkStatic -project rapidsnark.xcodeproj 
    xcodebuild  -destination 'generic/platform=iOS Simulator'  ARCHS=${ARCH} ONLY_ACTIVE_ARCH=NO -sdk iphonesimulator -project rapidsnark.xcodeproj  -target install -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO
		cd ..
	done
  
  fat_pkg_dir="${working_dir}/package_ios_simulator"
  fat_lib_dir="${fat_pkg_dir}/lib"
  
	mkdir -p "${fat_lib_dir}" 
  
  for lib in "libfq.a" "libfr.a" "libgmp.a" "librapidsnark.a";
  do
  	lipo "${pkg_dirs[0]}/lib/${lib}" "${pkg_dirs[1]}/lib/${lib}" -create -output "${fat_lib_dir}/${lib}"
  	echo "Wrote universal fat library for iPhone Simulator arm64/x86_64 to ${fat_lib_dir}/${lib}"
  done  
	cp -r "${include_dirs[0]}" "${fat_pkg_dir}"
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