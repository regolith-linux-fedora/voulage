#!/usr/bin/env bash
#
# Build one docs/fedora/templates/<template>.spec in mock for a Fedora release
# and run rpmlint on the spec and the built RPMs. Errors fail; warnings don't.
#
# Requires: mock (in a privileged container: MOCK_ISOLATION=simple), rpm-build,
# rpmlint, and what tests/fedora-template-fixtures.sh needs.
#
# Usage: tests/fedora-template-build.sh <template> <release> [results-dir]

set -euo pipefail

TEMPLATE="$1"
RELEASE="$2"
REPO="$(realpath "$(dirname "$0")/..")"
SPEC="$REPO/docs/fedora/templates/$TEMPLATE.spec"
RESULTS="$(realpath -m "${3:-results/$TEMPLATE-$RELEASE}")"
TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT

case "$(uname -m)" in
  x86_64|aarch64) ARCH="$(uname -m)" ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 2 ;;
esac

mkdir -p "$RESULTS"
echo "::group::Fixture sources for $TEMPLATE"
"$REPO/tests/fedora-template-fixtures.sh" "$TEMPLATE" "$TOP/SOURCES"
echo "::endgroup::"

echo "::group::Source RPM"
# In a package repo the spec is named after the package (rpmlint: invalid-spec-name)
NAME="$(rpmspec -q --srpm --qf '%{name}' "$SPEC")"
cp "$SPEC" "$TOP/$NAME.spec"
SPEC="$TOP/$NAME.spec"
rpmbuild -bs "$SPEC" --define "_topdir $TOP" --define "_sourcedir $TOP/SOURCES" --define "_srcrpmdir $TOP/SRPMS"
SRPM="$(find "$TOP/SRPMS" -name '*.src.rpm')"
echo "::endgroup::"

echo "::group::mock -r fedora-$RELEASE-$ARCH"
mock -r "fedora-$RELEASE-$ARCH" --isolation="${MOCK_ISOLATION:-simple}" \
  --resultdir "$RESULTS" --rebuild "$SRPM"
echo "::endgroup::"

echo "::group::rpmlint"
rpmlint "$SPEC" "$RESULTS"/*.rpm
echo "::endgroup::"
