## Changelog

All notable changes to this project will be documented in this file.

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### [1.0.1] - 2025-12-17

#### Fixed
- Fixed Nginx configuration templates referencing non-existent `includes` directory (changed to `partials`).
- Fixed SSH service integration: added `ENABLE_SSH` configuration option and updated `tbs.sh` to include the SSH profile when enabled.
- Standardized Alpine Linux versions across Nginx and SSH containers (upgraded SSH to Alpine 3.20).
- Fixed Nginx entrypoint script to correctly process `common.conf` into `includes` directory, and reverted templates to point to the processed file.
- Fixed MySQL 8.0+ compatibility by commenting out deprecated `query_cache` settings in `my.cnf`.
- Fixed Redis session configuration by defaulting `REDIS_PASSWORD` to empty in `sample.env` to match PHP configuration.

### [1.0.0] - 2025-12-16

#### Added
- Initial stable release of **PHP Turbo Stack**.
- Dual stack modes:
  - **Hybrid**: Nginx (reverse proxy) → Varnish → Apache (PHP via mod\_php).
  - **Thunder**: Nginx (frontend + backend) → PHP-FPM.
- Support for multiple PHP versions (7.4–8.4) via dedicated Docker images.
- Support for MySQL and MariaDB versions via dedicated Docker images.
- Pre-configured services: Nginx, Apache, MySQL/MariaDB, Redis, Varnish, Memcached, Mailpit, phpMyAdmin.
- `tbs.sh` helper script for:
  - Environment configuration (`tbs config`).
  - Stack lifecycle (`tbs start|stop|restart|build|status|logs`).
  - App management (`tbs addapp`, `tbs removeapp`, `tbs code`).
  - SSL management (`tbs ssl`, `tbs ssl-localhost`).
  - Backup & restore (`tbs backup`, `tbs restore`).

#### Security
- Documented production hardening steps in `README.md` and `SECURITY.md`.
- Ensured development-only tools (Mailpit, phpMyAdmin) are tied to `APP_ENV=development`.

---

Older versions will be documented here once new releases are made.


