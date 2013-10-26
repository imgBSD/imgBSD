#!/bin/sh
#
# Copyright (c) 2013 Ashley Diamond.
# All rights reserved.
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

# Size of each partition in MB
OS_PART_SIZE=2000

# Block size in MB to copy to the DISK
BLOCK_SIZE=1

# Size of CFG partition in MB
CFG_PART_SIZE=200

############################################

die() {
	echo ""
	echo "$@"
	exit 1
}

create_dirs() {
	mount_dir="/tmp_mount_${PROJECT}.$$"
	mkdir $mount_dir
	mount /dev/${DISK}s3b $mount_dir

	mkdir -p ${mount_dir}/.system/var_db
	mkdir -p ${mount_dir}/.system/pbi

	[ "$PROJECT" = "imgBSD" ] && mkdir -p ${mount_dir}/.system/gconf

	umount $mount_dir || umount -f $mount_dir

	rm -fr $mount_dir
}

isDiskLargeEnough() {
	# Hack: For now return true if it is a memory device untill we
	# can figure out a way to get the size of a memory device.
	[ -n "$(echo "$DISK" | grep md)" ] && return 0

	disk_size_in_GB=$(gpart show $DISK | grep "=>" | awk '{print $NF}' | tr -d '\(\)G')
	disk_size_in_MB=$(echo "$disk_size_in_GB * 1000" | bc | awk -F. '{print $1}') 

	required_size=$(echo "$OS_PART_SIZE * 2 + $CFG_PART_SIZE" | bc)
	echo "$required_size -gt $disk_size_in_MB"
	[ $disk_size_in_MB -gt $required_size ] || return 1
}

create_partitions() {
	# Destroy partition layout
	dd if=/dev/zero of=/dev/$DISK bs=512 count=1

	# Crete MBR layout and install bootloader
	gpart create -s mbr $DISK
	gpart bootcode -b /boot/boot0 $DISK

	# Reduce the time before a FreeBSD slice is booted
	boot0cfg -t 50 /dev/$DISK

	# Create the two OS partitions
	gpart add -t freebsd -s ${OS_PART_SIZE}M $DISK
	gpart add -t freebsd -s ${OS_PART_SIZE}M $DISK

	# Create a partition of the rest of the drive
	gpart add -t freebsd $DISK

	# Make sure 3rd part is destroyed even if not there
	gpart destroy -F ${DISK}s3 > /dev/null 2>&1 || true

	gpart set -a active -i 1 $DISK

	# Create a slice with the third partition
	gpart create -s bsd ${DISK}s3

	gpart add -t freebsd-ufs -a 4k -s ${CFG_PART_SIZE}M ${DISK}s3
	gpart add -t freebsd-ufs -a 4k ${DISK}s3

	# Create the file-systems
	newfs -LSurviveBoot /dev/${DISK}s3a > /dev/null 2>&1
	if [ "$PROJECT" = "imgBSD" ]; then
		newfs -U -LHome /dev/${DISK}s3b
	fi
}

write_images() {
	echo "DD'ing image from $IMAGE to partition /dev/${DISK}s1..."
	xzcat -f ${IMAGE} | dd of=/dev/${DISK}s1 bs=${BLOCK_SIZE}M
	echo "done"
}

usage() {
	echo "  -d    disk image to write to i.e. da0, ada0, md0"
	echo "  -p    project name, used to label partitions. i.e. imgBSD"
	echo "  -i    image file to write to disk, extension img.xz"
	echo ""
	echo "Optional"
	echo "  -b    size of block in MB to write to disk. Default 1MB"
	echo "  -s    size of each image partition in MB. Default 2000MB"
	echo ""
}

############################################
if [ $# -eq 0 ] ; then
	echo "You gave no arguments"
	usage
fi

set +e
args=`getopt i:p:b:d:s:h $*`
if [ $? -ne 0 ] ; then
	usage
fi
set -e

set -- $args
for i
do
	case "$i" 
	in
	-d) DISK="$2"; shift; shift;;
	-p) PROJECT="$2"; shift; shift;;
	-i) IMAGE="$2"; shift; shift;;
        -b) BLOCK_SIZE="$2"; shift; shift;;
	-s) OS_PART_SIZE="$2"; shift; shift;;
	-h) usage;;
	--) shift; break
	esac
done

if [ $# -gt 0 ] ; then
	echo "$0: Extraneous arguments supplied"
	usage
fi

[ -n "${DISK:-}" ] || die "You must enter a drive"
[ -n "${IMAGE:-}" ] || die "You must enter an image file"
[ -n "${PROJECT:-}" ] || die "You must enter a PROJECT name"
[ -e "${IMAGE:-}" ] || die "The image file $IMAGE does not exist"

###############################################

[ "$(whoami)" = "root" ] || die "You must be root"

# Get rid of /dev/ if its there
DISK=$(echo $DISK | sed 's%/dev/%%g')

# Does the DISK exist
[ -e "/dev/$DISK" ] || die "DISK does not exist"

# Make sure the disk is big enough
isDiskLargeEnough ||
	die "The disk is not big enough. You need atleast: $required_size"

create_partitions

write_images > /dev/null 2>&1

create_dirs > /dev/null 2>&1

exit 0
