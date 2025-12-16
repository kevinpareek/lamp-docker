## Changelog

All notable changes to this project will be documented in this file.

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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


