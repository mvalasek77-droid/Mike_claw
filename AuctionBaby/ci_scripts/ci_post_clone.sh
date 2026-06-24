#!/bin/sh
# Xcode Cloud — post-clone hook.
#
# Regenerates the Xcode project from project.yml with XcodeGen so the committed
# .xcodeproj never drifts from source. If XcodeGen isn't on the runner, the
# committed project is used as-is. The app has no secrets to materialise.
set -eu

echo "── Auction Baby post-clone ──"
echo "Branch: ${CI_BRANCH:-?}  Commit: ${CI_COMMIT:-?}"

if [ -n "${CI_WORKSPACE:-}" ]; then
  cd "$CI_WORKSPACE/AuctionBaby" 2>/dev/null || cd "$CI_WORKSPACE" 2>/dev/null || true
elif [ -d "../AuctionBaby" ]; then
  cd ".."
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen found — regenerating project."
  ( cd AuctionBaby 2>/dev/null || true; xcodegen generate ) || echo "xcodegen generate skipped"
else
  echo "XcodeGen not installed — using committed AuctionBaby.xcodeproj."
fi

echo "── post-clone done ──"
