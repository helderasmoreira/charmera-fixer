#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>, for example 1.0.0}"
TAG="v$VERSION"
ZIP="build/Charmera-Fixer-$VERSION.zip"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3" >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists" >&2
  exit 1
fi

swift test
VERSION="$VERSION" ./scripts/build-app.sh
rm -f "$ZIP"
ditto -c -k --keepParent "build/Charmera Fixer.app" "$ZIP"

git tag -a "$TAG" -m "$TAG"
git push origin main "$TAG"
gh release create "$TAG" "$ZIP" --title "Charmera Fixer $VERSION" --generate-notes
