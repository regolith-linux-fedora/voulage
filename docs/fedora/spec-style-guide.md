# Fedora spec style guide

How to turn a repo's `debian/` packaging into a Fedora spec. Every packaging
agent follows it. If a Task file disagrees with this guide, the Task file wins
for that Task and the guide gets fixed in a follow-up pull request.

Binding decisions: specs sit beside `debian/` (ADR 0001); Fedora packages
first; vendored Rust crates; Source Changes and Packaging Changes in separate
commits; Green is the only completion bar; agents never contact Upstream or
Fedora.

Worked specs: [templates/](templates/). Registry:
[override-exceptions.md](override-exceptions.md).

## 1. Where things live

- Fedora work for Upstream branch `B` happens only on `fedora/B` in the Port
  Org fork. Never commit to Upstream-named branches. Pull requests target
  `fedora/B`.
- `<source-package>.spec` sits at the repo root on `fedora/B`, beside `debian/`.
- One spec per Debian source package. Each Debian binary package becomes a
  subpackage of the same name, unless Fedora naming rules require another
  name. Record every rename in a comment above the `%package` line.

## 2. Version, Release and tags

- `Version` = the upstream part of the top `debian/changelog` version: drop
  the epoch (`1:`) and the Debian revision (the last `-…`). `4.10.0-1` →
  `4.10.0`; `2:1.0~rc2-0ubuntu3` → `1.0~rc2`. Keep `~` as `~`.
- `Release: N%{?dist}`, starting at 1, reset to 1 whenever `Version` changes.
- Fedora tags: `fedora/v<Version>-<Release>`, without the dist tag, e.g.
  `fedora/v4.10.0-1`.
- CI enforces this with `tools/check-version-match.sh` in `actions`:

      tools/check-version-match.sh <spec> <debian/changelog> [<tag>]

  Exit 0 when they match, 1 on a mismatch, 2 on bad usage or unreadable input.
  Its tests: `tools/test-check-version-match.sh`.
- The mapping must also keep the order of the whole changelog: for every pair
  of consecutive entries, the newer entry is strictly newer by dpkg's version
  ordering, and, when the upstream parts differ, strictly higher by
  rpmvercmp. A history that only steps the revision or the epoch is fine. Two
  ways this fails: an epoch bump such as `2:1.0-1` above `1.5-1` is newer to
  dpkg (the epoch decides) but lower to RPM; and a `+` sorts above letters
  for dpkg, so `2.0+b-1` above `2.0a-1` passes on both sides while the reverse
  order fails the dpkg side.

## 3. Dependencies

| Debian | RPM |
|---|---|
| `Depends` | `Requires` |
| `Recommends` | `Recommends` (dnf installs them by default, like apt) |
| `Suggests` | `Suggests` |
| `Build-Depends` | `BuildRequires`, as `pkgconfig(…)`, `cmake(…)` or `python3dist(…)` where possible |
| `${shlibs:Depends}`, `${misc:Depends}` | drop: RPM generates library dependencies |
| virtual package | `Provides: <virtual>` on each provider, `Requires: <virtual>` on consumers |
| `A \| B` | rich dependency `Requires: (A or B)` |
| mutually exclusive group (session, compositor, resource loader, look) | `Provides: <virtual>` + `Conflicts: <virtual>` on every member; copy Upstream's group semantics exactly |

Take Fedora package names from the dependency map (`docs/fedora/dependency-map.tsv`,
Task 01-07). Never guess a name.

`tools/deb2rpm-deps.py` in `actions` applies this table to a repo's
`debian/control` and prints the spec's relationship tags:

    tools/deb2rpm-deps.py --upstream <dir of <repo>/debian/control> --map <map.tsv> <debian/control>

Versions inside relations follow §2 (no epoch, no Debian revision). Debian's
bare `<`/`>` mean `<=`/`>=`; `Breaks` becomes `Conflicts`; `Architecture: all`
gives a noarch subpackage; arch lists become `%ifarch` on Fedora's arches;
`<!nocheck>` becomes `%bcond check`. Replaces + Conflicts depends on what the
name is: RPM's `Obsoletes` only matches real package names, so an exclusive
group's virtual name keeps `Conflicts`, two current packages that replace each
other keep `Conflicts`, a Fedora package we override gets the §10 form, and
only an old Regolith name gets `Obsoletes`.

## 4. Maintainer scripts → scriptlets

- `postinst`/`prerm`/`postrm` → `%post`/`%preun`/`%postun`. `$1` is the number
  of installed instances after the operation: in `%preun`/`%postun`, `0` means
  erase and `1` means upgrade.
- Drop what Fedora's file triggers do: icon cache, font cache, desktop
  database, glib schema compilation, `ldconfig`.
- `update-alternatives` → `alternatives` only where Fedora uses alternatives
  for that file; otherwise a plain file plus `Conflicts`.
- `update-initramfs` → `dracut`, only in Parity work.
- Never touch `/etc/apt`.
- Never setuid or `chmod +s`. Upstream's avizo postinst makes `light` setuid;
  on Fedora require Fedora's `light` and rely on udev rules and group
  permissions.
- `rm_conffile` → `%config(noreplace)` on the file that replaces it, plus an
  `Obsoletes` or cleanup note.

## 5. systemd units

- `BuildRequires: systemd-rpm-macros`.
- User units: `%{_userunitdir}`, with `%systemd_user_post`,
  `%systemd_user_preun`, `%systemd_user_postun`.
- System units: `%{_unitdir}`, with `%systemd_post`, `%systemd_preun`,
  `%systemd_postun_with_restart`.

## 6. GSettings overrides

- Install to `%{_datadir}/glib-2.0/schemas/` with a numeric prefix
  (`90_regolith-….gschema.override`). Keep Upstream's `Regolith` desktop key.
- Never call `glib-compile-schemas`; the file trigger does it.

## 7. Paths

- Use `%{_datadir}`, `%{_sysconfdir}`, `%{_bindir}`, `%{_libdir}`,
  `%{_libexecdir}` and friends, never literal paths.
- Ubuntu-only paths (`/usr/lib/x86_64-linux-gnu/…`, the mate-polkit agent
  path): a Packaging Change when the difference is Fedora-specific; a Source
  Change when the code can detect the path at runtime.

## 8. Templates

One worked spec per package type in [templates/](templates/). Each parses and
passes `rpmlint` with no errors.

| Template | Package type |
|---|---|
| [noarch-config.spec](templates/noarch-config.spec) | noarch config or metapackage, with subpackages |
| [meson.spec](templates/meson.spec) | meson C/Vala, with a systemd user unit |
| [rust-vendored.spec](templates/rust-vendored.spec) | Rust application with vendored crates |
| [python.spec](templates/python.spec) | Python (pyproject macros) |
| [fonts.spec](templates/fonts.spec) | fonts, per the Fedora font guidelines |
| [fedora-fork.spec](templates/fedora-fork.spec) | fork of a Fedora package, from Fedora's own spec |

## 9. Rust vendoring

- `ext-rpm.sh` makes the vendor tarball on the runner (which has network)
  while it builds the SRPM: `cargo vendor --locked` against the repo's
  `Cargo.lock`, packed as `Source1: %{name}-%{version}-vendor.tar.xz`. COPR then
  builds offline from the SRPM.
- `%prep`: `%autosetup -a1`, then `%cargo_prep -v vendor`.
- `%build`: `%cargo_build`, then `%{cargo_license_summary}`,
  `%{cargo_license} > LICENSE.dependencies` and `%{cargo_vendor_manifest}`.
- `%install`: `%cargo_install`, or a manual install for workspaces.
- `%files`: `%license LICENSE.dependencies cargo-vendor.txt`.
- `License:` covers the bundled crates as well as our code.
- `BuildRequires: cargo-rpm-macros >= 24`; `-v` and `%cargo_vendor_manifest`
  need it. Checked: F43 ships 28.5. Recheck on each new Target and record the
  version here.
- No `Cargo.lock` in the repo? Adding one is a Source Change.

## 10. Override Exceptions

When we ship our own build of something Fedora already provides:

- Use a distinct name (e.g. `sway-regolith`) with
  `Provides: <fedora-name> = %{version}-%{release}` and
  `Conflicts: <fedora-name>`. Never shadow Fedora's package with a higher
  version.
- Start the spec with
  `# Override Exception: <fedora pkg> — <reason> — evidence: <link> — exit condition: <when we can drop it>`.
- Add a row to [override-exceptions.md](override-exceptions.md): package,
  Fedora package overridden, Targets, reason, evidence (failing test or PR),
  exit condition, date.

## 11. Commits

- Source Changes and Packaging Changes never share a commit.
- Source Change commits follow Upstream's commit style and don't mention
  Fedora unless the change is about Fedora detection.
- Packaging commits start with `fedora:`.
- Every pull request says which kind each commit is.

## 12. Local Loop

On the agent workstation (Task 00-04):

1. `rpmbuild -bs <source-package>.spec`
2. `mock -r fedora-<N>-<arch> --addrepo=<COPR unstable repo URL> <srpm>`
3. `rpmlint` on the spec and the built RPMs
4. install-test in `podman run --rm -it fedora:<N>`
5. optionally, the Session Test

A Local Loop pass is never Green.
