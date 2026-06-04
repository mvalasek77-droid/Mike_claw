#!/bin/sh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "ChadDrop Xcode Cloud post-clone"
echo "Project: $PROJECT_DIR"
echo "Xcode Cloud: ${CI_XCODE_CLOUD:-FALSE}"
echo "Workflow: ${CI_WORKFLOW:-unknown}"
echo "Branch: ${CI_BRANCH:-unknown}"
echo "Action: ${CI_XCODEBUILD_ACTION:-unknown}"

if [ -f "$PROJECT_DIR/Config/Secrets.xcconfig" ]; then
  echo "Local Secrets.xcconfig found."
else
  echo "No Secrets.xcconfig found. That is expected for Xcode Cloud and offline-first builds."
fi

if [ -d "$PROJECT_DIR/TruthTranslator.xcodeproj" ]; then
  echo "Xcode project is present."
else
  echo "Missing TruthTranslator.xcodeproj."
  exit 1
fi
