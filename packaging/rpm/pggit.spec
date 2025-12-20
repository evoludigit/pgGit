Name:           pggit
Version:        0.1.0
Release:        1%{?dist}
Summary:        Git-like version control for PostgreSQL

License:        MIT
URL:            https://github.com/evoludigit/pgGit
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  postgresql-devel >= 15
Requires:       postgresql-server >= 15
Requires:       postgresql-contrib >= 15

%description
pgGit provides Git-style version control for PostgreSQL schemas:
- Automatic DDL tracking
- Branch and merge database schemas
- Complete audit trail
- Time-travel queries

%prep
%setup -q

%build
USE_PGXS=1 make %{?_smp_mflags}

%install
USE_PGXS=1 make install DESTDIR=%{buildroot}

# Install SQL files
mkdir -p %{buildroot}%{_datadir}/pgsql/extension/
install -m 644 sql/*.sql %{buildroot}%{_datadir}/pgsql/extension/
install -m 644 pggit.control %{buildroot}%{_datadir}/pgsql/extension/

# Install documentation
mkdir -p %{buildroot}%{_docdir}/%{name}
cp -r docs/* %{buildroot}%{_docdir}/%{name}/

%files
%license LICENSE
%doc README.md
%{_datadir}/pgsql/extension/pggit*.sql
%{_datadir}/pgsql/extension/pggit.control
%{_docdir}/%{name}

%changelog
* Mon Dec 20 2025 pgGit Team <team@pggit.dev> - 0.1.0-1
- Initial release
- Core DDL tracking functionality
- Git-style branching and merging
- PostgreSQL 15+ support