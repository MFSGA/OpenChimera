# TProxy / Redirect Transparent Proxy Expansion Plan

> **Status**: Planning / Deferred
> **Target milestone**: Later milestone (NOT milestone 1)
> **Current state**: OpenChimera only supports basic TUN mode. TProxy and Redirect modes
> require kernel modules, nftables integration, and expanded UCI schema.
>
> **See also**:
> - [`docs/qa-checklist.md`](qa-checklist.md) — baseline QA patterns
> - [`openchimera/files/openchimera.conf`](../openchimera/files/openchimera.conf) — current UCI schema
> - [`openchimera/files/openchimera.init`](../openchimera/files/openchimera.init) — current init lifecycle
> - [`.ref/OpenWrt-nikki/nikki/files/ucode/hijack.ut`](../.ref/OpenWrt-nikki/nikki/files/ucode/hijack.ut) — Nikki reference nftables template
> - [`.ref/OpenWrt-nikki/nikki/files/nikki.init`](../.ref/OpenWrt-nikki/nikki/files/nikki.init) — Nikki reference init (full TProxy/Redirect lifecycle)

---

## Table of Contents

1. [Overview and Motivation](#1-overview-and-motivation)
2. [Mode Comparison: TUN vs TProxy vs Redirect](#2-mode-comparison-tun-vs-tproxy-vs-redirect)
3. [Required Kernel Modules](#3-required-kernel-modules)
4. [Required Linux Kernel Configs](#4-required-linux-kernel-configs)
5. [nftables Ruleset Design](#5-nftables-ruleset-design)
6. [Chimera_Client Feature Requirements](#6-chimera_client-feature-requirements)
7. [New UCI Schema Fields](#7-new-uci-schema-fields)
8. [Init System Integration Points](#8-init-system-integration-points)
9. [Deferred Fields (Not Supported by Chimera)](#9-deferred-fields-not-supported-by-chimera)
10. [Risk Assessment](#10-risk-assessment)
11. [Implementation Ordering](#11-implementation-ordering)

---

## 1. Overview and Motivation

### 1.1 What This Plan Covers

This document describes how to extend OpenChimera beyond basic TUN mode to support
two additional transparent proxy modes: **TProxy** and **Redirect**. These modes
operate at different OSI layers and have different trade-offs for routing traffic
through the Chimera_Client proxy core without application-level configuration.

### 1.2 Why TProxy/Redirect?

| Need | TUN | TProxy | Redirect |
|------|-----|--------|----------|
| Per-app / per-user bypass rules | ❌ | ✅ | ✅ |
| UDP transparent proxy | ✅ (L3) | ✅ (nftables) | ❌ (TCP only) |
| Real source IP preservation | ❌ (L3 tunnel) | ✅ | ❌ (DNAT) |
| No kernel module requirements | `kmod-tun` only | `kmod-nft-tproxy` + `kmod-nft-socket` | None beyond nftables |
| Works with all apps without config | ✅ | ✅ | ✅ |

TProxy and Redirect give users more control over which traffic gets proxied,
support per-connection rules, and avoid the "all-or-nothing" nature of TUN mode.

### 1.3 When to Use Which

- **Use TUN when**: You need UDP proxying with minimum complexity, or you want all
  traffic proxied without per-app rules.
- **Use TProxy when**: You need transparent proxy with UDP support AND per-app
  access control, or you need to preserve original source IP addresses.
- **Use Redirect when**: TCP-only transparent proxy is sufficient, you want
  maximum simplicity, and per-app access control is needed.

---

## 2. Mode Comparison: TUN vs TProxy vs Redirect

### 2.1 TUN (Current — Milestone 1)

| Property | Detail |
|----------|--------|
| **Layer** | L3 (IP layer) |
| **Mechanism** | Creates a virtual `tun` network device. Kernel routes IP packets to this device; Chimera reads raw IP frames, processes them, and forwards via proxy. |
| **Kernel module** | `kmod-tun` |
| **Per-app rules** | ❌ Not directly. App-based bypass requires cgroup/packet marking in conjunction with routing rules. |
| **UDP support** | ✅ Native (L3 packets include UDP) |
| **Source IP preservation** | ❌ TUN termination hides original source IP behind the tunnel device IP. |
| **Complexity** | Low — Chimera manages the device. |
| **Chimera config** | `tun.enable: true`, `tun.device: nikki` |
| **OpenChimera deps** | `kmod-tun`, ip-full |
| **Routing** | Policy routing via route table 81 with fwmark 0x81/0xFF. |

**Current implementation in OpenChimera**:

The init script (`openchimera.init`) launches Chimera with `tun_enabled` in the
mixin config. Chimera creates a TUN device (`nikki`), and the kernel routes
traffic via `route-table 81`. There is no nftables integration in this mode —
Chimera manages TUN routing internally.

### 2.2 TProxy (Deferred — Future Milestone)

| Property | Detail |
|----------|--------|
| **Layer** | L4 (Transport layer) |
| **Mechanism** | Uses Linux TProxy (transparent proxy) socket option. Inbound traffic is intercepted at the `PREROUTING` nftables hook, marked, and redirected to the TProxy listener. The proxy socket preserves the original destination address via `IP_TRANSPARENT` / `IPV6_TRANSPARENT` socket options. |
| **Kernel modules** | `kmod-nft-tproxy`, `kmod-nft-socket` |
| **Per-app rules** | ✅ Via nftables — match on `skuid`, `skgid`, `cgroupv2`, source IP, MAC, etc. |
| **UDP support** | ✅ Full (separate TProxy listener for UDP) |
| **Source IP preservation** | ✅ The proxy receives the original destination address. |
| **Complexity** | High — requires nftables ruleset, ip rule/route for local traffic, and sysctl tweaks. |
| **Chimera config** | `tproxy-port: 7892` or listener with `type: tproxy` |
| **Nikki reference** | `routing.tproxy_route_table = 80`, `routing.tproxy_fw_mark = 0x80`, `routing.tproxy_fw_mask = 0xFF` |

**How it works (flow)**:

```
Client → nftables PREROUTING (mark + tproxy) → TProxy listener → rule matching → proxy outbound
                       ↓
                  mangle OUTPUT (for router/local traffic)
                       ↓
                  ip rule: fwmark 0x80/0xFF → table 80 → lo device
```

### 2.3 Redirect (Deferred — Future Milestone)

| Property | Detail |
|----------|--------|
| **Layer** | L3/4 (DNAT-based) |
| **Mechanism** | Uses nftables `redirect` action (equivalent to iptables REDIRECT). TCP traffic entering the box is DNATed to the Redirect listener port. The listener extracts the original destination from the DNAT target (SO_ORIGINAL_DST). |
| **Kernel modules** | None beyond nftables (in-kernel NAT support) |
| **Per-app rules** | ✅ Via nftables — same match options as TProxy. |
| **UDP support** | ❌ **TCP only.** Redirect cannot handle UDP transparently (nftables `redirect` only works for TCP). |
| **Source IP preservation** | ❌ Source IP is preserved but original destination is retrieved via `SO_ORIGINAL_DST` (similar to DNAT). The original destination is available to the application, but the packet appears as a locally destined connection — meaning the destination IP is the loopback/local address. |
| **Complexity** | Medium — simpler than TProxy because no TProxy socket option or routing table for local traffic is needed. |
| **Chimera config** | `redir-port: 7891` or listener with `type: redir` |
| **Nikki reference** | Used as `proxy.tcp_mode = redirect` |

**How it works (flow)**:

```
Client → nftables PREROUTING (redirect to :7891) → Redirect listener → rule matching → proxy outbound
                       ↓
                  nat OUTPUT (for router/local traffic)
                       ↓
                  (no special ip rule needed)
```

### 2.4 Mode Summary Table

| Feature | TUN | TProxy | Redirect |
|---------|-----|--------|----------|
| OSI layer | L3 | L4 | L3 (DNAT) |
| Kernel modules | `kmod-tun` | `kmod-nft-tproxy`, `kmod-nft-socket` | None extra |
| UDP | ✅ | ✅ | ❌ |
| TCP | ✅ | ✅ | ✅ |
| Per-app access control | ❌ (requires cgroup routing hacks) | ✅ (nftables) | ✅ (nftables) |
| Source IP preservation | ❌ | ✅ | Partial (SO_ORIGINAL_DST) |
| nftables rules | None (Chimera-managed) | Required (complex) | Required (moderate) |
| ip rule/route | TUN table 81 | TProxy table 80 + lo route | None |
| Complex sysctl | None | `net.bridge.bridge-nf-call-*` = 0 | None |
| Chimera_Client feature | `tun` | `tproxy` | `redir` |
| Configuration complexity | Low | High | Medium |

---

## 3. Required Kernel Modules

### 3.1 Module Matrix

| Module | TUN | TProxy | Redirect | OpenWrt package |
|--------|-----|--------|----------|-----------------|
| `tun` (in-kernel) | ✅ Required | ❌ Not needed | ❌ Not needed | `kmod-tun` |
| `nft_tproxy` | ❌ | ✅ Required | ❌ Not needed | `kmod-nft-tproxy` |
| `nft_socket` | ❌ | ✅ Required | ❌ Not needed | `kmod-nft-socket` |
| `nft_redir` | ❌ | ❌ Not needed | ✅ Required | Built into nftables (kernel `CONFIG_NFT_REDIR`) |
| `nft_chain_nat` | ❌ | ❌ Not needed | ✅ Required | Built into nftables (`kmod-nft-nat` on older kernels) |

### 3.2 Milestone 1 Status

Milestone 1 only requires `kmod-tun`. The TProxy/Redirect modules are **not
included** in milestone 1 dependency lists. This means:

- `openchimera/Makefile` currently lists only `kmod-tun` as a kernel module dependency.
- `kmod-nft-tproxy` and `kmod-nft-socket` must be added as **optional** or
  **conditional** dependencies in the Makefile when TProxy support is implemented.
- No additional modules are needed for Redirect beyond standard nftables NAT support
  (which is typically built into the default OpenWrt kernel anyway).

### 3.3 Module Verification

When TProxy support is being verified, confirm module availability:

```shell
# Check if modules are available
opkg list-installed | grep -E "kmod-nft-tproxy|kmod-nft-socket"

# Verify modules are loaded
lsmod | grep -E "^nft_tproxy|^nft_socket"

# If not loaded, load them
insmod nft_tproxy
insmod nft_socket
```

---

## 4. Required Linux Kernel Configs

The target OpenWrt kernel must have these CONFIG options enabled. For standard
OpenWrt 24.10+ kernels these are typically already enabled, but must be verified:

### 4.1 TProxy Requirements

```
CONFIG_NETFILTER_XT_MATCH_SOCKET=y        # Socket matching (for nft_socket)
CONFIG_NFT_TPROXY=y                        # nftables tproxy expression
CONFIG_IPV6_NFT_TPROXY=y                   # IPv6 nftables tproxy expression
CONFIG_NFT_SOCKET=y                        # nftables socket match
```

### 4.2 Redirect Requirements

```
CONFIG_NFT_REDIR=y                         # nftables redirect expression (usually built-in)
CONFIG_NFT_NAT=y                           # nftables NAT chain support
```

### 4.3 Verification on Target

```shell
# Check kernel config (if available)
zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_NFT_TPROXY|CONFIG_NFT_REDIR|CONFIG_NFT_SOCKET"

# Alternative: check via modules
find /lib/modules/$(uname -r) -name '*tproxy*' -o -name '*nft_redir*' 2>/dev/null
```

---

## 5. nftables Ruleset Design

### 5.1 Architecture Overview

Both TProxy and Redirect modes require a dedicated `inet nikki` nftables table
(similar to Nikki's approach in `hijack.ut`). This table is created, populated,
and destroyed by the OpenChimera init system.

The general structure:

```
table inet nikki {
    # Sets (IP ranges, ports, interfaces, marks)
    set reserved_ip { ... }
    set reserved_ip6 { ... }
    set proxy_nfproto { ... }
    set proxy_dport { ... }
    set bypass_dscp { ... }
    set lan_inbound_device { ... }
    # Optional: china_ip, china_ip6 (if geoip bypass is enabled)

    # === Router/local traffic chains (nat OUTPUT + mangle OUTPUT) ===
    chain nat_output { ... }         # DNS hijack, redirect for router-originated traffic
    chain mangle_output { ... }      # TProxy/TUN mark for router-originated traffic
    chain mangle_prerouting_router { ... } # TProxy accept on lo with mark

    # === LAN traffic chains (PREROUTING) ===
    chain dstnat { ... }             # DNS hijack + redirect
    chain mangle_prerouting_lan { ... }  # TProxy/TUN mark for LAN traffic

    # === Mode-specific sub-chains ===
    chain router_redirect { ... }    # redirect to redir-port
    chain router_tproxy { ... }      # mark + accept for TProxy
    chain lan_redirect { ... }       # redirect to redir-port (LAN)
    chain lan_tproxy { ... }         # tproxy to tproxy-port (LAN)
}
```

### 5.2 TProxy nftables Chains

**nat_output (router/local traffic)**:
```
type nat hook output priority filter; policy accept;
jump router_dns_hijack
fib daddr type { local, broadcast, anycast, multicast } counter return
ct direction reply counter return
ip daddr @reserved_ip counter return
ip6 daddr @reserved_ip6 counter return
meta l4proto { tcp, udp } ip dscp @bypass_dscp counter return
meta l4proto { tcp, udp } ip6 dscp @bypass_dscp counter return
jump router_redirect   # (if redirect mode)
```

**mangle_output (router/local traffic for TProxy)**:
```
type route hook output priority mangle; policy accept;
# (same bypass checks as nat_output)
meta l4proto vmap {
    tcp: jump router_tproxy,
    udp: jump router_tproxy
}
```

**router_tproxy sub-chain**:
```
meta nfproto @proxy_nfproto meta l4proto { tcp, udp }
meta mark set meta mark & 0xFFFFFF00 | 0x80 counter accept
```

**mangle_prerouting_router**:
```
type filter hook prerouting priority mangle - 1; policy accept;
iifname lo meta l4proto { tcp, udp } meta mark & 0xFF == 0x80 tproxy to :7892 counter accept
```

**mangle_prerouting_lan**:
```
type filter hook prerouting priority mangle; policy accept;
# (bypass checks)
iifname @lan_inbound_device meta l4proto vmap {
    tcp: jump lan_tproxy,
    udp: jump lan_tproxy
}
```

**lan_tproxy sub-chain**:
```
meta nfproto @proxy_nfproto meta l4proto { tcp, udp }
meta mark set meta mark & 0xFFFFFF00 | 0x80 tproxy to :7892 counter accept
```

### 5.3 Redirect nftables Chains

**nat_output (router/local traffic)**:
```
type nat hook output priority filter; policy accept;
jump router_dns_hijack
fib daddr type { local, broadcast, anycast, multicast } counter return
ct direction reply counter return
ip daddr @reserved_ip counter return
ip6 daddr @reserved_ip6 counter return
meta l4proto . th dport != @proxy_dport counter return
meta l4proto { tcp, udp } ip dscp @bypass_dscp counter return
jump router_redirect
```

**router_redirect sub-chain**:
```
meta nfproto @proxy_nfproto meta l4proto tcp redirect to :7891
```

**dstnat (LAN traffic)**:
```
type nat hook prerouting priority dstnat + 1; policy accept;
iifname @lan_inbound_device jump lan_dns_hijack
fib daddr type { local, broadcast, anycast, multicast } counter return
ct direction reply counter return
ip daddr @reserved_ip counter return
# ... (bypass checks)
iifname @lan_inbound_device jump lan_redirect
```

**lan_redirect sub-chain**:
```
meta nfproto @proxy_nfproto meta l4proto tcp redirect to :7891
```

### 5.4 DNS Hijack (Both Modes)

Both TProxy and Redirect need DNS hijack support:

```nftables
chain router_dns_hijack {
    meta nfproto { ipv4, ipv6 } meta l4proto { tcp, udp } th dport 53
    counter redirect to :1053    # redirect to Chimera's DNS listener
}

chain lan_dns_hijack {
    # Similar, but for LAN inbound interfaces
}
```

### 5.5 Access Control / Per-App Rules

Both modes support per-app access control via nftables match expressions:

```nftables
# By user ID
meta skuid { 53, 55 } counter return    # bypass DNS/proxy for dnsmasq, ftp

# By group ID
meta skgid { 53, 55 } counter return

# By cgroupv2 (for services like tailscale, netbird)
socket cgroupv2 level 2 "services/tailscale" counter return

# By source IP (LAN)
ip saddr { 192.168.1.100, 192.168.1.101 } counter return

# By MAC address
ether saddr { aa:bb:cc:dd:ee:ff } counter return
```

Access control rules are evaluated before the main proxy jump — if a match
returns (early exit), the traffic bypasses the proxy.

### 5.6 Implementation Approach in OpenChimera

There are two viable approaches for generating the nftables ruleset:

**Option A: ucode template (Nikki pattern)**

Generate the nftables ruleset using a `.ut` ucode template file. This is what
Nikki does — `hijack.ut` is a ucode template that reads UCI settings and
renders an nftables ruleset. This approach:

- Requires `ucode` runtime dependency (`libucode` + `ucode-mod-fw4`)
- Allows dynamic set population (IP ranges, ports, interfaces)
- Clean separation between logic and template
- Already proven in the Nikki reference

**Option B: Shell script generation**

Write a shell script that uses `nft` commands directly to construct the ruleset
at service start time. This approach:

- No additional runtime dependencies
- More error-prone (string handling)
- Harder to maintain for complex rulesets
- Simpler to implement initially

**Recommendation**: Use **Option A (ucode template)** for the final implementation,
matching the Nikki pattern. A shell-based fallback is acceptable for an initial
MVP if ucode adds too much dependency weight.

---

## 6. Chimera_Client Feature Requirements

### 6.1 Upstream Feature Flags

The upstream Chimera_Client (`clash-rs`) supports `tproxy` and `redir` as
optional Cargo features. These determine whether the binary is compiled with
transparent proxy listener support:

| Feature | Purpose | Binary impact |
|---------|---------|---------------|
| `tproxy` | Enables TProxy TCP+UDP listener | Adds `tproxy-port` config support |
| `redir` | Enables Redirect TCP listener | Adds `redir-port` config support |
| `tun` | Enables TUN device (currently used) | Adds `tun` config section support |

### 6.2 Current Status

The Chimera_Client binary shipped by `chimera-core` is built with `standard`
features, which includes `tun` but the `tproxy` and `redir` feature inclusion
needs verification. Checking the upstream `clash-bin/Cargo.toml`:

From `clash-bin`'s default feature set: `standard` includes
`trojan`, `ws`, `tls`, `hysteria`, `reality`, `port`, `tun`, etc. It is
**not confirmed** whether `tproxy` and `redir` are included in `standard` or
whether they require explicit feature flags.

### 6.3 Verification Required

Before implementation can proceed:

1. [ ] Check `Cargo.toml` of `clash-bin` or the metapackage to confirm whether
      `tproxy` and `redir` features are included in the `standard` meta-feature.
2. [ ] If not included, add them to the upstream feature set for the chimera-core
      binary build.
3. [ ] Verify at runtime: launch Chimera with `redir-port: 7891` or
      `tproxy-port: 7892` in config and confirm listeners bind.

### 6.4 Runtime Configuration

Chimera_Client supports two syntaxes for defining transparent proxy listeners:

**Legacy port syntax** (simpler, preferred for initial implementation):
```yaml
redir-port: 7891
tproxy-port: 7892
```

**Listener array syntax** (more flexible, supports per-listener config):
```yaml
listeners:
  - name: redir-in
    type: redir
    port: 7891
  - name: tproxy-in
    type: tproxy
    port: 7892
    # optional fields:
    # set-mark: 0x80
    # interface: lo
```

OpenChimera should support both syntaxes, defaulting to the simpler port
syntax for standard configurations.

---

## 7. New UCI Schema Fields

### 7.1 Current vs. Proposed Schema

**Current** (`openchimera.conf`, milestone 1):

```uci
config mixin 'mixin'
    option mixed_port '7890'
    option socks_port '1080'
    option port '8080'
    option api_listen '[::]:9090'
    option secret ''
    option tun_enabled '0'
    option tun_device 'nikki'
    option tun_dns_hijack '0'

config routing 'routing'
    option tun_route_table '81'
```

**Proposed additions** for TProxy/Redirect support:

```uci
# === New section: proxy mode configuration ===
config proxy 'proxy'
    option enabled '1'                          # Enable transparent proxy
    option tcp_mode 'redirect'                  # [tun|tproxy|redirect]  TCP mode selection
    option udp_mode 'tun'                       # [tun|tproxy]           UDP mode selection
    option ipv4_proxy '1'                       # Enable IPv4 transparent proxy
    option ipv6_proxy '0'                       # Enable IPv6 transparent proxy
    option ipv4_dns_hijack '1'                  # Hijack IPv4 DNS (port 53 → Chimera DNS)
    option ipv6_dns_hijack '0'                  # Hijack IPv6 DNS
    option router_proxy '1'                     # Proxy router-originated traffic
    option lan_proxy '1'                        # Proxy LAN client traffic
    option fake_ip_ping_hijack '1'              # Hijack ICMP echo to fake-ip range
    option proxy_tcp_dport '0-65535'            # TCP dport range to proxy
    option proxy_udp_dport '0-65535'            # UDP dport range to proxy
    list lan_inbound_interface 'lan'            # LAN interfaces to proxy

# === New section: routing/policy configuration ===
config routing 'routing'
    # Existing:
    option tun_route_table '81'
    # New for TProxy:
    option tproxy_route_table '80'
    option tproxy_fw_mark '0x80'
    option tproxy_fw_mask '0xFF'
    option tproxy_rule_pref '1024'
    # New for TUN:
    option tun_fw_mark '0x81'
    option tun_fw_mask '0xFF'
    option tun_rule_pref '1025'
    # Cgroup for bypassing proxy for system services
    option cgroup_id '0x12061206'
    option cgroup_name 'nikki'

# === New section: listener port configuration ===
config core 'core'
    option redirect_listener_name 'redir-in'    # Name for Redirect listener
    option tproxy_listener_name 'tproxy-in'     # Name for TProxy listener
    option tun_listener_name 'tun-in'           # Name for TUN listener

# === New section: reserved / bypass IP ranges ===
config bypass 'bypass'
    list reserved_ip '0.0.0.0/8'
    list reserved_ip '10.0.0.0/8'
    list reserved_ip '127.0.0.0/8'
    list reserved_ip '169.254.0.0/16'
    list reserved_ip '172.16.0.0/12'
    list reserved_ip '192.168.0.0/16'
    list reserved_ip '224.0.0.0/4'
    list reserved_ip '240.0.0.0/4'
    list reserved_ip6 '::/128'
    list reserved_ip6 '::1/128'
    list reserved_ip6 'fe80::/10'
    list reserved_ip6 'fc00::/7'
    list bypass_dscp '4'

# === New section: per-user/per-group access control (router) ===
config access_control 'router_acl'
    option enabled '0'
    list user 'dnsmasq'
    list user 'ntp'
    list group 'nogroup'
    list cgroup 'services/tailscale'
    option proxy '0'                            # Bypass proxy for these processes
    option dns '0'                              # Bypass DNS hijack for these processes

# === New section: per-IP/MAC access control (LAN) ===
config access_control 'lan_acl'
    option enabled '0'
    list ip '192.168.1.100'
    list ip6 '::1'
    list mac 'aa:bb:cc:dd:ee:ff'
    option proxy '0'                            # Bypass proxy
    option dns '0'                              # Bypass DNS hijack
```

### 7.2 Redir and TProxy Port Configuration

The redir and tproxy ports should be configurable either through the existing
mixin config or through a dedicated section. Recommended approach:

```uci
config mixin 'mixin'
    # Existing ports
    option mixed_port '7890'
    option socks_port '1080'
    option port '8080'
    # New transparent proxy ports
    option redir_port '7891'                    # Port for Redirect listener
    option tproxy_port '7892'                   # Port for TProxy listener
```

These translate to `redir-port: 7891` and `tproxy-port: 7892` in the
Chimera config YAML.

### 7.3 Field Value Constraints

| Field | Type | Default | Valid Values |
|-------|------|---------|--------------|
| `tcp_mode` | string | `redirect` | `tun`, `tproxy`, `redirect` |
| `udp_mode` | string | `tun` | `tun`, `tproxy` |
| `tproxy_fw_mark` | string | `0x80` | Any valid hex fwmark |
| `tproxy_fw_mask` | string | `0xFF` | Any valid hex mask |
| `tproxy_rule_pref` | integer | `1024` | 0–65535 |
| `tproxy_route_table` | integer | `80` | 1–252 (or 253–255 with caution) |
| `redir_port` | integer | `7891` | 1024–65535 |
| `tproxy_port` | integer | `7892` | 1024–65535 |

---

## 8. Init System Integration Points

### 8.1 Service Lifecycle Modifications

The current `openchimera.init` has no TProxy/Redirect lifecycle. The expanded
init script needs additional phases:

```
start_service() {
    1. Load UCI config
    2. Generate Chimera config.yaml (existing)
    3. Validate config (existing)
    4. [NEW] Install nftables ruleset (call nftables generation)
    5. [NEW] Configure ip rules/routes for TProxy (if tproxy mode)
    6. [NEW] Configure dummy device for IPv6 fake-ip route (if fake-ip)
    7. Start Chimera daemon via procd (existing)
    8. [NEW] Wait for listeners to be ready
    9. [NEW] Verify nftables rules are active
}

stop_service() / cleanup() {
    1. [NEW] Remove nftables rules (delete table inet nikki)
    2. [NEW] Remove ip rules/routes (tproxy + tun tables)
    3. [NEW] Remove dummy device
    4. [NEW] Restore sysctl values (bridge-nf-call-*)
    5. Kill Chimera daemon (existing)
}
```

### 8.2 Integration Points with openchimera.init

The current init script structure (`openchimera.init`):

```
boot() → start()
start_service() → config_load, config_gen, validate, procd_open_instance, ...
stop_service() → : (empty — no cleanup)
reload_service() → stop; start
service_triggers() → procd_add_reload_trigger
```

**Required changes** (for when this is implemented):

1. **`start_service()`**: After config validation and before `procd_open_instance`,
   call a new function (e.g., `setup_proxy_routing()`) that:
   - Installs nftables ruleset (via ucode template or shell)
   - Adds ip rules/routes for TProxy (if applicable)
   - Handles DNS hijack configuration

2. **`stop_service()`**: Replace the empty `:` with cleanup logic that:
   - Deletes the `inet nikki` nftables table
   - Flushes and deletes ip rules/routes
   - Restores sysctl settings

3. **New helper scripts**:
   - `/usr/bin/openchimera-nft-gen` — generates nftables ruleset from UCI
   - `/usr/bin/openchimera-routing-setup` — manages ip rules/routes

### 8.3 Composability with TUN Mode

The system must support mixed modes. The Nikki pattern allows different modes
for TCP and UDP:

| TCP mode | UDP mode | Behavior |
|----------|----------|----------|
| `redirect` | `tun` | TCP via Redirect, UDP via TUN |
| `tproxy` | `tproxy` | Both via TProxy |
| `tproxy` | `tun` | TCP via TProxy, UDP via TUN |
| `redirect` | `redirect` | TCP via Redirect, UDP unsupported (falls through) |
| `tun` | `tun` | Everything via TUN (current behavior) |

**nftables dispatch logic** (from Nikki's `hijack.ut`):

```
meta l4proto vmap {
    tcp: [jump router_tproxy|router_tun|router_redirect],
    udp: [jump router_tproxy|router_tun]    # redirect not valid for UDP
}
```

### 8.4 `firewall_include.sh` Pattern

OpenWrt's `fw4` firewall supports include scripts via `/etc/nikki/scripts/firewall_include.sh`
(or similar). When the firewall reloads, it sources this file. The include script
can re-insert nftables rules that OpenWrt's firewall might have removed.

```shell
# firewall_include.sh
config_load openchimera
config_get_bool proxy_enabled "proxy" "enabled" 0
if [ "$proxy_enabled" = 1 ]; then
    # Re-insert TUN accept rules (if TUN mode)
    # The main nftables table is managed separately (not via fw4)
fi
```

This pattern is used by Nikki and should be replicated for OpenChimera.

---

## 9. Deferred Fields (Not Supported by Chimera)

### 9.1 Chimera_Client Limitations

The upstream Chimera_Client (`clash-rs`) does not support several fields that
Mihomo/Nikki uses for automatic transparent proxy management. These will remain
**unsupported** in OpenChimera regardless of milestone:

| Field | Supported by Mihomo/Nikki | Supported by Chimera | Reason |
|-------|---------------------------|----------------------|--------|
| `auto-redirect` | ✅ | ❌ | Chimera is a userspace daemon; does not manage nftables/ip rules automatically |
| `auto-detect-interface` | ✅ | ❌ | Chimera does not auto-detect WAN interfaces |
| `disable-icmp-forwarding` | ✅ | ❌ | Chimera does not manage sysctl `net.ipv4.conf.*.forwarding` |
| `auto-route` | ✅ | ⚠️ Partial | Chimera can set TUN route table but does not manage ip rules dynamically |
| `tun.auto-redirect` | ✅ | ❌ | Per-listener auto-redirect is not implemented |
| `ebpf` / `ebpf.auto-redirect` | ✅ | ❌ | eBPF-based redirect is a Mihomo-specific feature |

These fields **must not appear** in Chimera config YAML generated by OpenChimera.
The config generation step (`openchimera-config-gen`) should explicitly strip
these fields if they appear in the user's base profile:

```yaml
# Strip these if present in user's profile
tun:
  auto-redirect: false       # Forced to false
  auto-detect-interface: false
  disable-icmp-forwarding: true   # OpenChimera manages this if needed
```

See Nikki's init script for the exact same pattern (lines 187-192 of
`.ref/OpenWrt-nikki/nikki/files/nikki.init`):

```shell
yq -M -i '(.tun) |= (
    .auto-route = false |
    .auto-redirect = false |
    .auto-detect-interface = false |
    .disable-icmp-forwarding = true
)' "$RUN_PROFILE_PATH"
```

### 9.2 Other Deferred Features

| Feature | Deferred to | Reason |
|---------|-------------|--------|
| LuCI web interface for TProxy/Redirect config | Post-Milestone 2 | CLI-only for now |
| GeoIP China bypass (nftables set) | Future milestone | Requires `geoip_cn.nft` generation + data |
| Routing mark per listener | Future milestone | Chimera may not support `set-mark` per listener |
| Bridge-netfilter compatibility | Future milestone | Complex; may need `sysctl` tweaks |
| Interface auto-detection | Never (will not implement) | Chimera does not support it — OpenChimera uses explicit interface config |

---

## 10. Risk Assessment

### R1: Chimera_Client TProxy Feature Availability

| Property | Value |
|----------|-------|
| **Risk** | The `tproxy` and `redir` Cargo features may not be included in the `standard` build of Chimera_Client, requiring changes to the upstream build config. |
| **Mitigation** | Verify upstream `Cargo.toml` before implementing. If features are missing, request their addition to the `standard` feature set. |
| **Severity** | Medium — a dealbreaker if features are absent, but the fix is trivial (add feature flags). |

### R2: nftables Version Compatibility

| Property | Value |
|----------|-------|
| **Risk** | Older OpenWrt kernels/firewall4 may not support all nftables expressions needed (e.g., `tproxy` expression, `socket cgroupv2` match). |
| **Mitigation** | Target OpenWrt 24.10+ (kernel 6.1+). Test nftables ruleset on target before shipping. Provide fallback for older kernels (degraded mode). |
| **Severity** | Medium — 24.10 is the minimum target, so this should be fine, but devices on older OpenWrt would not work. |

### R3: Mixed Mode Complexity

| Property | Value |
|----------|-------|
| **Risk** | Supporting mixed TCP/UDP modes (e.g., TCP via redirect, UDP via TUN) increases testing surface and may produce unexpected routing interactions. |
| **Mitigation** | Start with single-mode support (redirect only for MVP). Add mixed mode in follow-up. Include integration tests for every combination. |
| **Severity** | Medium — increases QA scope but does not block implementation. |

### R4: fw4 Interference

| Property | Value |
|----------|-------|
| **Risk** | OpenWrt's `fw4` firewall may interfere with the `inet nikki` nftables table, especially during firewall reloads (`/etc/init.d/firewall restart`). |
| **Mitigation** | Use a separate table (`inet nikki`) that fw4 does not manage. Provide a `firewall_include.sh` to re-insert TUN accept rules. Track fw4 reload triggers. |
| **Severity** | Medium — manageability issue, not a correctness issue. |

### R5: IPv6 TProxy Support

| Property | Value |
|----------|-------|
| **Risk** | IPv6 TProxy has additional considerations (e.g., `IPV6_TRANSPARENT` socket option, IPv6 routing rules). It may not work identically to IPv4. |
| **Mitigation** | Test IPv4 and IPv6 separately. Ship IPv4-only TProxy support first if IPv6 is problematic. |
| **Severity** | Low-Medium — incremental enablement is possible. |

### R6: Performance Impact

| Property | Value |
|----------|-------|
| **Risk** | TProxy mode adds CPU overhead for every proxied packet (nftables processing + routing rule lookup). Redirect mode is lighter but TCP-only. |
| **Mitigation** | Performance testing during QA. TProxy overhead is generally acceptable on modern router hardware. Document expected throughput for reference hardware. |
| **Severity** | Low — acceptable overhead for proxy functionality. |

### R7: Configuration Bloat

| Property | Value |
|----------|-------|
| **Risk** | The expanded UCI schema adds ~40 new fields. Users may find the configuration surface intimidating. |
| **Mitigation** | Provide sensible defaults (see Section 7). Document common configuration templates. LuCI interface (future milestone) should simplify this. |
| **Severity** | Low — defaults work out of the box for most cases. |

---

## 11. Implementation Ordering

### Phase 1 — Redirect MVP (Smallest Viable)

**Difficulty**: Medium
**Dependencies**: Upstream `redir` feature available, `kmod-nft-nat` (built-in)
**Estimated effort**: 1-2 weeks

1. [ ] Verify Chimera_Client `redir` feature is available in prebuilt binary
2. [ ] Add `redir_port` to UCI schema
3. [ ] Extend `openchimera-config-gen` to emit `redir-port` in YAML
4. [ ] Add `proxy` UCI section with `tcp_mode`, `enabled` fields
5. [ ] Create nftables generation script (shell-based, simple `redirect` chains)
6. [ ] Modify init script: install nftables on start, clean up on stop
7. [ ] Add DNS hijack support (nftables `redirect` to Chimera DNS port)
8. [ ] Test with TCP traffic (HTTP, HTTPS via proxy)

### Phase 2 — TProxy Support

**Difficulty**: High
**Dependencies**: `kmod-nft-tproxy`, `kmod-nft-socket`, upstream `tproxy` feature
**Estimated effort**: 2-3 weeks

1. [ ] Verify Chimera_Client `tproxy` feature availability
2. [ ] Add `tproxy_port` to UCI schema
3. [ ] Add `routing` section fields (fwmark, route table, rule preference)
4. [ ] Create ip rule/route setup script for TProxy routing table
5. [ ] Extend nftables generation with TProxy chains + tproxy expression
6. [ ] Add UDP support (separate TProxy UDP listener handling)
7. [ ] Test with TCP + UDP traffic

### Phase 3 — Access Control and Advanced Features

**Difficulty**: Medium
**Dependencies**: Phase 1 + 2 complete
**Estimated effort**: 2-3 weeks

1. [ ] Add `access_control` UCI sections for per-user/group/cgroup bypass
2. [ ] Add `lan_acl` for per-IP/MAC bypass rules
3. [ ] Add `bypass` section for reserved IP ranges
4. [ ] Add GeoIP China bypass (nftables set + geoip file)
5. [ ] Implement mixed TCP/UDP modes (e.g., TCP redirect + UDP TUN)
6. [ ] Add `firewall_include.sh` for fw4 reload compatibility
7. [ ] Add bridge-nf-call-* sysctl management for Docker compatibility

### Phase 4 — ucode Template Migration

**Difficulty**: Medium
**Dependencies**: Phase 1-3 complete
**Estimated effort**: 1 week

1. [ ] Create `hijack.ut` ucode template (based on Nikki reference)
2. [ ] Replace shell-based nftables generation with ucode
3. [ ] Add `ucode` runtime dependency to package
4. [ ] Remove shell-based generation scripts
5. [ ] Full regression test of all modes

### Phase 5 — LuCI Integration (Separate Milestone)

See the LuCI deferred feature in the main roadmap.

---

## Appendix A: Nikki Reference Configuration

Key reference values from the Nikki project that inform this plan:

```yaml
# Routing defaults (nikki.conf, routing section)
routing:
  tproxy_route_table: 80
  tproxy_fw_mark: '0x80'
  tproxy_fw_mask: '0xFF'
  tproxy_rule_pref: 1024
  tun_route_table: 81
  tun_fw_mark: '0x81'
  tun_fw_mask: '0xFF'
  tun_rule_pref: 1025
  cgroup_id: '0x12061206'
  cgroup_name: nikki
  dummy_device: nikki-dummy

# Core listener names
core:
  redirect_listener_name: redir-in
  tproxy_listener_name: tproxy-in
  tun_listener_name: tun-in
```

## Appendix B: Useful Diagnostic Commands

When implementing or debugging TProxy/Redirect:

```shell
# List nftables rules
nft list ruleset
nft list table inet nikki

# Monitor nftables trace
nft monitor trace
# (enable trace with: nft add rule inet nikki ... meta nftrace set 1)

# Check routing rules
ip rule show
ip route show table 80
ip route show table 81

# Check TProxy/TUN listeners
ss -tlnp | grep -E "7891|7892"
ss -ulnp | grep 7892

# Check socket transparency
cat /proc/net/sockstat6 | grep TCP
sysctl net.ipv4.ip_forward

# Verify nft_tproxy module
lsmod | grep nft_tproxy
modinfo nft_tproxy
```
