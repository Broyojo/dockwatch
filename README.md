# dockwatch

A workaround for a macOS bug that leaves an invisible Dock taking up space at the bottom of the screen.

## The bug

With **Automatically hide and show the Dock** turned on, windows sometimes stop reaching the bottom of the screen. Maximizing or resizing leaves an empty strip where the Dock would be if it were showing (88pt with a 62pt Dock icon size). The Dock itself stays hidden.

The usual workaround is to turn the autohide setting off and on again in System Settings.

Seen on macOS 27.0.1 (Apple Silicon), with or without an external display.

## What causes it

In the system log (`log show --predicate 'process == "Dock"'`), every incident follows the same sequence:

1. A trackpad swipe opens **Mission Control**, often after a few quick opens in a row.
2. To show itself inside Mission Control, the Dock temporarily switches autohide off internally (`setting autoHideOn=0`).
3. About 0.1–0.6 seconds later, while Mission Control is still open, the screen's usable area shrinks by the Dock's height, as if the Dock were always showing.
4. When Mission Control closes, the Dock switches autohide back on (`autoHideOn=1`), but **the reserved space is never released**.

So the Dock's own autohide setting comes back correctly, but the space reserved for the Dock does not. Opening and closing Mission Control again doesn't clear it. The only thing that does is turning autohide off and on, which makes the Dock recalculate the reserved space.

This involves only Apple components (Dock, WindowManager, WindowServer).

## The fix

`dockwatch` is a small background agent that:

- checks each screen's usable area (`NSScreen.visibleFrame`) every second, and whenever displays, Spaces or wake state change;
- if more than 20pt is reserved for the Dock while autohide is on, and that lasts more than 4 seconds, toggles autohide off and on (the Dock pops up for half a second and the space comes back);
- logs each incident and saves a snapshot of the Dock and Mission Control system log to `~/Library/Logs/dockwatch/`.

The toggle calls `CoreDockSetAutoHideEnabled`, the private function System Settings itself uses, so it needs no Accessibility or Automation permission.

## Usage

Requires the Xcode command-line tools (`swiftc`).

```sh
./install.sh --fix   # install as a login agent that auto-fixes (omit --fix to only log)
./fix.sh             # one-off manual fix
./uninstall.sh       # remove the agent
```

Logs: `~/Library/Logs/dockwatch/dockwatch.log`, plus one `stuck-*.log` snapshot per incident.

A quick manual alternative: press **⌘⌥D** twice (toggles autohide off and on).

## Caveats

- `CoreDockSetAutoHideEnabled` is a private API and could change or disappear in a future macOS release.
- This is a workaround, not a fix. If you see this bug too, please report it to Apple through Feedback Assistant and attach the `stuck-*.log` snapshots.
