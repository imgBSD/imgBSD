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

set -u
set -e

die() {
	echo "$@"
	echo ""
	exit 1
}

usage() {
	echo ""
	echo "  -s	Size of VBox image in MB. Should be atleast 5000"
	echo ""
	echo "  -i	ImgBSD img.xz file to use"
	exit 1
}

############################################
if [ $# -eq 0 ] ; then
	echo "You gave no arguments"
	usage
fi

set +e
args=`getopt i:s:h $*`
if [ $? -ne 0 ] ; then
	usage
fi
set -e

set -- $args
for i
do
	case "$i" 
	in
	-i) IMG="$2"; shift; shift;;
	-s) VBOX_SIZE="$2"; shift; shift;;
	-h) usage;;
	--) shift; break
	esac
done

if [ $# -gt 0 ] ; then
	echo "$0: Extraneous arguments supplied"
	usage
fi

[ -n "$IMG" ] || die "You did not enter an img file"
[ -n "$VBOX_SIZE" ] || die "Enter max size of VBOX image in MB, -s 8000"
[ $VBOX_SIZE -gt 4999 ] || die "You must enter a vbox size of 5000 or greater."
[ -e "$IMG" ] || die "Image cannot be found"

[ "$(whoami)" = "root" ] || die "You must be root"

which -s VBoxManage || die "You do not have VBoxManage installed"

IMG_DIR=$(dirname "$IMG")
SCRIPT_DIR=$(dirname "$0")


# Final image location/name
IMG_NAME=$(basename "$IMG")
DD_DISK_NAME=$(echo "$IMG_NAME" | awk -F'.img.xz' '{print $1}')

DD_DISK_IMAGE="${SCRIPT_DIR}/$DD_DISK_NAME"
VDI_IMAGE="${DD_DISK_IMAGE}.vdi"

PROJECT=$(echo "$DD_DISK_NAME" | awk -F'_' '{print $1}')

###############################################

echo "===> Creating empty disk image"
# 5GB = 5000MB*1024*1024 / 4096bytes (4k/blocksize) = 1280000
BYTES=$(let VBOX_SIZE*1024*1024 / 4096)
dd if=/dev/zero of="$DD_DISK_IMAGE" seek="$BYTES" count=0 bs=4k > /dev/null 2>&1

echo "===> Creating memory device"
MD=$(mdconfig -o async -a -t vnode -f "$DD_DISK_IMAGE" -x 63 -y 255)

# Partition disk image and install OS
trap "echo 'Running exit trap code' ; mdconfig -d -u $MD" 1 2 15 EXIT
	echo "===> Creating Bootable disk image"
	${SCRIPT_DIR}/create-bootable-drive.sh -d "$MD" -p "$PROJECT" -i "$IMG" -b "1"
trap - 1 2 15 EXIT

echo "===> Disconecting Memory Device"
mdconfig -d -u $MD

echo "===> Creating Vbox image"
[ -e "$VDI_IMAGE" ] && rm -f "$VDI_IMAGE"
VBoxManage convertdd "$DD_DISK_IMAGE" "$VDI_IMAGE" --format VDI  > /dev/null 2>&1

# Remove interim MD disk
rm -r "$DD_DISK_IMAGE"

echo "===> Changing permissions of disk"
chmod 777 "$VDI_IMAGE"

echo "===> Image created: $VDI_IMAGE"

exit 0
