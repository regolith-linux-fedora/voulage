# Override Exception: sway — Regolith needs sway built with its patches for trawl resources — evidence: https://github.com/regolith-linux-fedora/sway-regolith/pull/1 — exit condition: Fedora's sway carries the trawl patches
#
# Template: fork of a Fedora package.
# Start from Fedora's own spec (https://src.fedoraproject.org/rpms/sway) at the
# dist-git commit for the matching version, then change only what the fork
# needs. Use a distinct name and never shadow Fedora's package with a higher
# version. Add the matching row to docs/fedora/override-exceptions.md.
# Copy to <source-package>.spec at the repo root on fedora/<branch>.

%global fedora_name sway

Name:           sway-regolith
Version:        1.12
Release:        1%{?dist}
Summary:        i3-compatible window manager for Wayland, with Regolith patches
License:        MIT
URL:            https://github.com/regolith-linux/%{name}
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# BuildRequires as in Fedora's sway.spec (gnupg2 dropped: we build from git, not
# a signed release tarball).
BuildRequires:  gcc-c++
BuildRequires:  meson >= 1.3
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(gdk-pixbuf-2.0)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(json-c) >= 0.13
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libevdev)
BuildRequires:  pkgconfig(libinput) >= 1.26.0
BuildRequires:  pkgconfig(libpcre2-8)
BuildRequires:  pkgconfig(libsystemd) >= 239
BuildRequires:  pkgconfig(libudev)
BuildRequires:  pkgconfig(pango)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(scdoc)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-cursor)
BuildRequires:  pkgconfig(wayland-server) >= 1.21.0
BuildRequires:  pkgconfig(wayland-protocols) >= 1.41
BuildRequires:  pkgconfig(wlroots-0.20)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-icccm)
BuildRequires:  pkgconfig(xkbcommon) >= 1.5.0

Provides:       %{fedora_name} = %{version}-%{release}
Conflicts:      %{fedora_name}

%description
sway is a tiling Wayland compositor and a drop-in replacement for the i3
window manager. This build adds the Regolith patches that read settings from
trawl.

%prep
%autosetup -p1

%build
%meson -Dsd-bus-provider=libsystemd -Dwerror=false
%meson_build

%install
%meson_install

%files
%license LICENSE
%doc README.md
%dir %{_sysconfdir}/sway
%config(noreplace) %{_sysconfdir}/sway/config
# Fedora's sway grants CAP_SYS_NICE so it can raise its scheduling priority
%caps(cap_sys_nice=ep) %{_bindir}/sway
%{_bindir}/swaybar
%{_bindir}/swaymsg
%{_bindir}/swaynag
%{_datadir}/wayland-sessions/sway.desktop
%{_datadir}/backgrounds/sway/
%{bash_completions_dir}/sway*
%{fish_completions_dir}/sway*.fish
%{zsh_completions_dir}/_sway*
%{_mandir}/man1/sway*.1*
%{_mandir}/man5/sway*.5*
%{_mandir}/man7/sway*.7*

%changelog
* Thu Oct 15 2026 Regolith Fedora Port <port@regolith.invalid> - 1.12-1
- Initial package, from Fedora's sway.spec
