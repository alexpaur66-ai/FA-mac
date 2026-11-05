#!/bin/bash
# Checks this Mac for everything needed to build and run FA. Safe to run any time.
set -u
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; PROBLEMS=$((PROBLEMS+1)); }
PROBLEMS=0

echo "FA doctor"
echo

if [ "$(uname)" != "Darwin" ]; then fail "This is not macOS. The app only builds on a Mac."; exit 1; fi

MACOS=$(sw_vers -productVersion)
MAJOR=${MACOS%%.*}
if [ "$MAJOR" -ge 14 ]; then ok "macOS $MACOS"; else fail "macOS $MACOS is older than 14 (Sonoma), which the app requires."; fi

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then ok "Apple Silicon ($ARCH)"; else warn "Intel Mac ($ARCH): the app builds, but on-device AI (Phase 3) will not be available."; fi

if xcode-select -p >/dev/null 2>&1 && [ -d "$(xcode-select -p)/../.." ] && xcodebuild -version >/dev/null 2>&1; then
  ok "$(xcodebuild -version | tr '\n' ' ')"
else
  fail "Xcode is not installed or not selected. Install it from the App Store, open it once, then run: sudo xcode-select -s /Applications/Xcode.app"
fi

if swift --version >/dev/null 2>&1; then ok "$(swift --version 2>&1 | head -1)"; else fail "The swift command is missing (comes with Xcode)."; fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  ok "An Apple Development signing identity exists"
else
  warn "No Apple Development signing identity yet. In Xcode: Settings > Accounts > add your Apple ID; Xcode creates it on the first build."
fi

if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then ok "FileVault is on"; else warn "FileVault is off. Turn it on in System Settings > Privacy & Security so the invoice database is encrypted at rest."; fi

FREE_GB=$(df -g / | awk 'NR==2 {print $4}')
if [ "${FREE_GB:-0}" -ge 20 ]; then ok "${FREE_GB} GB free on the system disk"; else warn "Only ${FREE_GB} GB free; Xcode and builds need room."; fi

echo
if [ "$PROBLEMS" -eq 0 ]; then
  echo "All good. Open App/FA.xcodeproj in Xcode, pick the FA scheme and press Run."
else
  echo "$PROBLEMS problem(s) to fix first (see FAIL lines)."
fi
exit "$PROBLEMS"
