#!/bin/sh
# Download perch_v2_f16.onnx (≈200 MB, too large for the git repo) from this repo's latest GitHub release.
# Usage: scripts/fetch_model.sh [owner/repo]   (defaults to the repo the `origin` remote points at)
set -eu
cd "$(dirname "$0")/.."

dest="App/Resources/perch_v2_f16.onnx"
if [ -s "$dest" ]; then
    echo "$dest already exists"; exit 0
fi

repo="${1:-$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')}"
if [ -z "$repo" ]; then
    echo "No origin remote; pass the GitHub repo as owner/repo" >&2; exit 1
fi

url="https://github.com/$repo/releases/latest/download/perch_v2_f16.onnx"
echo "Downloading $url"
curl -fL --progress-bar -o "$dest.part" "$url"
mv "$dest.part" "$dest"
echo "Saved $dest"
