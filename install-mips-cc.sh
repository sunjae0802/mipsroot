#!/bin/bash

# Based on mipsemul-sys/install-mips from SESC, and CLFS 2.1, which have the
# following copyrights.

# Copyright (C) 2009 Milos Prvulovic
# Based on CLFS 2.1, Copyright © 2005-2013 Joe Ciccone, Jim Gifford, & Ryan Oliver 

# This file is part of SESC and is based on (and heavilly borrows from) CLFS
# Please read both the SESC (GPL) license and the CLFS (OPL) license before
# using this program.

# This program, like all of SESC, is distributed in the  hope that  it will  be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
# See the GNU General Public License for more details.

# Changes from CLFS 2.1 to get building with gcc 5+
# Added binutils-fix-errors-in-bfd-header.patch
# Added to configure line: --disable-werror
# Added gcc-4.8.1-fix-cfns-inlines.patch
# Added eglibc-2.18-fixmake-versioncheck.patch

if [ $# -gt 0 ]; then
    echo "Builds and installs a 32-bit MIPS cross-compiler based on CLFS 2.1."
    echo "Make sure you have sources available in the '$SOURCES' directory"
    echo "before building, and have symbolic links /tools and /cross-tools"
    echo "pointing to the \$CLFS/tools and \$CLFS/cross-tools."
    echo ""
    echo "Also, make *SURE* you run this script with an empty environment, i.e.:"
    echo "$ env -i HOME=\${HOME} TERM=\${TERM} PS1='\u:\w\$ ' CLFS=\`pwd\` $0"
    exit
fi

echo "-------------------------------"
echo "Checking environment           "
echo "-------------------------------"
env_lines=`env | wc -l`
if [ "$env_lines" -gt 10 ]
then
    env
    echo "We need to run $0 in a clean environment"
    exit 1
fi

###################################
# Configuration
# You should modify this section
###################################
if [ -z "$CLFS" ]
then
    echo "CLFS not set"
    exit 1
fi
echo "-----------------------------"
echo "Using $CLFS as base directory"
echo "-----------------------------"

SOURCES=${CLFS}/sources
BUILD=${CLFS}/build
LOG=build.log
CLFS_HOST="x86_64-cross-linux"
CLFS_TARGET="mips-unknown-linux-gnu"
KERNEL_VER="2.6.16" # XXX: CLFS 2.1 says 2.6.32, but we need 2.6.16

###################################
# Prepare for building
###################################
install -dv ${CLFS}
install -dv ${CLFS}/tools
install -dv ${CLFS}/cross-tools
echo "Checking for symbolic links in root /tools and /cross-tools"
READLINK_RESULT=`readlink /tools`
if [ ! -d /tools -o "$READLINK_RESULT" != "${CLFS}/tools" ]
then
    echo "/tools does not match ${CLFS}/tools"
    echo "Create link as root: ln -sv ${CLFS}/tools /"
    exit 1
fi
READLINK_RESULT=`readlink /cross-tools`
if [ ! -d /cross-tools -o "$READLINK_RESULT" != "${CLFS}/cross-tools" ]
then
    echo "/cross-tools does not match ${CLFS}/cross-tools"
    echo "Create link as root: ln -sv ${CLFS}/cross-tools /"
    exit 1
fi
if [ ! -d $SOURCES ]
then
    echo "SOURCES directory $SOURCES does not exist!"
    exit 1
fi

echo "----------------------"
echo "Setting up environment"
echo "----------------------"
set +h
umask 022
LC_ALL=POSIX
PATH=/cross-tools/bin:/bin:/usr/bin
export CLFS PATH
export CLFS_HOST CLFS_TARGET
unset CFLAGS
unset CXXFLAGS

mkdir -p $BUILD

################################################################
# Helper function function_install
#
# Function that takes the following arguments and
# extracts, builds and installs the specified package.
# All builds are done within the $BUILD directory, and
# extract sources from the $SOURCES directory.
#
#PACKAGE= # Name of the package
#VERSION= # Verson
#FILE="${PACKAGE}-${VERSION}.tar.??" # Source file
#SRCPATH="" # Override path to extracted source if exists
#             If empty, use ${PACKAGE}-${VERSION}
#BUILDPATH="" # Use a separate build directory if set
#PATCHES=() # Path commands done within SRCPATH. One per entry
#ACTIONS=() # Build commands done within BILDPATH. One per entry
#PRODUCT="" # File to check if build can be skipped
#################################################################
function_install() {
    if [ ! -z "${PRODUCT}" ] && [ -f "${PRODUCT}" ]; then
        echo "Skipping ${PACKAGE}"
        return
    fi
    if [ ! -f "${SOURCES}/${FILE}" ]; then
        echo "Source tarball for ${PACKAGE} not found!"
        exit 2
    fi

    echo "-----------------------------"
    echo Build/installing $PACKAGE
    echo "-----------------------------"

    pushd $BUILD

    if [ -z "${SRCPATH}" ]
    then
        SRCPATH="${PACKAGE}-${VERSION}"
    fi
    rm -rf $SRCPATH

    ext=${FILE##*.}
    if [ "$ext" = "gz" ]; then
        tar -xzf ${SOURCES}/$FILE
    elif [ "$ext" = "bz2" ]; then
        tar -xjf ${SOURCES}/$FILE
    elif [ "$ext" = "xz" ]; then
        tar -xJf ${SOURCES}/$FILE
    elif [ "$ext" = "lzma" ]; then
        tar --lzma -xf ${SOURCES}/$FILE
    fi
    echo "Extracted sources to $SRCPATH"

    pushd $SRCPATH

    # Apply patches
    for (( idx=0; $idx<${#PATCHES[*]}; idx=$idx+1 )); do
        action=${PATCHES[$idx]}
        if [ ! -z "${action}" ]; then
            eval ${action} > $LOG
            if [ $? -eq 0 ]; then
                echo "Done patch command \"${action}\" for ${PACKAGE}"
            else
                echo "Failed patch command \"${action}\" for ${PACKAGE}"
                exit 3
            fi
        fi
    done

    popd

    # Build
    if [ -n "$BUILDPATH" ]; then
        mkdir "$BUILDPATH"
        pushd "$BUILDPATH"
    else
        pushd $SRCPATH
    fi
    for (( idx=0; $idx<${#ACTIONS[*]}; idx=$idx+1 )); do
        action=${ACTIONS[$idx]}
        if [ ! -z "${action}" ]; then
            eval ${action} > $LOG
            if [ $? -eq 0 ]; then
                echo "Done build command \"${action}\" for ${PACKAGE}"
            else
                echo "Failed buld command \"${action}\" for ${PACKAGE}"
                exit 3
            fi
        fi
    done

    popd

    # Cleanup buildpath if it exists
    echo "Cleaning up build for ${PACKAGE}"
    if [ -n "$BUILDPATH" ]; then
        rm -rf "$BUILDPATH"
    fi
    rm -rf $SRCPATH

    popd
}

echo "--------------"
echo "Starting build"
echo "--------------"
PACKAGE=bc
VERSION=1.06.95
FILE="${PACKAGE}-${VERSION}.tar.bz2"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "./configure --prefix=/cross-tools"
    "make"
    "make install"
)
PRODUCT="/cross-tools/bin/bc"
function_install

PACKAGE=linux
VERSION=3.10.14
FILE="${PACKAGE}-${VERSION}.tar.xz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "make mrproper"
    "make ARCH=mips headers_check"
    "make ARCH=mips INSTALL_HDR_PATH=/tools headers_install"
)
PRODUCT="/tools/include/linux/errno.h"
function_install

PACKAGE=file
VERSION=5.15
FILE="${PACKAGE}-${VERSION}.tar.gz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "./configure --prefix=/cross-tools --disable-static"
    "make"
    "make install"
)
PRODUCT="/cross-tools/bin/file"
function_install

PACKAGE=m4
VERSION=1.4.17
FILE="${PACKAGE}-${VERSION}.tar.xz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "./configure --prefix=/cross-tools"
    "make"
    "make install"
)
PRODUCT="/cross-tools/bin/m4"
function_install

PACKAGE=ncurses
VERSION=5.9
FILE="${PACKAGE}-${VERSION}.tar.gz"
SRCPATH=""
BUILDPATH=""
PATCHES=(
    "patch -Np1 -i ${SOURCES}/ncurses-5.9-bash_fix-1.patch"
    "patch -Np1 -i ${SOURCES}/work_around_changed_output_of_GNU_cpp_5.x.patch"
)
ACTIONS=(
    "./configure --prefix=/cross-tools \
        --without-debug --without-shared"
    "make -C include"
    "make -C progs tic"
    "install -v -m755 progs/tic /cross-tools/bin"
)
PRODUCT="/cross-tools/bin/tic"
function_install

PACKAGE=gmp
VERSION=5.1.3
FILE="${PACKAGE}-${VERSION}.tar.xz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "./configure --prefix=/cross-tools --enable-cxx \
        --disable-static"
    "make"
    "make install"
)
PRODUCT="/cross-tools/lib/libgmp.so.10.1.3"
function_install

PACKAGE=mpfr
VERSION=3.1.2
FILE="${PACKAGE}-${VERSION}.tar.xz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "LDFLAGS=\"-Wl,-rpath,/cross-tools/lib\" \
        ./configure --prefix=/cross-tools \
        --disable-static --with-gmp=/cross-tools"
    "make"
    "make install"
)
PRODUCT="/cross-tools/lib/libmpfr.so.4.1.2"
function_install

PACKAGE=mpc
VERSION=1.0.1
FILE="${PACKAGE}-${VERSION}.tar.gz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "LDFLAGS="-Wl,-rpath,/cross-tools/lib" \
        ./configure --prefix=/cross-tools --disable-static \
        --with-gmp=/cross-tools --with-mpfr=/cross-tools"
    "make"
    "make install"
)
PRODUCT="/cross-tools/lib/libmpc.so.3.0.0"
function_install

PACKAGE=isl
VERSION=0.12.1
FILE="${PACKAGE}-${VERSION}.tar.lzma"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "LDFLAGS=\"-Wl,-rpath,/cross-tools/lib\" \
        ./configure --prefix=/cross-tools --disable-static \
        --with-gmp-prefix=/cross-tools"
    "make"
    "make install"
)
PRODUCT="/cross-tools/lib/libisl.so.10.2.1"
function_install

PACKAGE=cloog
VERSION=0.18.0
FILE="${PACKAGE}-${VERSION}.tar.gz"
SRCPATH=""
BUILDPATH=""
PATCHES=()
ACTIONS=(
    "LDFLAGS="-Wl,-rpath,/cross-tools/lib" \
        ./configure --prefix=/cross-tools --disable-static \
        --with-gmp-prefix=/cross-tools  --with-isl-prefix=/cross-tools"
    "make"
    "make install"
)
PRODUCT="/cross-tools/lib/libcloog-isl.so.4.0.0"
function_install

PACKAGE=binutils
VERSION=2.23.2
FILE="${PACKAGE}-${VERSION}.tar.bz2"
SRCPATH=""
BUILDPATH="binutils-build"
PATCHES=(
    "sed -i -e 's/@colophon/@@colophon/' -e 's/doc@cygnus.com/doc@@cygnus.com/' bfd/doc/bfd.texinfo"
    "patch -Np1 -i ${SOURCES}/binutils-fix-errors-in-bfd-header.patch"
)
ACTIONS=(
    "AR=ar AS=as ../binutils-2.23.2/configure \
        --prefix=/cross-tools --host=${CLFS_HOST} --target=${CLFS_TARGET} \
        --with-sysroot=${CLFS} --with-lib-path=/tools/lib --disable-nls \
        --disable-static --disable-multilib --disable-werror"
    "make configure-host"
    "make"
    "make install"
    "cp -v ../binutils-2.23.2/include/libiberty.h /tools/include"
)
PRODUCT="/cross-tools/bin/mips-unknown-linux-gnu-as"
function_install

PACKAGE=gcc
VERSION=4.8.1
FILE="${PACKAGE}-${VERSION}.tar.bz2"
SRCPATH=""
BUILDPATH="gcc-build"
PATCHES=(
    "patch -Np1 -i ${SOURCES}/gcc-4.8.1-branch_update-3.patch"
    "patch -Np1 -i ${SOURCES}/gcc-4.8.1-specs-1.patch"
    "echo -en '\n#undef STANDARD_STARTFILE_PREFIX_1\n#define STANDARD_STARTFILE_PREFIX_1 \"/tools/lib/\"\n' >> gcc/config/linux.h"
    "echo -en '\n#undef STANDARD_STARTFILE_PREFIX_2\n#define STANDARD_STARTFILE_PREFIX_2 \"\"\n' >> gcc/config/linux.h"
)
ACTIONS=(
    "touch /tools/include/limits.h"
    "AR=ar LDFLAGS=\"-Wl,-rpath,/cross-tools/lib\" \
        ../gcc-4.8.1/configure --prefix=/cross-tools \
        --build=${CLFS_HOST} --host=${CLFS_HOST} --target=${CLFS_TARGET} \
        --with-sysroot=${CLFS} --with-local-prefix=/tools \
        --with-native-system-header-dir=/tools/include --disable-nls \
        --disable-shared --with-mpfr=/cross-tools --with-gmp=/cross-tools \
        --with-isl=/cross-tools --with-cloog=/cross-tools --with-mpc=/cross-tools \
        --without-headers --with-newlib --disable-decimal-float --disable-libgomp \
        --disable-libmudflap --disable-libssp --disable-threads --disable-multilib \
        --disable-libatomic --disable-libitm --disable-libsanitizer \
        --disable-libquadmath --disable-target-libiberty --disable-target-zlib \
        --with-system-zlib --enable-cloog-backend=isl --disable-isl-version-check \
        --enable-languages=c --enable-checking=release"
    "make all-gcc all-target-libgcc"
    "make install-gcc install-target-libgcc"
)
PRODUCT="/cross-tools/bin/mips-unknown-linux-gnu-gcc"
function_install

PACKAGE=eglibc
VERSION=2.18
FILE="${PACKAGE}-${VERSION}-r24148.tar.xz"
SRCPATH=""
BUILDPATH="eglibc-build"
PATCHES=(
    "patch -Np0 -i ${SOURCES}/eglibc-2.18-fixmake-versioncheck.patch"
)
ACTIONS=(
    "echo \"libc_cv_ssp=no\" > config.cache"
    "BUILD_CC=\"gcc\" CC=\"${CLFS_TARGET}-gcc\" \
        AR=\"${CLFS_TARGET}-ar\" RANLIB=\"${CLFS_TARGET}-ranlib\" \
        ../eglibc-2.18/configure --prefix=/tools \
        --host=${CLFS_TARGET} --build=${CLFS_HOST} \
        --disable-profile --with-tls --enable-kernel=${KERNEL_VER} \
        --with-__thread --with-binutils=/cross-tools/bin \
        --with-headers=/tools/include --enable-obsolete-rpc \
        --cache-file=config.cache"
    "make"
    "make install"
)
PRODUCT="/tools/lib/libm.so.6"
function_install

# Second build and installation of gcc (also installs g++)
PACKAGE=gcc
VERSION=4.8.1
FILE="${PACKAGE}-${VERSION}.tar.bz2"
SRCPATH=""
BUILDPATH="gcc-build"
PATCHES=(
    "patch -Np1 -i ${SOURCES}/gcc-4.8.1-branch_update-3.patch"
    "patch -Np1 -i ${SOURCES}/gcc-4.8.1-specs-1.patch"
    "patch -Np2 -i ${SOURCES}/gcc-4.8.1-fix-cfns-inlines.patch"
    "echo -en '\n#undef STANDARD_STARTFILE_PREFIX_1\n#define STANDARD_STARTFILE_PREFIX_1 \"/tools/lib/\"\n' >> gcc/config/linux.h"
    "echo -en '\n#undef STANDARD_STARTFILE_PREFIX_2\n#define STANDARD_STARTFILE_PREFIX_2 \"\"\n' >> gcc/config/linux.h"
)
ACTIONS=(
    "touch /tools/include/limits.h"
    "AR=ar LDFLAGS=\"-Wl,-rpath,/cross-tools/lib\" \
        ../gcc-4.8.1/configure --prefix=/cross-tools \
        --build=${CLFS_HOST} --target=${CLFS_TARGET} --host=${CLFS_HOST} \
        --with-sysroot=${CLFS} --with-local-prefix=/tools \
        --with-native-system-header-dir=/tools/include --disable-nls \
        --enable-shared --disable-static --enable-languages=c,c++ \
        --enable-__cxa_atexit --enable-c99 --enable-long-long --enable-threads=posix \
        --disable-multilib --with-mpc=/cross-tools --with-mpfr=/cross-tools \
        --with-gmp=/cross-tools --with-cloog=/cross-tools \
        --enable-cloog-backend=isl --with-isl=/cross-tools \
        --disable-isl-version-check --with-system-zlib --enable-checking=release \
        --enable-libstdcxx-time"
    "make AS_FOR_TARGET=\"${CLFS_TARGET}-as\" \
        LD_FOR_TARGET=\"${CLFS_TARGET}-ld\""
    "make install"
)
PRODUCT="/tools/bin/mips-unknown-linux-gnu-g++"
function_install

###################################
# The END
###################################
echo "DONE"
