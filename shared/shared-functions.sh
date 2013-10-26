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

die () {
	echo ""
	echo "$@"
	echo ""
	exit 1
}

create_archive ( ) (

	local target_dir=$1
	local build_dir=$2
	local store_dir=$3
	local target=$4

	local archive="${store_dir}/${target}.tar.xz"

	pprint 2 "create archive"
	pprint 3 "log: ${target_dir}/logs/create_archive"

	(
	rm -f "$archive"
	cd ${build_dir}/${target}

	if which -s pixz; then
		tar -cf - * | pixz -4 -t -o "$archive"
	else
		echo "Consider installing pixz to speed up compression time"
		echo "for multicore systems."
		tar cJf ${store_dir}/${target}.tar.xz *
	fi

	chmod 777 "$archive"
	pprint 3 "Archive created: $archive"

	) > ${target_dir}/logs/create_archive 2>&1
)

