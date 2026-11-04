# Template: meson C/Vala application with a systemd user service.
# Modelled on a Regolith daemon such as trawl: one Debian source package that
# builds a library, a daemon and a development package.
# Copy to <source-package>.spec at the repo root on fedora/<branch>.

Name:           regolith-exampled
Version:        0.4.1
Release:        1%{?dist}
Summary:        Example Regolith session daemon
License:        GPL-3.0-or-later
URL:            https://github.com/regolith-linux/%{name}
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# Debian Build-Depends, as pkgconfig() capabilities where they exist.
BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  vala
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  systemd-rpm-macros

# ${shlibs:Depends} and ${misc:Depends} are dropped: RPM generates library
# dependencies itself.
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}

%description
A session daemon that serves Regolith settings over D-Bus. It runs as a
systemd user service.

%package        libs
Summary:        Shared library for %{name}

%description    libs
The shared library used by %{name} and its clients.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}

%description    devel
Headers, the pkg-config file and the Vala API for building against the
%{name} library.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%check
%meson_test

# Debian postinst enabled the unit for every user; RPM uses the user macros.
%post
%systemd_user_post %{name}.service

%preun
%systemd_user_preun %{name}.service

%postun
%systemd_user_postun %{name}.service

%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}
%{_userunitdir}/%{name}.service

%files          libs
%license LICENSE
%{_libdir}/libexampled.so.0*

%files          devel
%{_includedir}/exampled/
%{_libdir}/libexampled.so
%{_libdir}/pkgconfig/exampled.pc
%{_datadir}/vala/vapi/exampled.vapi

%changelog
* Thu Oct 15 2026 Regolith Fedora Port <port@regolith.invalid> - 0.4.1-1
- Initial package
