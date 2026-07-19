#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this cleanup as root." >&2
    exit 1
fi

/usr/bin/pmset -a disablesleep 0
sleep_disabled="$(/usr/bin/pmset -g | /usr/bin/sed -nE 's/^[[:space:]]*SleepDisabled[[:space:]]+([01])[[:space:]]*$/\1/p' | /usr/bin/tail -n 1)"
if [[ "$sleep_disabled" != "0" ]]; then
    echo "Normal sleep could not be verified; refusing to continue uninstall." >&2
    exit 1
fi

/bin/launchctl bootout system/com.kaji.app.power-helper 2>/dev/null || true
/bin/rm -f /Library/LaunchDaemons/com.kaji.app.power-helper.plist
/bin/rm -f /Library/PrivilegedHelperTools/com.kaji.app.power-helper

echo "Power Protect was disabled and its legacy installed files were removed. Remove Kaji.app only after this command succeeds."
