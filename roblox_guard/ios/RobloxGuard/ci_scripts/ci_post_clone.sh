#!/bin/zsh
# Xcode Cloud hook: runs right after the repo is cloned, before dependency
# resolution/build. We keep RobloxGuard.xcodeproj out of source control and
# generate it from project.yml here so the checked-in project can't drift
# from this file — see https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
set -euo pipefail

echo "Installing XcodeGen..."
brew install xcodegen

echo "Generating RobloxGuard.xcodeproj from project.yml..."
cd "$CI_PRIMARY_REPOSITORY_PATH/roblox_guard/ios/RobloxGuard"
xcodegen generate
