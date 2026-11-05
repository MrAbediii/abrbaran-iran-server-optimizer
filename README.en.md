<h1 align="center">☁️ ABR BARAN · Iran Server Optimizer</h1>

<p align="center">
A smart, safe and good-looking single-file Bash tool that prepares a Linux server for use in Iran:<br>
DNS · package mirrors · Docker · BBR · kernel tuning · security · updates — every change verified and reversible.
</p>

<p align="center">
<a href="https://github.com/aliabedi94/abrbaran-iran-server-optimizer/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/aliabedi94/abrbaran-iran-server-optimizer/actions/workflows/ci.yml/badge.svg"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
<img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
</p>

<p align="center"><a href="README.md">فارسی</a></p>

## Why

On servers inside Iran, `apt update` is slow or fails, `download.docker.com` and Docker Hub are hard to reach, default DNS may return wrong answers or ISP block pages, and GitHub is sometimes unreachable. Generic "Linux optimizer" scripts don't know any of that and apply most settings blindly.

This tool does the opposite: **measure first, decide, verify, and roll back on failure.**

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/aliabedi94/abrbaran-iran-server-optimizer/main/abrbaran-optimizer.sh -o abrbaran-optimizer.sh \
  && sudo bash abrbaran-optimizer.sh
```

Without arguments in a terminal you get an interactive menu. Non-interactive examples:

```bash
sudo bash abrbaran-optimizer.sh -y                      # all low-risk steps, no prompts
sudo bash abrbaran-optimizer.sh -y --docker --fail2ban  # + Docker and Fail2ban
sudo bash abrbaran-optimizer.sh --only dns,repo         # only DNS and mirrors
sudo bash abrbaran-optimizer.sh --dry-run               # report only, change nothing
sudo bash abrbaran-optimizer.sh --status                # read-only server report
sudo bash abrbaran-optimizer.sh --restore               # roll everything back
```

## What it does

| Module | What | Smart part |
|---|---|---|
| `dns` | Tests 25 Iranian + international resolvers | Detects hijacked answers (ISP block pages), confirms with a real resolve, auto-rollback |
| `repo` | Probes ~90 Ubuntu/Debian/RPM mirrors in parallel | Real download-speed test of top 3 Iranian + top 3 foreign; auto-discovers repo paths; **mirror failover during `apt update/upgrade`** to the next best mirror |
| `docker` | Installs Docker Engine + Compose from healthy mirrors, configures Docker Hub registry mirrors | Verifies the repo **GPG fingerprint** against Docker's official key; merges `daemon.json` (never overwrites); log rotation; verified with a real `docker pull` |
| `bbr` | Enables BBR | Measures throughput before/after and reverts if slower |
| `tune` | 15+ sysctl parameters sized by RAM | Only changes what needs changing |
| `tools` | git, htop, tmux, jq, ncdu, … | Installs only what is missing and available |
| `system` | Swap (if none), nofile limits, journald cap, fstrim, `/etc/hosts` fix | Skips containers / btrfs / zfs / low disk |
| `security` | SSH keep-alive & brute-force limits, optional UFW and Fail2ban | `sshd -t` validated; never touches password/root login (warns only); **45-second anti-lockout confirm** for the firewall |
| `github` / `time` / `update` | GitHub reachability, Asia/Tehran + NTP, safe upgrade | Reboot only when needed, scheduled with delay |

Sensitive features (Docker, firewall, Fail2ban, reboot) are never enabled by `-y` alone; use `--docker`, `--firewall`, `--fail2ban`, `--reboot-now`.

## Supported systems

Ubuntu 20.04 – 26.04 (incl. deb822 sources), Debian 11 – 13, Rocky / AlmaLinux / CentOS Stream / Fedora / Oracle Linux. DNS, sysctl, BBR, time and update also work on openSUSE, Alpine and Arch on a best-effort basis.

## Safety

Backups go to `/var/backups/abrbaran-optimizer/<timestamp>` plus an `original` snapshot of the first run. Every sensitive change is verified and reverted on failure; `Ctrl+C` also rolls back half-finished changes. `--restore` reverts the script's configuration (installed packages, Docker, swapfile and UFW are intentionally kept).

## Contributing

Lists of DNS servers and mirrors live at the top of the script. Every entry is probed at runtime, so adding one is safe. See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © ABR BARAN IDC — <https://abrbaranidc.ir>
