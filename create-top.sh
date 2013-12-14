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

# Size of the /etc ramdisk in 512 bytes sectors.
# 20480 = 10MB
RAMDISK_ETCSIZE=20480

# Size of the /tmp+/var ramdisk in 512 bytes sectors (usefull for log files).
# 102400 = 50MB
RAMDISK_VARSIZE=102400

DISK_LABEL=imgBSD

# Media geometry, only relevant if bios doesn't understand LBA.
DISK_SECTS=63
DISK_HEADS=255

# Max size of OS that is allowed in MB.
MAX_OS_SIZE=2000

# Newfs parameters to use
NEWFS="-b 4096 -f 512 -i 8192 -O2 -o time"

# Progress Print level
PPLEVEL=3

#######################################################################
#
# Main functions
#
#######################################################################

run_customize() (
	pprint 2 "run customize scripts"
	for c in ${CUSTOM_FUNCTIONS:-}
	do
		pprint 2 "customize \"$c\""
		pprint 3 "log: ${TARGET_DIR}/logs/cust.$c"
		pprint 4 "`type $c`"
		( set -x ; $c ) > ${TARGET_DIR}/logs/cust.$c 2>&1
	done
)

run_release_functions() (
        pprint 2 "run release scripts"
	if [ -n "${RELEASE_FUNCTIONS:-}" ]; then
		for c in $RELEASE_FUNCTIONS
		do
		        pprint 2 "release function \"$c\""
		        pprint 3 "log: ${TARGET_DIR}/logs/release.$c"
		        pprint 4 "`type $c`"
		        ( set -x ; $c ) > ${TARGET_DIR}/logs/release.$c 2>&1
		done
	else
		pprint 3 "There were no release functions"
	fi
)

run_late_customize() (
	pprint 2 "run late customize scripts"
	if [ -n "${LATE_CUSTOM_FUNCTIONS:-}" ]; then
		for c in $LATE_CUSTOM_FUNCTIONS
		do
			pprint 2 "late customize \"$c\""
			pprint 3 "log: ${TARGET_DIR}/logs/late_cust.$c"
			pprint 4 "`type $c`"
			( set -x ; $c ) > ${TARGET_DIR}/logs/late_cust.$c 2>&1
		done
	else
		pprint 3 "There were no late customize functions"
	fi
)

setup_imgBSD() (
        pprint 2 "configure imgBSD setup"
        pprint 3 "log: ${TARGET_DIR}/logs/setup_imgBSD"

        (
        cd ${WORLDDIR}

        # Move /usr/local/etc to /etc/local so that the /cfg stuff
        # can stomp on it.  Otherwise packages like ipsec-tools which
        # have hardcoded paths under ${prefix}/etc are not tweak-able.
        if [ -d usr/local/etc ] ; then
                (
                mkdir -p etc/local
                cd usr/local/etc
                find . -print | cpio -dumpl ../../../etc/local
                cd ..
                rm -rf etc
                ln -s ../../etc/local etc
                )
        fi

        for d in var etc
        do
                # link /$d under /conf
                # we use hard links so we have them both places.
                # the files in /$d will be hidden by the mount.
                # XXX: configure /$d ramdisk size
                mkdir -p conf/base/$d conf/default/$d
                find $d -print | cpio -dumpl conf/base/
        done

        echo "$RAMDISK_ETCSIZE" > conf/base/etc/md_size
        echo "$RAMDISK_VARSIZE" > conf/base/var/md_size

        # pick up config files from the special partition
        echo "mount -o ro /dev/ufs/SurviveBoot" > conf/default/etc/remount

        ) > ${TARGET_DIR}/logs/setup_imgBSD 2>&1
)

setup_base ( ) {
	pprint 2 "setting-up base"

	[ ! -e "$TARGET_DIR" ] || rm -rf $TARGET_DIR

	mkdir -p $TARGET_DIR
	mkdir -p ${TARGET_DIR}/logs

	printenv > ${TARGET_DIR}/_.env

	# Uncompress the base ready for topping
	tar -Jxf "$BASE_BINARY" -C $TARGET_DIR
}

install_packages ( ) (
        pprint 2 "install packages"
	pprint 3 "log: ${TARGET_DIR}/logs/install_packages"

	(
	mkdir ${WORLDDIR}/packages
	mkdir -p ${WORLDDIR}/usr/local/etc
	mkdir -p ${WORLDDIR}/var/cache/pkg/All

	trap "echo 'Running exit trap code' ; umount -f ${PACKAGE_DIR} ; umount -f ${PACKAGE_DIR}/All" 1 2 15 EXIT

	mount_nullfs -o ro ${PACKAGE_DIR} ${WORLDDIR}/packages
	mount_nullfs -o ro ${PACKAGE_DIR}/All ${WORLDDIR}/var/cache/pkg/All

	echo "packagesite: file:///packages" >> ${WORLDDIR}/usr/local/etc/pkg.conf

	cp /usr/bin/install-info ${WORLDDIR}/usr/bin

	while read line; do
		[ -z "$line" ] && continue
		firstChar=`echo $line | cut -c 1`
	        [ "$firstChar" == "#"  ] && continue
		packages="${packages:-} $line"
	done < ${PORT_LIST}

	chroot ${WORLDDIR} sh -c "env ASSUME_ALWAYS_YES=1 pkg install $packages > /pkg_install.log"

	umount -f ${PACKAGE_DIR}
	umount -f ${PACKAGE_DIR}/All
        trap - 1 2 15 EXIT

	# Remove the package repo settings
	rm ${WORLDDIR}/usr/local/etc/pkg.conf
	mv ${WORLDDIR}/pkg_install.log  ${TARGET_DIR}/logs

	) > ${TARGET_DIR}/logs/install_packages 2>&1
)

setup_etc ( ) (
        pprint 2 "configure /etc"
	pprint 3 "log: ${TARGET_DIR}/logs/setup_etc"

        (
        cd ${WORLDDIR}

	# Allow DNS resolving during installation
	echo "nameserver 8.8.8.8" >> etc/resolv.conf

        # create diskless marker file
        touch etc/diskless

        # Make root filesystem R/O by default
        echo "root_rw_mount=NO" >> etc/defaults/rc.conf

        echo "/dev/ufs/${PROJECT}0 / ufs ro 1 1" > etc/fstab
        echo "/dev/ufs/SurviveBoot /cfg ufs ro 2 2" >> etc/fstab
	echo "tmpfs /media tmpfs rw,mode=01777 0 0" >> etc/fstab
	echo "tmpfs /tmp tmpfs rw,mode=01777 0 0" >> etc/fstab
        mkdir -p cfg
        ) > ${TARGET_DIR}/logs/setup_etc
)

newfs_part ( ) (
	local dev mnt lbl
	dev=$1
	mnt=$2
	lbl=$3
	echo newfs ${NEWFS} ${DISK_LABEL:+-L${DISK_LABEL}${lbl}} ${dev}
	newfs ${NEWFS} ${DISK_LABEL:+-L${DISK_LABEL}${lbl}} ${dev}
	mount -o async ${dev} ${mnt}
)

populate_slice ( ) (
	local dev dir mnt lbl
	dev=$1
	dir=$2
	mnt=$3
	lbl=$4
	test -z $2 && dir=${WORLDDIR}/var/empty
	test -d $dir || dir=${WORLDDIR}/var/empty
	echo "Creating ${dev} with ${dir} (mounting on ${mnt})"
	newfs_part $dev $mnt $lbl
	cd ${dir}
	find . -print | grep -Ev '/(CVS|\.svn)' | cpio -dumpv ${mnt}
	df -i ${mnt}
	umount -f ${mnt}
)

required_size ( ) {
	local os_size=$(du -sm $WORLDDIR | awk '{print $1}')

	local required_space=$(( $os_size + 50 ))

	if [ $MAX_OS_SIZE -lt $required_space ]; then
		echo "OS too large! Allowed size: $MAX_OS_SIZE was $required_space" \
			>> ${TARGET_DIR}/logs/create_image
		exit 1
	fi

	echo $(( $required_space * 1000 * 1000 / 512 ))
}

create_image ( ) (
	pprint 2 "create image"
	pprint 3 "log: ${TARGET_DIR}/logs/create_image"

	(
	IMG_SIZE=$(required_size)
	echo $IMG_SIZE

	IMG=${IMG_CONSTRUCT_DIR}/${TARGET}.img
	MNT=${TARGET_DIR}/_.mnt
	mkdir -p ${MNT}

	echo "Creating md backing file..."
	rm -f ${IMG}
	dd if=/dev/zero of=${IMG} seek=${IMG_SIZE} count=0
	MD=`mdconfig -a -t vnode -f ${IMG} -x ${DISK_SECTS} -y ${DISK_HEADS}`

	trap "echo 'Running exit trap code' ; df -i ${MNT} ; umount -f ${MNT} || true ; mdconfig -d -u $MD" 1 2 15 EXIT

	bsdlabel -w -B -b ${WORLDDIR}/boot/boot ${MD}
	bsdlabel ${MD}

	# Create first image
	populate_slice /dev/${MD}a ${WORLDDIR} ${MNT} "0"
	mount /dev/${MD}a ${MNT}
	echo "Generating mtree..."
	( cd ${MNT} && mtree -c ) > ${TARGET_DIR}/logs/mtree
	( cd ${MNT} && du -k ) > ${TARGET_DIR}/logs/du
	umount -f ${MNT}

	mdconfig -d -u $MD

	trap - 1 2 15 EXIT

	rm -rf ${MNT}

	) > ${TARGET_DIR}/logs/create_image 2>&1
)

compress_image ( ) (
	pprint 2 "compress image"
	pprint 3 "log: ${TARGET_DIR}/logs/compress_image"

	(
	cd ${IMG_CONSTRUCT_DIR}

	if which -s pixz; then
		pixz "${TARGET}.img"
	else
		echo "Consider installing pixz to speed up compression time on multicore systems."
		xz "${TARGET}.img"
	fi

	md5 "${TARGET}.img.xz" > "${TARGET}.img.xz.md5"

	[ "$IMG_CONSTRUCT_DIR" = "$IMG_STORE_DIR" ] ||
		mv ${TARGET}.img* $IMG_STORE_DIR

	# Let all users remove the image
	chmod 777 $IMG_STORE_DIR/${TARGET}*

	) > ${TARGET_DIR}/logs/compress_image 2>&1

	pprint 3 "Image created: ${IMG_STORE_DIR}/${TARGET}.img.xz"
)

release_info ( ) {
	pprint 2 "updating /RELEASE.txt"
	pprint 3 "log: ${TARGET_DIR}/logs/release_info"
	(
	local release_file=${WORLDDIR}/RELEASE.txt

	echo "BUILD_TIME=$(date +%H:%M)" >> $release_file
	echo "BUILD_DATE=$(date +%Y%m%d)" >> $release_file
	echo "BUILD_VERSION=$BUILD_VERSION" >> $release_file
	echo "OS_SIZE=$(du -sm $WORLDDIR | awk '{print $1}')MB" >> $release_file

	# get contents of conf file
	cat "$CONF_FILE" | grep -w '^PORTS_VERSION\|^EXTRA_DESC\|^BUILD_NUM' | \
		sed 's/"//g' >> $release_file

	# Get git sha if available
	if [ -f .git/refs/heads/master ]; then
		sha1=$(cat .git/refs/heads/master)
		echo "GIT_REVISION=$sha1" >> $release_file
	fi
	) >> ${TARGET_DIR}/logs/release_info 2>&1
}

#######################################################################
# Install the stuff under ./Files

install_files() (
	pprint 2 "install files"
	pprint 3 "log: ${TARGET_DIR}/logs/install_files"

	(
	cd ${PROJECT_DIR}/Files
	find . -print | grep -Ev '/(CVS|\.svn)' | cpio -Ldumpv -R root:wheel ${WORLDDIR}

	cd ${SCRIPT_DIR}/shared/Files
	find . -print | grep -Ev '/(CVS|\.svn)' | cpio -Ldumpv -R root:wheel ${WORLDDIR}

	) > ${TARGET_DIR}/logs/install_files 2>&1
)

#######################################################################
# Convenience function:
# 	Register all args as customize function.

customize_cmd () {
	CUSTOM_FUNCTIONS="${CUSTOM_FUNCTIONS:-} $*"
}

#######################################################################
# Convenience function:
# 	Register all args as late customize function to run just before
#	image creation.

late_customize_cmd () {
	LATE_CUSTOM_FUNCTIONS="${LATE_CUSTOM_FUNCTIONS:-} $*"
}

#######################################################################
# Convenience function:
#       Register all args as release function to run before
#       exiting script.

release_cmd () {
        RELEASE_FUNCTIONS="${RELEASE_FUNCTIONS:-} $*"
}

#######################################################################
# Allow root login via ssh

cust_allow_ssh_root () (
	sed -i "" -e '/PermitRootLogin/s/.*/PermitRootLogin yes/' \
	    ${WORLDDIR}/etc/ssh/sshd_config
)

#######################################################################
# Commands to run once as a final step

last_orders() {
	pprint 2 "Last orders"

	# Let all users remove the target dir
	chmod 777 ${TARGET_DIR}

	# Tag this target in local git repo
	[ -z "$(git tag | grep ^$TARGET$)" ] &&	git tag "$TARGET"

	[ -z "${BUILD_NUM:-}" ] || increment_build_num
}

increment_build_num() {
	NUM=$(sed -n "s/^BUILD_NUM\=\(.*\)/\1/p" ${CONF_FILE} | sed 's/"//g')
	[ -n "$NUM" ] || return 0
	NUM=$(echo $NUM | sed 's/0*//')
	NUM=$(($NUM+1))

	count=$(echo $NUM | wc -L)
	while [ $count -lt 3 ]; do
		NUM="0$NUM"
		count=$(echo $NUM | wc -L)
	done

	sed -i.bak s/^BUILD_NUM=.*/BUILD_NUM=$NUM/g ${CONF_FILE}
	rm ${CONF_FILE}.bak
}

compress_kernel() {
	# Compress the kernel (save 3Mb)
	if [ -f ${WORLDDIR}/boot/kernel/kernel ]; then
		if ! gzip -v9 ${WORLDDIR}/boot/kernel/kernel; then
			echo "Error during zipping the kernel"
		fi
	fi
}

# Progress Print
#	Print $2 at level $1.
pprint() {
    if [ "$1" -le $PPLEVEL ]; then
	runtime=$(( `date +%s` - $BUILD_STARTTIME ))
	printf "%s %.${1}s %s\n" "`date -u -r $runtime +%H:%M:%S`" "#####" "$2" 1>&3
    fi
}

usage () {
	(
	echo "Usage: $0 [-qvas r <release dir> -D <target dir> -A <dir to archive> -p <project dir> ] -c conf-file"
	echo ""
	echo "Compulsory:"
	echo "  -c	Specify conf file"
	echo ""
	echo "Build Options:"
	echo "  -s	Skip creating the img binary and just create the target dir"
	echo "  -a	Archive target dir to .tar.xz once the build is complete"
	echo ""
	echo "Post Build - Choose only one:"
	echo "  -D	Create disk img binary of specified target dir only"
	echo "  -A	Archive specified target dir to .tar.xz only"
	echo ""
	echo "Other:"
	echo "  -q	Make output more quiet"
	echo "  -v	Make output more verbose"
	echo "  -r      Release Build - run release functions and store everything to release directory"
	echo "  -p	Specify dir containing the projects conf files (default is relative to conf file)."
	echo "    	Usefull when using a conf file not in the same directory as the project files"
	) 1>&2
	exit 2
}

#######################################################################
# Parse arguments

diskimg_only=false
archive_only=false
do_archive=false
skip_img_build=false
release_build=false

if [ $# -eq 0 ] ; then
	echo "You gave no arguments"
	usage
fi

set +e
args=`getopt c:p:A:D:asqr:hv $*`
[ $? -ne 0 ] && usage
set -e

set -- $args
for i
do
	case "$i" 
	in
	-c) . "$2"; export CONF_FILE="$2"; shift; shift;;
	-D) diskimg_only=true; export TARGET_DIR_IN="$2"; shift; shift;;
	-a) do_archive=true; shift;;
	-A) archive_only=true; export ARCHIVE_IN="$2";  shift; shift;;
	-s) skip_img_build=true; shift;;
	-p) export PROJ_DIR_IN="$2"; shift; shift;;
	-r) export release_build=true; export STORE_DIR_IN="$2"; shift; shift;;
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

# This script should be run as root, or with sudo
[ "$(whoami)" = "root" ] || die "You are not root"

# Does the user want the project directory separate from the conf file directory
if [ -n "${PROJ_DIR_IN:-}" ]; then
	PROJECT_DIR="$PROJ_DIR_IN"
else
	PROJECT_DIR="$(dirname $(dirname "$CONF_FILE"))"
fi

# Absolute path to the config file
CONF_FILE=$(realpath "$CONF_FILE")

[ -d "$BUILD_DIR" ] || mkdir -p "$BUILD_DIR"
[ -e "$BASE_BINARY" ] || mkdir -p "$BASE_BINARY"
[ -d "$IMG_STORE_DIR" ] || mkdir -p "$IMG_STORE_DIR"
[ -d "$IMG_CONSTRUCT_DIR" ] || mkdir -p "$IMG_CONSTRUCT_DIR"
set -e

# If the user has given a BUILD_NUM process it
$release_build && unset BUILD_NUM
[ -n "${BUILD_NUM:-}" ] && ADD_BUILD_NUM="_$BUILD_NUM"

# Get the base info from compressed archive
base_info=$(tar -xJqOf $BASE_BINARY _.w/RELEASE.txt)
BASE_VERSION=$(echo "$base_info" | grep ^"BASE_VERSION=" | awk -F'=' '{print $NF}')
BSD_VERSION=$(echo "$base_info" | grep ^"BSD_VERSION=" | awk -F'=' '{print $NF}')

# Get Current date for BUILD_VERSION
BUILD_VERSION=$(date '+%Y%m%d')

TARGET=${PROJECT}_${EXTRA_DESC:-GENERIC}_b${BSD_VERSION}-${BASE_VERSION:-0.0}_${BUILD_VERSION}${ADD_BUILD_NUM:-}
TARGET_DIR="${BUILD_DIR}/${TARGET}"
WORLDDIR=${TARGET_DIR}/_.w

if $release_build; then
	IMG_STORE_DIR="${STORE_DIR_IN}/$TARGET"
	mkdir -p "$IMG_STORE_DIR"
fi

BUILD_STARTTIME=`date +%s`

export CUSTOM_FUNCTIONS
export NEWFS
export TARGET
export TARGET_DIR
export DISK_HEADS
export DISK_SECTS
export WORLDDIR
export DISK_LABEL
export BASE_ARCHIVE_NAME
export MAX_OS_SIZE
export PROJECT
export BASE_BINARY
export IMG_CONSTRUCT_DIR
export IMG_STORE_DIR
export PROJECT_DIR
export PORT_LIST

#######################################################################

# File descriptor 3 is used for logging output, see pprint
exec 3>&1

if $diskimg_only; then
	TARGET_DIR="$TARGET_DIR_IN"
	TARGET=$(basename "$TARGET_DIR_IN")
	WORLDDIR=${TARGET_DIR}/_.w
	pprint 1 "$TARGET image build starting"
	create_image
	compress_image
	pprint 1 "$TARGET image build completed"
	exit 0
elif $archive_only; then
	TARGET=$(basename "$ARCHIVE_IN")
	pprint 1 "Creating archive of target: $TARGET"
	create_archive "$ARCHIVE_IN" "$BUILD_DIR" "$IMG_STORE_DIR" "$TARGET"
	pprint 1 "Archiving of $TARGET completed"
	exit 0
fi

pprint 1 "$PROJECT image build starting"

setup_base
setup_etc
install_packages
install_files
run_customize
setup_imgBSD
run_late_customize
release_info

if $skip_img_build; then
	pprint 2 "Skipping creating the image file"
else
	pprint 2 "Creating image file"
	create_image
	compress_image
fi

# Does the user want to archive the target dir
$do_archive && create_archive "$TARGET_DIR" "$BUILD_DIR" "$IMG_STORE_DIR" "$TARGET"

last_orders

pprint 1 "$PROJECT image completed successfully"

# If !"release (-r) is given then run separate release functions
$release_build && run_release_functions

exit 0
