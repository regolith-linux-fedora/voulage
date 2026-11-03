#!/bin/bash

set -e
set -o errexit
# Extension for Fedora RPM and COPR support
#
# Source RPMs are built with rpmbuild from the checked-out tree, binary RPMs
# with mock, and publishing submits the source RPM to the stage's COPR project.
# COPR's build result is authoritative, so a publishing run skips the local mock
# build unless RPM_LOCAL_MOCK=yes.
#
# Environment:
#   COPR_PUBLISH      "yes" to submit builds to COPR (default "no")
#   COPR_OWNER        COPR owner of the stage projects (default "@regolith")
#   COPR_CONFIG_FILE  copr-cli config file (default ~/.config/copr)
#   COPR_DRY_RUN      "yes" to print the copr-cli command instead of running it
#   MOCK_ISOLATION    mock --isolation value (default "simple", works in containers)
#   RPM_LOCAL_MOCK    "yes", "no" or "auto" (default: mock only when not publishing)

COPR_OWNER="${COPR_OWNER:-@regolith}"
COPR_URL="${COPR_URL:-https://copr.fedorainfracloud.org}"
COPR_DOWNLOAD_URL="${COPR_DOWNLOAD_URL:-https://download.copr.fedorainfracloud.org}"
COPR_CLI="${COPR_CLI:-copr-cli}"
MOCK_ISOLATION="${MOCK_ISOLATION:-simple}"
RPM_LOCAL_MOCK="${RPM_LOCAL_MOCK:-auto}"

RPM_SPEC=""
RPM_SRPM=""
RPM_COPR_REPO=""

#### RPM specific functions

rpm_arch() {
  case "$ARCH" in
    amd64) echo "x86_64" ;;
    arm64) echo "aarch64" ;;
    *)     echo "$ARCH" ;;
  esac
}

# mock config and COPR chroot name, e.g. fedora-43-x86_64, fedora-rawhide-aarch64
rpm_chroot() {
  echo "$DISTRO-$CODENAME-$(rpm_arch)"
}

# unstable -> regolith-unstable, testing -> regolith-testing, stable -> regolith
copr_project() {
  if [ "$SUITE" == "stable" ]; then
    echo "regolith"
  else
    echo "regolith-$SUITE"
  fi
}

rpm_publishing() {
  [ "$LOCAL_BUILD" == "false" ] && [ "$COPR_PUBLISH" == "yes" ]
}

rpm_work_path() {
  echo "$PKG_BUILD_PATH/.rpm/$PACKAGE_NAME"
}

rpm_output_path() {
  echo "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"
}

# The spec sits at the top of the repo and is named after the source package.
find_spec() {
  local src="$PKG_BUILD_PATH/$PACKAGE_NAME"

  if [ -f "$src/$PACKAGE_NAME.spec" ]; then
    echo "$src/$PACKAGE_NAME.spec"
    return 0
  fi

  local specs=("$src"/*.spec)
  if [ "${#specs[@]}" -eq 1 ] && [ -f "${specs[0]}" ]; then
    echo -e "\033[0;33mWarning: expected $PACKAGE_NAME.spec, using $(basename "${specs[0]}")\033[0m" >&2
    echo "${specs[0]}"
    return 0
  fi

  return 1
}

rpmspec_query() {
  rpmspec -q --srpm --define "dist %{nil}" --qf "$1" "$RPM_SPEC"
}

# Write a tarball of the checked-out tree named like the spec's Source0.
archive_tree() {
  local src="$1"
  local target="$2"

  local file prefix
  file="$(basename "$target")"
  prefix="$file"
  for ext in .tar.gz .tgz .tar.xz .tar.bz2 .tar.zst; do
    prefix="${prefix%"$ext"}"
  done

  local compress=""
  case "$file" in
    *.tar.gz|*.tgz) compress="gzip -n" ;;
    *.tar.xz)       compress="xz" ;;
    *.tar.bz2)      compress="bzip2" ;;
    *.tar.zst)      compress="zstd -q" ;;
    *)
      echo -e "\033[0;31mError: don't know how to create Source0 $file\033[0m"
      return 1
      ;;
  esac

  pushd "$src" >/dev/null
  if [ -f .gitmodules ]; then
    # git archive leaves out submodules; tar the tree with stable metadata instead
    local mtime
    mtime="$(git log -1 --format=%ct)"
    tar --sort=name --mtime="@$mtime" --owner=0 --group=0 --numeric-owner \
      --exclude=.git --exclude=.github --transform "s|^\.|$prefix|" -cf - . | $compress > "$target"
  else
    git archive --format=tar --prefix="$prefix/" HEAD | $compress > "$target"
  fi
  popd >/dev/null
}

copr_repo_available() {
  local url
  url="$COPR_DOWNLOAD_URL/results/$COPR_OWNER/$(copr_project)/$(rpm_chroot)/"
  if curl -fsSL -o /dev/null "${url}repodata/repomd.xml"; then
    RPM_COPR_REPO="$url"
    return 0
  fi
  RPM_COPR_REPO=""
  return 1
}

# Stages that build branch heads instead of release tags (see handle_package()
# in main.sh), as in ext-debian.sh.
is_snapshot_stage() {
  [ "$STAGE" == "experimental" ] || [ "$STAGE" == "unstable" ]
}

# Print the snapshot marker of the checked out commit: the UTC committer date
# and time and the short commit hash, for example "20261026.185700git52ece7e".
# It only depends on the commit, so every chroot that builds the same commit
# gets the same version-release, and building a commit again does not change it.
snapshot_marker() {
  local src="$1"
  local commit_time commit_hash

  if ! commit_time=$(TZ=UTC0 git -C "$src" -c safe.directory='*' show -s --format=%cd --date=format-local:%Y%m%d.%H%M%S HEAD 2>/dev/null) ||
    ! commit_hash=$(git -C "$src" -c safe.directory='*' rev-parse HEAD 2>/dev/null); then
    return 1
  fi

  echo "${commit_time}git${commit_hash:0:7}"
}

# Fedora's %{?dist} replaces Upstream's -1regolith-<codename> suffix, so only
# snapshot stages change the spec: they append the snapshot marker to Release,
# so that every new commit is published under a new, higher version-release
# instead of the one already in COPR. "Release: 1%{?dist}" becomes
# "Release: 1.20261026.185700git52ece7e%{?dist}", which sorts above 1 and below
# 2 or any higher Version.
update_changelog() {
  is_snapshot_stage || return 0

  local spec marker
  # dist_valid reports packages without a spec
  spec="$(find_spec 2>/dev/null)" || return 0

  if ! marker=$(snapshot_marker "$PKG_BUILD_PATH/$PACKAGE_NAME"); then
    echo "::warning::No git commit found for $PACKAGE_NAME, building it for $STAGE without a snapshot release."
    return 0
  fi

  if grep -q "^Release:.*$marker" "$spec"; then
    return 0
  fi

  if ! grep -q "^Release:" "$spec" || grep -q "^Release:.*autorelease" "$spec"; then
    echo "::warning::$PACKAGE_NAME has no plain Release: field, building it for $STAGE without a snapshot release."
    return 0
  fi

  if grep -q '^Release:.*%{?dist}' "$spec"; then
    sed -i -E "s/^(Release:.*)%\{\?dist\}/\1.${marker}%{?dist}/" "$spec"
  else
    sed -i -E "s/^(Release:.*[^[:space:]])[[:space:]]*$/\1.${marker}/" "$spec"
  fi

  echo -e "\033[0;34mSnapshot release for $STAGE: $(grep -m1 '^Release:' "$spec" | sed -E 's/^Release:[[:space:]]*//')\033[0m"
}

# Determine if the package can be built for this distro: it needs a spec
dist_valid() {
  if RPM_SPEC="$(find_spec)"; then
    return 0
  fi

  echo -e "\033[0;33mno-spec: $PACKAGE_NAME has no $PACKAGE_NAME.spec at the top of the repo, skipping.\033[0m"
  echo "NOSPEC:$PACKAGE_NAME"
  return 1
}

# Collect every source the spec names into the SOURCES directory
stage_source() {
  echo "::group::Preparing sources for $PACKAGE_NAME"
  local src="$PKG_BUILD_PATH/$PACKAGE_NAME"
  local work
  work="$(rpm_work_path)"

  rm -rf "$work"
  mkdir -p "$work/SOURCES" "$work/SRPMS" "$work/results"

  local tag url file
  while IFS= read -r line; do
    tag="${line%%:*}"
    url="${line#*: }"
    file="$(basename "$url")"

    if [ "$tag" == "Source0" ]; then
      echo -e "\033[0;34mGenerating $file from the git tree\033[0m"
      archive_tree "$src" "$work/SOURCES/$file"
    elif [ -f "$src/$file" ]; then
      echo "Using $file from the repo"
      cp "$src/$file" "$work/SOURCES/"
    elif [[ "$url" == *://* ]]; then
      echo "Downloading $file"
      curl -fsSL -o "$work/SOURCES/$file" "$url"
    else
      echo -e "\033[0;31mError: $tag $file is neither in the repo nor a URL\033[0m"
      return 1
    fi
  done < <(spectool --list-files --all "$RPM_SPEC")

  ls -l "$work/SOURCES"
  echo "::endgroup::"
}

build_src_package() {
  set -e

  echo "::group::Building source package $PACKAGE_NAME"
  local work
  work="$(rpm_work_path)"

  rpmbuild -bs "$RPM_SPEC" \
    --define "_topdir $work/rpmbuild" \
    --define "_sourcedir $work/SOURCES" \
    --define "_srcrpmdir $work/SRPMS"

  RPM_SRPM="$(find "$work/SRPMS" -name '*.src.rpm' | head -n1)"
  if [ -z "$RPM_SRPM" ]; then
    echo -e "\033[0;31mError: rpmbuild produced no source RPM\033[0m"
    return 1
  fi

  mkdir -p "$(rpm_output_path)"
  cp "$RPM_SRPM" "$(rpm_output_path)/"
  echo "Built $(basename "$RPM_SRPM")"
  echo "::endgroup::"
}

build_bin_package() {
  set -e

  local local_mock="$RPM_LOCAL_MOCK"
  if [ "$local_mock" == "auto" ]; then
    if rpm_publishing; then
      local_mock="no"
    else
      local_mock="yes"
    fi
  fi

  if [ "$local_mock" != "yes" ]; then
    echo "Skipping local mock build of $PACKAGE_NAME, COPR builds $(rpm_chroot) on publish."
    return 0
  fi

  echo "::group::Building binary packages $PACKAGE_NAME in mock $(rpm_chroot)"
  local work
  work="$(rpm_work_path)"

  local mock_args=(-r "$(rpm_chroot)" --isolation="$MOCK_ISOLATION" --resultdir "$work/results")
  if [ -n "$RPM_COPR_REPO" ]; then
    mock_args+=(--addrepo "$RPM_COPR_REPO")
  fi

  mock "${mock_args[@]}" --rebuild "$RPM_SRPM"

  find "$work/results" -name '*.rpm' ! -name '*.src.rpm' -exec cp {} "$(rpm_output_path)/" \;
  ls -l "$(rpm_output_path)"
  echo "::endgroup::"
}

# return 0 if source package already exists in repo, otherwise 1
source_pkg_exists() {
  local name version
  name="$(rpmspec_query '%{name}')"
  version="$(rpmspec_query '%{version}-%{release}')"

  local builds
  if ! builds="$(curl -fsSL -G "$COPR_URL/api_3/build/list/" \
      --data-urlencode "ownername=$COPR_OWNER" \
      --data-urlencode "projectname=$(copr_project)" \
      --data-urlencode "packagename=$name" \
      --data-urlencode "limit=50" \
      --data-urlencode "order=id" \
      --data-urlencode "order_type=DESC")"; then
    echo -e "\033[0;33mWarning: could not query COPR builds of $name\033[0m" >&2
    return 1
  fi

  # COPR reports the source RPM's version-release, which carries the dist tag
  echo "$builds" | jq -e --arg version "$version" --arg chroot "$(rpm_chroot)" '
    [.items[]
      | select(.state == "succeeded")
      | select(.chroots | index($chroot))
      | select((.source_package.version // "") | sub("\\.fc[0-9]+$"; "") == $version)
    ] | length > 0' >/dev/null
}

# Submit the source package to the stage's COPR project and wait for the result
publish() {
  local project
  project="$COPR_OWNER/$(copr_project)"

  if ! rpm_publishing; then
    echo "Not publishing $PACKAGE_NAME to $project (COPR_PUBLISH is not \"yes\")."
    return 0
  fi

  case "$SUITE" in
    unstable|testing) ;;
    *)
      echo -e "\033[0;31mError: refusing to publish to $project, only unstable and testing are automated.\033[0m"
      return 1
      ;;
  esac

  echo "::group::Publishing $PACKAGE_NAME to COPR $project $(rpm_chroot)"
  local nvr
  nvr="$(rpmspec_query '%{name}-%{version}-%{release}')"

  if source_pkg_exists; then
    echo "$nvr already built in $project for $(rpm_chroot), nothing to publish."
    echo "::endgroup::"
    return 0
  fi

  local copr_cmd=("$COPR_CLI")
  if [ -n "$COPR_CONFIG_FILE" ]; then
    copr_cmd+=(--config "$COPR_CONFIG_FILE")
  fi
  copr_cmd+=(build --chroot "$(rpm_chroot)" "$project" "$RPM_SRPM")

  if [ "$COPR_DRY_RUN" == "yes" ]; then
    echo "COPR dry run: ${copr_cmd[*]}"
  else
    # copr-cli waits for the build and fails if COPR fails it
    "${copr_cmd[@]}"
  fi

  echo "CHLOG:Published $nvr in $DISTRO/$CODENAME/$STAGE ($project $(rpm_chroot)) from ${PKG_LINE:-$PACKAGE_NAME}"
  echo "::endgroup::"
}

archive_setup_scripts() {
  # Following allows for internal dependencies
  echo "::group::Looking for COPR repo $COPR_OWNER/$(copr_project) $(rpm_chroot)"
  if copr_repo_available; then
    echo "mock builds will use $RPM_COPR_REPO"
  else
    echo "COPR repo not available yet, mock builds use Fedora repos only."
  fi
  echo "::endgroup::"
}

archive_cleanup_scripts() {
  # mock gets the COPR repo per build, nothing to clean up on the host
  :
}

# Setup COPR repo for internal dependencies
setup() {
  source_setup_scripts
  archive_setup_scripts
}
