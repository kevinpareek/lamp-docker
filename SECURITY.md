## Security Policy

### Supported Versions

This project follows semantic versioning. At the moment, the **1.x** line is supported.

- **1.x** – Actively supported (bug fixes and security updates).

### Reporting a Vulnerability

If you discover a security vulnerability:

- **Do not** open a public GitHub issue with sensitive details.
- Instead, contact the maintainer privately (for example via the email address on their GitHub profile or by opening a minimal issue asking for a private contact channel).
- Please include:
  - A clear description of the issue and impact.
  - Steps to reproduce.
  - Any suggested mitigation or patch (if you have one).

The maintainer will:

1. Acknowledge receipt as soon as reasonably possible.
2. Investigate and confirm the issue.
3. Prepare a fix and a coordinated disclosure plan, including a new tagged release (e.g. `v1.x.y`) if needed.

### Recommended Hardening for Production

The default configuration is tuned for local development. For production or internet-facing deployments, **you must harden your environment**:

- **Environment & Credentials**
  - Set `APP_ENV=production` in `.env`.
  - Change all default database credentials (`MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`) to strong, unique values.
  - Disable Xdebug by setting `INSTALL_XDEBUG=false`.
- **Network Exposure**
  - Expose only HTTP/HTTPS (80/443) from the host or load balancer.
  - Keep MySQL, Redis, and other internal services bound to `127.0.0.1` or internal/private networks only.
- **TLS / Certificates**
  - For `INSTALLATION_TYPE=live`, ensure domains point to the correct server before using Certbot/Let’s Encrypt.
  - Regularly renew and rotate certificates as needed.
- **Updates & Scanning**
  - Periodically rebuild images to pick up upstream security patches.
  - Run container image scanners (e.g. `trivy`, `docker scout`) against your built images and apply updates based on their reports.

Following these guidelines will help keep your PHP Turbo Stack deployments safer in real-world environments.


