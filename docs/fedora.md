# Fedora

Fedora packages are built by `.github/workflows/build-rpm-v1.yml` with the
`.github/scripts/ext-rpm.sh` extension and published to COPR. The flow is the
same as Debian and Ubuntu: `main.sh` merges the package models, resolves refs,
compares them with the committed manifest and builds only what changed.

## Package models

```text
stage/<stage>/fedora/package-model.json             # every package, pointed at its regolith-linux-fedora fork
stage/<stage>/fedora/<release>/package-model.json   # per release overrides (43, 44, 45, rawhide)
```

- Unstable refs are `fedora/<upstream-ref>` branches in the forks.
- Testing refs start at the Upstream testing tags and are replaced by
  `fedora/v<Version>-<Release>` tags when a package's spec is released.
- Ubuntu-only packages are `null`. Packages without a spec are skipped and
  logged as `no-spec`, they don't fail the build.
- `tests/fedora-model.sh` checks the merged models.

Add a release by copying an existing release folder in both stages, then add
the release to `ghcr.io/regolith-linux-fedora/ci-fedora` and to the COPR
projects' chroots.

## Building

The spec is `<package>.spec` at the top of the package repo. For each changed
package the extension:

1. in unstable (and experimental), which build branch heads, appends a
   snapshot marker to the spec's `Release`: the UTC committer date and time and
   the short commit hash, so `1%{?dist}` becomes
   `1.20261026.185700git52ece7e%{?dist}`. Every new commit is published under a
   higher version-release than the last, and still below the next release.
   Testing builds release tags and keeps the spec's `Release`;
1. creates `Source0` from the checked-out tree with `git archive`, named as
   the spec names it, and collects the other sources from the repo or by URL.
   A source named `<name>-<version>-vendor.tar.xz` (or `.tar.gz`, `.tar.zst`,
   `.tar.bz2`) that is in neither is made with `cargo vendor --locked` from
   the repo's `Cargo.lock`, as a tarball with a top-level `vendor/` directory,
   so COPR builds Rust packages offline (`%autosetup -a1`,
   `%cargo_prep -v vendor`);
1. builds a source RPM with `rpmbuild -bs`;
1. builds binary RPMs with `mock -r fedora-<release>-<arch>` when not
   publishing, with the stage's COPR repo added so earlier Regolith packages
   resolve;
1. when publishing, submits the source RPM with `copr-cli build --chroot
   fedora-<release>-<arch> @regolith/regolith-<stage>` and waits for COPR. A
   build that already succeeded for the same version-release and chroot is not
   submitted again.

mock needs a privileged container. Inside one, `--isolation=simple` works.

Only unstable and testing are published by automation. The stable project
(`@regolith/regolith`) is published by humans.

## Running locally

`ci-fedora` is private: log in first with a classic token that has `read:packages`
(`echo $TOKEN | docker login ghcr.io -u <login> --password-stdin`). In CI the
workflow logs in with the `GHCR_READ_TOKEN` org secret, or `GITHUB_TOKEN`.

```shell
docker run --rm --privileged -v "$PWD:/voulage" ghcr.io/regolith-linux-fedora/ci-fedora:43-amd64 \
  /voulage/.github/scripts/main.sh build \
    --extension /voulage/.github/scripts/ext-rpm.sh --git-repo-path /voulage \
    --manifest-path /tmp/manifests --pkg-build-path /tmp/packages --pkg-publish-path /tmp/publish \
    --distro fedora --codename 43 --arch amd64 --stage unstable --suite unstable --component main \
    --only-package regolith-session
```

Built RPMs land in `/tmp/publish/fedora/43/unstable/`. Set `COPR_PUBLISH=yes`
(with `~/.config/copr`) to publish, or add `COPR_DRY_RUN=yes` to print the
`copr-cli` command instead.
