#!/bin/sh

RUSBMUX="/Library/LaunchDaemons/com.abdullah-albanna.rusbmux.plist"
APPLE_USBMUXD="/System/Library/LaunchDaemons/com.apple.usbmuxd.plist"

launchctl bootout system "$RUSBMUX" 2>/dev/null || true

launchctl bootstrap system "$APPLE_USBMUXD"

exit 0
