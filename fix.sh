#!/bin/zsh
# One-shot fix: same as toggling "Automatically hide and show the Dock" in System Settings.
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/fix.swift" <<'S'
import Foundation
let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
typealias F = @convention(c) (Bool) -> Void
let set = unsafeBitCast(dlsym(h, "CoreDockSetAutoHideEnabled")!, to: F.self)
set(false); usleep(600_000); set(true)
S
swift "$tmp/fix.swift"
