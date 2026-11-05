# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [4.0.4] — 2026-11-05

### Fixed
- apt/dpkg could freeze at the very end of an install/upgrade ("Processing triggers for debianutils") on some servers. apt now runs with `timeout --foreground`, stdin from `/dev/null` and `Dpkg::Use-Pty=0`, so it can never be stopped by terminal signals.
- Watchdog: if an operation prints nothing for 60 seconds, process state is written to the log and any stopped apt/dpkg process is resumed.

## [4.0.3] — 2026-11-05

### Added
- Beginner-friendly **guide** printed before each sensitive question (tools, system resources, Docker, SSH tuning, UFW firewall, Fail2ban, system update): what it does, the risk, the commands you will need afterwards and how to undo it. Hidden with `-y`.

## [4.0.2] — 2026-11-05

### Fixed
- Progress bar for apt upgrade/install now reflects the **whole** operation (taken from apt's own status: download 0–40%, install 40–100%) instead of reaching 100% after the first package.
- Slow `man-db` trigger no longer stalls installs/upgrades (auto-update of the man index is deferred to its timer).

## [4.0.1] — 2026-11-05

### Added
- Real percentage progress bar for package installs (apt: download/unpack/setup/triggers; dnf/yum: n/m), Docker installation and swap creation.
- Animated "working" bar for every other long step (previously a plain spinner).

### Changed
- Tools step now lists **all** packages before asking, on its own line (no more truncated "..." list and no RTL/LTR text mix-ups).
- Package installs use `--no-install-recommends` and show the current dpkg trigger, so slow triggers are visible instead of looking like a hang.

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
