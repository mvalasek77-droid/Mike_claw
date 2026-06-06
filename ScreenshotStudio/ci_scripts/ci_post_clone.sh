#!/bin/sh
# Xcode Cloud post-clone hook.
#
# The .xcodeproj is committed, so a clone is buildable as-is. This hook simply
# regenerates the project from project.yml when XcodeGen is available, keeping
# the committed project honest with the spec. It is a no-op otherwise.
set -e

cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null 2>&1; then
  echo "▸ Regenerating project with XcodeGen"
  xcodegen generate
else
  echo "▸ XcodeGen not present — using committed ScreenshotStudio.xcodeproj"
fi
