# Fedora Targets and dependency map

Two generated files that the Fedora port reads. Regenerate them, don't edit
them by hand.

## targets.json

The Fedora releases and architectures the port builds. **CI matrices read
this file and nothing else**: the ci-fedora images (ci-images), the voulage
Fedora stage tree (`stage/<stage>/fedora/<release>/`) and the per-repo Fedora
workflows (actions) all follow it.

Rule (also stored in the file as `rule`):

> Every Fedora release in Bodhi state `current` is a blocking Target, so the
> oldest release leaves at its EOL. A branched release that is not yet
> `current` (Bodhi state `pending` or `frozen`) is a non-blocking early-warning
> Target until it becomes `current`. Rawhide is the non-blocking Canary Target.
> Architectures: x86_64 and aarch64.

| Key | Meaning |
|---|---|
| `targets` | blocking releases: CI failures here fail the run |
| `early_warning` | branched release before it is `current`: non-blocking |
| `canary` | Rawhide: non-blocking, `fedora_version` is the Fedora number it will become |
| `sources.versions_indexed` | the date the repo indexes behind `versions` were dumped |
| `versions` | per release: GNOME (`gnome-control-center`, `gnome-shell`), `sway`, every `wlroots*` package, `gtklock`, `gtk3`, `gtk4`, `cargo-rpm-macros`, and `sway_links_wlroots`: the wlroots soname Fedora's sway requires, the package providing it and its `-devel` |

Versions come from `dnf repoquery --latest-limit=1` in
`registry.fedoraproject.org/fedora:<release>` with the image's default repos,
for each architecture (`--forcearch`). When the two architectures differ,
`versions` is keyed by architecture.

## dependency-map.tsv

Every package name in the `debian/control` files of the Fedora Baseline
(Upstream's unstable Stage, 2026-10-05, plus `sway-regolith`
`package-sway-v1.12`), mapped to Fedora on each release.

| Column | Meaning |
|---|---|
| `debian_name` | the name as written in `debian/control` |
| `field` | the fields it appears in (`Depends`, `Build-Depends`, ...) |
| `used_by` | Baseline source packages that name it |
| `constraints` | version and architecture constraints, kept as written |
| `fedora_43` ... `fedora_rawhide` | what satisfies it: a package name, or a capability with its providers in parentheses (e.g. `pkgconfig(gtk4) (gtk4-devel)`); `-` when nothing does; `x86_64:... aarch64:...` when the architectures differ; `regolith` for packages the port builds |
| `status` | `same` (same name on every release), `renamed`, `capability` (use the capability, e.g. `pkgconfig()`), `gap` (nothing on Fedora), `problem` (missing on some releases, or needs a decision), `drop` (Debian-only, no meaning on Fedora; the note says why), `regolith` (built by the port) |
| `owner` | the plan Task that owns a `gap` or `problem` |
| `notes` | how it was resolved, alternatives, decisions |

Prefer the capability column for `BuildRequires`: `pkgconfig(...)` survives
Fedora package renames.

## Regenerating

From the plans repository (`regolith-linux-fedora/plans`):

```shell
python3 tools/fedora_depmap.py index                       # Fedora repo indexes, ~10 min (podman or docker)
python3 tools/fedora_depmap.py targets <voulage>/docs/fedora --date YYYY-MM-DD
python3 tools/fedora_depmap.py depmap <voulage>/docs/fedora
tests/fedora-docs.sh                                       # in voulage: what CI checks
```

Curated decisions (drops, problems, owners) live in
`tools/fedora_depmap_rules.tsv` in the plans repository. Refresh `targets.json`
whenever a Fedora release changes Bodhi state, and both files on every Rebase.
