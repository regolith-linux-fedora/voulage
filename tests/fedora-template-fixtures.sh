#!/usr/bin/env bash
#
# Write the sources a docs/fedora/templates/<template>.spec needs into a
# SOURCES directory, so the template can be built in mock. The templates
# describe example packages that don't exist, so their Source0 URLs don't
# resolve: each fixture is the smallest project that fits the spec. The
# fedora-fork template builds the real sway-regolith from its fork.
#
# Requires: bash, git, tar, xz; cargo for rust-vendored; network for
# rust-vendored (cargo vendor) and fedora-fork (git clone).
#
# Usage: tests/fedora-template-fixtures.sh <template> <sources-dir>

set -euo pipefail

TEMPLATE="$1"
SOURCES="$(realpath "$2")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# pack <dir-name>: tar.gz $WORK/<dir-name> into SOURCES/<dir-name>.tar.gz
pack() {
  tar -C "$WORK" --owner=0 --group=0 -czf "$SOURCES/$1.tar.gz" "$1"
}

mkdir -p "$SOURCES"

case "$TEMPLATE" in
  noarch-config)
    d="$WORK/regolith-look-example-1.2.0"
    mkdir -p "$d/light" "$d/dark"
    echo "GPL-3.0-only fixture" > "$d/LICENSE"
    echo "wm.client.focused.color.border: #268bd2" > "$d/light/root"
    echo "wm.client.focused.color.border: #002b36" > "$d/dark/root"
    printf '[org.gnome.desktop.interface:Regolith]\ngtk-theme='"'"'Adwaita'"'"'\n' \
      > "$d/light/90_regolith-look-example-light.gschema.override"
    pack regolith-look-example-1.2.0
    ;;

  meson)
    d="$WORK/regolith-exampled-0.4.1"
    mkdir -p "$d/lib" "$d/src" "$d/data"
    echo "GPL-3.0-or-later fixture" > "$d/LICENSE"
    echo "# regolith-exampled" > "$d/README.md"
    cat > "$d/meson.build" <<'EOF'
project('regolith-exampled', ['c', 'vala'], version: '0.4.1', meson_version: '>=0.60')
glib = dependency('glib-2.0')
gio = dependency('gio-2.0')
lib = shared_library('exampled', 'lib/exampled.c',
  version: '0.4.1', soversion: '0', dependencies: [glib], install: true)
install_headers('lib/exampled.h', subdir: 'exampled')
install_data('lib/exampled.vapi', install_dir: get_option('datadir') / 'vala' / 'vapi')
import('pkgconfig').generate(lib, name: 'exampled', description: 'Example library',
  subdirs: 'exampled', requires: 'glib-2.0')
exe = executable('regolith-exampled', 'src/main.vala',
  dependencies: [glib, gio], link_with: lib,
  vala_args: ['--vapidir', meson.current_source_dir() / 'lib', '--pkg', 'exampled'],
  c_args: ['-I' + meson.current_source_dir() / 'lib'], install: true)
install_data('data/regolith-exampled.service', install_dir: get_option('prefix') / 'lib' / 'systemd' / 'user')
test('version', exe, args: ['--version'])
EOF
    cat > "$d/lib/exampled.h" <<'EOF'
#pragma once
#include <glib.h>
const gchar *exampled_version (void);
EOF
    cat > "$d/lib/exampled.c" <<'EOF'
#include "exampled.h"
const gchar *exampled_version (void) { return "0.4.1"; }
EOF
    cat > "$d/lib/exampled.vapi" <<'EOF'
[CCode (cheader_filename = "exampled.h")]
namespace Exampled {
  [CCode (cname = "exampled_version")]
  public unowned string version ();
}
EOF
    cat > "$d/src/main.vala" <<'EOF'
int main (string[] args) {
  stdout.printf ("regolith-exampled %s\n", Exampled.version ());
  return 0;
}
EOF
    cat > "$d/data/regolith-exampled.service" <<'EOF'
[Unit]
Description=Example Regolith session daemon

[Service]
ExecStart=/usr/bin/regolith-exampled

[Install]
WantedBy=default.target
EOF
    pack regolith-exampled-0.4.1
    ;;

  python)
    d="$WORK/regolith-example-py-2.1.0"
    mkdir -p "$d/regolith_example"
    echo "MIT fixture" > "$d/LICENSE"
    echo "# regolith-example-py" > "$d/README.md"
    cat > "$d/pyproject.toml" <<'EOF'
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "regolith-example-py"
version = "2.1.0"
description = "Example Regolith utility"
license = "MIT"
license-files = ["LICENSE"]

[project.scripts]
regolith-example = "regolith_example:main"

[tool.setuptools]
packages = ["regolith_example"]
EOF
    cat > "$d/regolith_example/__init__.py" <<'EOF'
def main():
    print("regolith-example 2.1.0")
EOF
    pack regolith-example-py-2.1.0
    ;;

  fonts)
    d="$WORK/fonts-example-3.4.0"
    mkdir -p "$d/fonts"
    echo "OFL-1.1 fixture" > "$d/OFL.txt"
    echo "# Example Mono" > "$d/README.md"
    # any OFL TrueType font stands in for Example Mono
    font=$(fc-list --format '%{file}\n' ':fontformat=TrueType:spacing=mono' 2>/dev/null | grep -m1 '\.ttf$' || true)
    if [ -z "$font" ]; then
      echo "fonts fixture: no monospaced TrueType font found (install e.g. liberation-mono-fonts)" >&2
      exit 1
    fi
    cp "$font" "$d/fonts/ExampleMono-Regular.ttf"
    pack fonts-example-3.4.0
    cat > "$SOURCES/60-regolith-example-mono-fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>Example Mono</family>
    <default><family>monospace</family></default>
  </alias>
</fontconfig>
EOF
    ;;

  rust-vendored)
    d="$WORK/regolith-example-rs-0.9.0"
    mkdir -p "$d/src"
    echo "GPL-3.0-only fixture" > "$d/LICENSE"
    echo "# regolith-example-rs" > "$d/README.md"
    cat > "$d/Cargo.toml" <<'EOF'
[package]
name = "regolith-example-rs"
version = "0.9.0"
edition = "2021"
license = "GPL-3.0-only"

# one small crate, so the vendor tarball and cargo-vendor.txt aren't empty
[dependencies]
itoa = "1"
EOF
    cat > "$d/src/main.rs" <<'EOF'
fn main() {
    let mut buf = itoa::Buffer::new();
    println!("regolith-example-rs 0.{}.0", buf.format(9));
}
EOF
    (cd "$d" && cargo generate-lockfile -q)
    pack regolith-example-rs-0.9.0
    # the recipe in spec-style-guide.md §9: cargo vendor --locked, packed as Source1
    (cd "$d" && cargo vendor --locked -q vendor >/dev/null && mkdir -p vendor)
    tar -C "$d" --owner=0 --group=0 -cJf "$SOURCES/regolith-example-rs-0.9.0-vendor.tar.xz" vendor
    ;;

  fedora-fork)
    git clone -q --depth 1 --branch fedora/package-sway-v1.12 \
      https://github.com/regolith-linux-fedora/sway-regolith.git "$WORK/src"
    git -C "$WORK/src" archive --format=tar --prefix=sway-regolith-1.12/ HEAD | gzip -n \
      > "$SOURCES/sway-regolith-1.12.tar.gz"
    ;;

  *)
    echo "unknown template: $TEMPLATE" >&2
    exit 2
    ;;
esac

ls -l "$SOURCES"
