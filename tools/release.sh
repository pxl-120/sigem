#!/usr/bin/env bash
#
# release.sh — package pkg/ into SignalEmojiPkg.zip and publish a GitHub release.
#
# What it does:
#   1. Reads the version from version.json  (release tag = "v<version>").
#   2. Refuses to continue if that tag — or a release using it — already exists.
#   3. Zips the *contents* of pkg/ (NOT the pkg/ directory itself) into
#      SignalEmojiPkg.zip at the repository root.
#   4. Creates a GitHub release tagged v<version> with `gh`, attaching both
#      SignalEmojiPkg.zip and version.json as assets.
#
# The tag check runs before anything is published, so an already-released
# version prints an error and quits WITHOUT creating a release.
#
# Usage:
#   tools/release.sh
#
# Requires: bash, zip, git, gh (authenticated — see `gh auth login`).

set -euo pipefail

# --- locate the repo root (this script lives in <root>/tools) ----------------
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$script_dir/.." && pwd)

pkg_dir="$root_dir/pkg"
version_file="$root_dir/version.json"
zip_path="$root_dir/SignalEmojiPkg.zip"

die()  { printf 'error: %s\n' "$1" >&2; exit 1; }
info() { printf '%s\n' "$1" >&2; }

# --- sanity checks -----------------------------------------------------------
command -v zip >/dev/null 2>&1 || die "'zip' is not installed."
command -v gh  >/dev/null 2>&1 || die "'gh' (GitHub CLI) is not installed."
[ -d "$pkg_dir" ]      || die "pkg/ directory not found at $pkg_dir"
[ -f "$version_file" ] || die "version.json not found at $version_file"

# --- read the version --------------------------------------------------------
# version.json uses JS-object style with an unquoted key, e.g. { version: "0.2.3" },
# so parse it with a tolerant regex rather than a strict JSON parser. The regex
# also copes with a quoted key ("version":) and an unquoted value.
version=$(grep -oP '"?version"?\s*:\s*"?\K[0-9][^"[:space:],]*' "$version_file" | head -n1 || true)
[ -n "$version" ] || die "could not read a version from $version_file"
tag="v$version"
info "Version $version  ->  tag $tag"

# --- refuse to clobber an existing tag / release -----------------------------
# Check the remote tag (published releases always have one) and, separately,
# any release with this tag (catches drafts that don't yet have a git tag).
remote_tag=$(git ls-remote --tags origin "refs/tags/$tag" 2>/dev/null) \
  || die "could not query remote 'origin' for existing tags."
[ -z "$remote_tag" ] \
  || die "tag $tag already exists on origin — bump the version in version.json first."
if gh release view "$tag" >/dev/null 2>&1; then
  die "a release tagged $tag already exists — bump the version in version.json first."
fi

# --- build the zip (contents of pkg/, without the pkg/ directory itself) ------
info "Zipping pkg/ contents -> $(basename "$zip_path")"
rm -f "$zip_path"                       # zip appends to an existing archive; start clean
( cd "$pkg_dir" && zip -r -q -X "$zip_path" . -x '*.DS_Store' )
info "Created $(basename "$zip_path") ($(du -h "$zip_path" | cut -f1))"

# --- publish the release -----------------------------------------------------
info "Creating GitHub release $tag ..."
gh release create "$tag" \
  "$zip_path" \
  "$version_file" \
  --title "$tag" \
  --generate-notes

info "Done — release $tag published with SignalEmojiPkg.zip and version.json."
