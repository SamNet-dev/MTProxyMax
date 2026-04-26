<p align="center">
  <h1 align="center">MTProxyMax</h1>
  <p align="center"><b>The Ultimate Telegram MTProto Proxy Manager</b></p>
  <p align="center">
    One script. Full control. Zero hassle.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-1.0.7-brightgreen" alt="Version"/>
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
    <a href="#-changelog">Changelog</a> &bull;
    <a href="https://www.samnet.dev/learn/networking/mtproto-proxy-telegram/">Full Guide ↗</a>
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
- 🏷️ **Tags & templates** — group users by category, onboard in seconds with reusable limit sets
- 📅 **Monthly quota reset** — subscription-style automatic traffic resets per user
- 🤖 **Telegram bot** with 17 commands — manage everything from your phone
- 🗂️ **Replication** — sync config to slave servers automatically via rsync+SSH
- 📦 **Server migration** — tarball-based export/import with one command
- 💾 **Encrypted backups** — AES-256 backups with autoclean policy
- 🖥️ **Interactive TUI** — no need to memorize commands, menu-driven setup
- 📊 **Prometheus metrics** — real per-user traffic stats, not just iptables guesses
- 🔗 **Proxy chaining** — route through SOCKS5 upstreams for extra privacy
- 🚨 **Maintenance mode + IP banlist** — graceful pre-restart, fine-grained blocking
- 🩺 **Doctor, verify, audit log** — comprehensive diagnostics and change history
- ⚙️ **Engine tuning** — whitelisted parameter tuning without editing raw TOML
- 🔄 **Auto-recovery + auto-rotate** — detects downtime, rotates aging secrets automatically
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

| Limit | Description | Example | Best For |
|-------|-------------|---------|----------|
| **Max Connections** | Concurrent TCP connections (~3 per device) | `15` | **Device limiting** |
| **Max IPs** | Unique IP addresses allowed | `5` | Anti-sharing / abuse |
| **Data Quota** | Lifetime bandwidth cap | `10G`, `500M` | Fair usage |
| **Expiry Date** | Auto-disable after date | `2026-12-31` | Temporary access |

> **Tip:** Each Telegram app opens **~3 TCP connections** (one per DC). So for device limiting, multiply by 3: `conns 15` ≈ max 5 devices. Setting below 5 will likely break even a single device. IP limits are less reliable because mobile users roam between cell towers (briefly showing 2 IPs for 1 device), and multiple devices behind the same WiFi share 1 IP. Use `ips` as a secondary anti-sharing measure.
>
> **Traffic and quotas are lifetime (cumulative)**, not monthly. They don't auto-reset. Use `mtproxymax secret reset-traffic <label>` to manually reset counters, or rotate the secret.

```bash
mtproxymax secret setlimits alice 100 5 10G 2026-12-31
```

---

### 📋 User Management Recipes

<details>
<summary><b>Limit Devices Per User (Recommended)</b></summary>

```bash
mtproxymax secret setlimit alice conns 5    # Single device (~3 conns per device, with headroom)
mtproxymax secret setlimit family conns 15  # Family — up to 5 devices
```

Each Telegram app opens ~3 TCP connections. Setting `conns 5` allows one device with headroom. If someone shares their link, the second device will hit the limit.

</details>

<details>
<summary><b>Device Limit Tiers</b></summary>

| Scenario | `conns` | `ips` (optional) |
|----------|---------|-------------------|
| Single person, one device | `1` | `2` (allow roaming) |
| Single person, multiple devices | `3` | `5` |
| Small family | `5` | `10` |
| Small group / office | `30` | `50` |
| Public/open link | `0` | `0` (unlimited) |

> Set `ips` slightly higher than `conns` to allow for mobile roaming (cell tower switches temporarily show 2 IPs for 1 device).

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
mtproxymax secret setlimit alice conns 10   # ~3 devices
mtproxymax secret setlimit bob conns 5     # 1 device
mtproxymax secret setlimit charlie conns 15 # ~5 devices
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

### 🗂️ Replication (Master-Slave Config Sync)

Keep multiple proxy servers in sync automatically. The master pushes config changes to all slaves via rsync+SSH on a configurable interval. Slaves receive `secrets.conf`, `upstreams.conf`, `instances.conf`, and `config.toml` — their own role settings and local state are never overwritten.

**Setup takes two commands:**

```bash
# On master — run wizard, select Master, add slave
mtproxymax replication setup

# On slave — run wizard, select Slave
mtproxymax replication setup
```

**How it works:**
- Master generates a self-contained sync script at `/opt/mtproxymax/mtproxymax-sync.sh`
- A systemd timer fires every N seconds (default: 60) and runs the sync
- On change — proxy container on slave is automatically restarted
- `settings.conf` and `replication.conf` are always excluded — slave role is never overwritten

```bash
mtproxymax replication status     # Show role, timer state, last sync
mtproxymax replication sync       # Trigger immediate sync
mtproxymax replication logs       # View sync log
mtproxymax replication test       # Test SSH connectivity to all slaves
mtproxymax replication promote    # Promote slave to master (failover)
```

**Roles:**

| Role | Description |
|------|-------------|
| **Master** | Pushes config to slaves on schedule |
| **Slave** | Receives config, read-only. Changes must be made on master |
| **Standalone** | Replication disabled (default) |

---


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

### 🌐 Custom Telegram URLs (Restricted Regions)

For regions where `core.telegram.org` is blocked, the engine can fetch proxy configuration from a custom mirror:

```bash
mtproxymax tg-urls                                                    # Show current URLs
mtproxymax tg-urls set secret https://mirror.example.com/getProxySecret
mtproxymax tg-urls set config-v4 https://mirror.example.com/getProxyConfig
mtproxymax tg-urls set config-v6 https://mirror.example.com/getProxyConfigV6
mtproxymax tg-urls clear                                              # Reset to defaults
```

Also available in **TUI: Settings > [u] Custom Telegram URLs**.

---

### 🩺 Doctor & Diagnostics

Single command that checks everything — Docker, engine, port, metrics, TLS cert, secrets, disk space, Telegram bot:

```bash
mtproxymax doctor
```

More targeted checks:

```bash
mtproxymax port-check     # Test if port is reachable from outside
mtproxymax connections    # Live active connections per user
mtproxymax uptime         # One-line status (scriptable)
mtproxymax config         # Display current engine config
```

---

### 💾 Config Profiles

Save and restore entire configurations (settings + secrets + upstreams) as named snapshots. Useful for switching between stealth/debug/production setups:

```bash
mtproxymax profile save stealth       # Snapshot current config
mtproxymax profile list               # List saved profiles
mtproxymax profile load stealth       # Restore + auto-restart
mtproxymax profile delete stealth
```

---

### 📦 Bulk Operations & Search

Managing many users? These commands scale to hundreds of secrets:

```bash
mtproxymax secret info <label>              # Full view of one user
mtproxymax secret search <query>            # Find by label or notes
mtproxymax secret top [traffic|conns]       # Top 5 users right now
mtproxymax secret sort [traffic|conns|date|name]  # Reorder list
mtproxymax secret stats                     # Compact overview: traffic/quota/expiry %
mtproxymax secret generate-links [txt|html] # Bulk export all links (HTML includes QR codes)
mtproxymax secret export > backup.csv       # Export to CSV
mtproxymax secret import backup.csv         # Import from CSV
mtproxymax secret archive <label>           # Soft-delete (restorable)
mtproxymax secret unarchive <label>         # Restore from archive
mtproxymax secret clone <src> <new>         # Duplicate with all limits
mtproxymax secret bulk-extend <days>        # Extend all expiry dates
mtproxymax secret disable-expired           # Auto-disable all expired secrets
```

---

### 🏷️ Tags & Templates

Tag users to group them logically (family, work, beta, premium), then run bulk operations by tag:

```bash
mtproxymax secret tag alice family,premium    # Assign tags
mtproxymax secret list --tag family            # Filter by tag
mtproxymax secret tags                         # Show all tags
mtproxymax secret untag alice                  # Clear tags
```

Save reusable limit templates to quickly onboard users:

```bash
mtproxymax template save premium 15 5 50G 2026-12-31 "Premium tier"
mtproxymax template list
mtproxymax secret add alice --template premium    # Apply at creation
mtproxymax template apply premium bob             # Apply to existing secret
```

Also available in **TUI: Secrets > [y] Tags / [k] Templates**.

---

### 📅 Monthly Quota Reset & Auto-Rotate

Automatic scheduled operations — no cron setup required (runs from the Telegram bot's 5-min maintenance loop):

```bash
# Per-secret monthly reset — resets traffic counter on day N of each month (handles short months)
mtproxymax secret quota-reset alice 1          # Reset on the 1st
mtproxymax secret quota-reset bob 15           # Reset on the 15th
mtproxymax secret quota-reset alice off        # Disable

# Global auto-rotate — rotates secrets older than N days
mtproxymax auto-rotate 90                      # Rotate every 90 days
mtproxymax auto-rotate off                     # Disable

# Bulk rotate with dry-run
mtproxymax secret rotate --all --dry-run       # Preview
mtproxymax secret rotate --all                 # Do it
```

TUI: **Secrets > [q] Monthly reset** and **[r] Rotate all**, **Settings > [a] Auto-rotate policy**.

---

### 🚨 Maintenance Mode & IP Banlist

**Maintenance mode** rejects new connections with TCP RST while keeping existing sessions alive. Perfect for graceful pre-restart announcements:

```bash
mtproxymax maintenance on          # Reject new clients
mtproxymax maintenance status      # Check current state
mtproxymax maintenance off         # Restore
```

**IP banlist** — block specific IPs/CIDRs at the firewall level (survives reboots):

```bash
mtproxymax ban 192.0.2.0/24        # Ban a subnet
mtproxymax ban 1.2.3.4              # Ban a single IP
mtproxymax bans                     # List all bans
mtproxymax unban 1.2.3.4            # Remove ban
```

Different from geo-blocking (which works by country). Both can run together.

---

### 💾 Encrypted Backups & Server Migration

**Encrypted backups** — AES-256-CBC with PBKDF2 key derivation (100k iterations). Password entered interactively, passed to openssl via environment variable (hidden from `ps aux`):

```bash
mtproxymax backup --encrypt                # Create (password prompt)
mtproxymax backup restore-encrypted file.tar.gz.enc
mtproxymax backup autoclean 30             # Delete backups older than 30 days
```

Set `BACKUP_RETENTION_DAYS` in settings.conf for automatic cleanup via the bot's sweep loop.

**Server migration** — pack everything into a tarball and transfer:

```bash
# On old server
mtproxymax migrate export                      # → /tmp/mtproxymax-migrate-YYYYMMDD-HHMMSS.tar.gz
scp /tmp/mtproxymax-migrate-*.tar.gz new-server:/tmp/

# On new server
mtproxymax migrate import /tmp/mtproxymax-migrate-*.tar.gz
# Auto-backs up current state first, then restarts
```

Includes: settings, secrets, upstreams, instances, tags, archives, banlist, profiles. Replication role is preserved per-server.

---

### ⚙️ Engine Tuning

Expose advanced engine parameters without editing raw TOML — changes are merged into the generated `config.toml` on every reload:

```bash
mtproxymax tune list                       # Show whitelisted params + current overrides
mtproxymax tune set fake_cert_len 4096     # Larger fake cert
mtproxymax tune set log_level debug        # Verbose logging
mtproxymax tune set mask_relay_timeout_ms 120000   # 2-minute mask relay timeout
mtproxymax tune clear log_level            # Revert one to default
mtproxymax tune clear all                  # Revert all
```

Whitelisted params are regex-validated on input. Invalid values are rejected. Also available in **TUI: Settings > [n] Engine tuning**.

---

### ✅ Verify & Audit

**`verify`** runs an end-to-end install check — Docker running, port bound, TLS handshake succeeds, domain reachable, Telegram API reachable, bot token valid:

```bash
mtproxymax verify
```

**`history`** shows an audit log of config changes (secret add/remove/rotate, domain changes, etc.) with timestamps:

```bash
mtproxymax history 100        # Last 100 events
```

**`speedtest`** measures outbound bandwidth and latency:

```bash
mtproxymax speedtest
```

---

### 🐚 Bash Completion

Get tab-completion for all commands:

```bash
sudo mtproxymax completion > /etc/bash_completion.d/mtproxymax
source /etc/bash_completion.d/mtproxymax
# Now: mtproxymax <TAB> or mtproxymax secret <TAB> works
```

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
| **Master-Slave Replication** | ✅ (rsync+SSH, systemd) | ❌ | ❌ | ❌ |
| **Geo-Blocking** | ✅ | IP allowlist/blocklist | ❌ | ❌ |
| **Ad-Tag Support** | ✅ | ❌ (removed in v2) | ✅ | Varies |
| **QR Code Generation** | ✅ | ❌ | ❌ | Some |
| **Auto-Recovery** | ✅ (with alerts) | ❌ | ❌ | ❌ |
| **Auto-Update** | ✅ | ❌ | ❌ | ❌ |
| **Docker** | ✅ (multi-arch) | ✅ | ❌ | Varies |
| **User Expiry Dates** | ✅ | ❌ | ❌ | ❌ |
| **Bandwidth Quotas** | ✅ | ❌ | ❌ | ❌ |
| **Device Limits** | ✅ | ❌ | ❌ | ❌ |
| **Tags & Templates** | ✅ | ❌ | ❌ | ❌ |
| **Encrypted Backups** | ✅ (AES-256) | ❌ | ❌ | ❌ |
| **Server Migration** | ✅ (tarball export/import) | ❌ | ❌ | ❌ |
| **Maintenance Mode** | ✅ (graceful RST) | ❌ | ❌ | ❌ |
| **Audit Log** | ✅ | ❌ | ❌ | ❌ |
| **Engine Tuning UI** | ✅ (whitelisted params) | ❌ | Raw files | ❌ |
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


Master-Slave Replication (optional):

  Master Server              Slave Server(s)
  ┌──────────────┐           ┌──────────────┐
  │ mtproxymax   │──rsync──▶ │ mtproxymax   │
  │ (systemd     │   +SSH    │ (receives    │
  │  timer 60s)  │           │  config)     │
  └──────────────┘           └──────────────┘
```

| Component | Role |
|-----------|------|
| **mtproxymax.sh** | Single bash script: CLI, TUI, config manager |
| **telemt** | Rust MTProto engine running inside Docker |
| **Telegram bot service** | Independent systemd service polling Bot API |
| **Replication sync service** | systemd timer pushing config to slave servers |
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

**Core operations:**
```bash
mtproxymax secret add <label>           # Add user (optional: --template <name>)
mtproxymax secret remove <label>        # Remove user (supports --dry-run)
mtproxymax secret list                  # List all users
mtproxymax secret list --tag <tag>      # Filter list by tag
mtproxymax secret list --csv            # Output as CSV for spreadsheets
mtproxymax secret info <label>          # Full detail view (limits, traffic, link, QR)
mtproxymax secret search <query>        # Find secrets by label or notes
mtproxymax secret rotate <label>        # New key, same label
mtproxymax secret rotate --all          # Bulk rotate (supports --dry-run)
mtproxymax secret clone <src> <new>     # Duplicate with all limits
mtproxymax secret rename <old> <new>    # Rename a secret
mtproxymax secret enable <label>        # Re-enable user
mtproxymax secret disable <label>       # Temporarily disable
mtproxymax secret disable-expired       # Disable all expired secrets
mtproxymax secret link [label]          # Show proxy link
mtproxymax secret qr [label]            # Show QR code
mtproxymax secret generate-links [txt|html]  # Bulk export all links
mtproxymax secret note <label> [text]   # Attach notes/description
mtproxymax secret logs <label> [lines]  # Per-user activity log
```

**Limits & Quotas:**
```bash
mtproxymax secret setlimit <label> <type> <value>          # Set individual limit
mtproxymax secret setlimits <label> <conns> <ips> <quota> [expires]  # Set all limits
mtproxymax secret extend <label> <days>   # Extend one secret's expiry
mtproxymax secret bulk-extend <days>      # Extend all secrets' expiry
mtproxymax secret quota-reset <label> <day|off>  # Monthly quota reset on day N
mtproxymax secret reset-traffic <label|all>      # Reset traffic counters
```

**Tags & Templates:**
```bash
mtproxymax secret tag <label> <tag1,tag2>  # Assign tags to a secret
mtproxymax secret untag <label>            # Clear all tags
mtproxymax secret tags [label]             # Show all tags or for one secret
mtproxymax template save <name> <conns> <ips> <quota> [expires] [notes]
mtproxymax template list                   # List saved templates
mtproxymax template apply <name> <label>   # Apply template to existing secret
mtproxymax template delete <name>
mtproxymax secret add alice --template premium  # Add with preset limits
```

**Organization & Lifecycle:**
```bash
mtproxymax secret sort [traffic|conns|date|name]  # Reorder the list
mtproxymax secret top [traffic|conns] [N]  # Top N users (default 5)
mtproxymax secret stats                 # Compact per-user overview
mtproxymax secret archive <label>       # Soft-delete (restorable)
mtproxymax secret unarchive <label>     # Restore from archive
mtproxymax secret archives              # List archived secrets
mtproxymax secret export > file.csv     # Export to CSV
mtproxymax secret import file.csv       # Import from CSV
mtproxymax secret add-batch <l1> <l2> ...     # Add many at once
mtproxymax secret remove-batch <l1> <l2> ...  # Remove many at once
mtproxymax auto-rotate [N|off]          # Global policy: auto-rotate older than N days
```

</details>

<details>
<summary><b>Configuration</b></summary>

```bash
mtproxymax port [get|<number>]          # Get/set proxy port
mtproxymax ip [get|auto|<address>]      # Get/set custom IP for proxy links
mtproxymax domain [get|clear|<host>]    # Get/set FakeTLS domain
mtproxymax mask-backend [host:port]     # Set mask backend for non-proxy traffic
mtproxymax mask-relay-bytes [N|0|clear] # Max bytes per dir on mask relay (0=unlimited)
mtproxymax tg-urls [get|set <field> <url>|clear]  # Custom Telegram infra URLs
mtproxymax adtag set <hex>              # Set ad-tag
mtproxymax adtag remove                 # Remove ad-tag
mtproxymax config                       # Show current engine config
```

**Engine Tuning (advanced):**
```bash
mtproxymax tune list                    # Show whitelisted tunable params + current values
mtproxymax tune get <param>             # Show current value
mtproxymax tune set <param> <value>     # Set a tunable (e.g. fake_cert_len, mask_relay_timeout_ms, log_level)
mtproxymax tune clear <param|all>       # Clear one or all tunings
```

Tunings are applied via sed post-processing on the generated config.toml — no TOML duplicate-key issues. Whitelisted params include: `fake_cert_len`, `client_handshake`, `tg_connect`, `client_keepalive`, `client_ack`, `replay_check_len`, `replay_window_secs`, `ignore_time_skew`, `listen_backlog`, `max_connections`, `accept_permit_timeout_ms`, `prefer_ipv6`, `fast_mode`, `log_level`, `mask_relay_timeout_ms`, `mask_relay_idle_timeout_ms`.

</details>

<details>
<summary><b>Profiles</b></summary>

```bash
mtproxymax profile save <name>          # Snapshot current config
mtproxymax profile load <name>          # Restore profile (auto-restarts)
mtproxymax profile list                 # List all saved profiles
mtproxymax profile delete <name>        # Delete a profile
```

</details>

<details>
<summary><b>Backup, Restore & Migration</b></summary>

```bash
# Regular (unencrypted) backups
mtproxymax backup                       # Create a timestamped backup
mtproxymax restore <file>               # Restore from a backup file
mtproxymax backups                      # List available backups
mtproxymax backup autoclean [days]      # Delete backups older than N days

# Encrypted backups (AES-256 + PBKDF2)
mtproxymax backup --encrypt             # Create encrypted backup (password prompt)
mtproxymax backup restore-encrypted <file>  # Restore encrypted backup
# Or: mtproxymax restore --encrypted <file>

# Server migration (tarball-based — all settings, secrets, tags, bans, archives, profiles)
mtproxymax migrate export [file]        # Export all state to a tarball
mtproxymax migrate import <file>        # Import state from a tarball (auto-backs up current first)
```

The migrate workflow is perfect for server pivots: run `migrate export` on the old server, `scp` the tarball, run `migrate import` on the new server. Replication config is preserved per-role.

</details>

<details>
<summary><b>Notifications & Bot</b></summary>

```bash
mtproxymax notify <message>             # Send custom message via Telegram bot
mtproxymax telegram setup               # Interactive bot setup
mtproxymax telegram status              # Show bot status
mtproxymax telegram test                # Send test message
mtproxymax telegram disable             # Disable bot
mtproxymax telegram remove              # Remove bot completely
```

</details>

<details>
<summary><b>Periodic Maintenance</b></summary>

```bash
mtproxymax sweep                        # Run all periodic tasks (called by bot loop every 5 min)
mtproxymax auto-rotate [N|off]          # Auto-rotate secrets older than N days
# Monthly quota reset is per-secret: see `secret quota-reset` in User Secrets
```

Periodic tasks run automatically via the Telegram bot daemon's 5-min loop when installed. Can be triggered manually via `sweep` or scheduled via cron.

</details>

<details>
<summary><b>Polish & Completion</b></summary>

```bash
mtproxymax completion                   # Emit bash tab-completion script
mtproxymax changelog                    # Show GitHub release notes since installed version

# Install bash completion (root):
sudo mtproxymax completion > /etc/bash_completion.d/mtproxymax
# Or in your shell:
eval "$(mtproxymax completion)"
```

</details>


<details>
<summary><b>Replication</b></summary>

```bash
mtproxymax replication setup            # Interactive wizard (master/slave/standalone)
mtproxymax replication status           # Role, timer state, last sync, slave list
mtproxymax replication add <host> [port] [label]   # Register a slave server
mtproxymax replication remove <host_or_label>      # Remove a slave
mtproxymax replication list             # List all slaves
mtproxymax replication enable           # Enable sync timer
mtproxymax replication disable          # Disable sync timer
mtproxymax replication sync             # Trigger immediate sync
mtproxymax replication test [host]      # Test SSH connectivity to slave(s)
mtproxymax replication logs             # Show sync log
mtproxymax replication reset            # Remove all replication config
mtproxymax replication promote          # Promote slave to master (failover)
```

</details>

<details>
<summary><b>Security & Routing</b></summary>

**Geo-Blocking:**
```bash
mtproxymax geoblock add <CC>            # Block country
mtproxymax geoblock remove <CC>         # Unblock country
mtproxymax geoblock list                # List blocked countries
```

**IP Banlist:**
```bash
mtproxymax ban <ip|cidr>                # Ban a specific IP/CIDR (iptables, survives reboots)
mtproxymax unban <ip|cidr>              # Remove ban
mtproxymax bans                         # List banned IPs
```

**Maintenance Mode:**
```bash
mtproxymax maintenance on               # Reject new connections gracefully (RST), keep existing alive
mtproxymax maintenance off              # Restore normal operation
mtproxymax maintenance status           # Check current state
```

**Upstream Routing:**
```bash
mtproxymax upstream list                # List upstreams
mtproxymax upstream add <name> <type> <host:port> [user] [pass] [weight]
mtproxymax upstream remove <name>       # Remove upstream
mtproxymax upstream test <name>         # Test connectivity
mtproxymax sni-policy [mask|drop]       # Unknown SNI action (mask=permissive, drop=strict)
```

</details>

<details>
<summary><b>Monitoring</b></summary>

```bash
mtproxymax traffic                      # Per-user traffic breakdown
mtproxymax connections                  # Live active connections per user
mtproxymax metrics                      # Engine metrics dashboard
mtproxymax metrics live [seconds]       # Auto-refresh metrics (default: 5s)
mtproxymax logs                         # Stream live logs
mtproxymax health                       # Quick health check
mtproxymax doctor                       # Comprehensive diagnostics (port, TLS, secrets, disk, bot)
mtproxymax verify                       # End-to-end install check (port, TLS, Telegram API, metrics)
mtproxymax port-check                   # Test if proxy port is reachable from outside
mtproxymax speedtest                    # Outbound bandwidth/latency test from server
mtproxymax uptime                       # One-line status (scriptable)
mtproxymax status [--json]              # Proxy status (JSON for monitoring integrations)
mtproxymax info                         # Comprehensive server overview (OS, IPv4/IPv6, users, services)
mtproxymax history [lines]              # Audit log of config changes
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
| `/opt/mtproxymax/settings.conf` | Proxy settings (port, domain, limits, tunings prefs) |
| `/opt/mtproxymax/secrets.conf` | User keys, limits, expiry dates |
| `/opt/mtproxymax/secrets_archive.conf` | Archived secrets (soft-deleted, restorable) |
| `/opt/mtproxymax/secrets_tags.conf` | User tags (label → comma-separated tags) |
| `/opt/mtproxymax/secrets_quota_reset.conf` | Per-secret monthly quota reset days |
| `/opt/mtproxymax/templates.conf` | Reusable limit templates |
| `/opt/mtproxymax/tunings.conf` | Engine parameter overrides (from `tune set`) |
| `/opt/mtproxymax/banlist.conf` | Banned IPs/CIDRs (iptables-backed) |
| `/opt/mtproxymax/upstreams.conf` | Upstream routing rules |
| `/opt/mtproxymax/instances.conf` | Multi-port instance config |
| `/opt/mtproxymax/profiles/` | Saved config profiles (named snapshots) |
| `/opt/mtproxymax/audit.log` | Config change history |
| `/opt/mtproxymax/connection.log` | Per-user activity log |
| `/opt/mtproxymax/mtproxy/config.toml` | Generated telemt engine config |
| `/opt/mtproxymax/backups/` | Automatic backups (auto-cleaned via `BACKUP_RETENTION_DAYS`) |

---

## 📋 Changelog

### v1.0.7 — Tags, Templates, Migration, Maintenance, IP Banlist & More

- `secret tag/untag/tags` + `secret list --tag` — group users, run bulk ops by tag
- `secret logs <label>` — per-user activity log filter
- `secret rotate --all` + `--dry-run` — bulk rotate with preview
- `secret quota-reset <label> <day>` — monthly quota reset (resets traffic on day N of each month)
- `secret list --csv` — CSV output for spreadsheets
- `template save/list/apply/delete` + `secret add --template <name>` — reusable limit templates
- `auto-rotate [days]` — global policy to auto-rotate secrets older than N days
- `migrate export/import` — tarball-based server migration
- `maintenance on/off` — reject new connections, keep existing alive (graceful pre-restart mode)
- `ban/unban/bans` — iptables-based IP banlist (survives reboots)
- `backup --encrypt` — AES-256 encrypted backups with password
- `backup autoclean [days]` — remove backups older than N days (automatic via `BACKUP_RETENTION_DAYS`)
- `sweep` — internal periodic maintenance command (quota resets, auto-rotate, backup cleanup)
- `info` — comprehensive server overview (OS, network, users, services, security)
- `changelog` — show GitHub release notes since installed version
- `tune list/get/set/clear` — whitelisted engine parameter tuning (fake_cert_len, timeouts, etc.)
- `verify` — end-to-end install verification
- `history [lines]` — config change audit log (secret add/remove/rotate, domain changes)
- `completion` — emit bash tab-completion script
- `speedtest` — outbound bandwidth/latency test from server

### v1.0.6 — Profiles, Archive, Search, Info, Port Check & More

- `secret info <label>` — full detail view (limits, live traffic, link, QR)
- `secret search <query>` — find secrets by partial label or notes
- `secret archive/unarchive` — soft-delete and restore secrets
- `secret top [traffic|conns]` — top N users at a glance
- `secret generate-links [txt|html]` — bulk export links with QR codes
- `config` — display current engine config
- `uptime` — one-line scriptable output for monitoring
- `notify <message>` — send custom Telegram notification
- `port-check` — test if proxy port is reachable from outside
- `profile save|load|list|delete` — named config snapshots
- `mask-backend [host:port]` — set mask backend from CLI/TUI ([#71](https://github.com/SamNet-dev/MTProxyMax/issues/71))
- Metrics bound to 127.0.0.1 only ([#65](https://github.com/SamNet-dev/MTProxyMax/issues/65))
- Fix domain change exit in non-TTY ([#64](https://github.com/SamNet-dev/MTProxyMax/pull/64))
- Fix empty label in non-TTY secret add/remove ([#66](https://github.com/SamNet-dev/MTProxyMax/issues/66))
- Fix upstream table column alignment ([#67](https://github.com/SamNet-dev/MTProxyMax/issues/67))
- Fix false "Update available" badge ([#68](https://github.com/SamNet-dev/MTProxyMax/issues/68))
- Fix invisible "Enter choice" prompt ([#69](https://github.com/SamNet-dev/MTProxyMax/issues/69))
- Fix bot uptime always 0m ([#70](https://github.com/SamNet-dev/MTProxyMax/issues/70))
- Telegram bot: instant response, no temp files ([#62](https://github.com/SamNet-dev/MTProxyMax/issues/62))

### v1.0.5 — Engine v3.4.8, Clone, Bulk-Extend, Doctor, Stats & More

- Engine v3.4.8 — bounded relay queues (memory safety), hot-path pressure caps, IP tracker observability fixes, TLS 1.2/1.3 fronting correctness, full ServerHello default, ALPN in TLS fetcher, configurable Telegram infrastructure URLs
- `secret clone <src> <new>` — duplicate a secret with all its limits
- `secret bulk-extend <days>` — extend all secrets' expiry at once
- `secret extend <label> <days>` — extend a single secret's expiry
- `secret rename`, `secret export/import`, `secret disable-expired`, `secret sort`, `secret stats`
- `connections` — live active connections per user
- `doctor` — comprehensive diagnostics (port, TLS, secrets, disk, Telegram bot)
- Auto-rotate secrets on domain change, startup warnings for expired/near-expiry secrets
- Telegram bot: instant response (long-polling), single awk pass, no temp files
- Metrics bound to localhost only ([#65](https://github.com/SamNet-dev/MTProxyMax/issues/65))
- Fedora 41+ Docker install fix ([#61](https://github.com/SamNet-dev/MTProxyMax/issues/61))

### v1.0.4 — Replication, Engine v3.3.39, Metrics Dashboard

- Replication — master/slave sync via rsync+SSH with wizard, promote, and role guards
- Engine v3.3.39 — Apple/XNU fixes, ME rewrite, conntrack control, TLS fronting fix, memory hard-bounds, bounded retries
- Engine metrics dashboard — `mtproxymax metrics` / `mtproxymax metrics live`
- Unknown SNI policy — configurable `mask` or `drop` ([#40](https://github.com/SamNet-dev/MTProxyMax/issues/40))
- Reset traffic counters — `mtproxymax secret reset-traffic <label|all>`
- Alpine fixes — broken pipe, double-input, SNI rejection ([#37](https://github.com/SamNet-dev/MTProxyMax/issues/37), [#38](https://github.com/SamNet-dev/MTProxyMax/issues/38))

### v1.0.3 — Quota Enforcement, Multi-Port, Hot-Reload

- Secret notes, expiry warnings, quota auto-disable at 100%
- JSON status, connection log, backup & restore
- Multi-port instances, hot-reload for secrets
- Whitelist geo-blocking ([#29](https://github.com/SamNet-dev/MTProxyMax/issues/29))

### v1.0.2 — Persistent Traffic

- Traffic counters survive restarts, saved every 60s ([#13](https://github.com/SamNet-dev/MTProxyMax/issues/13))
- Atomic writes with flock, pre-stop flush, batched stats loading

### v1.0.1 — Batch Secrets

- `secret add-batch` / `secret remove-batch` ([#12](https://github.com/SamNet-dev/MTProxyMax/issues/12))

### v1.0.0 — Initial Release

- telemt 3.x Rust engine, TUI + CLI, multi-user secrets, FakeTLS, Telegram bot, proxy chaining, geo-blocking

---

## 🙏 Credits

Built on top of **telemt** — a high-performance MTProto proxy engine written in Rust/Tokio. All proxy protocol handling, FakeTLS, traffic masking, and per-user enforcement is powered by telemt.

---

## 📖 Documentation & Guides

For step-by-step tutorials with screenshots and detailed explanations, visit our guides on SamNet:

- **[Complete MTProto Proxy Setup Guide](https://www.samnet.dev/learn/networking/mtproto-proxy-telegram/)** — Full walkthrough: install, multi-user management, FakeTLS, Telegram bot, proxy chaining, geo-blocking, replication, and ad-tag monetization.
- **[3X-UI Panel Setup Guide](https://www.samnet.dev/learn/networking/xui-setup/)** — If you need VLESS/VMess/Reality/Trojan protocols alongside MTProto.
- **[Server Hardening Guide](https://www.samnet.dev/learn/security/server-hardening/)** — Secure your proxy server: SSH hardening, firewall rules, fail2ban.
- **[iptables Cheat Sheet](https://www.samnet.dev/learn/cheatsheets/iptables-guide/)** — Firewall rules reference for protecting your proxy.
- **[VPN Leak Test](https://www.samnet.dev/tools/vpn-leak-test/)** — Verify your proxy is hiding your real IP.
- **[Port Scanner](https://www.samnet.dev/tools/port-scanner/)** — Check if your proxy port is accessible from the internet.

---

## 💖 Donate

If you find MTProxyMax useful, consider supporting its development:

[**samnet.dev/donate**](https://www.samnet.dev/donate/)

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

The **telemt engine** (included as a Docker image) is licensed under the [Telemt Public License 3 (TPL-3)](https://github.com/telemt/telemt/blob/main/LICENSE) — a permissive license that allows use, redistribution, and modification with attribution.

Copyright (c) 2026 SamNet Technologies
