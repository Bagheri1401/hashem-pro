# Security policy / سیاست امنیتی

This project is an **early-stage MVP** for trusted administrators. It has not been validated in production. Do not expose its management interface directly to the public Internet. Do not install without a backup, and independently audit it before production use.

## Sensitive files
Never publish `/etc/grefrp/`, `/var/lib/grefrp/`, SSH keys, database files, `panel.env`, admin password hashes, or FRP tokens. Even if a value is stored as a hash, treat it as sensitive. **Do not paste server credentials into GitHub issues**.

## Reporting vulnerabilities
Please report suspected security issues privately to the repository maintainer using GitHub's **Report a vulnerability** feature (when the maintainer enables private vulnerability reporting), or via a private channel the maintainer lists in the repository. Do not open public issues containing exploit details or credentials.

## Operational caveats
- The panel listens on `127.0.0.1` and uses SSH port forwarding for administrative access.
- It runs privileged commands; restrict access to trusted operators.
- GRE is not encrypted and requires IP protocol 47 to pass end-to-end.
- FRP TLS protects its connection, but application traffic should use its own encryption as appropriate.
- There is no automatic failover, client quota management, or completed penetration test.
