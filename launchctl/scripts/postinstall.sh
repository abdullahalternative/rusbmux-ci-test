#!/bin/sh

APPLE_USBMUXD="/System/Library/LaunchDaemons/com.apple.usbmuxd.plist"
RUSBMUX="/Library/LaunchDaemons/com.abdullah-albanna.rusbmux.plist"

launchctl bootout system "$APPLE_USBMUXD" 2>/dev/null || true

launchctl bootstrap system "$RUSBMUX"

exit 0
