# Template: Python application built with the pyproject macros.
# Copy to <source-package>.spec at the repo root on fedora/<branch>.

Name:           regolith-example-py
Version:        2.1.0
Release:        1%{?dist}
Summary:        Example Regolith utility written in Python
License:        MIT
URL:            https://github.com/regolith-linux/%{name}
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  python3-devel

%description
An example command-line utility. Build and runtime dependencies come from
the project metadata through the generated Python requirements.

%prep
%autosetup

%generate_buildrequires
%pyproject_buildrequires

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files -l regolith_example

%check
%pyproject_check_import

%files -f %{pyproject_files}
%doc README.md
%{_bindir}/regolith-example

%changelog
* Thu Oct 15 2026 Regolith Fedora Port <port@regolith.invalid> - 2.1.0-1
- Initial package
