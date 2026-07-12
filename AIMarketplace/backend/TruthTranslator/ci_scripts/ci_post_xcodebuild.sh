#!/bin/sh
set -eu

echo "ChadDrop Xcode Cloud post-xcodebuild"
echo "Action: ${CI_XCODEBUILD_ACTION:-unknown}"
echo "Product: ${CI_PRODUCT:-unknown}"
echo "Result bundle: ${CI_RESULT_BUNDLE_PATH:-not provided}"
