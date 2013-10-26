#!/bin/sh
#
# Copyright (c) 2013 Ashley Diamond.
# All rights reserved.
#
# Based on nanoBSD.sh script: Copyright (c) 2005 Poul-Henning Kamp.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

set -e
set -u

. shared/shared-functions.sh

SCRIPT_DIR=$(pwd)

# Progress Print level
PPLEVEL=3

#######################################################################
#
# The functions which do the real work.
# Can be overridden from the config file(s)
#
#######################################################################

prep_env ( ) (
	pprint 2 "Clean and create object directory (${TARGET_DIR})"

	if ! rm -rf ${TARGET_DIR} > /dev/null 2>&1 ; then
		chflags -R noschg ${TARGET_DIR}
		rm -r ${TARGET_DIR}
	fi
	mkdir -p ${TARGET_DIR}/_.w
	mkdir -p ${TARGET_DIR}/logs/base
	printenv > ${TARGET_DIR}/logs/base/environment

	# Assumes KERN_CONF file is not needed in BSD source
	rm -f ${BSD_SRC}/sys/${ARCH}/conf/${KERNEL_CONF}
	cp ${PROJECT_DIR}/conf/${KERNEL_CONF} ${BSD_SRC}/sys/${ARCH}/conf
)

make_conf_build ( ) (
	pprint 2 "Construct build make.conf ($MAKE_CONF_BUILD)"

	echo "${CONF_WORLD}" > ${MAKE_CONF_BUILD}
	echo "${CONF_BUILD}" >> ${MAKE_CONF_BUILD}
	echo "SRCCONF=/dev/null" >> ${MAKE_CONF_BUILD}
)

build_buildtools ( ) (
	pprint 2 "Creating build tools"
	pprint 3 "log: ${TARGET_DIR}/logs/base/build_buildtools"

	cd ${BSD_SRC}

	env TARGET_ARCH=${ARCH} ${MAKE_IN_PARALLEL} kernel-toolchain \
		__MAKE_CONF=${MAKE_CONF_BUILD} \
		KERNCONF=${KERNEL_CONF}
		> ${TARGET_DIR}/logs/base/build_buildtools 2>&1
)

build_world ( ) (
	pprint 2 "run buildworld"
	pprint 3 "log: ${TARGET_DIR}/logs/base/build_world"

	cd ${BSD_SRC}
	env TARGET_ARCH=${ARCH} ${MAKE_IN_PARALLEL} \
		__MAKE_CONF=${MAKE_CONF_BUILD} buildworld \
		> ${TARGET_DIR}/logs/base/build_world 2>&1
)

build_kernel ( ) (
	pprint 2 "build kernel ($KERNEL_CONF)"
	pprint 3 "log: ${TARGET_DIR}/logs/base/build_kernel"

	(
	cd ${BSD_SRC};
	# unset these just in case to avoid compiler complaints
	# when cross-building
	unset TARGET_CPUTYPE
	unset TARGET_BIG_ENDIAN

	env TARGET_ARCH=${ARCH} ${MAKE_IN_PARALLEL} buildkernel \
		__MAKE_CONF=${MAKE_CONF_BUILD} \
		KERNCONF=${KERNEL_CONF}
	) > ${TARGET_DIR}/logs/base/build_kernel 2>&1
)

make_conf_install ( ) (
	pprint 2 "Construct install make.conf ($MAKE_CONF_INSTALL)"

	echo "${CONF_WORLD}" > ${MAKE_CONF_INSTALL}
	echo "${CONF_INSTALL}" >> ${MAKE_CONF_INSTALL}
	echo "SRCCONF=/dev/null" >> ${MAKE_CONF_INSTALL}
)

install_world ( ) (
	pprint 2 "installworld"
	pprint 3 "log: ${TARGET_DIR}/logs/base/install_world"

	cd ${BSD_SRC}
	env TARGET_ARCH=${ARCH} \
	${MAKE_IN_PARALLEL} __MAKE_CONF=${MAKE_CONF_INSTALL} installworld \
		DESTDIR=${WORLDDIR} \
		> ${TARGET_DIR}/logs/base/install_world 2>&1
	chflags -R noschg ${WORLDDIR}
)

install_etc ( ) (

	pprint 2 "install /etc"
	pprint 3 "log: ${TARGET_DIR}/logs/base/install_etc"

	cd ${BSD_SRC}
	env TARGET_ARCH=${ARCH} \
	${MAKE_IN_PARALLEL} __MAKE_CONF=${MAKE_CONF_INSTALL} distribution \
		DESTDIR=${WORLDDIR} \
		> ${TARGET_DIR}/logs/base/install_etc 2>&1
	# make.conf doesn't get created by default, but some ports need it
	# so they can spam it.
	cp /dev/null ${WORLDDIR}/etc/make.conf
)

install_kernel ( ) (
	pprint 2 "install kernel ($KERNEL_CONF)"
	pprint 3 "log: ${TARGET_DIR}/logs/base/install_kernel"

	(
	cd ${BSD_SRC}
	env TARGET_ARCH=${ARCH} ${MAKE_IN_PARALLEL} installkernel \
		DESTDIR=${WORLDDIR} \
		__MAKE_CONF=${MAKE_CONF_INSTALL} \
		KERNCONF=${KERNEL_CONF}
	) > ${TARGET_DIR}/logs/base/install_kernel 2>&1
)

release_info ( ) {
	pprint 2 "creating /RELEASE.txt"
	pprint 3 "log: ${TARGET_DIR}/logs/release_info"
	(
	local release_file=${WORLDDIR}/RELEASE.txt

	echo "BASE_BUILD_TIME=$(date +%H:%M)" > $release_file
	echo "BASE_BUILD_DATE=$(date +%Y%m%d)" >> $release_file
	echo "BASE_PROJECT=$(cat "$CONF_FILE" | grep ^"PROJECT=")"
	cat "$CONF_FILE" |
		grep -w '^BASE_VERSION\|^BASE_BSD\|^BASE_SVN' \
		>> $release_file

	) > ${TARGET_DIR}/logs/release_info 2>&1
}

# Progress Print
#	Print $2 at level $1.
pprint() {
    if [ "$1" -le $PPLEVEL ]; then
	runtime=$(( `date +%s` - $STARTTIME ))
	printf "%s %.${1}s %s\n" "`date -u -r $runtime +%H:%M:%S`" "#####" "$2" 1>&3
    fi
}

usage () {
	(
	echo "Usage: $0 [-qv] [-c config_file]"
	echo "	-q	make output more quiet"
	echo "	-v	make output more verbose"
	echo "	-c	specify config file"
	) 1>&2
	exit 2
}

#######################################################################
# Parse arguments

if [ $# -eq 0 ] ; then
	echo "You gave no arguments"
	usage
fi

set +e
args=`getopt c:hqv $*`
if [ $? -ne 0 ] ; then
	usage
fi
set -e

set -- $args
for i
do
	case "$i" 
	in
	-c) . "$2"; export CONF_FILE="$2"; shift; shift;;
	-h) usage;;
	-q) PPLEVEL=$(($PPLEVEL - 1)); shift;;
	-v) PPLEVEL=$(($PPLEVEL + 1)); shift;;
	--) shift; break
	esac
done

if [ $# -gt 0 ] ; then
	echo "$0: Extraneous arguments supplied"
	usage
fi

#######################################################################
# Setup and Export Internal variables

set +e
[ -n "$CONF_FILE" ] || die "You have provided a configuration file (-c)"
[ -f "$CONF_FILE" ] || die "You have not given a configuration file"
[ "$(whoami)" = "root" ] || die "You are not root"

PROJECT_DIR="$(dirname $(dirname $CONF_FILE))"
[ -f "${PROJECT_DIR}/conf/$KERNEL_CONF" ] ||
	die "Kernel Config \"KERNEL_CONF\" file not found in ${PROJECT_DIR}/conf/$KERNEL_CONF"

[ -d "$BINARY_STORE_DIR" ] || mkdir -p "$BINARY_STORE_DIR"
[ -d "$BUILD_DIR" ] || mkdir -p "$BUILD_DIR"
[ -n "$MAKE_IN_PARALLEL" ] || MAKE_IN_PARALLEL="make"
[ -n ${ARCH:-} ] || ARCH=`uname -p`
set -e

TARGET_NAME=${PROJECT}_base-${BASE_VERSION}_${BSD_VERSION}_${ARCH}
TARGET_DIR=${BUILD_DIR}/${TARGET_NAME}

WORLDDIR=${TARGET_DIR}/_.w
MAKE_CONF_BUILD=${TARGET_DIR}/make.conf.build
MAKE_CONF_INSTALL=${TARGET_DIR}/make.conf.install

export ARCH
export MAKE_CONF_BUILD
export MAKE_CONF_INSTALL
export TARGET_DIR
export TARGET_NAME
export MAKE_IN_PARALLEL
export BSD_SRC
export WORLDDIR
export BINARY_STORE_DIR
export KERNEL_CONF
export PROJECT_DIR

# File descriptor 3 is used for logging output, see pprint
exec 3>&1

STARTTIME=`date +%s`
pprint 1 "$PROJECT image ${TARGET_NAME} build starting"

pprint 2 "Creating build tree (as instructed)"
prep_env
make_conf_build

[ "$ARCH" = "armv6" ] && build_buildtools

build_world

pprint 2 "Doing buildkernel (as instructed)"
build_kernel

make_conf_install
install_world
install_etc
install_kernel

release_info

create_archive $TARGET_DIR $BUILD_DIR $BINARY_STORE_DIR $TARGET_NAME

pprint 1 "$PROJECT base: $TARGET_NAME completed"

exit 0
