# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [4.0.0] — 2026-11-05

### Added
- **Docker module:** install Docker Engine + Compose from the fastest healthy mirror (Iranian and international), GPG fingerprint verification, distro-package fallback, Docker Hub registry mirrors with live probing, safe `daemon.json` merge, log rotation, real `docker pull` verification.
- **Interactive main menu** and manual step picker; non-interactive `--only`, `--skip-<module>`, `--docker`, `--firewall`, `--fail2ban`.
- **`--status`:** read-only server report.
- **Tools module:** common admin packages (git, htop, tmux, jq, ncdu, …).
- **System resources module:** swap (when absent), nofile limits, journald size cap, fstrim timer, `/etc/hosts` hostname fix, Ubuntu MOTD ads off.
- **Security module:** safe SSH tuning (validated with `sshd -t`), SSH audit warnings, optional UFW with anti-lockout confirm, optional Fail2ban.
- 12 Iranian + 13 international DNS providers; hijacked-answer detection (`10.10.34.x`, `0.0.0.0`, loopback).
- ~56 Ubuntu / 38 Debian mirrors, 29 RPM hosts, automatic repo-path discovery for `@` entries.
- Unit tests (`tests/run.sh`) and GitHub Actions CI (syntax, ShellCheck, tests, dry-run on 6 distros).

### Changed
- Branding: **ABR BARAN · Iran Server Optimizer**. License: MIT.
- Tables show the top entries by default (`--show-all` for everything).
- Mirror/DNS probing parallelism 8 → 12; real speed test for top 3 Iranian + top 3 foreign mirrors.

## [3.x]
- Mirror failover (including mid-update), Ubuntu 26.04 support, deb822 handling, BBR before/after measurement, loading indicators, backup/restore.
