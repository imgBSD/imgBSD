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

project_setup() {

	# Allow root to be writable
	mv ${WORLDDIR}/root ${WORLDDIR}/etc/root
	ln -s etc/root ${WORLDDIR}/root

	# Symbolic Links
	rm -fr ${WORLDDIR}/mnt
	mkdir -p ${WORLDDIR}/var/mnt
    	ln -s var/mnt ${WORLDDIR}/mnt

	# Move gconf Folder (35MB) out of /usr/local/etc so it does
	# not end up in /etc and /conf
	mkdir -p ${WORLDDIR}/usr/local/relocated
	mkdir -p ${WORLDDIR}/usr/local/relocated/gconf
        mv ${WORLDDIR}/usr/local/etc/gconf/gconf.xml.defaults ${WORLDDIR}/usr/local/relocated/gconf
        mv ${WORLDDIR}/usr/local/etc/gconf/schemas ${WORLDDIR}/usr/local/relocated/gconf
        ln -s /usr/local/relocated/gconf/gconf.xml.defaults ${WORLDDIR}/usr/local/etc/gconf/gconf.xml.defaults
        ln -s /usr/local/relocated/gconf/schemas ${WORLDDIR}/usr/local/etc/gconf/schemas

	# Relocate pkg database using Hardlink
	mv ${WORLDDIR}/var/db/pkg/local.sqlite ${WORLDDIR}/usr/local/relocated
	ln ${WORLDDIR}/usr/local/relocated/local.sqlite ${WORLDDIR}/var/db/pkg/local.sqlite

	# Remove Broken link to SRC
	rm -rf ${WORLDDIR}/sys

	mkdir ${WORLDDIR}/usr/home
	ln -s usr/home ${WORLDDIR}/home

	# fstab
	echo "proc /proc procfs rw 0 0" >> ${WORLDDIR}/etc/fstab
	echo "/dev/ufs/Home /usr/home ufs rw,noatime 0 0" >> ${WORLDDIR}/etc/fstab
	echo "/home/.system/pbi /usr/pbi unionfs rw 0 0" >> ${WORLDDIR}/etc/fstab
	echo "/home/.system/var_db /var/db unionfs rw 0 0" >> ${WORLDDIR}/etc/fstab
}

project_late_setup() {

}

create_guest_account() {
	chroot ${WORLDDIR} sh -c 'echo "begin" | \
		pw useradd -n begin -c "Begin Here (Guest)" -G wheel,operator \
		-s /bin/sh -d /tmp/begin_home -h 0'
}

linux_compat() {
	mkdir -p ${WORLDDIR}/usr/local/lib/browser_plugins
	ln -s /usr/local/lib/npapi/linux-f10-flashplugin/libflashplayer.so \
		   ${WORLDDIR}/usr/local/lib/browser_plugins/
	echo "linproc /compat/linux/proc linprocfs rw 0 0" >> ${WORLDDIR}/etc/fstab
}

