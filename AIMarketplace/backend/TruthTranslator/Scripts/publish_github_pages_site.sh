#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="$ROOT_DIR/Web"
REPO_NAME="${1:-chaddrop-support}"
VISIBILITY="${2:-public}"
PUBLISH_DIR="${CHADDROP_GITHUB_SITE_DIR:-$HOME/Desktop/ChadDrop-GitHubPages}"

if [[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" ]]; then
  echo "Visibility must be public or private."
  exit 1
fi

if [[ ! -d "$SITE_DIR" ]]; then
  echo "Could not find website files: $SITE_DIR"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is missing. Install it from https://cli.github.com/ and run this script again."
  exit 1
fi

if [[ -e "$PUBLISH_DIR" ]]; then
  echo "Publish directory already exists: $PUBLISH_DIR"
  echo "Move it or set CHADDROP_GITHUB_SITE_DIR to a new folder before running again."
  exit 1
fi

mkdir -p "$PUBLISH_DIR"
cp -R "$SITE_DIR"/. "$PUBLISH_DIR"/

cd "$PUBLISH_DIR"
git init
git add .
git commit -m "Create ChadDrop support site"

if ! gh auth status >/dev/null 2>&1; then
  gh auth login
fi

echo ""
echo "This will create a $VISIBILITY GitHub repository named: $REPO_NAME"
echo "It publishes only the support/privacy website files, not the iOS app source code."
read -r -p "Type CREATE to continue: " CONFIRM

if [[ "$CONFIRM" != "CREATE" ]]; then
  echo "Canceled. No GitHub repository was created."
  exit 0
fi

gh repo create "$REPO_NAME" "--$VISIBILITY" --source . --remote origin --push

OWNER_AND_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
open "https://github.com/$OWNER_AND_REPO/settings/pages"

echo ""
echo "Next step in GitHub:"
echo "1. Open Settings -> Pages."
echo "2. Source: Deploy from a branch."
echo "3. Branch: main, folder: /root."
echo "4. Save."
echo ""
echo "Your URLs will usually be:"
echo "https://$(echo "$OWNER_AND_REPO" | cut -d/ -f1).github.io/$REPO_NAME/support.html"
echo "https://$(echo "$OWNER_AND_REPO" | cut -d/ -f1).github.io/$REPO_NAME/privacy.html"
