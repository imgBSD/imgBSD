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

RC_LOCAL_FILE="/etc/rc.conf.local"
WLAN_INTERFACES="an ath ath_pci bwi bwn ipw iwi iwn malo mwl ral wi wpi"
INTERFACES=$(ifconfig -l)
EXISTING_WLAN_COUNTER=""

#######################################

isWLAN() {
	for wlan_if in $WLAN_INTERFACES; do
		[ $1 = $wlan_if ] && return 0
	done
	return 1
}

startDhclient() {
	local ifs=$(echo "$new_if_list" | grep DHCP | \
		awk -F'_' '{print $NF}' | awk -F'=' '{print $1}')

	for i in $ifs; do
		(dhclient -q "$i" ) &
	done
}

setWlanCounter() {

	[ -f "$RC_LOCAL_FILE" ] || return 0

	EXISTING_WLAN_COUNTER=$(cat "$RC_LOCAL_FILE" | grep "ifconfig_wlan" | \
		grep -v "DHCP" | wc -l | tr -d ' ')
}

addLineToIFList() {
	local line="$1"
	new_if_list="${new_if_list:-}
$line"
}

addWLAN() {
	local interface="$1"

	local WLAN_COUNT=$(echo -e "${new_if_list:-}" | grep ^wlans_ | wc -l | tr -d ' ')

	if [ -n "$EXISTING_WLAN_COUNTER" ]; then
		WLAN_COUNTER=$(expr $EXISTING_WLAN_COUNTER + $WLAN_COUNT + 1)
	else
		WLAN_COUNTER=$WLAN_COUNT
	fi

	addLineToIFList "ifconfig_wlan${WLAN_COUNTER}=\"WPA DHCP\""
	addLineToIFList "wlans_${interface}=\"wlan${WLAN_COUNTER}\""
}

lanConfigOverrides() {
	local interface="$1"

	[ -f "$RC_LOCAL_FILE" ] || return 1

	result=$(cat "$RC_LOCAL_FILE" | grep "ifconfig_${interface}=" | grep -v "DHCP" )

	[ -n "${result:-}" ] || return 1
}

wlanConfigOverrides() {
	local interface="$1"

	[ -f "$RC_LOCAL_FILE" ] || return 1

	wlan_num=$(cat "$RC_LOCAL_FILE" | grep "wlans_${interface}=" | tr -d '\"' | awk -F '=wlan' '{print $NF}')
	result=$(cat "$RC_LOCAL_FILE" | grep "ifconfig_wlan${wlan_num}=" | grep -v "DHCP")

	[ -n "${result:-}" ] || return 1
}

addNonWLAN() {
	local interface="$1"

	addLineToIFList "ifconfig_${interface}=\"DHCP\""
}

scan_INTERFACES() {
	for interface in $INTERFACES; do
		# ignore local interface
		[ $interface = "lo0" ] && continue

		interface_name=$(echo $interface | tr -d [0-9])

		if isWLAN $interface_name ; then
			wlanConfigOverrides $interface || addWLAN $interface
		else
			# This is not a WLAN interface
			lanConfigOverrides $interface || addNonWLAN $interface
		fi
	done

	# Remove empty lines and sort the new list
	new_if_list=$(echo -e "${new_if_list:-}" | sed '/^$/d' | sort | uniq)
}

#######################################

# Get details of what is currently in RC_LOCAL file
if [ -f "$RC_LOCAL_FILE" ]; then
	old_if_list=$(cat "$RC_LOCAL_FILE" | grep ^'ifconfig_\|wlans_' | grep -v 'DHCP')

	# Remove empty lines and sort the list
	old_if_list=$(echo -e "${old_if_list:-}" | sed '/^$/d' | sort | uniq)
else
	old_if_list=""
fi

setWlanCounter
scan_INTERFACES

# Only perform aditional actions if the lists are different
[ "$new_if_list" != "$old_if_list" ] || exit 0

echo -e "$new_if_list">> "$RC_LOCAL_FILE"
(cfg add ${RC_LOCAL_FILE}) &

startDhclient

exit 0
