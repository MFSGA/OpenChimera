# Migration Guide: Nikki to OpenChimera

> **Target audience**: Users migrating from [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) (OpenWrt + Mihomo) to OpenChimera (OpenWrt + Chimera_Client / clash-rs).
>
> **Milestone 1**: x86_64 only. CLI-only. No LuCI, no TProxy/Redirect, no subscription scheduler.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Package Architecture](#2-package-architecture)
3. [UCI Schema Mapping](#3-uci-schema-mapping)
4. [Binary Path Changes](#4-binary-path-changes)
5. [Config Format Differences](#5-config-format-differences)
6. [TUN Configuration](#6-tun-configuration)
7. [Removed Features in Milestone 1](#7-removed-features-in-milestone-1)
8. [Migration Steps](#8-migration-steps)
9. [Profile / Config Migration](#9-profile--config-migration)
10. [Troubleshooting](#10-troubleshooting)
11. [Reference](#11-reference)

---

## 1. Overview

Nikki is an OpenWrt integration for **Mihomo** (a Go-based Clash fork with many
extensions). OpenChimera is an OpenWrt integration for **Chimera_Client** (a
Rust-based clash-rs core).

The two cores are **not interchangeable**. Chimera_Client implements a subset of
the Clash-compatible config format. Fields that are Mihomo-specific
(`auto-redirect`, `auto-detect-interface`, `disable-icmp-forwarding`, etc.) will
cause validation errors in Chimera.

### Key differences at a glance

| Area | Nikki | OpenChimera |
|------|-------|-------------|
| Core binary | Mihomo (Go) | Chimera_Client / clash-rs (Rust) |
| Binary path | `/usr/bin/mihomo` (direct) | `/usr/bin/mihomo` (alternatives-managed symlink) |
| Actual binary location | `/usr/bin/mihomo` | `/usr/libexec/chimera` |
| UCI config file | `/etc/config/nikki` | `/etc/config/openchimera` |
| Service name | `nikki` | `openchimera` |
| Init script | `/etc/init.d/nikki` | `/etc/init.d/openchimera` |
| Config generator | nikki-mixin (ucode) | openchimera-config-gen (shell) |
| Hot reload | SIGHUP supported | Restart only |
| LuCI | `luci-app-nikki` included | None (milestone 1) |
| Transparent proxy | TUN + TProxy + Redirect | TUN only (milestone 1) |
| Subscription management | Built-in | None (milestone 1) |
| DNS config via UCI | Full DNS schema | None (configure in profile YAML) |
| Access control | Router + LAN ACLs | None (milestone 1) |

---

## 2. Package Architecture

### Nikki

```
nikki (single package)
  ├── Provides: mihomo
  ├── /usr/bin/mihomo         (core binary)
  ├── /etc/config/nikki       (UCI config)
  ├── /etc/init.d/nikki       (init script)
  └── /usr/libexec/nikki/     (helper scripts, ucode templates)
```

### OpenChimera

```
chimera-core (binary provider)
  ├── Provides: mihomo
  ├── Alternatives: /usr/bin/mihomo → /usr/libexec/chimera (priority 300)
  ├── Conflicts: mihomo-meta, mihomo-alpha
  └── /usr/libexec/chimera    (actual binary)

openchimera (management layer)
  ├── Depends: mihomo (virtual provider from chimera-core)
  ├── /etc/config/openchimera (UCI config)
  ├── /etc/init.d/openchimera (init script)
  ├── /usr/bin/openchimera-config-gen (config generator)
  └── /etc/openchimera/run/   (runtime directory)
```

**What this means for migration**: Nikki bundles everything in one package.
OpenChimera splits the core binary (`chimera-core`) from the management layer
(`openchimera`). Both must be installed. The `mihomo` virtual provider system
ensures only one core provider is active at a time.

### Package dependencies comparison

| Dependency | Nikki | OpenChimera |
|------------|-------|-------------|
| `ca-bundle` | Yes | Yes |
| `curl` | Yes | Yes |
| `yq` | Yes | Yes |
| `kmod-tun` | Yes | Yes |
| `kmod-nft-tproxy` | Yes | **No** (deferred) |
| `kmod-nft-socket` | Yes | **No** (deferred) |
| `kmod-dummy` | Yes | **No** (deferred) |
| `firewall4` | Yes | **No** (deferred) |
| `ip-full` | Yes | **No** (not needed for TUN-only) |
| `kmod-inet-diag` | Yes | **No** (not needed for TUN-only) |

---

## 3. UCI Schema Mapping

Nikki's UCI schema (`/etc/config/nikki`) has 12+ sections with dozens of
options. OpenChimera's schema (`/etc/config/openchimera`) has 5 sections with a
minimum viable set.

### Section mapping

| Nikki section | OpenChimera section | Status |
|---|---|---|
| `config` | `config` | **Migrated** (subset) |
| `status` | `status` | **Migrated** (same structure) |
| `core` | `core` | **Migrated** (different options) |
| `mixin` | `mixin` | **Migrated** (reduced options) |
| `proxy` | `proxy` | **Migrated** (reduced options) |
| `routing` | `routing` | **Migrated** (reduced options) |
| `procd` | — | **Removed** — env vars not needed |
| `subscription` | — | **Removed** — no subscription scheduler |
| `authentication` | — | **Removed** — configure in profile YAML |
| `hosts` | — | **Removed** — configure in profile YAML |
| `nameserver` | — | **Removed** — configure in profile YAML |
| `nameserver_policy` | — | **Removed** — configure in profile YAML |
| `sniff` | — | **Removed** — configure in profile YAML |
| `router_access_control` | — | **Removed** — deferred |
| `lan_access_control` | — | **Removed** — deferred |
| `editor` | — | **Removed** — no LuCI |
| `log` | — | **Removed** — basic logging via config.log_file |

### Detailed option mapping — `config` section

| Nikki option | OpenChimera option | Notes |
|---|---|---|
| `init` | — | Not needed (no subscription init) |
| `enabled` | `enabled` | Same meaning |
| `profile` | — | Profile management deferred |
| `start_delay` | — | Removed |
| `scheduled_restart` | — | Removed |
| `scheduled_restart_cron` | — | Removed |
| `test_profile` | — | Removed |
| `core_only` | — | Removed |
| `log_level` | `log_level` | Same meaning |
| `log_file` | `log_file` | Same meaning (renamed from nikki) |

### Detailed option mapping — `core` section

| Nikki option | OpenChimera option | Notes |
|---|---|---|
| `redirect_listener_name` | — | Removed (no redirect) |
| `tproxy_listener_name` | — | Removed (no tproxy) |
| `tun_listener_name` | — | Not exposed via UCI (set in profile) |

### Detailed option mapping — `mixin` section

| Nikki option | OpenChimera option | Notes |
|---|---|---|
| `log_level` | (via `config.log_level`) | Moved to config section |
| `mode` | — | Configure in profile YAML |
| `ipv6` | — | Configure in profile YAML |
| `allow_lan` | — | Configure in profile YAML |
| `ui_path` / `ui_url` | — | Removed (no dashboard) |
| `api_listen` | `api_listen` | Same meaning |
| `secret` | `secret` | Same meaning |
| `selection_cache` | — | Removed |
| `mixed_port` | `mixed_port` | Same meaning |
| `port` | `port` | Same meaning |
| `socks_port` | `socks_port` | Same meaning |
| `redir_port` | — | Removed (no redirect) |
| `tproxy_port` | — | Removed (no tproxy) |
| `authentication` | — | Configure in profile YAML |
| `tun_enabled` | `tun_enabled` | Same meaning |
| `tun_device` | `tun_device` | Same meaning |
| `tun_stack` | — | Not configurable via UCI (defaults to `mixed`) |
| `tun_dns_hijack` | `tun_dns_hijack` | Same meaning |
| `tun_dns_hijacks` | — | Single on/off replaces list |
| `dns_enabled` / `dns_listen` / ... | — | Configure in profile YAML |
| `sniffer_*` | — | Configure in profile YAML |
| `rule` / `rule_provider` | — | Configure in profile YAML |
| `mixin_file_content` | — | Removed |
| `match_process` | — | Removed |

### Detailed option mapping — `proxy` section

| Nikki option | OpenChimera option | Notes |
|---|---|---|
| `enabled` | `enabled` | Same meaning |
| `tcp_mode` | — | Removed (TUN only) |
| `udp_mode` | — | Removed (TUN only) |
| `ipv4_dns_hijack` / `ipv6_dns_hijack` | — | Removed |
| `ipv4_proxy` / `ipv6_proxy` | — | Removed |
| `fake_ip_ping_hijack` | — | Removed |
| `router_proxy` / `lan_proxy` | — | Removed |
| `lan_inbound_interface` | — | Removed |
| `reserved_ip` / `reserved_ip6` | — | Removed |
| `bypass_dscp` | — | Removed |
| `bypass_china_mainland_ip` / `ip6` | — | Removed |
| `proxy_tcp_dport` / `proxy_udp_dport` | — | Removed |
| `tun_timeout` / `tun_interval` | — | Removed |

### Detailed option mapping — `routing` section

| Nikki option | OpenChimera option | Notes |
|---|---|---|
| `tproxy_fw_mark` / `tproxy_fw_mask` | — | Removed (no tproxy) |
| `tun_fw_mark` / `tun_fw_mask` | — | Not exposed (TUN managed by core) |
| `tproxy_rule_pref` / `tproxy_route_table` | — | Removed (no tproxy) |
| `tun_route_table` | `tun_route_table` | Same meaning |
| `cgroup_id` / `cgroup_name` | — | Removed |
| `dummy_device` | — | Removed |

---

## 4. Binary Path Changes

### Nikki

The Mihomo binary is installed directly at `/usr/bin/mihomo`. There is no
alternatives management.

### OpenChimera

OpenChimera uses OpenWrt's **alternatives** system (via `PROVIDES` and
`ALTERNATIVES` in the Makefile):

```
/usr/bin/mihomo → /usr/libexec/chimera  (priority 300, provided by chimera-core)
```

- `/usr/libexec/chimera` is the actual binary (downloaded from upstream).
- `/usr/bin/mihomo` is an alternatives-managed symlink.
- The `openchimera` init script calls `/usr/bin/mihomo` (the symlink).
- Other packages can provide the same `mihomo` virtual provider at different
  priority levels.

**During migration**: After uninstalling Nikki, ensure no stale `/usr/bin/mihomo`
binary remains. The alternatives system manages this automatically when using
`opkg`.

---

## 5. Config Format Differences

### Nikki's generated config.yaml

Nikki generates a `config.yaml` that mixes standard Clash fields with
Mihomo-specific extensions:

```yaml
mixed-port: 7890
socks-port: 1080
port: 8080
redir-port: 7891          # Mihomo-specific
tproxy-port: 7892         # Mihomo-specific
external-controller: [::]:9090
secret: ""
log-level: warning

tun:
  enable: true
  device: nikki
  stack: mixed            # Mihomo-specific
  auto-redirect: false     # Mihomo-specific — NOT supported by Chimera
  auto-detect-interface: true  # Mihomo-specific — NOT supported by Chimera
  dns-hijack:
    - "0.0.0.0/0"
    - "::/0"

dns:
  enabled: true
  listen: 0.0.0.0:1053
  mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  # ...
```

### OpenChimera's generated config.yaml

OpenChimera generates a minimal Chimera-compatible config:

```yaml
# Generated by OpenChimera config_gen.sh
mixed-port: 7890
socks-port: 1080
external-controller: 0.0.0.0:9090
log-level: info

tun:
  enable: true
  device: nikki
  route-table: 81
  dns-hijack:
    - "0.0.0.0/0"
    - "::/0"
```

**Key differences**:

| Field | Nikki | OpenChimera | Why |
|-------|-------|-------------|-----|
| `redir-port` | Included | **Excluded** | Chimera does not support redirect |
| `tproxy-port` | Included | **Excluded** | Chimera does not support tproxy |
| `tun.stack` | `mixed` | **Excluded** | Chimera does not expose stack selection |
| `tun.auto-redirect` | `false` | **Excluded** | Chimera does not support this |
| `tun.auto-detect-interface` | `true` | **Excluded** | Chimera does not support this |
| `tun.route-table` | Set by init | **Explicit** | OpenChimera sets this in config |
| `dns` block | Full DNS config | **User-managed** | DNS must be in profile YAML |

### Config fields that will cause validation errors

If your profile YAML (the one referenced by `config_path`) contains any of these
Mihomo-only fields, `mihomo -t` validation will fail:

- `auto-redirect` (in tun block)
- `auto-detect-interface` (in tun block)
- `disable-icmp-forwarding`
- `redir-port` (top-level)
- `tproxy-port` (top-level)
- `find-process-mode`
- `global-client-fingerprint`
- `unified-delay`
- `tcp-concurrent`

**Remove these fields from your profile YAML before migrating.**

---

## 6. TUN Configuration

### Nikki approach

Nikki's TUN setup uses auto-detection:

```
tun:
  enable: true
  device: nikki
  stack: mixed                             # Auto-detection of best stack
  auto-route: true                         # Nikki manages routing
  auto-redirect: false                     # Nikki manages iptables redirect
  auto-detect-interface: true              # Nikki picks the WAN interface
```

Nikki also manages nftables rules (via ucode templates) for TProxy/Redirect,
applies firewall marks, and sets up routing tables on the device.

### OpenChimera approach

OpenChimera uses explicit TUN configuration:

```
tun:
  enable: true
  device: nikki
  route-table: 81                          # Explicit, user-configured
  dns-hijack:
    - "0.0.0.0/0"
    - "::/0"
```

- No `auto-route`, `auto-redirect`, or `auto-detect-interface`.
- The TUN `device` name defaults to `nikki` (same as Nikki default) for
  compatibility.
- The `route-table` is set explicitly via UCI (default: `81`).
- TUN stack defaults to `mixed` (Chimera's default).
- No nftables integration in milestone 1 — TUN mode works entirely within the
  Chimera core process.

**Migration action**: If you relied on Nikki's `auto-detect-interface` to find
your WAN interface, you must manually configure your interface and routing in
OpenWrt instead. Chimera's TUN mode handles routing internally.

---

## 7. Removed Features in Milestone 1

These Nikki features are **not available** in OpenChimera milestone 1. They are
either deferred to later milestones or will never be supported (because Chimera
does not implement them).

### 7.1 LuCI Web Interface

Nikki includes `luci-app-nikki` with full web management. OpenChimera milestone
1 is **CLI-only**. A LuCI app design document exists
([docs/luci-app-design.md](luci-app-design.md)) but no implementation has been
started.

**Mitigation**: All management is done via UCI commands and the init script.
See [Quick Start](../README.md#quick-start) in the README.

### 7.2 TProxy / Redirect Transparent Proxy

Nikki supports transparent proxy via TProxy and Redirect modes (TCP) with full
nftables integration. OpenChimera milestone 1 supports **TUN only**.

**Why**: TProxy/Redirect require additional kernel modules
(`kmod-nft-tproxy`, `kmod-nft-socket`), nftables rulesets, and careful routing
design. These are tracked in
[docs/tproxy-redirect-plan.md](tproxy-redirect-plan.md) for a later milestone.

**Mitigation**: Use TUN mode for transparent proxying. TUN handles both TCP and
UDP transparently without the complexity of nftables rules.

### 7.3 Subscription / Profile Scheduler

Nikki has built-in subscription management with cron-based scheduled updates.
OpenChimera milestone 1 has **no subscription system**.

**Mitigation**: Manage your profile YAML externally and copy it to the device,
or write a cron script that fetches and validates profiles manually.

### 7.4 SIGHUP Hot Reload

Nikki supports SIGHUP-based hot reload (via `reload_service` in the init script
and the `fast_reload` option). OpenChimera uses a **restart-based reload**:

```shell
# Nikki: hot reload
killall -HUP mihomo

# OpenChimera: restart (config is regenerated automatically)
/etc/init.d/openchimera restart
```

**Impact**: A restart drops all active connections. For most proxy use cases
this is acceptable. If you need zero-downtime reloads, this is a known
limitation.

### 7.5 DNS Configuration via UCI

Nikki provides extensive DNS configuration through UCI (`mixin.dns_*` options).
OpenChimera does not expose DNS in its UCI schema.

**Mitigation**: Configure DNS directly in your profile YAML (the file referenced
by `config_path`).

### 7.6 Access Control (Router / LAN)

Nikki provides fine-grained access control (bypass IP ranges, user/group/cgroup
filtering, interface-based routing). OpenChimera milestone 1 has **no access
control**.

**Mitigation**: Use OpenWrt's built-in firewall rules or nftables to restrict
access to the proxy ports.

### 7.7 Authentication

Nikki has a UCI `authentication` section for proxy credentials. OpenChimera
does not expose this in UCI.

**Mitigation**: Configure proxy authentication in your profile YAML under the
`authentication` field (standard Clash field, supported by Chimera).

### 7.8 Scheduled Restart

Nikki supports cron-based scheduled restarts via UCI. OpenChimera does not.

**Mitigation**: Use OpenWrt's built-in cron (`crontab -e`) to schedule restarts:

```shell
# Restart openchimera daily at 3 AM
0 3 * * * /etc/init.d/openchimera restart
```

### 7.9 Environment Variable Tuning

Nikki exposes environment variables via the `procd` UCI section
(`env_*` options) for loopback detection, QUIC GSO, IPv6 check, etc.
OpenChimera does not expose these.

**Mitigation**: Chimera_Client handles these internally. If you need custom
env vars, set them in the init script manually.

---

## 8. Migration Steps

### Prerequisites

- OpenWrt 24.10 or later (x86_64)
- Backup your existing Nikki config and profile YAML

### Step 1: Backup Nikki configuration

```shell
# Backup UCI config
uci export nikki > /tmp/nikki-backup.uci

# Backup the init config and profile
cp /etc/config/nikki /tmp/nikki-backup.conf
cp /etc/nikki/*.yaml /tmp/ 2>/dev/null || true

# Note your current settings
uci show nikki
```

### Step 2: Clean and sanitize your profile YAML

```shell
# Copy your profile
cp /etc/nikki/run/config.yaml /tmp/profile-clean.yaml
```

Edit the copy and remove all fields listed in
[Section 5](#config-fields-that-will-cause-validation-errors). Chimera works
with standard Clash config fields only.

### Step 3: Remove Nikki

```shell
opkg remove luci-app-nikki luci-i18n-nikki-zh-cn nikki --force-removal-of-dependent-packages
```

If you have `mihomo-meta` or `mihomo-alpha` installed, remove those too:

```shell
opkg remove mihomo-meta mihomo-alpha
```

### Step 4: Install OpenChimera

Build the packages using the OpenWrt SDK
(see [docs/sdk-build.md](sdk-build.md)) or download prebuilt `.ipk` files.

```shell
opkg install chimera-core_*.ipk openchimera_*.ipk
```

### Step 5: Configure OpenChimera UCI

```shell
# Enable the service
uci set openchimera.config.enabled=1

# Set your profile path (point to your sanitized profile)
uci set openchimera.config.config_path=/etc/openchimera/profile.yaml

# Copy your sanitized profile
cp /tmp/profile-clean.yaml /etc/openchimera/profile.yaml

# Set TUN if needed
uci set openchimera.mixin.tun_enabled=1

# Commit
uci commit openchimera
```

### Step 6: Start and verify

```shell
/etc/init.d/openchimera start

# Check logs
cat /var/log/openchimera/core.log

# Verify proxy is running
curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10
```

### Step 7 (optional): Map any remaining Nikki UCI values

If you had custom ports, API settings, or TUN device names, transfer them:

```shell
# Old Nikki → New OpenChimera
uci set openchimera.mixin.mixed_port="$(uci get nikki.mixin.mixed_port 2>/dev/null || echo 7890)"
uci set openchimera.mixin.socks_port="$(uci get nikki.mixin.socks_port 2>/dev/null)"
uci set openchimera.mixin.port="$(uci get nikki.mixin.port 2>/dev/null)"
uci set openchimera.mixin.api_listen="$(uci get nikki.mixin.api_listen 2>/dev/null || echo '[::]:9090')"
uci set openchimera.mixin.secret="$(uci get nikki.mixin.secret 2>/dev/null)"
uci set openchimera.mixin.tun_device="$(uci get nikki.mixin.tun_device 2>/dev/null || echo 'nikki')"
uci set openchimera.mixin.tun_dns_hijack="$(uci get nikki.mixin.tun_dns_hijack 2>/dev/null || echo 0)"
uci set openchimera.routing.tun_route_table="$(uci get nikki.routing.tun_route_table 2>/dev/null || echo 81)"
uci set openchimera.config.log_level="$(uci get nikki.config.log_level 2>/dev/null || echo 'warning')"
uci commit openchimera
/etc/init.d/openchimera restart
```

---

## 9. Profile / Config Migration

Your existing Nikki profile YAML (the one synced from your subscription or
written by hand) needs modification to work with Chimera.

### What to remove

Remove these top-level keys if present:

```yaml
# ❌ Remove these:
redir-port: 7891
tproxy-port: 7892
find-process-mode: strict
global-client-fingerprint: chrome
unified-delay: false
tcp-concurrent: true
```

Remove these from the `tun:` block:

```yaml
tun:
  # ❌ Remove these:
  auto-redirect: false
  auto-detect-interface: true
  disable-icmp-forwarding: false
  # stack: mixed               # Remove if present (Chimera defaults to mixed)
  # gso: true                  # Remove if present
  # gso-max-size: 65536        # Remove if present
  # gso-queue-size: 1024       # Remove if present
```

### What to keep

Standard Clash fields that work with Chimera:

```yaml
# ✅ Keep these:
port: 8080
socks-port: 1080
mixed-port: 7890
external-controller: 0.0.0.0:9090
secret: ""
log-level: info

tun:
  enable: true
  device: nikki
  dns-hijack:
    - "0.0.0.0/0"
    - "::/0"

dns:
  enabled: true
  listen: 0.0.0.0:1053
  mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "+.lan"
    - "+.local"
  nameserver:
    - "https://223.5.5.5/dns-query"
    - "https://1.1.1.1/dns-query"
  fallback:
    - "tls://8.8.4.4:853"
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - "240.0.0.0/4"

proxies:
  # Your proxy definitions (same format as Nikki/Mihomo)
  - name: "my-server"
    type: ss
    server: example.com
    port: 8388
    cipher: aes-256-gcm
    password: "secret"

proxy-groups:
  # Your groups (same format)

rules:
  # Your rules (same format)
```

### Important note about `rule-providers` and `proxy-providers`

Chimera_Client supports both `rule-providers` and `proxy-providers` in standard
Clash format. These work the same as in Nikki/Mihomo. No migration needed.

### Important note about `tun.stack`

Nikki allows setting `tun.stack` to `gvisor` or `system` (or `mixed`).
Chimera_Client uses `mixed` by default and does not expose stack selection via
configuration. If you used `gvisor` or `system` in Nikki, your TUN performance
characteristics may change. There is no workaround.

---

## 10. Troubleshooting

### "Unknown field" errors during validation

If `mihomo -t` reports unknown fields, your profile contains Mihomo-only keys.
See [Section 5](#config-fields-that-will-cause-validation-errors) for the full
list of fields to remove.

### Service fails to start

Check the log file:

```shell
cat /var/log/openchimera/core.log
```

Common issues:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `config validation failed` | Profile has Mihomo-only fields | Remove unsupported fields |
| `binary not found` | `chimera-core` not installed | Run `opkg install chimera-core` |
| `permission denied` | Binary not executable | Run `chmod +x /usr/libexec/chimera` |
| `TUN device error` | `kmod-tun` not loaded | Run `opkg install kmod-tun && modprobe tun` |

### TUN not working

Ensure the TUN kernel module is loaded:

```shell
modprobe tun
lsmod | grep tun
```

If you see no output, install `kmod-tun`:

```shell
opkg install kmod-tun
```

### Port conflicts

If another service is using the same ports, change them:

```shell
uci set openchimera.mixin.mixed_port=7891
uci commit openchimera
/etc/init.d/openchimera restart
```

### Stale Nikki files

After removing Nikki, check for leftover files:

```shell
ls -la /etc/config/nikki          # Should not exist
ls -la /etc/init.d/nikki          # Should not exist
ls -la /etc/nikki/                # Should not exist
ls -la /usr/bin/mihomo            # Should be linked to /usr/libexec/chimera
```

### Alternatives system conflicts

If another package provides `mihomo` (e.g., `mihomo-meta`), remove it:

```shell
opkg remove mihomo-meta
opkg install chimera-core
```

---

## 11. Reference

### Documentation index

| Document | Description |
|----------|-------------|
| [README.md](../README.md) | Project overview, quick start, configuration |
| [docs/arch-matrix.md](arch-matrix.md) | Architecture support matrix and artifact policy |
| [docs/sdk-build.md](sdk-build.md) | Step-by-step SDK build instructions |
| [docs/qa-checklist.md](qa-checklist.md) | QA environment checklist and test plan |
| [docs/integration-verification.md](integration-verification.md) | chimera-core + openchimera integration verification |
| [docs/aarch64-enablement.md](aarch64-enablement.md) | Path to enable aarch64 support |
| [docs/luci-app-design.md](luci-app-design.md) | LuCI web interface design (deferred) |
| [docs/cicd-release-feed.md](cicd-release-feed.md) | CI/CD release feed design (deferred) |
| [docs/tproxy-redirect-plan.md](tproxy-redirect-plan.md) | TProxy/Redirect expansion plan (deferred) |
| **docs/migration-guide.md** | **This document — Nikki to OpenChimera migration** |

### Upstream references

- [Chimera_Client](https://github.com/MFSGA/Chimera_Client) — upstream project
- [Clash config spec](https://github.com/Dreamacro/clash/wiki/configuration) —
  standard Clash config reference
- [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — the project this
  guide helps you migrate from
