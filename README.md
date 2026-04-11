> ## ⚠️ Custom Fork Notice
>
> **This is a modified fork of [SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax) with extended secret-key management.**
>
> Unlike the upstream version, this fork lets you:
>
> - 🔑 **Set a custom secret during installation** — pass your own 32-char hex key via `MTPROXY_SECRET` when running the one-line installer, instead of relying on auto-generation.
> - ✏️ **Change the secret of any existing user profile at any time** — a new `secret setkey` command (and a **[9] Change secret key** entry in the Secret Management TUI) replaces the raw key for an existing label without touching its traffic counters, limits, notes, or expiry. Unlike `secret rotate` (always random), `setkey` lets you paste a specific key.
> - 🛠 **Pre-seed other install options non-interactively** — `MTPROXY_LABEL`, `MTPROXY_PORT`, and `MTPROXY_DOMAIN` environment variables are now honoured by `install.sh`, so you can fully script a `curl | sudo bash` install with zero prompts.
>
> ### Quick examples
>
> **Install with a custom secret in one line:**
>
> ```bash
> curl -sL https://raw.githubusercontent.com/nellimonix/MTProxyMax/main/install.sh \
>   | sudo MTPROXY_SECRET=000102030405060708090a0b0c0d0e0f \
>          MTPROXY_LABEL=alice \
>          MTPROXY_PORT=443 \
>          MTPROXY_DOMAIN=cloudflare.com bash
> ```
>
> The installer strips `ee`/`dd` prefixes and any trailing domain hex automatically, so you can also paste a full FakeTLS-formatted secret.
>
> **Change an existing profile's secret:**
>
> ```bash
> sudo mtproxymax secret setkey alice 11223344556677889900aabbccddeeff   # your own key
> sudo mtproxymax secret setkey alice                                    # auto-generate
> ```
>
> Or open `sudo mtproxymax` → **[2] Secret Management** → **[9] Change secret key**.
>
> `setkey` hot-reloads the engine via `SIGHUP`, so connected clients are not dropped. It refuses duplicate keys and rejects anything that isn't exactly 32 hex characters. If Telegram notifications are enabled, the bot sends you the new proxy link and QR automatically.
>
> Everything else — FakeTLS, multi-user secrets, per-user limits, Telegram bot, replication, proxy chaining, geo-blocking, metrics, auto-recovery — behaves exactly as documented below.

---

<p align="center">
  <h1 align="center">MTProxyMax</h1>
  <p align="center"><b>The Ultimate Telegram MTProto Proxy Manager</b></p>
  <p align="center">One script. Full control. Zero hassle.</p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-1.0.5-brightgreen" alt="Version"/>
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="License"/>
    <img src="https://img.shields.io/badge/engine-Rust_(telemt_3.x)-orange" alt="Engine"/>
    <img src="https://img.shields.io/badge/platform-Linux-lightgrey" alt="Platform"/>
    <img src="https://img.shields.io/badge/bash-4.2+-yellow" alt="Bash"/>
    <img src="https://img.shields.io/badge/docker-multi--arch-blue" alt="Docker"/>
  </p>
</p>

---

MTProxyMax is a full-featured Telegram MTProto proxy manager powered by the **telemt 3.x Rust engine**. It wraps the raw proxy engine with an interactive TUI, a complete CLI, a Telegram bot for remote management, per-user access control, traffic monitoring, proxy chaining, and automatic updates — all in a single bash script.

<img src="main.png" width="600" alt="MTProxyMax Main Menu"/>

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nellimonix/MTProxyMax/main/install.sh)"
```

---

## 🚀 Quick Start

### One-Line Install (auto-generated secret)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nellimonix/MTProxyMax/main/install.sh)"
```

### One-Line Install (custom secret — this fork only)

```bash
curl -sL https://raw.githubusercontent.com/nellimonix/MTProxyMax/main/install.sh \
  | sudo MTPROXY_SECRET=000102030405060708090a0b0c0d0e0f MTPROXY_LABEL=alice bash
```

### After Install

```bash
mtproxymax                        # Open interactive TUI
mtproxymax status                 # Check proxy health
mtproxymax secret setkey alice    # Replace key (this fork only)
```

---

## ✨ Features

- 🔐 **Multi-user secrets** with individual bandwidth quotas, device limits, and expiry dates
- 🔑 **Custom secret keys** — set your own at install time or replace an existing one (this fork)
- 🛡️ **FakeTLS V2** — mirrors real TLS 1.3, indistinguishable from HTTPS to DPI
- 🤖 **Telegram bot** with 17 commands
- 🗂️ **Master-slave replication** via rsync+SSH
- 🖥️ **Interactive TUI** and complete CLI
- 📊 **Prometheus per-user traffic stats**
- 🔗 **Proxy chaining** (SOCKS5/4 with weighted load balancing)
- 🌍 **Geo-blocking** (IP-level CIDR blocklists)
- 💰 **Ad-tag monetization**
- 🔄 **Auto-recovery with Telegram alerts**
- 🐳 **Pre-built multi-arch Docker images**

For the full list of limits, recipes, FakeTLS details, replication architecture, and per-command documentation, see the relevant sections in the upstream README — everything applies to this fork unchanged.

---

## 🔧 Install-Time Environment Variables (This Fork)

Any variable you set is applied non-interactively; anything left unset falls back to the normal interactive wizard.

| Variable | Purpose | Example |
|----------|---------|---------|
| `MTPROXY_SECRET` | 32-char hex secret for the first profile. Accepts `ee`/`dd`-prefixed FakeTLS secrets too — prefix and domain hex are stripped automatically. | `000102030405060708090a0b0c0d0e0f` |
| `MTPROXY_LABEL`  | Label for the first profile | `alice` |
| `MTPROXY_PORT`   | Proxy port (1–65535) | `443` |
| `MTPROXY_DOMAIN` | FakeTLS cover domain | `cloudflare.com` |

---

## 📖 New Commands in This Fork

### `secret setkey <label> [hex]`

Replace the raw secret key of an existing profile without losing any of its state (traffic counters, limits, notes, expiry).

```bash
# Set a specific key
sudo mtproxymax secret setkey alice 11223344556677889900aabbccddeeff

# Auto-generate a new random key
sudo mtproxymax secret setkey alice

# Paste a full FakeTLS secret — prefix and domain hex are stripped automatically
sudo mtproxymax secret setkey alice ee11223344556677889900aabbccddeeff636c6f7564666c6172652e636f6d
```

**Difference from `secret rotate`:** `rotate` always generates a random key. `setkey` lets you paste a specific key of your choice.

Also accessible via TUI: `sudo mtproxymax` → **[2] Secret Management** → **[9] Change secret key**.

---

## 📖 CLI Reference

### User Secrets

```bash
mtproxymax secret add <label>           # Add user (random key)
mtproxymax secret remove <label>        # Remove user
mtproxymax secret list                  # List all users
mtproxymax secret rotate <label>        # New random key, same label
mtproxymax secret setkey <label> [hex]  # Replace with a specific key (this fork)
mtproxymax secret enable <label>        # Re-enable user
mtproxymax secret disable <label>       # Temporarily disable
mtproxymax secret link [label]          # Show proxy link
mtproxymax secret qr [label]            # Show QR code
mtproxymax secret setlimit <label> <type> <value>
mtproxymax secret setlimits <label> <conns> <ips> <quota> [expires]
mtproxymax secret reset-traffic <label|all>
```

For the full CLI reference (proxy management, replication, upstreams, geoblock, metrics, engine, Telegram bot), see the upstream documentation — all commands work identically in this fork.

---

## 📋 Changelog

### Fork changes (nellimonix)

- `MTPROXY_SECRET`, `MTPROXY_LABEL`, `MTPROXY_PORT`, `MTPROXY_DOMAIN` env vars for fully non-interactive `curl | sudo bash` installs
- `secret setkey <label> [hex]` — replace an existing profile's key with one you provide (or auto-generate) without losing traffic counters, limits, notes, or expiry
- New TUI entry **[9] Change secret key** under Secret Management
- Hot-reload on key change via `SIGHUP` (no dropped connections); duplicate-key detection; `ee`/`dd`-prefix and domain-hex auto-stripping

### v1.0.5 — Clone, Bulk-Extend, Doctor, Stats & More

- `secret clone <src> <new>` — duplicate a secret with all its limits
- `secret bulk-extend <days>` — extend all secrets' expiry at once
- `secret extend <label> <days>` — extend a single secret's expiry
- `secret rename`, `secret export/import`, `secret disable-expired`, `secret sort`, `secret stats`
- `connections` — live active connections per user
- `doctor` — comprehensive diagnostics (port, TLS, secrets, disk, Telegram bot)
- Auto-rotate secrets on domain change, startup warnings for expired/near-expiry secrets
- QR code shown inline after `secret add` (if qrencode installed)
- Fedora 41+ Docker install fix (dnf5 `--addrepo`, Fedora repo URL)

### v1.0.4 — Replication, Engine v3.3.39, Metrics Dashboard

- Replication — master/slave sync via rsync+SSH with wizard, promote, and role guards
- Engine v3.3.39 — Apple/XNU fixes, ME rewrite, conntrack control, TLS fronting fix, memory hard-bounds, bounded retries
- Engine metrics dashboard — `mtproxymax metrics` / `mtproxymax metrics live`
- Unknown SNI policy — configurable `mask` or `drop`
- Reset traffic counters — `mtproxymax secret reset-traffic <label|all>`

### v1.0.3 — Quota Enforcement, Multi-Port, Hot-Reload
### v1.0.2 — Persistent Traffic
### v1.0.1 — Batch Secrets
### v1.0.0 — Initial Release

---

## 🙏 Credits

Built on top of **telemt** — a high-performance MTProto proxy engine written in Rust/Tokio.

Upstream project: [SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax) — all credit for the original work goes to SamNet Technologies. This fork only adds custom-secret management on top.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details. Copyright (c) 2026 SamNet Technologies. Fork modifications contributed under the same license.
