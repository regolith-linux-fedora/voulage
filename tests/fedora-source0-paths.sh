#!/usr/bin/env bash
#
# Check that stage_source() in .github/scripts/ext-rpm.sh limits Source0 to the
# paths of a spec's "%global source0_paths" line (spec style guide, "Large
# repositories"), keeps the whole tree without one, and fails clearly on a path
# the tree doesn't have.
#
# Requires: bash, git, rpmdevtools (spectool), tar, gzip (run it in ci-fedora
# or a Fedora container).
#
# Usage: tests/fedora-source0-paths.sh [path/to/voulage]

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
PACKAGE_NAME="fonts-hello"
SRC="$PKG_BUILD_PATH/$PACKAGE_NAME"
TARBALL="$PKG_BUILD_PATH/.rpm/$PACKAGE_NAME/SOURCES/$PACKAGE_NAME-1.0.tar.gz"
trap 'rm -rf "$PKG_BUILD_PATH" "$HOME"' EXIT

# make_package <spec line> [gitmodules]: a package repo with one commit and
# three top-level trees, of which a font package might want two
make_package() {
  rm -rf "$SRC"
  mkdir -p "$SRC/fonts/keep" "$SRC/fonts/other" "$SRC/debian"
  echo keep > "$SRC/fonts/keep/a.ttf"
  echo other > "$SRC/fonts/other/b.ttf"
  echo copyright > "$SRC/debian/copyright"
  echo control > "$SRC/debian/control"
  if [ "${2:-}" = gitmodules ]; then
    : > "$SRC/.gitmodules"
  fi
  cat > "$SRC/$PACKAGE_NAME.spec" <<EOF
Name:           $PACKAGE_NAME
Version:        1.0
Release:        1%{?dist}
Summary:        test
License:        OFL-1.1
$1
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

%description
test
EOF
  git -C "$SRC" init -q
  git -C "$SRC" add .
  GIT_COMMITTER_DATE="2026-11-18T18:00:00Z" GIT_AUTHOR_DATE="2026-11-18T18:00:00Z" \
    git -C "$SRC" -c user.name=test -c user.email=test@example.com commit -q -m init
  RPM_SPEC="$SRC/$PACKAGE_NAME.spec"
}

# files <tarball>: the regular files in it, sorted
files() {
  tar -tzf "$1" | grep -v '/$' | sort | tr '\n' ' '
}

limited="fonts-hello-1.0/debian/copyright fonts-hello-1.0/fonts/keep/a.ttf "

# with source0_paths only those paths are archived, under the usual prefix
make_package '%global source0_paths fonts/keep debian/copyright'
if ! out="$(stage_source 2>&1)"; then
  fail "stage_source failed: $out"
elif [ "$(files "$TARBALL")" != "$limited" ]; then
  fail "limited Source0 has: $(files "$TARBALL")"
elif ! grep -q 'Source0 limited to: fonts/keep debian/copyright' <<<"$out"; then
  fail "stage_source doesn't say Source0 is limited: $out"
fi

# the same commit gives the same tarball
first="$(sha256sum "$TARBALL" 2>/dev/null | cut -d' ' -f1)"
stage_source >/dev/null 2>&1
if [ "$(sha256sum "$TARBALL" 2>/dev/null | cut -d' ' -f1)" != "$first" ]; then
  fail "a second stage_source made a different $(basename "$TARBALL")"
fi

# the tar path for repos with submodules honours the paths too
make_package '%global source0_paths fonts/keep debian/copyright' gitmodules
if ! out="$(stage_source 2>&1)"; then
  fail "stage_source failed with .gitmodules: $out"
elif [ "$(files "$TARBALL")" != "$limited" ]; then
  fail "limited Source0 with .gitmodules has: $(files "$TARBALL")"
fi

# without the line the whole tree is archived, as before
make_package ''
whole="fonts-hello-1.0/debian/control fonts-hello-1.0/debian/copyright fonts-hello-1.0/fonts-hello.spec fonts-hello-1.0/fonts/keep/a.ttf fonts-hello-1.0/fonts/other/b.ttf "
if ! out="$(stage_source 2>&1)"; then
  fail "stage_source failed without source0_paths: $out"
elif [ "$(files "$TARBALL")" != "$whole" ]; then
  fail "whole-tree Source0 has: $(files "$TARBALL")"
elif grep -q 'Source0 limited' <<<"$out"; then
  fail "stage_source says Source0 is limited without source0_paths"
fi

# a path the tree doesn't have fails and says which
make_package '%global source0_paths fonts/missing debian/copyright'
if out="$(stage_source 2>&1)"; then
  fail "stage_source succeeded with a missing source0_paths entry"
elif ! grep -q 'could not archive Source0.*fonts/missing' <<<"$out"; then
  fail "unexpected error for a missing path: $out"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK: Source0 paths"
