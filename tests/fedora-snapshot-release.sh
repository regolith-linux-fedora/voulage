#!/usr/bin/env bash
#
# Check the Release that update_changelog() in .github/scripts/ext-rpm.sh writes
# for each stage: unstable and experimental get a snapshot marker that only
# depends on the commit and sorts between the spec's release and the next one,
# testing keeps the spec's Release.
#
# Requires: bash, git, rpm, GNU sed (run it in ci-fedora or a Fedora container)
#
# Usage: tests/fedora-snapshot-release.sh [path/to/voulage]

set -euo pipefail

REPO="$(realpath "${1:-$(dirname "$0")/..}")"

# keep the user's git configuration out of the fixtures
export GIT_CONFIG_NOSYSTEM=1
export HOME
HOME="$(mktemp -d)"

failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# shellcheck source=SCRIPTDIR/../.github/scripts/ext-rpm.sh
source "$REPO/.github/scripts/ext-rpm.sh"
set +e

PKG_BUILD_PATH="$(mktemp -d)"
PACKAGE_NAME="regolith-hello"
trap 'rm -rf "$PKG_BUILD_PATH" "$HOME"' EXIT

# make_package <release line>: a package repo with one commit at a fixed date
make_package() {
  local src="$PKG_BUILD_PATH/$PACKAGE_NAME"
  rm -rf "$src"
  mkdir -p "$src"
  printf 'Name: %s\nVersion: 1.2\n%s\nSummary: test\n' "$PACKAGE_NAME" "$1" > "$src/$PACKAGE_NAME.spec"
  git -C "$src" init -q
  git -C "$src" add .
  GIT_COMMITTER_DATE="2026-10-26T18:57:00Z" GIT_AUTHOR_DATE="2026-10-26T18:57:00Z" \
    git -C "$src" -c user.name=test -c user.email=test@example.com commit -q -m init
}

head_short() {
  git -C "$PKG_BUILD_PATH/$PACKAGE_NAME" rev-parse --short=7 HEAD
}

release_of() {
  grep -m1 '^Release:' "$PKG_BUILD_PATH/$PACKAGE_NAME/$PACKAGE_NAME.spec" | sed -E 's/^Release:[[:space:]]*//'
}

# expect_release <stage> <release line> <expected release>
expect_release() {
  make_package "$2"
  STAGE="$1" update_changelog >/dev/null
  local expected="${3//@HEAD@/$(head_short)}"
  if [ "$(release_of)" != "$expected" ]; then
    fail "$1 with '$2': expected '$expected', got '$(release_of)'"
  fi
}

# expect_newer <a> <b>: rpm sorts version-release a above b
expect_newer() {
  if [ "$(rpm --eval "%{lua: print(rpm.vercmp('$1', '$2'))}")" != "1" ]; then
    fail "expected $1 > $2"
  fi
}

expect_release unstable     'Release: 1%{?dist}'        '1.20261026.185700git@HEAD@%{?dist}'
expect_release experimental 'Release: 1%{?dist}'        '1.20261026.185700git@HEAD@%{?dist}'
expect_release unstable     'Release:        0.1%{?dist}' '0.1.20261026.185700git@HEAD@%{?dist}'
expect_release unstable     'Release: 3'                '3.20261026.185700git@HEAD@'
expect_release unstable     'Release: %autorelease'     '%autorelease'
expect_release testing      'Release: 1%{?dist}'        '1%{?dist}'

# building the same checkout again doesn't append a second marker
make_package 'Release: 1%{?dist}'
STAGE=unstable update_changelog >/dev/null
STAGE=unstable update_changelog >/dev/null
if [ "$(release_of)" != "1.20261026.185700git$(head_short)%{?dist}" ]; then
  fail "second run changed the release to '$(release_of)'"
fi

# a package without a spec is left to dist_valid
rm -f "$PKG_BUILD_PATH/$PACKAGE_NAME/$PACKAGE_NAME.spec"
if ! STAGE=unstable update_changelog >/dev/null; then
  fail "update_changelog failed for a package without a spec"
fi

expect_newer '1.2-1.20261026.185700git52ece7e' '1.2-1'
expect_newer '1.2-1.20261027.000000git0000000' '1.2-1.20261026.185700git52ece7e'
expect_newer '1.2-1.20261026.185701gitfffffff' '1.2-1.20261026.185700git52ece7e'
expect_newer '1.2-2' '1.2-1.20261026.185700git52ece7e'
expect_newer '1.3-1' '1.2-1.20261026.185700git52ece7e'
expect_newer '1.2-0.2' '1.2-0.1.20261026.185700git52ece7e'

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK: snapshot releases"
