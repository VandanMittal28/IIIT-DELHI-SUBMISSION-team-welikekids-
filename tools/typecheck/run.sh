#!/bin/bash
# Verification harness for the luma-ui-redesign branch.
#
# There is no Xcode on this machine (Command Line Tools only), so `xcodebuild` and the iOS
# Simulator are unavailable. This script is the substitute. It runs two stages:
#
#   1. PARSE    — `swiftc -parse` over every app source. Pure syntax, needs no SDK, covers
#                 100% of the code including the ARKit camera views.
#   2. TYPECHECK— `swiftc -typecheck` against the macOS SDK over the SwiftUI sources, with
#                 `shims.swift` standing in for iOS-only API and `app_model_stub.swift`
#                 standing in for the Supabase-backed `AppModel`. This is what actually
#                 catches wrong argument labels, bad modifier chains and missing members.
#
# Stage 2 cannot prove the code builds for iOS — only that it is internally consistent. See
# PLAN.md "Environment reality".
#
# Usage: tools/typecheck/run.sh [-q]

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/ios/Sidequest"
HARNESS="$ROOT/tools/typecheck"
WORK="$(printf '%s' "${TMPDIR:-/tmp}" | sed 's#/*$##')/sq-typecheck.$$"
QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

status=0

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

# ------------------------------------------------------- stage 0: project membership
say "== stage 0: Xcode target membership =="
if out=$(python3 "$ROOT/tools/sync-xcode-sources.py" --check 2>&1); then
    say "   ok — $out"
else
    echo "PROJECT FAIL: $out"
    echo "   run: python3 tools/sync-xcode-sources.py"
    status=1
fi
say ""

# ---------------------------------------------------------------- stage 1: parse
say "== stage 1: syntax (swiftc -parse) =="
parse_failures=0
for file in "$SRC"/*.swift "$ROOT"/ios/SidequestTests/*.swift; do
    if ! out=$(swiftc -parse "$file" 2>&1); then
        echo "PARSE FAIL: ${file#"$ROOT"/}"
        echo "$out" | head -30
        parse_failures=$((parse_failures + 1))
        status=1
    fi
done
if [ "$parse_failures" -eq 0 ]; then
    say "   ok — $(ls "$SRC"/*.swift "$ROOT"/ios/SidequestTests/*.swift | wc -l | tr -d ' ') files parse cleanly"
fi

# ------------------------------------------------------------ stage 2: typecheck
say ""
say "== stage 2: types (swiftc -typecheck, macOS SDK + shims) =="

# Sources that can be type-checked. Excluded, with reasons:
#   SidequestApp.swift   — UIApplicationDelegate / UIApplicationDelegateAdaptor, iOS-only.
#   AppModel.swift       — depends on the Supabase SPM package; replaced by app_model_stub.swift.
#   CameraGuidanceView.swift — ARKit and UIViewRepresentable have no macOS equivalent.
CHECKABLE=(
    Models.swift
    Theme.swift
    Components.swift
    RootView.swift
    DiscoverView.swift
    EventDetailView.swift
    MyJourneyView.swift
    CommunityView.swift
    AccountView.swift
    NavigateView.swift
)

# Copy the checkable sources, stripping the imports that do not resolve on macOS. The shim
# file re-declares what those modules provided.
for name in "${CHECKABLE[@]}"; do
    if [ ! -f "$SRC/$name" ]; then
        echo "TYPECHECK FAIL: missing source $name"
        status=1
        continue
    fi
    sed -E \
        -e 's/^import (UIKit|ARKit|Supabase|PhotosUI)$/\/\/ [shimmed] &/' \
        -e 's/for: \.(navigationBar|tabBar)\)/for: .automatic)/g' \
        "$SRC/$name" > "$WORK/$name"
done

cp "$HARNESS/shims.swift" "$HARNESS/app_model_stub.swift" "$WORK/" 2>/dev/null

SDK="$(xcrun --sdk macosx --show-sdk-path)"
if out=$(swiftc -typecheck \
        -sdk "$SDK" \
        -target x86_64-apple-macosx14.0 \
        -swift-version 5 \
        "$WORK"/*.swift 2>&1); then
    say "   ok — ${#CHECKABLE[@]} sources type-check"
else
    echo "TYPECHECK FAIL"
    # Rewrite temp paths back to repo paths so the output is clickable.
    echo "$out" | sed "s#$WORK/#ios/Sidequest/#g" | grep -E 'error:|warning:' | head -60
    echo "$out" | sed "s#$WORK/#ios/Sidequest/#g" | grep -c 'error:' | xargs -I{} echo "   ({} errors total)"
    status=1
fi

say ""
if [ "$status" -eq 0 ]; then say "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit "$status"
