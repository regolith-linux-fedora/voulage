# Template: noarch configuration package with subpackages.
# Modelled on a regolith-look-* repo: debian/control has one source package and
# one binary package per look, and the looks exclude each other.
# Copy to <source-package>.spec at the repo root on fedora/<branch>.

Name:           regolith-look-example
Version:        1.2.0
Release:        1%{?dist}
Summary:        Example look packages for Regolith
License:        GPL-3.0-only
URL:            https://github.com/regolith-linux/%{name}
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch

%description
Configuration files for an example Regolith look, split the same way as the
Debian binary packages built from this repository.

# Debian: Package: regolith-look-example-light
#         Provides: regolith-look   Conflicts: regolith-look
%package        light
Summary:        Light variant of the example look
Requires:       regolith-wm-config
Requires:       (fonts-jetbrains-mono or jetbrains-mono-fonts)
Provides:       regolith-look
Conflicts:      regolith-look

%description    light
The light variant of the example look: window manager resources, the GTK
theme setting and a GSettings override.

# Debian: Package: regolith-look-example-dark
%package        dark
Summary:        Dark variant of the example look
Requires:       regolith-wm-config
Provides:       regolith-look
Conflicts:      regolith-look

%description    dark
The dark variant of the example look.

%prep
%autosetup

%build
# Nothing to build.

%install
for variant in light dark; do
    install -Dpm 0644 -t %{buildroot}%{_datadir}/regolith-look/example-$variant \
        $variant/root
done
# GSettings override: numeric prefix, Upstream's Regolith desktop key kept.
# The glib schema file trigger compiles it; never call glib-compile-schemas.
install -Dpm 0644 light/90_regolith-look-example-light.gschema.override \
    %{buildroot}%{_datadir}/glib-2.0/schemas/90_regolith-look-example-light.gschema.override

%files          light
%license LICENSE
%{_datadir}/regolith-look/example-light/
%{_datadir}/glib-2.0/schemas/90_regolith-look-example-light.gschema.override

%files          dark
%license LICENSE
%{_datadir}/regolith-look/example-dark/

%changelog
* Thu Oct 15 2026 Regolith Fedora Port <port@regolith.invalid> - 1.2.0-1
- Initial package
