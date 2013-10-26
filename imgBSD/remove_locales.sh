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

remove_locale_dir_pattern() {
        local DIRECTORY=$1
	local DIRS_TO_KEEP=$2
	local pattern=""

	cd ${WORLDDIR}/$DIRECTORY

	for d in $DIRS_TO_KEEP; do
		for i in $d; do
			if [ -z "$pattern" ]; then
				pattern="-name $i"
			else
				pattern="$pattern -o -name $i"
			fi
		done
	done

	BEFORE=`du -m -d 0 ${WORLDDIR} | awk '{ print $1 }'`

	find . -maxdepth 1 -type d ! \( $pattern \) -print | xargs rm -rvRf || true

	AFTER=`du -m -d 0 ${WORLDDIR} | awk '{ print $1 }'`
	echo "### Size before=" $BEFORE " size after=" $AFTER
}

remove_locale_file_pattern() {
        local DIRECTORY=$1
	local DIRS_TO_KEEP=$2
	local pattern=""

	cd ${WORLDDIR}/$DIRECTORY

	for d in $DIRS_TO_KEEP; do
		for i in $d; do
			if [ -z "$pattern" ]; then
				pattern="-name $i"
			else
				pattern="$pattern -o -name $i"
			fi
		done
	done

	BEFORE=`du -m -d 0 ${WORLDDIR} | awk '{ print $1 }'`

	find . -maxdepth 1 ! \( $pattern \) -print | xargs rm -rvRf || true

	AFTER=`du -m -d 0 ${WORLDDIR} | awk '{ print $1 }'`
	echo "### Size before=" $BEFORE " size after=" $AFTER
}

remove_share_locales() {

        DIRECTORY="usr/share/locale"
	DIRS_TO_KEEP="UTF-8 en* *GB la_LN* C"

	remove_locale_dir_pattern "$DIRECTORY" "$DIRS_TO_KEEP"
}

remove_X11_locales() {

        DIRECTORY="usr/local/lib/X11/locale"
	DIRS_TO_KEEP="POSIX en* *GB translit_* C"

	remove_locale_dir_pattern "$DIRECTORY" "$DIRS_TO_KEEP"
}

remove_i18n_locales() {

        DIRECTORY="compat/linux/usr/share/i18n/locales"
	DIRS_TO_KEEP="en* *GB POSIX C"

	remove_locale_file_pattern "$DIRECTORY" "$DIRS_TO_KEEP"
}

remove_linux_locales() {

        DIRECTORY="compat/linux/usr/share/locale"
	DIRS_TO_KEEP="C en*"

	remove_locale_dir_pattern "$DIRECTORY" "$DIRS_TO_KEEP"
}

remove_gconf_locales() {

        DIRECTORY="usr/local/relocated/gconf/gconf.xml.defaults"
	FILES_TO_KEEP="%gconf-tree.xml *en* C"

	remove_locale_file_pattern "$DIRECTORY" "$FILES_TO_KEEP"
}

local_share_locale() {

        DIRECTORY="usr/local/share/locale"
	DIRS_TO_KEEP="en* en_*"

	remove_locale_dir_pattern "$DIRECTORY" "$DIRS_TO_KEEP"
}

remove_chromium_locales() {

        DIRECTORY="usr/local/share/chromium/locales"
	FILES_TO_KEEP="en*"

	remove_locale_file_pattern "$DIRECTORY" "$FILES_TO_KEEP"
}

locale_other() {

	DIRS_TO_REMOVE='\
	usr/local/lib/perl5/5.14*/mach/auto/Encode/JP
	usr/local/lib/perl5/5.14*/mach/auto/Encode/KR
	usr/local/lib/perl5/5.14*/mach/auto/Encode/TW
	usr/local/lib/perl5/5.14*/mach/auto/Encode/CN'

	for d in $DIRS_TO_REMOVE
	do	
		echo "Removing ${WORLDDIR}/$d"
		rm -r ${WORLDDIR}/$d ||	echo "Error: Can't remove it!"
	done
}
