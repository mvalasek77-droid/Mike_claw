#!/bin/sh
# Xcode Cloud — post-clone hook.
#
# Runs once after Xcode Cloud clones the repo, before the build starts.
# Path convention: ci_scripts/ci_post_clone.sh next to the .xcodeproj.
#
# Today this just logs the build environment so the first run's logs are
# easy to triage. No secrets touched — `Build.xcconfig` uses `#include?`
# for `Secrets.xcconfig`, so a missing secrets file produces empty
# `AIMKT_WORKER_URL` / `AIMKT_SHARED_SECRET` values and the build still
# succeeds. The admin configures the Worker at runtime via Payout Setup.

set -eu

echo "── Xcode Cloud post-clone ──"
echo "Branch: ${CI_BRANCH:-?}"
echo "Commit: ${CI_COMMIT:-?}"
echo "Workflow: ${CI_WORKFLOW:-?}"
echo "Xcode: $(xcodebuild -version | head -1)"
echo "Swift: $(swift --version | head -1)"
echo "Working dir: $(pwd)"

# Sanity: confirm the optional secrets file is absent. If a future
# operator wires it up via Xcode Cloud env vars they can add a step
# here to materialize Secrets.xcconfig from secrets before the build.
if [ -f "../AIMarketplace/Config/Secrets.xcconfig" ]; then
  echo "Secrets.xcconfig: present"
else
  echo "Secrets.xcconfig: absent (defaults to empty; admin configures at runtime)"
fi

echo "── post-clone done ──"
