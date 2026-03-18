<p align="center">
  <h1 align="center">MTProxyMax</h1>
  <p align="center"><b>The Ultimate Telegram MTProto Proxy Manager</b></p>
  <p align="center">
    One script. Full control. Zero hassle.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-1.0.2-brightgreen" alt="Version"/>
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="License"/>
    <img src="https://img.shields.io/badge/engine-Rust_(telemt_3.x)-orange" alt="Engine"/>
    <img src="https://img.shields.io/badge/platform-Linux-lightgrey" alt="Platform"/>
    <img src="https://img.shields.io/badge/bash-4.2+-yellow" alt="Bash"/>
    <img src="https://img.shields.io/badge/docker-multi--arch-blue" alt="Docker"/>
  </p>
  <p align="center">
    <a href="#-quick-start">Quick Start</a> &bull;
    <a href="#-features">Features</a> &bull;
    <a href="#-comparison">Comparison</a> &bull;
    <a href="#-telegram-bot-17-commands">Telegram Bot</a> &bull;
    <a href="#-cli-reference">CLI Reference</a> &bull;
    <a href="#-changelog">Changelog</a>
  </p>
</p>

---

MTProxyMax is a full-featured Telegram MTProto proxy manager powered by the **telemt 3.x Rust engine**. It wraps the raw proxy engine with an interactive TUI, a complete CLI, a Telegram bot for remote management, per-user access control, traffic monitoring, proxy chaining, and automatic updates — all in a single bash script.

<img src="main.png" width="600" alt="MTProxyMax Main Menu"/>

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/install.sh)"
```

---

## Why MTProxyMax?

Most MTProxy tools give you a proxy and a link. That's it. MTProxyMax gives you a **full management platform**:

- 🔐 **Multi-user secrets** with individual bandwidth quotas, device limits, and expiry dates
- 🤖 **Telegram bot** with 17 commands — manage everything from your phone
- 🖥️ **Interactive TUI** — no need to memorize commands, menu-driven setup
- 📊 **Prometheus metrics** — real per-user traffic stats, not just iptables guesses
- 🔗 **Proxy chaining** — route through SOCKS5 upstreams for extra privacy
- 🔄 **Auto-recovery** — detects downtime, restarts automatically, alerts you on Telegram
- 🐳 **Pre-built Docker images** — installs in seconds, not minutes

---

## 🚀 Quick Start

### One-Line Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/install.sh)"
```

The interactive wizard walks you through everything: port, domain, first user secret, and optional Telegram bot setup.

### Manual Install

```bash
curl -fsSL https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/mtproxymax.sh -o mtproxymax
chmod +x mtproxymax
sudo ./mtproxymax install
```

### After Install

```bash
mtproxymax           # Open interactive TUI
mtproxymax status    # Check proxy health
```

---

## ✨ Features

### 🛡️ FakeTLS V2 Obfuscation

Your proxy traffic looks identical to normal HTTPS traffic. The **Fake TLS V2** engine mirrors real TLS 1.3 sessions — per-domain profiles, real cipher suites, dynamic certificate lengths, and realistic record fragmentation. The TLS handshake SNI points to a cover domain (e.g., `cloudflare.com`), making it indistinguishable from regular web browsing to any DPI system.

**Traffic masking** goes further — when a non-Telegram client probes your server, the connection is forwarded to the real cover domain. Your server responds exactly like cloudflare.com would.

---

### 👥 Multi-User Secret Management

Each user gets their own **secret key** with a human-readable label:

- **Add/remove** users instantly — config regenerates and proxy hot-reloads
- **Enable/disable** access without deleting the key
- **Rotate** a user's secret — new key, same label, old link stops working
- **QR codes** — scannable directly in Telegram

---

### 🔒 Per-User Access Control

Fine-grained limits enforced at the engine level:

| Limit | Description | Example |
|-------|-------------|---------|
| **Max Connections** | Simultaneous TCP connections | `100` |
| **Max IPs** | Unique devices/IPs allowed | `5` |
| **Data Quota** | Total bandwidth cap | `10G`, `500M` |
| **Expiry Date** | Auto-disable after date | `2026-12-31` |

```bash
mtproxymax secret setlimits alice 100 5 10G 2026-12-31
```

---

### 📋 User Management Recipes

<details>
<summary><b>Prevent Key Sharing</b></summary>

```bash
mtproxymax secret setlimit alice ips 1    # Single person only
mtproxymax secret setlimit family ips 5   # Family of up to 5 devices
```

If someone with `ips 1` shares their link, the second device gets rejected automatically.

</details>

<details>
<summary><b>IP Limit Tiers</b></summary>

| Scenario | `max_ips` |
|----------|-----------|
| Single person, one device | `1` |
| Single person, multiple devices | `2-3` |
| Small family | `5` |
| Small group / office | `20-30` |
| Public/open link | `0` (unlimited) |

</details>

<details>
<summary><b>Time-Limited Sharing Link</b></summary>

```bash
mtproxymax secret add shared-link
mtproxymax secret setlimits shared-link 50 30 10G 2026-06-01
```

When the expiry date hits, the link stops working automatically.

</details>

<details>
<summary><b>Per-Person Keys (Recommended)</b></summary>

```bash
mtproxymax secret add alice
mtproxymax secret add bob
mtproxymax secret add charlie

# Each person gets their own link — revoke individually
mtproxymax secret setlimit alice ips 2
mtproxymax secret setlimit bob ips 1
mtproxymax secret setlimit charlie ips 3
```

</details>

<details>
<summary><b>Disable, Rotate, Remove</b></summary>

```bash
mtproxymax secret disable bob    # Temporarily cut off
mtproxymax secret enable bob     # Restore access

mtproxymax secret rotate alice   # New key, old link dies instantly

mtproxymax secret remove bob     # Permanent removal
```

</details>

---

### 🤖 Telegram Bot (17 Commands)

Full proxy management from your phone. Setup takes 60 seconds:

```bash
mtproxymax telegram setup
```

| Command | Description |
|---------|-------------|
| `/mp_status` | Proxy status, uptime, connections |
| `/mp_secrets` | List all users with active connections |
| `/mp_link` | Get proxy details + QR code image |
| `/mp_add <label>` | Add new user |
| `/mp_remove <label>` | Delete user |
| `/mp_rotate <label>` | Generate new key for user |
| `/mp_enable <label>` | Re-enable disabled user |
| `/mp_disable <label>` | Temporarily disable user |
| `/mp_limits` | Show all user limits |
| `/mp_setlimit` | Set user limits |
| `/mp_traffic` | Per-user traffic breakdown |
| `/mp_upstreams` | List proxy chains |
| `/mp_health` | Run diagnostics |
| `/mp_restart` | Restart proxy |
| `/mp_update` | Check for updates |
| `/mp_help` | Show all commands |

**Automatic alerts:**
- 🔴 Proxy down → instant notification + auto-restart attempt
- 🟢 Proxy started → sends connection details + QR codes
- 📊 Periodic traffic reports at your chosen interval

---

### 🔗 Proxy Chaining (Upstream Routing)

Route traffic through intermediate servers:

```bash
# Route 20% through Cloudflare WARP
mtproxymax upstream add warp socks5 127.0.0.1:40000 - - 20

# Route through a backup VPS
mtproxymax upstream add backup socks5 203.0.113.50:1080 user pass 80

# Hostnames are supported (resolved by the engine)
mtproxymax upstream add remote socks5 my-proxy.example.com:1080 user pass 50
```

Supports **SOCKS5** (with auth), **SOCKS4**, and **direct** routing with weight-based load balancing. Addresses can be IPs or hostnames.

---

### 📊 Real-Time Traffic Monitoring

Prometheus metrics give you real per-user stats:

```bash
mtproxymax traffic       # Per-user breakdown
mtproxymax status        # Overview with connections count
```

- Bytes uploaded/downloaded per user
- Active connections per user
- Cumulative tracking across restarts

---

### 🌍 Geo-Blocking

```bash
mtproxymax geoblock add ir    # Block Iran
mtproxymax geoblock add cn    # Block China
mtproxymax geoblock list      # See blocked countries
```

IP-level CIDR blocklists enforced via iptables — traffic is dropped before reaching the proxy.

---

### 💰 Ad-Tag Monetization

```bash
mtproxymax adtag set <hex_from_MTProxyBot>
```

Get your ad-tag from [@MTProxyBot](https://t.me/MTProxyBot). Users see a pinned channel — you earn from the proxy.

---

### ⚙️ Engine Management

```bash
mtproxymax engine status              # Current engine version
mtproxymax engine rebuild             # Force rebuild engine image
mtproxymax rebuild                    # Force rebuild from source
```

Engine updates are delivered through `mtproxymax update`. Pre-built multi-arch Docker images (amd64 + arm64) are pulled automatically. Source compilation is the automatic fallback.

---

## 📊 Comparison

### MTProxyMax vs Other Solutions

| Feature | **MTProxyMax** | **mtg v2** (Go) | **Official MTProxy** (C) | **Bash Installers** |
|---------|:-:|:-:|:-:|:-:|
| **Engine** | telemt 3.x (Rust) | mtg (Go) | MTProxy (C) | Various |
| **FakeTLS** | ✅ | ✅ | ❌ (needs patches) | Varies |
| **Traffic Masking** | ✅ | ✅ | ❌ | ❌ |
| **Multi-User Secrets** | ✅ (unlimited) | ❌ (1 secret) | Multi-secret | Usually 1 |
| **Per-User Limits** | ✅ (conns, IPs, quota, expiry) | ❌ | ❌ | ❌ |
| **Per-User Traffic Stats** | ✅ (Prometheus) | ❌ | ❌ | ❌ |
| **Telegram Bot** | ✅ (17 commands) | ❌ | ❌ | ❌ |
| **Interactive TUI** | ✅ | ❌ | ❌ | ❌ |
| **Proxy Chaining** | ✅ (SOCKS5/4, weighted) | ✅ (SOCKS5) | ❌ | ❌ |
| **Geo-Blocking** | ✅ | IP allowlist/blocklist | ❌ | ❌ |
| **Ad-Tag Support** | ✅ | ❌ (removed in v2) | ✅ | Varies |
| **QR Code Generation** | ✅ | ❌ | ❌ | Some |
| **Auto-Recovery** | ✅ (with alerts) | ❌ | ❌ | ❌ |
| **Auto-Update** | ✅ | ❌ | ❌ | ❌ |
| **Docker** | ✅ (multi-arch) | ✅ | ❌ | Varies |
| **User Expiry Dates** | ✅ | ❌ | ❌ | ❌ |
| **Bandwidth Quotas** | ✅ | ❌ | ❌ | ❌ |
| **Device Limits** | ✅ | ❌ | ❌ | ❌ |
| **Active Development** | ✅ | ✅ | Abandoned | Varies |

<details>
<summary><b>Why Not mtg?</b></summary>

[mtg](https://github.com/9seconds/mtg) is solid and minimal — by design. It's **"highly opinionated"** and intentionally barebones. Fine for a single-user fire-and-forget proxy.

But mtg v2 dropped ad-tag support, only supports one secret, has no user limits, no management interface, and no auto-recovery.

</details>

<details>
<summary><b>Why Not the Official MTProxy?</b></summary>

[Telegram's official MTProxy](https://github.com/TelegramMessenger/MTProxy) (C implementation) was **last updated in 2019**. No FakeTLS, no traffic masking, no per-user controls, manual compilation, no Docker.

</details>

<details>
<summary><b>Why Not a Simple Bash Installer?</b></summary>

Scripts like MTProtoProxyInstaller install a proxy and give you a link. That's it. No user management, no monitoring, no bot, no updates, no recovery.

MTProxyMax is not just an installer — it's a **management platform** that happens to install itself.

</details>

---

## 🏗️ Architecture

```
Telegram Client
      │
      ▼
┌─────────────────────────┐
│  Your Server (port 443) │
│  ┌───────────────────┐  │
│  │  Docker Container  │  │
│  │  ┌─────────────┐  │  │
│  │  │   telemt     │  │  │  ← Rust/Tokio engine
│  │  │  (FakeTLS)   │  │  │
│  │  └──────┬──────┘  │  │
│  └─────────┼─────────┘  │
│            │             │
│     ┌──────┴──────┐     │
│     ▼             ▼     │
│  Direct      SOCKS5     │  ← Upstream routing
│  routing     chaining   │
└─────────┬───────────────┘
          │
          ▼
   Telegram Servers
```

| Component | Role |
|-----------|------|
| **mtproxymax.sh** | Single bash script: CLI, TUI, config manager |
| **telemt** | Rust MTProto engine running inside Docker |
| **Telegram bot service** | Independent systemd service polling Bot API |
| **Prometheus endpoint** | `/metrics` on port 9090 (localhost only) |

---

## 📖 CLI Reference

<details>
<summary><b>Proxy Management</b></summary>

```bash
mtproxymax install              # Run installation wizard
mtproxymax uninstall            # Remove everything
mtproxymax start                # Start proxy
mtproxymax stop                 # Stop proxy
mtproxymax restart              # Restart proxy
mtproxymax status               # Show proxy status
mtproxymax menu                 # Open interactive TUI
```

</details>

<details>
<summary><b>User Secrets</b></summary>

```bash
mtproxymax secret add <label>           # Add user
mtproxymax secret remove <label>        # Remove user
mtproxymax secret list                  # List all users
mtproxymax secret rotate <label>        # New key, same label
mtproxymax secret enable <label>        # Re-enable user
mtproxymax secret disable <label>       # Temporarily disable
mtproxymax secret link [label]          # Show proxy link
mtproxymax secret qr [label]            # Show QR code
mtproxymax secret setlimit <label> <type> <value>  # Set individual limit
mtproxymax secret setlimits <label> <conns> <ips> <quota> [expires]  # Set all limits
```

</details>

<details>
<summary><b>Configuration</b></summary>

```bash
mtproxymax port [get|<number>]          # Get/set proxy port
mtproxymax ip [get|auto|<address>]      # Get/set custom IP for proxy links
mtproxymax domain [get|clear|<host>]    # Get/set FakeTLS domain
mtproxymax adtag set <hex>              # Set ad-tag
mtproxymax adtag remove                 # Remove ad-tag
```

</details>

<details>
<summary><b>Security & Routing</b></summary>

```bash
mtproxymax geoblock add <CC>            # Block country
mtproxymax geoblock remove <CC>         # Unblock country
mtproxymax geoblock list                # List blocked countries
mtproxymax upstream list                # List upstreams
mtproxymax upstream add <name> <type> <host:port> [user] [pass] [weight]
mtproxymax upstream remove <name>       # Remove upstream
mtproxymax upstream test <name>         # Test connectivity
```

</details>

<details>
<summary><b>Monitoring</b></summary>

```bash
mtproxymax traffic                      # Per-user traffic breakdown
mtproxymax logs                         # Stream live logs
mtproxymax health                       # Run diagnostics
```

</details>

<details>
<summary><b>Engine & Updates</b></summary>

```bash
mtproxymax engine status                # Show current engine version
mtproxymax engine rebuild               # Force rebuild engine image
mtproxymax rebuild                      # Force rebuild from source
mtproxymax update                       # Check for script + engine updates
```

</details>

<details>
<summary><b>Telegram Bot</b></summary>

```bash
mtproxymax telegram setup               # Interactive bot setup
mtproxymax telegram status              # Show bot status
mtproxymax telegram test                # Send test message
mtproxymax telegram disable             # Disable bot
mtproxymax telegram remove              # Remove bot completely
```

</details>

---

## 💻 System Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky, AlmaLinux, Alpine |
| **Docker** | Auto-installed if not present |
| **RAM** | 256MB minimum |
| **Access** | Root required |
| **Bash** | 4.2+ |

---

## 📁 Configuration Files

| File | Purpose |
|------|---------|
| `/opt/mtproxymax/settings.conf` | Proxy settings (port, domain, limits) |
| `/opt/mtproxymax/secrets.conf` | User keys, limits, expiry dates |
| `/opt/mtproxymax/upstreams.conf` | Upstream routing rules |
| `/opt/mtproxymax/mtproxy/config.toml` | Generated telemt engine config |

---

## 📋 Changelog

### v1.0.2 — Persistent Traffic & TUI Performance

- **Persistent Traffic Counters** — Traffic stats (TRAFFIC IN / TRAFFIC OUT) now survive container restarts ([#13](https://github.com/SamNet-dev/MTProxyMax/issues/13))
- **Always-On Traffic Tracking** — Cumulative traffic saved to disk every 60s, even without Telegram bot enabled
- **Pre-Stop Traffic Flush** — Final traffic snapshot saved before every stop/restart, no data loss on clean shutdown
- **TUI Batch Stats Loading** — Single metrics fetch + single file read replaces per-user subprocess spawning
- **Atomic File Writes with Locking** — Traffic files use `flock` to prevent race conditions between daemon and CLI
- **Fixed In/Out Direction Mapping** — Consistent `from_client`=in, `to_client`=out across all functions

### v1.0.1 — Batch Secret Management

- **Batch Add** — `secret add-batch <l1> <l2> ...` adds multiple secrets with a single restart ([#12](https://github.com/SamNet-dev/MTProxyMax/issues/12))
- **Batch Remove** — `secret remove-batch <l1> <l2> ...` removes multiple secrets with a single restart
- **`--no-restart` flag** — `secret add/remove/add-batch/remove-batch --no-restart` for scripting and automation
- **TUI options** — Interactive menu options [6] and [7] for batch operations

### v1.0.0 — Engine v3.3.22

**Engine Upgrade (v3.3.3 → v3.3.22):**

- **Adaptive Buffers** — Dynamic buffer sizing: less RAM at low load, more throughput at high load
- **Session Eviction** — Smarter cleanup of idle/dead connections under memory pressure
- **Flow Performance** — 3x faster D2C flush (1500μs → 500μs) + immediate ACK flushing for lower latency
- **Tighter Timeouts** — Keepalive 60s → 15s, ACK 300s → 90s for faster dead-connection cleanup
- **Hot-Reload Fixes** — More reliable config reload without restart
- **Configurable max_connections** — New option to cap total connections (default: 10000)
- **Event-Driven ME** — Pool switches from busy-polling to event-driven, reducing CPU on idle servers
- **CPU/RAM Hot-Path Optimization** — Removed hot-path obstacles for lower resource usage under load
- **ME Writer Rebinding** — Lifecycle fixes: proper cleanup of stale writers, faster recovery after drops
- **Source-IP ME Routing** — Routing decisions factor in source IP for multi-homed servers
- **ME/DC Reroute** — Dynamic rerouting when preferred datacenter path degrades
- **Per-Upstream Runtime Selftest** — Built-in diagnostics for upstream connectivity

### v1.0.0 — Per-User Limits + Telegram Bot

- Per-user connection, IP, quota, and expiry limits
- Telegram bot with 17 commands for remote management
- Proxy chaining via SOCKS5/SOCKS4 upstreams
- Geo-blocking with CIDR blocklists
- Auto-recovery with Telegram alerts

### v1.0.0 — Initial Release

- Full MTProto proxy management with telemt 3.x Rust engine
- Interactive TUI + complete CLI
- Multi-user secret management with QR codes
- FakeTLS obfuscation with traffic masking
- Prometheus metrics endpoint
- Auto-update system

---

## 🙏 Credits

Built on top of **telemt** — a high-performance MTProto proxy engine written in Rust/Tokio. All proxy protocol handling, FakeTLS, traffic masking, and per-user enforcement is powered by telemt.

---

## 💖 Donate

If you find MTProxyMax useful, consider supporting its development:

[**samnet.dev/donate**](https://www.samnet.dev/donate/)

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

Copyright (c) 2026 SamNet Technologies
