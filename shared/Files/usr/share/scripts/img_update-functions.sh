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

die() {
	echo "$@"
	exit 1
}

am_i_root() {
	[ "$(whoami)" = "root" ] || die "You must be root"
}

timer() {
	if [ "$1" = "start" ]; then
		T="$(date +%s)"
	elif [ "$1" = "stop" ]; then
		T="$(($(date +%s)-T))"
		printf "Took: %02dh %02dm %02ds\n" "$((T/3600%24))" \
		    "$((T/60%60))" "$((T%60))"""
	fi
}

############################################################
set_partition_info() {
	# Get data just once
	GLABEL_DATA=$(glabel status)

	CURRENT_LABEL=$(mount | grep -w / | awk '{print $1}' | awk -F"/" '{print $NF}')

	# Common label name of both partitions
	LABEL=$(echo ${CURRENT_LABEL} | sed 's/.\{1\}$//')

	# What slice is currently running
	CURRENT_SLICE=$(echo "$GLABEL_DATA" | grep $CURRENT_LABEL | awk '{print $3}' |\
		sed 's/.\{1\}$//')

	DRIVE=$(echo $CURRENT_SLICE | awk -F"s" '{print $1}')

	CURRENT_PARTITION_NUM=$(echo $CURRENT_SLICE | awk -F"s" '{print $2}')

	# The Target Label is simply the opposite to the current one
	if [ "$CURRENT_LABEL" = "${LABEL}0" ]; then
		TARGET_LABEL="${LABEL}1"
	else
		TARGET_LABEL="${LABEL}0"
	fi

	# Used for dd'ing img and labeling new drive with tunefs
        TARGET_SLICE=$(echo "$GLABEL_DATA" | grep $TARGET_LABEL | awk '{print $3}' |\
		sed 's/.\{1\}$//' )

	# If project has changed searching by label will not work
	if [ -z "${TARGET_SLICE:-}" -o "$TARGET_LABEL" = "$CURRENT_LABEL" ]; then
		echo "# Could not easily detected target label."
		echo "# Falling back to locating by matching partition size"
		# Get size of current partition
		CUR_SIZE=$(gpart list $CURRENT_SLICE | grep Mediasize | \
			tail -1 | awk '{print $2}')

		#Get partition from matching size
		TARGET_SLICE=$(gpart list | grep -v $CURRENT_SLICE | \
			grep -B1 $CUR_SIZE | grep Name | \
			awk '{print $3}' | uniq)
	fi

	# Used to set the partition as active with gpart
	TARGET_PARTITION_NUM=$(echo $TARGET_SLICE | awk -F"s" '{print $2}')

	ACTIVE_PARTITION=$(gpart show "$DRIVE" | grep "\[active\]" | awk '{print $3}')
}

print_partition_info() {
	echo ""
	echo "    Current Label = $CURRENT_LABEL"
	echo "     Target Label = $TARGET_LABEL"
	echo "            DRIVE = $DRIVE"
	echo "    CURRENT SLICE = $CURRENT_SLICE"
	echo "     TARGET SLICE = $TARGET_SLICE"
	echo "CURRENT PARTITION = $CURRENT_PARTITION_NUM"
	echo " TARGET PARTITION = $TARGET_PARTITION_NUM"
	echo " ACTIVE PARTITION = $ACTIVE_PARTITION"
	echo ""
}

check_for_update() {
	#get version file
	#find what the lastest version is
}

compare_md5() {
	local img=$1
	md5file=${img}.md5
	md5_of_image=$(md5 $img | awk '{print $4}')
	extracted_md5=$(cat $md5file | awk '{print $4}') &&

        [ "$md5_of_image" = "$extracted_md5" ] ||
		die "md5 Checksums to not match. ERROR!"
}

unmount_target() {
	mounted=$(mount | grep $LABEL | grep -vw / | awk '{print $3}')
	if [ -n "${mounted}" ]; then
		if ! umount $mounted; then umount -f $mounted; fi
	else
		mounted=$(mount | grep $DRIVE | grep ${LABEL}0 | \
			grep -vw / | awk '{print $3}')
		if [ -n "${mounted}" ]; then
			if ! umount $mounted; then umount -f $mounted; fi
		fi
	fi
}

get_from_s3() {
	url="s3.imgbsd.org"
	ls_files=$(curl -s $url | \
		sed "s%\>\<%>\\`echo -e '\n\r'`<%g" | \
		grep -o '<Key>.*</\Key>' | \
		awk -F'<Key>' '{print $2}' | \
		awk -F'</Key>' '{print $1}')
}

get_disk_image() {
	mkdir -p $IMG_DIR &&
        cd $IMG_DIR && 
	IMAGE_VERSION=$(curl -s ${SERVER}/${LABEL}/latest | tail -1)
	[ -e "${IMG_DIR}/${IMAGE_VERSION}" ] || curl -O ${SERVER}/${LABEL}/$IMAGE_VERSION
        	#scp ${SERVER}/$IMAGE_VERSION $IMG_DIR &&
	curl -O ${SERVER}/${LABEL}/${IMAGE_VERSION}.md5
	compare_md5 "$IMG"
}

overlay_has_files() {
	local overlay_dir=$1

	[ -d "$overlay_dir" ] || return 1

	[ -n "$(ls -A $overlay_dir > /dev/null 2>&1)" ] || return 1
} 

do_overlay_copy() {
	local overlay_dir=$1
	local mnt_dir=$2

	# Copy Overlay
	if [ -d "$overlay_dir" ]; then
		cd "$overlay_dir"
		find . -print | cpio -dumpl ${mnt_dir}
	fi
}

setup_first_part() (
	echo "Preparing image on first partition"
	if overlay_has_files "$OVERLAY_DIR"; then
		mkdir -p $MNT_DIR
		trap "umount ${MNT_DIR}" 1 2 15 EXIT
			mount /dev/ufs/${LABEL}0 ${MNT_DIR}
			do_overlay_copy $OVERLAY_DIR $MNT_DIR
			umount $MNT_DIR
		trap 1 2 15 EXIT
	fi
)

setup_second_part() (
	echo "Preparing image on second partition"
	mkdir -p $MNT_DIR
	trap "umount ${MNT_DIR}" 1 2 15 EXIT
	mount /dev/ufs/${LABEL}1 ${MNT_DIR}
	sed -i "" "s/${LABEL}0/${LABEL}1/" ${MNT_DIR}/conf/base/etc/fstab
	sed -i "" "s/${LABEL}0/${LABEL}1/" ${MNT_DIR}/etc/fstab
	# Copy Overlay
	if overlay_has_files "$OVERLAY_DIR"; then
		do_overlay_copy $OVERLAY_DIR $MNT_DIR
	fi
	umount $MNT_DIR
	trap 1 2 15 EXIT
)

copy_img_to_drive() {
	local img="$1"
	echo "Copying image to /dev/${TARGET_SLICE}"
	xzcat "$img" | dd of=/dev/${TARGET_SLICE} obs=64k > /dev/null 2>&1
	fsck_ffs -n /dev/${TARGET_SLICE}a > /dev/null 2>&1
}

perform_system_upgrade() {
	local img="$1"
	if [ "$TARGET_LABEL" = "${LABEL}1" ]; then
		trap "tunefs -L ${LABEL}1 /dev/${TARGET_SLICE}a" EXIT INT TERM
       			copy_img_to_drive "$img"
		trap - EXIT
		tunefs -L ${LABEL}1 /dev/${TARGET_SLICE}a
		setup_second_part
	elif [ "$TARGET_LABEL" = "${LABEL}0" ]; then
		copy_img_to_drive "$img"
		setup_first_part
	fi
}

store_update_info() {
	local file_out="/tmp/img_update.txt"
	print_partition_info > "$file_out"
}

set_active_partition() {
	local partition="$1"
	local drive="$2"
	gpart set -a active -i "$partition" "$drive" > /dev/null 2>&1
}

ensure_current_part_is_active_part() {
	current_active_part_num=$(gpart show "$DRIVE" | grep "\[active\]" | awk '{print $3}')
	if [ ! "$current_active_part_num" = "$CURRENT_PARTITION_NUM" ]; then
		echo "***The system has already been updated since last boot.***"
		echo "***Reverting active partition to current in case of update failure.***"
		set_active_partition "$CURRENT_PARTITION_NUM" "$DRIVE"
	fi
}
