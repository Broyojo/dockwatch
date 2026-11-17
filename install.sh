#!/bin/zsh
# Installs dockwatch as a login agent. Pass --fix to also auto-clear the stuck reservation.
set -e
cd "${0:A:h}"
[[ dockwatch -nt dockwatch.swift ]] || swiftc -O dockwatch.swift -o dockwatch
ARGS="<string>$PWD/dockwatch</string>"
[[ "$1" == "--fix" ]] && ARGS="$ARGS<string>--fix</string>"
mkdir -p ~/Library/Logs/dockwatch
cat > ~/Library/LaunchAgents/com.user.dockwatch.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.user.dockwatch</string>
  <key>ProgramArguments</key><array>$ARGS</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/dockwatch/stderr.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/com.user.dockwatch 2>/dev/null || true
for i in {1..50}; do launchctl print gui/$(id -u)/com.user.dockwatch &>/dev/null || break; sleep 0.1; done
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.dockwatch.plist
echo "dockwatch running. Log: ~/Library/Logs/dockwatch/dockwatch.log"
