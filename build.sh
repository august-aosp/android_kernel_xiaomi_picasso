#!/usr/bin/env bash
#
#  build.sh - Automic kernel building script for Rosemary Kernel
#
#  Copyright (C) 2021-2023, Crepuscular's AOSP WorkGroup
#  Author: EndCredits <alicization.han@gmail.com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.
#
#  Configure your .env before using this script.
#

#####################################
###### Setup build environment ######
#####################################
source .env.sh

THREAD=$(nproc --all);

TARGET_KERNEL_FILE=arch/arm64/boot/Image;
TARGET_KERNEL_DTB=arch/arm64/boot/dtb;
TARGET_KERNEL_DTBO=arch/arm64/boot/dtbo.img

DEFCONFIG_PATH=arch/arm64/configs
DEFCONFIG_NAME="vendor/${DEVICE}_user_defconfig";

START_SEC=$(date +%s);

TARGET_KERNEL_NAME=$(cat $DEFCONFIG_PATH/$DEFCONFIG_NAME | grep CONFIG_LOCALVERSION= | cut -d = -f 2 | sed 's/"//g' | sed 's/^-//')
TARGET_KERNEL_VERSION=$(make kernelversion);

GIT_COMMIT=$(git rev-parse --short HEAD);

ANYKERNEL_PATH=AnyKernel3;

# Define build variants and their corresponding fragments
declare -A BUILD_VARIANTS_MAP=(
    ["vanilla"]=""
    ["ksu"]="vendor/kernelsu.config"
    ["debug"]="vendor/debug.config"
)

BUILD_VARIANT="vanilla"
BUILD_OPT=""

usage(){
    echo "build.sh: A very simple Kernel build helper"
    echo "usage: build.sh <optional argument> <operation>"
    echo
    echo "Build operations:"
    echo "    all             Perform a build without cleaning."
    echo "    cleanbuild      Clean the source tree and build files then perform a all build."
    echo
    echo "    flashable       Only generate the flashable zip file. Don't use it before you have built once."
    echo "    savedefconfig   Save the defconfig file to source tree."
    echo "    defconfig       Only build kernel defconfig"
    echo "    version         Display the version number."
    echo
    echo "Optional argument"
    echo "    --variant|-v    Specify the build variant (e.g., vanilla, susfs, debug)."
    echo "    --help|-h       Display this help message."
    echo
}

parse_args(){
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--variant)
            if [[ -n "${BUILD_VARIANTS_MAP[$2]}" || "$2" == "vanilla" ]]; then
                BUILD_VARIANT="$2"
                shift 2
            else
                echo "Unknown build variant: $2"
                echo "Supported variants: ${!BUILD_VARIANTS_MAP[*]}"
                exit 1
            fi
            ;;
            --help|-h)
            usage
            exit 0
            ;;
            -*|--*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
            *)
            BUILD_OPT="$1"
            shift 1
            ;;
        esac
    done
}

parse_args "$@";

OUT="../out/$DEVICE/$BUILD_VARIANT"
build_args="CC=clang \
            ARCH=arm64 \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            LLVM=1 \
            LLVM_IAS=1 \
            LD=ld.lld \
            O=$OUT \
            -j$THREAD \
            KBUILD_BUILD_USER=$BUILD_USER \
            KBUILD_BUILD_HOST=$BUILD_HOST";

TARGET_PACKAGED_KERNEL_NAME=$TARGET_KERNEL_NAME-$TARGET_KERNEL_VERSION-$BUILD_VARIANT-$GIT_COMMIT;

#####################################
########## Build functions ##########
#####################################
link_all_dtb_files(){
    find $OUT/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + > $OUT/arch/arm64/boot/dtb;
}

make_defconfig(){
    echo "------------------------------";
    echo " Building Kernel Defconfig..";
    echo "------------------------------";

    FRAGMENT="${BUILD_VARIANTS_MAP[$BUILD_VARIANT]}"
    if [[ -n "$FRAGMENT" ]]; then
        DEFCONFIG_NAME="$DEFCONFIG_NAME $FRAGMENT"
    fi

    make $build_args $DEFCONFIG_NAME;
}

build_kernel(){
    echo "------------------------------";
    echo " Building Kernel ...........";
    echo "------------------------------";

    make $build_args;
    END_SEC=$(date +%s);
    COST_SEC=$[ $END_SEC-$START_SEC ];
    echo "Kernel Build Costed $(($COST_SEC/60))min $(($COST_SEC%60))s"

}

patch_kernel_properties(){
    sed -i \
    -e "s|\${KERNEL_STRING}|${KERNEL_STRING}|g" \
    -e "s|\${DEVICE}|${DEVICE}|g" \
    -e "s|\${SUPPORTED_VERSIONS}|${SUPPORTED_VERSIONS}|g" \
    $ANYKERNEL_PATH/anykernel.sh;
}

generate_flashable(){
    echo "------------------------------";
    echo " Generating Flashable Kernel";
    echo "------------------------------";

    cd $OUT;
    
    if [ ! -d $ANYKERNEL_PATH ]; then
        echo ' Getting AnyKernel ';
        git clone --depth=1 https://github.com/august-aosp/AnyKernel3.git $ANYKERNEL_PATH;
        patch_kernel_properties;
    else
        echo ' Anykernel 3 Detected. Skipping download ';
    fi

    echo ' Removing old package file ';
    rm -rf $ANYKERNEL_PATH/$TARGET_KERNEL_NAME*;

    echo ' Copying Kernel File '; 
    cp -r $TARGET_KERNEL_FILE $ANYKERNEL_PATH/;
    cp -r $TARGET_KERNEL_DTB $ANYKERNEL_PATH/;
    cp -r $TARGET_KERNEL_DTBO $ANYKERNEL_PATH/;

    echo ' Packaging flashable Kernel ';
    cd $ANYKERNEL_PATH;
    zip -q -r $TARGET_PACKAGED_KERNEL_NAME.zip *;

    echo " Target File:  $OUT/$ANYKERNEL_PATH/$TARGET_PACKAGED_KERNEL_NAME.zip ";
}

save_defconfig(){
    echo "------------------------------";
    echo " Saving kernel config ........";
    echo "------------------------------";

    make $build_args $DEFCONFIG_NAME;
    END_SEC=$(date +%s);
    COST_SEC=$[ $END_SEC-$START_SEC ];
    echo "Finished. Kernel config saved to $OUT/.config"
    echo "Moving kernel defconfig to source tree"
    cp $OUT/.config $DEFCONFIG_PATH/$DEFCONFIG_NAME
    echo "Kernel Config Build Costed $(($COST_SEC/60))min $(($COST_SEC%60))s"

}

clean(){
    echo "Clean source tree and build files..."
    make mrproper -j$THREAD;
    make clean -j$THREAD;
    rm -rf $OUT;
}

main(){
    if [ $BUILD_OPT == "savedefconfig" ]
    then
        save_defconfig;
    elif [ $BUILD_OPT == "cleanbuild" ]
    then
        clean;
        make_defconfig;
        build_kernel;
        link_all_dtb_files;
        generate_flashable;
    elif [ $BUILD_OPT == "flashable" ]
    then
        generate_flashable;
    elif [ $BUILD_OPT == "kernelonly" ]
    then
        make_defconfig
        build_kernel
    elif [ $BUILD_OPT == "all" ]
    then
        make_defconfig
        build_kernel
        link_all_dtb_files
        generate_flashable
    elif [ $BUILD_OPT == "defconfig" ]
    then
        make_defconfig;
    elif [ $BUILD_OPT == "version" ]
    then
        echo "Current version is: $TARGET_KERNEL_NAME-$TARGET_KERNEL_VERSION"
    else
        echo "Incorrect usage. Please run: "
        echo "  bash build.sh --help (or -h) "
        echo "to display help message."
    fi
}

main;
