# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.2] - 2025-12-20

### 🚀 Added
- **State Tracking**: Added a lightweight state tracker (`data/config/.tbs_state`) to detect config changes between runs.
- **State CLI**: New `tbs state` command (`show|reset|init|diff`) to inspect and manage tracked configuration.
- **DB Password Guard**: Added a MySQL/MariaDB entrypoint wrapper (`bin/tbs-db-entrypoint.sh`) to rotate the root password when the environment password changes.
- **Auto Backup on DB Change**: Automatically creates a database backup before database version changes (upgrade/change), and adds safer flows for downgrades.

### ✨ Changed
- **Windows Compatibility**: Improved path normalization and `tbs` command installation for Git Bash/Windows while keeping macOS/Linux behavior.
- **Startup Behavior**: `tbs start/restart/build` now detects critical config changes and triggers rebuilds only when needed.
- **Line Endings Hardening**: Enforced LF line endings for shell/Docker files and added automatic fixes to reduce container start failures on Windows.

### 🐛 Fixed
- **DB Healthcheck Auth**: Healthcheck prefers non-root credentials when available and improves argument handling.

## [1.0.1] - 2025-12-18

### 🚀 Added
- **Per-App Configuration System**: Introduced a robust JSON-based configuration engine for granular control over individual applications (`sites/apps/`).
- **Dedicated SSH/SFTP Service**: Implemented a standalone SSH container providing secure, isolated shell access for each application, replacing legacy SFTP.
- **Advanced App Isolation**: Enhanced security by implementing randomized 12-character unique User IDs (UIDs) for application environments.
- **Diagnostic Dashboard**: Redesigned the landing page (`index.php`) with real-time service health monitoring and environment-specific security audits.
- **Granular PHP Control**: Added support for per-app PHP-FPM pools and custom `.user.ini` configurations.

### ✨ Changed
- **App-Centric Architecture**: Pivoted the entire stack management to an application-first model via the unified `tbs app` CLI.
- **CLI Modernization**: Streamlined all application operations under a single, intuitive command structure.
- **Scoped Database Management**: Refactored database and user creation to be automatically scoped and prefixed per application.
- **Infrastructure Optimization**: Renamed the database service to `dbhost` to improve internal DNS resolution and networking clarity.

### 🐛 Fixed
- **Nginx Path Resolution**: Resolved issues with configuration templates referencing legacy `includes` directories (migrated to `partials`).
- **SSH Integration**: Fixed SSH profile loading in `tbs.sh` and added the `ENABLE_SSH` toggle.
- **Container Standardization**: Upgraded and synchronized Alpine Linux versions (3.20) across all core service images.
- **MySQL 8.0+ Compatibility**: Fixed startup failures by deprecating legacy `query_cache` settings in `my.cnf`.
- **Redis Authentication**: Corrected session handling by standardizing `REDIS_PASSWORD` defaults in `sample.env`.

---

## [1.0.0] - 2025-12-16

### 🎉 Added
- Initial stable release of **PHP Turbo Stack**
- **Dual Stack Modes**:
  - **Hybrid**: Nginx (reverse proxy) → Varnish → Apache (PHP via mod_php)
  - **Thunder**: Nginx (frontend + backend) → PHP-FPM
- **PHP Support**: Multiple versions (7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5) via dedicated Docker images
- **Database Support**: MySQL (5.7, 8.0, 8.4) and MariaDB (10.3, 10.4, 10.5, 10.6, 10.11, 11.4)
- **Pre-configured Services**: Nginx, Apache, MySQL/MariaDB, Redis, Varnish, Memcached, Mailpit, phpMyAdmin
- **TBS CLI** (`tbs.sh`) with commands for:
  - Environment configuration (`tbs config`)
  - Stack lifecycle (`tbs start|stop|restart|build|status|logs`)
  - App management (`tbs app add|rm|db|ssh|domain|ssl|php|config`)
  - SSL management (mkcert for local, Let's Encrypt for production)
  - Backup & restore (`tbs backup`, `tbs restore`)

### 🔒 Security
- Documented production hardening steps in `README.md` and `SECURITY.md`
- Development-only tools (Mailpit, phpMyAdmin) tied to `APP_ENV=development`

---

> 💡 **Note:** For older versions and detailed release history, check the [GitHub Releases](https://github.com/kevinpareek/turbo-stack/releases) page.


