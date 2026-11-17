#!/bin/zsh
launchctl bootout gui/$(id -u)/com.user.dockwatch 2>/dev/null; rm -f ~/Library/LaunchAgents/com.user.dockwatch.plist; echo "dockwatch removed"
