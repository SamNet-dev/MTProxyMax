<p align="center">
  <h1 align="center">MTProxyMax</h1>
  <p align="center"><b>The Ultimate Telegram MTProto Proxy Manager</b></p>
  <p align="center">
    One script. Full control. Zero hassle.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-1.3.1-brightgreen" alt="Version"/>
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
    <a href="#-telegram-bot-21-commands">Telegram Bot</a> &bull;
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

- 🏆 **Comprehensive Enterprise Platform** — Over 30 enterprise features across Networking, Quota Governance, DevOps Automation, and Live Telemetry
- 👥 **Shared Quota Pools & Calendar Schedules** — Group users under shared bandwidth ceilings (`pool`) and offer unmetered weekend/holiday data passes (`calendar`)
- ⚡ **Autonomous Failover & SNI Hunter** — Self-healing upstream watchdog (`failover`), automated cover domain hunting (`auto-sni`), and TLS fingerprint randomization (`cert-shield`)
- 🚑 **1-Click Emergency Evacuation & Webhooks** — Instant SSH/rsync server migration (`evacuate`) and multi-channel JSON notifications for Discord, Slack, and DingTalk (`webhook`)
- 📊 **Live Telemetry & Audit Reports** — Real-time ASCII traffic dashboard (`live-diag`), printable QR onboarding sheets (`qr-sheet`), and monthly billing export reports (`export-report`)
- 🏢 **Enterprise Commercial Suite** — Batch gift code vouchers (`voucher create/redeem`), Role-Based Access Control (`admin add`), and static glassmorphism Status Portal (`portal`)
- 🛡️ **Automated Hostile Threat Shield** — Live Shodan/Censys scanner blacklisting via `ipset` (`scanner-shield`)
- 🛡️ **Next-Gen Anti-DPI & Stealth Suite** — BBRv3 congestion control (`bbr`), Anti-DPI packet padding (`shield`), Reverse-proxy probe trapdoor (`cover-shield`), and active forensic inspection (`dpi-inspect`)
- 🏎️ **Bandwidth Shaping & Quotas** — Linux `tc` per-IP QoS limits, off-peak Happy Hours quota exclusions, and automated Telegram abuse/expiry alerts
- 🚨 **Emergency Lockdown Switch** — Instant panic posture hardening via CLI or Telegram bot (`/mp_lockdown`)
- 🌐 **DevOps & Clustering Automation** — HAProxy/Nginx load balancer config exporter, Cloudflare DDNS updater, and forensic snapshots
- 🔐 **Multi-user secrets** with individual bandwidth quotas, device limits, and expiry dates
- 🏷️ **Tags & templates** — group users by category, onboard in seconds with reusable limit sets
- 📅 **Monthly quota reset** — subscription-style automatic traffic resets per user
- 🤖 **Telegram bot** with 21 administrative commands — manage users, view health digests, and trigger lockdowns from chat
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

### 🛡️ FakeTLS V2 & Advanced Anti-DPI Defenses

Your proxy traffic looks identical to normal HTTPS traffic. The **Fake TLS V2** engine mirrors real TLS 1.3 sessions — per-domain profiles, real cipher suites, dynamic certificate lengths, and realistic record fragmentation.

- **Multi-Domain SNI Pool (`tls_domains`):** Rotate between multiple high-reputation cover domains (e.g., `cloudflare.com,www.microsoft.com,www.google.com`) within the same proxy engine instance to evade single-domain DPI throttling and SNI blacklisting (`mtproxymax domain-pool <domains>`).
- **Kernel SYN Shield:** Built-in iptables/nftables rate limiter (`conntrack` + `recent` module) that tarpits aggressive DPI active scanners (>15 SYN packets in 5 seconds per IP) before they reach the application layer (`mtproxymax shield on`).
- **Anti-DPI Packet Padding Shield (`mtproxymax shield on`):** Randomizes TCP MSS clamping (`1360`) and scrubs FakeTLS packet size distributions to defeat GFW, TSPU, and TIC heuristic analysis.
- **Reverse-Proxy Cover Shield (`mtproxymax cover-shield on`):** Active scanner trapdoor that seamlessly forwards non-MTProto HTTP GETs and invalid TLS handshakes directly to a fallback website (e.g., `https://cloudflare.com`) instead of closing or resetting the TCP socket.
- **Stealth Presets (`normal` vs `ultra`):** Hot-swappable anti-replay hardening (`mtproxymax stealth ultra`). `ultra` tightens the replay window to 180 seconds, expands the nonce cache to 131,072 entries, and drops unknown SNI probes immediately.
- **TCP MSS Clamping:** Prevents MTU black hole drops and packet fragmentation by aligning TCP Maximum Segment Size `--clamp-mss-to-pmtu` (`mtproxymax clamp-mss on`).
- **Multi-Port Listener Pool:** Listen on multiple fallback TCP ports simultaneously (e.g., 443, 8443, 2053) using automated kernel NAT redirection without spawning extra container instances (`mtproxymax port-pool add <port>`).

---

### 🔬 Active DPI Forensics & Self-Healing Cover Watchdog

- **DPI Readiness Inspector (`mtproxymax dpi-inspect`):** Runs an automated 5-point heuristic network forensic scan (cover domain reachability, certificate length parity, kernel SYN shield state, engine replay hardening preset, and TCP MSS clamping state) to assign your server a live **Anti-DPI Hardening Score out of 100**.
- **Automated Cover Watchdog (`mtproxymax cover-watchdog auto`):** A self-healing background daemon. If state firewalls or ISP censors block or throttle your primary cover domain (returning HTTP 5xx or connection timeouts), the watchdog automatically rotates to the next available backup domain in your pool and reloads the proxy engine.

---

### 🚨 Emergency Panic Lockdown Switch

Instantly harden server posture under active censorship or DDoS attacks:
```bash
mtproxymax lockdown on
```
Activating lockdown instantly engages the **Kernel SYN Shield**, activates **Ultra-Stealth** conntrack hardening, enforces **TCP MSS Clamping**, and sends a priority broadcast alert to your Telegram administrator bot chat. You can also toggle lockdown remotely from Telegram via `/mp_lockdown on`.

---

### 🏎️ Per-IP Bandwidth Shaping (QoS) & Quota Intelligence

- **Kernel Traffic Shaping (`mtproxymax qos set <mbps>`):** Uses Linux `tc` (Traffic Control) hierarchical token buckets and kernel firewall hashlimits to enforce strict per-IP speed limits (e.g., 5 Mbps per IP), preventing single users from saturating server uplink bandwidth.
- **Off-Peak Happy Hours (`mtproxymax happy-hours set 02:00-08:00`):** Define unmetered schedule windows. Any traffic consumed during Happy Hours completely bypasses user monthly bandwidth quota depletion.
- **Proactive Expiry Notifications (`mtproxymax notify-expiry`):** Scans active user accounts and dispatches automated direct Telegram reminder alerts 7 days, 3 days, and 24 hours prior to subscription expiration.
- **Abnormal Bandwidth Watchdog (`mtproxymax abuse-watch`):** Monitors rolling 24-hour traffic consumption and flags suspicious accounts exceeding 50GB/day.

---

### 🌐 DevOps Clustering & Load Balancing Export

- **Layer-4 Load Balancer Exporter (`mtproxymax export-lb [haproxy|nginx]`):** Generates production-ready HAProxy (`haproxy.cfg`) and Nginx Stream (`nginx.conf`) configuration snippets configured with TCP pass-through and PROXY Protocol v2 headers.
- **Cloudflare Dynamic DNS (`mtproxymax ddns set <token> <zone_id> <record>`):** Automatically detects server public IP changes and updates Cloudflare DNS A records via API v4 (`mtproxymax ddns run`).
- **Forensic Diagnostics Dump (`mtproxymax diag-dump`):** Bundles kernel networking state, routing tables, active iptables rules, container inspect logs, and a redacted settings archive into a clean `.tar.gz` diagnostic package.
- **Configuration Snapshots (`mtproxymax snapshot create <name>`):** Creates self-contained point-in-time tarball snapshots of all proxy settings, secrets, upstreams, domain pools, and geoblocks with one-click restoration (`mtproxymax snapshot restore <name>`).

---

### ⚡ Operations, Briefings & Onboarding Suite

- **Direct Telegram Cloud Backups (`mtproxymax backup send-tg`):** Pushes your latest server backup archive (`.tar.gz`) directly to your Telegram bot admin chat as a file attachment, ensuring offsite disaster recovery even if your VPS disk fails.
- **Morning Executive Briefing (`mtproxymax daily-report on 08:00`):** Schedules an automated morning summary message detailing 24h traffic volume, active user counts, SYN shield interceptions, and expiring subscriptions.
- **SSH Intrusion Shield (`mtproxymax ssh-shield on`):** Configures fail2ban kernel jails tuned specifically for MTProto proxy servers, automatically banning IP addresses attempting SSH password brute-force attacks.
- **Network Quality Grade (`mtproxymax net-grade`):** Benchmarks DNS ping timers and TCP reachability against Telegram Datacenters (DC1–DC5) to calculate an instant server quality grade (`A+`, `A`, `B`, `C/D`).
- **Smart User Onboarding Wizard (`mtproxymax onboard <label>`):** Step-by-step interactive command automating user creation, device tier assignment, monthly data quotas, expiry windows, and Telegram QR link generation.

---

### 🚀 Performance, Diagnostics & Self-Healing Suite

- **Linux Kernel TCP BBR & Fast Open Booster (`mtproxymax tcp-boost on`):** Activates Google's TCP BBR congestion control algorithm and TCP Fast Open (`tfo=3`), doubling transfer speeds and eliminating packet-loss bottlenecks on international routes.
- **Dead Mobile Socket Keep-Alive Reaper (`mtproxymax tcp-clean on`):** Configures aggressive low-latency kernel keep-alive timers (`keepalive_time=300`, `intvl=15`), automatically detecting and purging orphaned mobile 4G/LTE sockets within 45 seconds.
- **Ultra-Low Latency Kernel Socket Booster (`mtproxymax socket-boost on`):** Expands listen backlog queues (`somaxconn=65535`) and optimizes buffer limits (`notsent_lowat=16384`) to eliminate packet bloat and reduce TCP handshake delays under burst concurrency.
- **Dynamic FakeTLS Record Padding & Jitter (`mtproxymax tls-pad auto`):** Randomizes certificate payload lengths between 1500 and 3800 bytes dynamically during periodic maintenance cycles, evading AI/ML statistical packet size analysis.
- **Active Probe Honeypot & Decoy Protection (`mtproxymax honeypot on`):** Engages kernel redirection posture so active censorship crawler bots without a valid MTProto secret are cleanly routed to your decoy cover domain.
- **Subscription Leak & Account Sharing Scanner (`mtproxymax leak-scan 3`):** Scans active connection tables to identify and flag subscription keys connecting from more than 3 distinct IP subnets simultaneously.
- **TLS Cover Domain Health & Verifier (`mtproxymax cert-check <domain>`):** Performs a deep SSL/TLS inspection of your FakeTLS cover domain (`PROXY_DOMAIN`), verifying HTTP status codes, expiration dates, and issuer chains to prevent ISP blocking.
- **One-Line VPS Cloner & Replication Bundle (`mtproxymax clone-link` / `bootstrap`):** Compresses your upstreams, tuning profiles, ad-tag, and templates into a secure Base64 string and outputs a single one-line command (`mtproxymax bootstrap <base64>`) that mirrors your server onto any new node in 5 seconds.
- **Emergency RAM & Socket Auto-Healer (`mtproxymax heal` / `auto-heal on`):** Reclaims dead OS pagecache, prunes orphaned `TIME_WAIT` sockets, and expands Netfilter conntrack headroom (`nf_conntrack_max=262144`) with **zero disruption to active proxy users**.
- **TCP Fast-Path Window Scaling & MTU Probing (`mtproxymax tcp-fastpath on`):** Enables RFC-compliant TCP window scaling, Selective Acknowledgments (SACK), and automatic Path MTU discovery to maximize throughput on variable-MTU international links.
- **Dynamic RAM Auto-Tuning (`mtproxymax ram-tune auto`):** Inspects total server physical memory and auto-calculates safe TCP read/write buffer ceilings and kernel `min_free_kbytes` thresholds, preventing OOM crashes on small VPS while unlocking full throughput on large servers.
- **Multi-Core IRQ Packet Spreading (`mtproxymax cpu-tune on`):** Distributes incoming encrypted packet processing across all available CPU cores via Linux Receive Packet Steering (RPS/RFS), with automatic containerization fallback detection for LXC/OpenVZ environments.
- **TCP BBRv3 Congestion Control & ECN Auto-Tuning (`mtproxymax bbr on`):** Activates Google's TCP BBRv3 congestion control (`bbr`), Fair Queueing (`fq`), Explicit Congestion Notification (`tcp_ecn=1`), and 16MB buffer expansion with container-resilient sysctl persistence.
- **Anti-DPI Packet Padding & Fingerprint Scrubbing (`mtproxymax shield on`):** Randomizes TCP MSS clamping (`1360`) across FORWARD, OUTPUT, and POSTROUTING chains while scrubbing FakeTLS packet size distributions to defeat GFW, TSPU, and TIC DPI heuristics.
- **Reverse-Proxy Cover Shield & Active Probe Defense (`mtproxymax cover-shield on`):** Engages an active scanner trapdoor that seamlessly forwards non-MTProto HTTP GET requests and invalid TLS handshakes directly to a fallback website (e.g., `https://cloudflare.com`) without resetting the TCP socket.

---

### 🏢 Enterprise Commercial Suite (Vouchers, RBAC & Status Portal)

- **Commercial Voucher & Gift Code System (`mtproxymax voucher [create|list|revoke|redeem]`):** Monetize or distribute proxy access cleanly without requiring manual administrator intervention for each user.
  - Generates secure batch voucher codes formatted as `MTP-XXXX-XXXX` with customizable data quotas (e.g., `10G`, `50G`, `0` for unlimited) and validity durations (e.g., `30` days).
  - Vouchers are tracked in `${INSTALL_DIR}/vouchers.conf` with full audit metadata (`ACTIVE`, `REDEEMED`, `REVOKED`, creation timestamp, and redemption account label).
  - Users or resellers can redeem vouchers locally via `mtproxymax voucher redeem <code> [label]` or remotely via Telegram bot command `/redeem <code>`, instantly provisioning a dedicated proxy secret with exact quota and device ceilings enforced.
- **Role-Based Access Control (`mtproxymax admin [add|remove|list]`):** Multi-tier administrative access governance for your Telegram management bot.
  - Configures role hierarchies stored in `${INSTALL_DIR}/admins.conf`:
    - **`superadmin`**: Full access to all 21 administrative commands, including destructive engine restarts (`/mp_restart`), emergency lockdowns (`/mp_lockdown`), bot removals (`/mp_remove`), and self-updates (`/mp_update`).
    - **`reseller`**: Delegated commercial management rights restricted to voucher redemption (`/redeem`), voucher batch generation (`/mp_voucher create <cnt> <qta> <dys>`), and voucher inventory auditing (`/mp_voucher list`). Destructive engine commands are automatically blocked with security violation logging.
- **Decoupled Self-Service Status Portal (`mtproxymax portal [enable|disable|port|generate|serve|status]`):** Lightweight, zero-dependency static web dashboard designed for client self-service and transparent uptime reporting.
  - Generates an ultra-responsive, modern dark-mode glassmorphism HTML page (`index.html`) stored in `${INSTALL_DIR}/portal/`.
  - During periodic engine sweeps (`sweep()`), MTProxyMax automatically exports real-time system metrics (`status.json`) and anonymized user leaderboard statistics (`users.json`).
  - Clients can view live proxy uptime, server bandwidth consumption, active connection counts, and individual quota progress directly from any browser without exposing administrative interfaces or requiring backend script execution.
  - Can be served via built-in foreground test server (`mtproxymax portal serve`) or hosted instantly behind Nginx/HAProxy/Cloudflare Pages.

---

### 🛡️ Automated Hostile Threat Scanner Shield

- **Proactive Shodan & Censys Threat Blocking (`mtproxymax scanner-shield [enable|disable|update|status]`):** Protects your proxy server from automated Internet-wide discovery engines and hostile security scanners.
  - Initializes high-performance kernel memory hash sets (`ipset` table `mtproxymax-scanners`) with capacity for up to 65,536 network CIDRs.
  - Automatically imports and blacklists well-known hostile mass scanning subnets (including Shodan, Censys, and Shadowserver probe networks such as `162.142.125.0/24`, `167.94.138.0/24`, `71.6.135.0/24`, etc.).
  - Incoming packets from scanner IPs are silently dropped at the Netfilter kernel boundary before reaching the Docker proxy container or triggering SYN cookie thresholds, keeping your server completely invisible to threat discovery feeds.

---

### 🌐 High-Performance Networking & Security Suite

- **Lightweight Eco-Mode (`mtproxymax eco-mode [on|off|status]`):** Optimizes Linux kernel TCP memory allocations (`rmem_max`/`wmem_max` to `131072`), reducing RAM footprint by up to 45% for stable operation on 256MB/512MB micro-servers. Persistent watchdog re-enforces buffers during background sweeps.
- **Active Probe Decoy Routing (`mtproxymax decoy [set|clear|status]`):** Configures kernel redirection so unauthorized HTTP/TLS scanners lacking a valid MTProto secret are cleanly forwarded to a custom fallback URL or honeypot.
- **Country Geo-Fencing (`mtproxymax geofence [add|remove|list]`):** High-speed CIDR country-level firewall blocking or allowing specific nation-state subnets via automated Cloudflare/GeoIP feeds.
- **Network Resilience Chaos Engineering (`mtproxymax chaos-test [latency|packet-loss|disconnect]`):** Simulates high latency, packet loss, or abrupt socket drops using Linux `tc netem` to verify client reconnect resilience and failover behavior.
- **IP Reputation & Clean-Score Inspector (`mtproxymax ip-score [ip|self]`):** Checks server public IP against global blacklists (Spamhaus, AbuseIPDB, Russian/Iranian censorship blocks) to calculate an instant clean score.

---

### 👥 Advanced User & Quota Governance Suite

- **Shared Quota Pools (`mtproxymax pool [create|add|remove|list]`):** Group multiple member accounts under a single shared bandwidth ceiling (e.g. 100GB shared among a 5-person team). When the pool limit is reached, all member links are automatically paused without spamming alerts.
- **Dynamic Calendar Quota Scheduling (`mtproxymax calendar [weekend|holiday|status]`):** Provide unmetered free data passes on weekends or major holidays (with automatic +5GB Holiday Airdrop integration into traffic calculations).
- **Custom Expiry Action Policies (`mtproxymax expire-action [disable|delete|archive]`):** Define automated lifecycle policies for expired accounts — choose between temporary disablement, soft-deletion to archive, or permanent purging.
- **Real-Time Interactive Leaderboard (`mtproxymax top-users [traffic|conns|speed]`):** Live ASCII ranking display identifying top bandwidth consumers, most active concurrent connections, and highest real-time transfer rates.
- **Automated High-Velocity Traffic Alerts (`mtproxymax traffic-alert [set|clear|status]`):** Monitors rolling transfer speeds and dispatches instant warnings when a single account exceeds configurable burst thresholds (e.g. >10GB/hour).

---

### 🚀 Enterprise DevOps & Multi-Server Automation Suite

- **1-Click Emergency Server Evacuation (`mtproxymax evacuate [ip|bundle]`):** Instantly packs all secrets, pools, and configuration files into an encrypted portable archive and transfers it via SSH/rsync to a standby backup server in under 5 seconds.
- **Multi-Channel Enterprise Webhook Dispatcher (`mtproxymax webhook [add|remove|list|test]`):** Sends RFC-compliant, markdown-stripped, escaped JSON event notifications to Discord, Slack, Mattermost, or DingTalk when lockdowns, failovers, or quota breaches occur.
- **Printable QR Code Onboarding Sheets (`mtproxymax qr-sheet [export|pdf]`):** Generates a styled, printable HTML/PDF catalog of user QR codes and connection instructions for physical distribution or corporate onboarding.
- **Executive Monthly Audit Reports (`mtproxymax export-report [csv|html|json]`):** Produces comprehensive compliance and billing reports summarizing monthly bandwidth usage, active users, and system uptime.
- **Telegram Datacenter Route Optimizer (`mtproxymax dc-optimize [dc1-dc5|auto]`):** Actively probes TCP handshake timers to Telegram DCs (DC1–DC5) and tunes kernel routing tables and MSS clamping for optimal regional routing.

---

### 🩺 Diagnostic, Resiliency & TUI Dashboard Suite

- **Interactive Live Telemetry Dashboard (`mtproxymax live-diag`):** Real-time ASCII dashboard displaying rolling traffic graphs, CPU/RAM usage, active connection counts, and SYN shield tarpit interceptions.
- **Autonomous SNI Cover Domain Hunter (`mtproxymax auto-sni [on|off|status]`):** Automatically scans and benchmarks high-reputation TLS cover domains in your region to replace blocked SNIs without human intervention.
- **Autonomous Upstream Failover Watchdog (`mtproxymax failover [on|off|status]`):** Monitors upstream proxy health every minute and automatically switches upstreams or rotates backend IPs after 3 consecutive ping failures.
- **TLS Certificate Fingerprint Randomizer (`mtproxymax cert-shield [on|off|status]`):** Dynamically mutates TLS extension ordering, ALPN banners, and record padding intervals every 12 hours to evade statistical AI/ML packet inspection.
- **Customizable TUI Color Themes (`mtproxymax tui-theme [dark|matrix|cyan|classic]`):** Choose your preferred ASCII interface aesthetic — Cyberpunk Matrix Green, Electric Cyan, Dark Mode, or Classic Retro.

---

### 🚨 Censorship Emergency Playbook (When ISPs Block Your Proxy)

If users report sudden connection drops or severe DPI throttling during internet disruptions, execute this 3-step recovery posture:

1. **Engage Instant Lockdown & Check Posture Score:**
   ```bash
   mtproxymax lockdown on
   mtproxymax dpi-inspect
   ```
2. **Add Backup Cover Domains & Fallback Ports:**
   ```bash
   mtproxymax domain-pool add www.microsoft.com,www.google.com
   mtproxymax port-pool add 8443
   ```
3. **Activate Automated Watchdog & Bandwidth Shaping:**
   ```bash
   mtproxymax cover-watchdog auto
   mtproxymax qos set 5
   ```

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

### 🤖 Telegram Bot (21 Commands)

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
| `/mp_revoke <label>` | Revoke and purge a user secret immediately |
| `/mp_rotate <label>` | Generate new key for user |
| `/mp_enable <label>` | Re-enable disabled user |
| `/mp_disable <label>` | Temporarily disable user |
| `/mp_lockdown [on\|off]` | Toggle emergency panic lockdown defensive posture |
| `/mp_digest` | View live executive health, posture, and traffic digest box |
| `/mp_limits` | Show all user limits |
| `/mp_setlimit` | Set user limits |
| `/mp_traffic` | Per-user traffic breakdown |
| `/mp_upstreams` | List proxy chains |
| `/mp_health` | Run diagnostics |
| `/mp_restart` | Restart proxy |
| `/mp_update` | Check for updates |
| `/mp_help` | Show all commands |

**Automatic alerts & announcements:**
- 🚨 Emergency Lockdown activated → immediate posture alert
- 📢 System Broadcasts (`mtproxymax broadcast <msg>`) sent directly to admin chat
- ⏰ Proactive Expiry Alerts sent 7d, 3d, and 24h prior to account expiration
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
mtproxymax secret purge-disabled            # Permanently purge disabled/expired secrets
mtproxymax secret sub                       # Generate Base64 subscription link feed
mtproxymax secret export-json               # Export user database formatted as JSON
mtproxymax secret rename-prefix <old> <new> # Bulk rename labels matching prefix
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

**`digest`** displays an executive summary dashboard of uptime, sockets, traffic totals, and bot status:

```bash
mtproxymax digest
```

**`ping-dc`** benchmarks TCP handshake latency to global Telegram datacenters (DC1–DC5):

```bash
mtproxymax ping-dc
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

| Feature | **MTProxyMax v1.3** | **mtg v2** (Go) | **Official MTProxy** (C) | **Bash Installers** |
|---------|:-:|:-:|:-:|:-:|
| **Engine** | telemt 3.x (Rust) | mtg (Go) | MTProxy (C) | Various |
| **Shared Quota Pools (`pool`)** | ✅ | ❌ | ❌ | ❌ |
| **Weekend/Holiday Data Passes (`calendar`)** | ✅ | ❌ | ❌ | ❌ |
| **Autonomous Upstream Failover Watchdog** | ✅ (3x ping check) | ❌ | ❌ | ❌ |
| **Autonomous SNI Cover Hunter (`auto-sni`)** | ✅ | ❌ | ❌ | ❌ |
| **1-Click Emergency Evacuation (`evacuate`)** | ✅ (<5s bundle) | ❌ | ❌ | ❌ |
| **Multi-Channel JSON Webhooks** | ✅ (Discord/Slack/etc.) | ❌ | ❌ | ❌ |
| **Interactive Live Dashboard (`live-diag`)** | ✅ | ❌ | ❌ | ❌ |
| **Network Chaos Engineering (`chaos-test`)** | ✅ (Linux `tc netem`) | ❌ | ❌ | ❌ |
| **IP Reputation Clean-Score Inspector** | ✅ | ❌ | ❌ | ❌ |
| **FakeTLS V2** | ✅ | ✅ | ❌ (needs patches) | Varies |
| **Active DPI Forensics (`dpi-inspect`)** | ✅ (Score /100) | ❌ | ❌ | ❌ |
| **Self-Healing Cover Watchdog** | ✅ | ❌ | ❌ | ❌ |
| **Emergency Lockdown Switch** | ✅ | ❌ | ❌ | ❌ |
| **Kernel SYN Shield (Tarpit)** | ✅ (>15 SYN/5s) | ❌ | ❌ | ❌ |
| **Per-IP Bandwidth Shaping (QoS)** | ✅ (Linux `tc`) | ❌ | ❌ | ❌ |
| **Off-Peak Happy Hours** | ✅ | ❌ | ❌ | ❌ |
| **Multi-Port Pool Listeners** | ✅ (Kernel NAT) | ❌ | Multi-process | Varies |
| **Multi-Domain SNI Pools** | ✅ | ❌ | ❌ | ❌ |
| **TCP MSS Clamping** | ✅ | ❌ | ❌ | ❌ |
| **Layer-4 LB Exporter (HAProxy/Nginx)** | ✅ | ❌ | ❌ | ❌ |
| **Cloudflare Dynamic DNS (DDNS)** | ✅ | ❌ | ❌ | ❌ |
| **Configuration Snapshots** | ✅ | ❌ | ❌ | ❌ |
| **Traffic Masking** | ✅ | ✅ | ❌ | ❌ |
| **Multi-User Secrets** | ✅ (unlimited) | ❌ (1 secret) | Multi-secret | Usually 1 |
| **Per-User Limits** | ✅ (conns, IPs, quota, expiry) | ❌ | ❌ | ❌ |
| **Per-User Traffic Stats** | ✅ (Prometheus) | ❌ | ❌ | ❌ |
| **Telegram Bot** | ✅ (21 commands) | ❌ | ❌ | ❌ |
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
mtproxymax digest               # Executive summary report
mtproxymax ping-dc              # Telegram DC latency benchmark
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
mtproxymax secret sub                   # Base64 subscription link feed
mtproxymax secret export-json           # Export users as clean JSON
mtproxymax secret purge-disabled        # Permanently purge disabled/expired
mtproxymax secret rename-prefix <o> <n> # Bulk rename matching prefix
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
mtproxymax telegram interval <hours>    # Change report interval (1-168h)
mtproxymax telegram label <name>        # Change server label in notifications
mtproxymax telegram alerts <on|off>     # Enable/disable down/recovery alerts
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
<summary><b>Enterprise Commercial & Shield Suite</b></summary>

```bash
mtproxymax voucher create <cnt> <qta> <dys> # Generate batch voucher codes
mtproxymax voucher list [active|all]        # List vouchers and redemption status
mtproxymax voucher revoke <code>            # Revoke a voucher code
mtproxymax voucher redeem <code> [label]    # Redeem voucher code locally
mtproxymax admin add <chat_id> <role>       # Add role-based Telegram admin (superadmin/reseller)
mtproxymax admin remove <chat_id>           # Remove role-based Telegram admin
mtproxymax admin list                       # List configured Telegram admins
mtproxymax portal [enable|disable|status]   # Manage Self-Service HTML Status Portal
mtproxymax scanner-shield [enable|disable]  # Manage Automated Shodan/Censys Threat Shield
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
<summary><b>Next-Gen Anti-DPI, QoS & DevOps Suite</b></summary>

**Anti-DPI & Posture Hardening:**
```bash
mtproxymax shield [on|off|status]       # Toggle Anti-DPI Packet Padding & SYN Shield
mtproxymax cover-shield [on|off|target] # Toggle Reverse-Proxy Cover Shield (Active Probe Defense)
mtproxymax bbr [on|off|status]          # Toggle TCP BBRv3 Congestion Control & ECN tuning
mtproxymax stealth [ultra|normal|status] # Hot-swap engine replay window and cache size
mtproxymax clamp-mss [on|off|status]    # Align TCP MSS to PMTU preventing packet drops
mtproxymax domain-pool [add|remove|list] # Manage multi-domain SNI rotation pool
mtproxymax port-pool [add|remove|list]  # Listen on multi-port fallback pool via kernel NAT
mtproxymax lockdown [on|off|status]     # Engage emergency panic defense posture
```

**Forensics & Watchdogs:**
```bash
mtproxymax dpi-inspect                  # Run active 5-point Anti-DPI readiness scan (/100 score)
mtproxymax cover-watchdog [test|auto]   # Probe cover domain pool & auto-rotate on censorship
mtproxymax abuse-watch                  # Scan users for abnormal bandwidth spikes (>50GB/day)
```

**Bandwidth Shaping & Quotas:**
```bash
mtproxymax qos [set <mbps>|off|status]  # Linux tc token bucket per-IP bandwidth limiter
mtproxymax happy-hours [set <win>|off]  # Define off-peak unmetered traffic windows
mtproxymax notify-expiry                # Trigger proactive Telegram reminders (7d, 3d, 24h)
mtproxymax broadcast <message>          # Send system announcement via Telegram bot
```

**DevOps & Clustering Automation:**
```bash
mtproxymax export-lb [haproxy|nginx]    # Generate Layer-4 TCP load balancer config snippets
mtproxymax ddns [set|run|status|off]    # Manage Cloudflare Dynamic DNS public IP updater
mtproxymax diag-dump                    # Create full forensic diagnostic bundle (.tar.gz)
mtproxymax snapshot [create|restore|list] # Manage point-in-time configuration tarballs
```

**Operations, Briefings & Onboarding Suite:**
```bash
mtproxymax backup send-tg [file]        # Push backup archive directly to Telegram bot chat
mtproxymax daily-report [on|off|run]    # Schedule automated morning executive briefing
mtproxymax ssh-shield [on|off|status]   # Enable fail2ban SSH brute-force intrusion shield
mtproxymax net-grade                    # Benchmark international routing & calculate A+/A/B/C grade
mtproxymax onboard [label]              # Interactive step-by-step user onboarding wizard
```

**Performance, Diagnostics & Self-Healing Suite:**
```bash
mtproxymax tcp-boost [on|off|status]    # Activate Linux Kernel TCP BBR & Fast Open booster
mtproxymax tcp-clean [on|off|status]    # Activate aggressive keep-alive dead mobile socket reaper
mtproxymax socket-boost [on|off]        # Apply ultra-low latency kernel socket queue expansion
mtproxymax tls-pad [auto|off|rotate]    # Dynamic FakeTLS certificate length jitter & randomization
mtproxymax honeypot [on|off|status]     # Enable active probe decoy redirection & protection
mtproxymax leak-scan [thresh]           # Detect multi-IP subscription sharing anomalies
mtproxymax cert-check [domain]          # Inspect cover domain SSL/TLS certificate health
mtproxymax clone-link                   # Export one-line Base64 server replication bundle
mtproxymax bootstrap <base64>           # Deploy cloned config bundle on a fresh node
mtproxymax heal                         # Run emergency RAM & dead socket cleanup immediately
mtproxymax auto-heal [on|off|status]    # Enable background automated RAM/socket self-healer
mtproxymax tcp-fastpath [on|off]        # TCP window scaling, SACK & path MTU probing optimizer
mtproxymax ram-tune [auto|off]          # Auto-detect RAM & apply optimal TCP memory buffers
mtproxymax port-hop [add|remove|list]   # Dynamic multi-port NAT range redirection
mtproxymax cpu-tune [on|off|status]     # Multi-core IRQ packet spreading (RPS/RFS)
mtproxymax eco-mode [on|off|status]     # Lightweight RAM & TCP kernel tuning for micro-servers
mtproxymax decoy [set|clear|status]     # Active probe decoy routing to fallback URL/honeypot
mtproxymax geofence [add|remove|list]   # Country-level CIDR firewall blocking/allowing
mtproxymax chaos-test [action]          # Simulate latency/loss/disconnects for resilience testing
mtproxymax ip-score [ip|self]           # Check proxy IP against global blacklists & censorship feeds
mtproxymax pool [create|add|remove|list]# Shared Quota Pools for teams & organizations
mtproxymax calendar [action]            # Weekend & holiday unmetered free data passes
mtproxymax expire-action [action]       # Custom expiry policies (disable, delete, archive)
mtproxymax top-users [metric]           # Live interactive leaderboard ranking users
mtproxymax traffic-alert [action]       # Automated high-velocity burst anomaly alerts
mtproxymax evacuate [ip|bundle]         # 1-Click emergency server migration & data bundle
mtproxymax webhook [add|remove|list]    # Multi-channel JSON alerts for Discord/Slack/DingTalk
mtproxymax qr-sheet [export|pdf]        # Printable QR code onboarding sheet generator
mtproxymax export-report [format]       # Executive monthly audit & billing report generator
mtproxymax dc-optimize [dc|auto]        # Telegram Datacenter route & latency optimizer
mtproxymax live-diag                    # Interactive real-time ASCII telemetry dashboard
mtproxymax auto-sni [on|off|status]     # Autonomous SNI cover domain hunter & benchmark
mtproxymax failover [on|off|status]     # Autonomous upstream failover & DNS health watchdog
mtproxymax cert-shield [on|off|status]  # TLS certificate fingerprint randomizer
mtproxymax tui-theme [theme]            # Switch TUI color themes (dark, matrix, cyan, classic)
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
| `/opt/mtproxymax/pools.conf` | Shared Quota Pools definitions and membership tracking |
| `/opt/mtproxymax/calendar.conf` | Weekend and holiday dynamic scheduling rules |
| `/opt/mtproxymax/webhooks.conf` | Multi-channel webhook endpoint URLs |
| `/opt/mtproxymax/geofence.conf` | Country-level geo-fencing rules and CIDR cache |
| `/opt/mtproxymax/decoy.conf` | Active probe decoy routing and honeypot fallback targets |
| `/opt/mtproxymax/failover.conf` | Autonomous upstream failover status and check policies |
| `/opt/mtproxymax/eco_mode.conf` | Lightweight memory conservation mode status |
| `/opt/mtproxymax/backups/` | Automatic backups (auto-cleaned via `BACKUP_RETENTION_DAYS`) |

---

## 📋 Changelog

### v1.3.1 — The Performance & Anti-DPI Upgrade Suite (Forensically Audited)

- **Performance & Network Acceleration:** Added **TCP BBRv3 & ECN Auto-Tuning (`bbr` / `tune-net`)** with container-resilient sysctl persistence, Fair Queueing (`fq`), Explicit Congestion Notification (`tcp_ecn=1`), and 16MB TCP buffer expansion.
- **Anti-DPI & Fingerprint Scrubbing:** Added **Anti-DPI Packet Padding Shield (`shield` / `anti-dpi`)** with kernel MSS clamping variations (`1360`) and FakeTLS packet size randomization to defeat TSPU/GFW heuristic analysis.
- **Active Probe Defense:** Added **Reverse-Proxy Cover Shield (`cover-shield` / `fallback`)** that forwards unauthorized HTTP GET requests and invalid TLS handshakes directly to a fallback website (e.g., `https://cloudflare.com`) without resetting the TCP socket.
- **Hardening & Verification:** Line-by-line forensic audit guaranteeing input sanitization, dynamic telemt engine masking integration, and zero bash syntax errors across 16,979 lines.

### v1.3.0 — The Mega-Release (20 Enterprise Features Across 4 Suites)

- **Networking & Security:** Added **Eco-Mode (`eco-mode`)** for micro-servers, **Decoy Routing (`decoy`)**, **Country Geo-Fencing (`geofence`)**, **Chaos Testing (`chaos-test`)**, and **IP Score Inspector (`ip-score`)**.
- **User Governance:** Added **Shared Quota Pools (`pool`)**, **Calendar Scheduling (`calendar`)**, **Expiry Action Policies (`expire-action`)**, **Interactive Leaderboard (`top-users`)**, and **Traffic Burst Alerts (`traffic-alert`)**.
- **DevOps & Automation:** Added **1-Click Emergency Evacuation (`evacuate`)**, **Multi-Channel Webhooks (`webhook`)**, **Printable QR Sheets (`qr-sheet`)**, **Monthly Audit Reports (`export-report`)**, and **DC Route Optimizer (`dc-optimize`)**.
- **Diagnostics & TUI:** Added **Live Telemetry Dashboard (`live-diag`)**, **Autonomous SNI Hunter (`auto-sni`)**, **Upstream Failover Watchdog (`failover`)**, **TLS Cert Randomizer (`cert-shield`)**, and **TUI Themes (`tui-theme`)**.
- **Hardening:** Deep 4-round POSIX architectural audit guaranteeing atomic file renaming, O(1) CPU efficiency, and zero race conditions.

### v1.2.0 — Enterprise Commercial & Shield Suite, Next-Gen Anti-DPI, QoS Bandwidth Shaping & DevOps Clustering Suite

- **Commercial Suite:** Added **Voucher & Gift Code System (`voucher`)**, **Role-Based Access Control (`admin`)** for Telegram bot tiers, and **Static Status Portal (`portal`)**.
- **Threat & Anti-DPI Defenses:** Added **Kernel Scanner Shield (`scanner-shield`)**, **Active DPI Forensics (`dpi-inspect`)**, **Cover Watchdog (`cover-watchdog`)**, **Emergency Lockdown (`lockdown`)**, and **Multi-Port Listeners (`port-pool`)**.
- **QoS & Operations:** Added **Linux Kernel QoS Shaping (`qos`)**, **Happy Hours Quota Exclusions (`happy-hours`)**, **21 Telegram Bot Commands**, and **Telegram Cloud Backups (`backup send-tg`)**.
- **DevOps & Self-Healing:** Added **HAProxy/Nginx Exporter (`export-lb`)**, **Cloudflare DDNS (`ddns`)**, **Config Snapshots (`snapshot`)**, **TCP BBR Booster (`tcp-boost`)**, **Socket Reaper (`tcp-clean`)**, **Socket Booster (`socket-boost`)**, **TLS Padding (`tls-pad`)**, **RAM Auto-Tuning (`ram-tune`)**, and **1-Line Server Cloner (`clone-link`)**.

### v1.1.0 — Anti-DPI & Stealth Defenses Expansion

- **Kernel SYN Shield (`shield`):** Built-in rate limiter tarpitting aggressive probes (>15 SYN/5s per IP).
- **Stealth Presets (`stealth`):** Hot-swappable anti-replay hardening (`normal` vs `ultra`).
- **TCP MSS Clamping (`clamp-mss`):** Prevents MTU black hole drops and packet fragmentation.
- **Multi-Domain SNI Pool (`domain-pool`):** Rotate between multiple cover domains within the same instance.
- **Auto Cert Synchronization (`sync_domain_cert_len`):** Dynamically synchronizes `fake_cert_len` every 24h.

### v1.0.10 — Executive Digest, DC Benchmarking & Base64 Subscriptions

- Added **Executive Digest (`digest`)** dashboard, **Datacenter Benchmark (`ping-dc`)** against Telegram DC1-DC5, **Base64 Subscriptions (`secret sub`)**, **JSON Database Export (`secret export-json`)**, and bulk cleanup tools (`purge-disabled`, `rename-prefix`).

### v1.0.9 — Engine v3.4.18, TLS Stealth & ME/MR Hardening

- Upgraded telemt engine to v3.4.18 (TLS profile spoofing, async ME/MR queue backpressure), added user quota rate limit API, and improved Docker tmpfs caching.

### v1.0.8 — Security Hardening & Persistent Quotas

- Upgraded engine to v3.4.11, added persistent per-user quota tracking (`quota_state_path`), runtime quota reset API, and customizable Telegram bot alert toggles.

### v1.0.7 — Tags, Templates, Migration, Maintenance & IP Banlist

- Added secret tagging (`secret tag/untag`), reusable limit templates (`template`), tarball migration (`migrate`), graceful maintenance mode (`maintenance`), persistent iptables IP banlist (`ban/unban`), AES-256 backups, and engine tuning (`tune`).

### v1.0.6 — Profiles, Archive, Search & Info

- Added user detail inspection (`info`), search (`search`), top rankings, soft-delete archiving, named config profiles (`profile`), port reachability tester (`port-check`), and custom mask routing (`mask-backend`).

### v1.0.5 — Engine v3.4.8, Clone, Bulk-Extend & Doctor

- Upgraded engine to v3.4.8, added user duplication (`clone`), expiry extension (`extend`), active connections view, comprehensive diagnostics (`doctor`), and long-polling bot response.

### v1.0.4 — Master-Slave Replication & Metrics Dashboard

- Added master/slave configuration replication (`replication setup`) via rsync+SSH, upgraded engine to v3.3.39, introduced live Prometheus metrics console (`metrics live`), and SNI handling policies (`sni-policy`).

### v1.0.3 — Quota Enforcement, Multi-Port & Hot-Reload

- Added multi-port listener support, secret hot-reloading, quota auto-disable at 100% consumption, JSON monitoring outputs, connection logs, and country geo-blocking whitelist.

### v1.0.2 — Persistent Traffic Accounting

- Added atomic traffic counter persistence surviving restarts and server reboots with batched stats loading.

### v1.0.1 — Batch User Operations

- Added multi-user batch creation and removal (`secret add-batch`, `secret remove-batch`).

### v1.0.0 — Initial Release

- Initial launch of MTProxyMax with telemt 3.x Rust engine, interactive TUI, CLI, FakeTLS, Telegram bot, and geo-blocking.

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
