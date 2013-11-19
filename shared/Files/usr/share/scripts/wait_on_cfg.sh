#!/bin/sh

LOG_FILE="/var/log/autocfg"

# Script to wait for changes to files and autosaves them to /cfg

save_to_cfg() {
    [ -n "${1:-}" ] || return 0
    if [ -n "$(echo "$1" | grep 'passwd\|pwd.db\|spwd.db\|master.passwd')" ]; then
        /usr/sbin/cfg password || echo "Failed to save password files"
    fi
}

while :; do
    (
    save_to_cfg "${changed:-}" || true
    ) >> "$LOG_FILE" 2>&1
    sleep 1
    changed=$(/usr/local/bin/wait_on -h \
		/etc/passwd \
		/etc/pwd.db \
		/etc/spwd.db \
		/etc/master.passwd)
done
