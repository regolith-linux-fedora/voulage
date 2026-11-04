# Template: Rust application with vendored crates.
# Source1 is not in the repository. ext-rpm.sh makes it on the runner while it
# builds the SRPM, with `cargo vendor --locked` against Cargo.lock, so COPR
# builds offline from the SRPM.
# Copy to <source-package>.spec at the repo root on fedora/<branch>.

Name:           regolith-example-rs
Version:        0.9.0
Release:        1%{?dist}
Summary:        Example Regolith tool written in Rust
# Our code is GPL-3.0-only. The rest covers the vendored crates: update it from
# the %%{cargo_license_summary} output in the build log whenever Cargo.lock
# changes.
License:        GPL-3.0-only AND (Apache-2.0 OR MIT) AND Unicode-3.0
URL:            https://github.com/regolith-linux/%{name}
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
Source1:        %{name}-%{version}-vendor.tar.xz

BuildRequires:  cargo-rpm-macros >= 24

%description
An example command-line tool, built from the crates bundled in Source1.

%prep
%autosetup -a1
%cargo_prep -v vendor

%build
%cargo_build
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
%cargo_install

%check
%cargo_test

%files
%license LICENSE
%license LICENSE.dependencies cargo-vendor.txt
%doc README.md
%{_bindir}/%{name}

%changelog
* Thu Oct 15 2026 Regolith Fedora Port <port@regolith.invalid> - 0.9.0-1
- Initial package
