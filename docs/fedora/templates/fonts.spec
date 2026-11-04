# Template: font package, following the Fedora font packaging guidelines
# (fonts-rpm-macros). %%fontpkg writes Name, Summary, License and the
# description from the variables below.
# Copy to <source-package>.spec at the repo root on fedora/<branch>.

Version:        3.4.0
Release:        1%{?dist}
URL:            https://github.com/regolith-linux/fonts-example

%global foundry           regolith
%global fontlicense       OFL-1.1
%global fontlicenses      OFL.txt
%global fontdocs          README.md
%global fontfamily        Example Mono
%global fontsummary       Example Mono, a monospaced font for terminals
%global fonts             fonts/*.ttf
%global fontconfs         %{SOURCE10}
%global fontdescription   %{expand:
Example Mono is a monospaced font for terminals and status bars.}

Source0:        %{url}/archive/v%{version}/fonts-example-%{version}.tar.gz
Source10:       60-%{fontpkgname}.conf

%fontpkg

%prep
%autosetup -n fonts-example-%{version}

%build
%fontbuild

%install
%fontinstall

%check
%fontcheck

%fontfiles

%changelog
* Thu Oct 15 2026 Regolith Fedora Port <port@regolith.invalid> - 3.4.0-1
- Initial package
