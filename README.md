![GitHub License](https://img.shields.io/github/license/MFSGA/OpenChimera?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/MFSGA/OpenChimera?style=for-the-badge&logo=github)

English | [中文](README.zh.md)

# OpenChimera

OpenWrt integration for [Chimera_Client](https://github.com/MFSGA/Chimera_Client) (clash-rs), a Rust-based proxy core.

OpenChimera packages the upstream Chimera_Client binary as an OpenWrt package and adds a management layer with UCI configuration, procd init service, and runtime tooling.

## Packages

OpenChimera provides two OpenWrt packages:

| Package | Role | What it does |
|---|---|---|
| `chimera-core` | Prebuilt binary core | Downloads the upstream `clash_chimera` binary, installs it to `/usr/libexec/chimera`, and exposes `/usr/bin/mihomo` via OpenWrt alternatives. |
| `openchimera` | Management layer | Provides UCI config, procd init script, config generation, validation, logging, and sysupgrade persistence. Depends on the `mihomo` virtual provider from `chimera-core`. |

## Milestone 1 Scope

Milestone 1 focuses on a minimal, buildable, and testable x86_64 OpenWrt integration.

### What is included

- `chimera-core` as a prebuilt binary package for `x86_64` (no Rust source compilation inside the SDK)
- `openchimera` management package with minimal UCI schema and procd lifecycle
- Basic TUN support via `kmod-tun`
- Mixed port, SOCKS port, and HTTP port proxy modes
- Config validation before service start
- Restart-based reload (no SIGHUP)
- Local SDK build workflow

### What is deferred

These features are **not** part of milestone 1. They are planned for later milestones:

| Feature | Reason |
|---|---|
| **aarch64 support** | Upstream CI does not publish `aarch64-unknown-linux-musl` artifacts. Only gnu-linked binaries exist for aarch64, which are incompatible with OpenWrt's musl libc. Support will be enabled once a verified musl artifact is available. |
| **Rust source compilation** | Milestone 1 uses a prebuilt binary to keep the SDK build simple and avoid Rust toolchain dependencies inside the OpenWrt build system. Source compilation may be added in a later milestone if the upstream CI pipeline changes or if self-hosted cross builds are required for missing architectures. |
| **LuCI web interface** | A LuCI app is planned but not yet implemented. Milestone 1 is CLI-only. |
| **TProxy / Redirect** | Transparent proxy modes beyond basic TUN are deferred. They require additional kernel modules (`kmod-nft-tproxy`, `kmod-nft-socket`), nftables integration, and careful routing design. |
| **Subscription / profile scheduler** | Automatic subscription updates and cron-based profile refresh are not included in milestone 1. |
| **Release feed / CI/CD** | A hosted opkg feed and CI publish workflow are future work. Milestone 1 uses a local SDK build path only. |

### Architecture support

| Architecture | Milestone 1 | Notes |
|---|---|---|
| `x86_64` (musl) | ✅ Supported | Primary target. Upstream provides `x86_64-unknown-linux-musl` artifacts. |
| `aarch64` (musl) | ⏳ Deferred | Blocked until upstream publishes `aarch64-unknown-linux-musl` artifacts. |
| `x86_64` (gnu) | ❌ Excluded | glibc-linked binaries cannot run on OpenWrt musl. |
| `aarch64` (gnu) | ❌ Excluded | glibc-linked binaries cannot run on OpenWrt musl. |

### Version pinning

Every `chimera-core` release references a specific pinned upstream tag (e.g., `v0.21.1`). The moving `latest` tag is never used. This ensures reproducible builds and clear upgrade paths.

## Prerequisites

- OpenWrt SDK for `x86_64` (OpenWrt 24.10 or later recommended)
- Linux host with standard build tools (gcc, make, etc.)

## SDK Build

Build both packages using an OpenWrt SDK for x86_64.

```shell
# Quick reference — add feed, update, install, compile
echo "src-git openchimera https://github.com/MFSGA/OpenChimera.git;main" >> "feeds.conf.default"
./scripts/feeds update -a
./scripts/feeds install -a
make package/chimera-core/compile V=s
make package/openchimera/compile V=s
```

The compiled `.ipk` files will be found under `bin/packages/x86_64/openchimera/`.

> **Full step-by-step instructions** — including SDK setup, prerequisites,
> troubleshooting, and build notes — are in
> **[docs/sdk-build.md](docs/sdk-build.md)**.

## Install

Copy the built `.ipk` files to your OpenWrt device and install:

```shell
opkg install chimera-core_*.ipk openchimera_*.ipk
```

## Quick Start

After installation:

1. Enable the service:
   ```shell
   uci set openchimera.main.enabled=1
   uci commit openchimera
   ```

2. Configure a proxy port (optional, default is `mixed-port: 7890`):
   ```shell
   uci set openchimera.main.mixed_port=7890
   uci commit openchimera
   ```

3. Start the service:
   ```shell
   /etc/init.d/openchimera start
   ```

4. Verify the proxy is running:
   ```shell
   curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10
   ```

5. Check logs:
   ```shell
   cat /var/log/openchimera/core.log
   ```

## Configuration

UCI config is stored at `/etc/config/openchimera`. The schema covers:

- `enabled` - Enable or disable the service
- `config_path` - Path to the core YAML config
- `work_dir` - Working directory for the core process
- `mixed_port`, `port`, `socks_port` - Proxy listen ports
- `external_controller`, `secret` - API binding and authentication
- `tun_enabled`, `tun_device`, `tun_route_table` - Basic TUN settings
- `log_path` - Log file location

## Documentation

| Document | Description |
|----------|-------------|
| **[docs/sdk-build.md](docs/sdk-build.md)** | Full SDK build instructions with prerequisites, troubleshooting, and build notes |
| **[docs/arch-matrix.md](docs/arch-matrix.md)** | Architecture support matrix (x86_64, aarch64) and artifact pinning policy |
| **[docs/qa-checklist.md](docs/qa-checklist.md)** | QA environment checklist and verification procedures |
| **[docs/integration-verification.md](docs/integration-verification.md)** | chimera-core + openchimera integration verification report |
| **[docs/migration-guide.md](docs/migration-guide.md)** | Migration guide for users coming from Nikki / mihomo-meta to OpenChimera |
| **[docs/aarch64-enablement.md](docs/aarch64-enablement.md)** | Plan and prerequisites for enabling aarch64 support |
| **[docs/luci-app-design.md](docs/luci-app-design.md)** | LuCI web interface design document (deferred, not yet implemented) |
| **[docs/cicd-release-feed.md](docs/cicd-release-feed.md)** | CI/CD release feed design (deferred, not yet implemented) |
| **[docs/tproxy-redirect-plan.md](docs/tproxy-redirect-plan.md)** | TProxy / Redirect transparent proxy expansion plan (deferred, not yet implemented) |

## Compatibility

OpenChimera integrates the `clash-rs` / Chimera_Client core, which implements a Clash-compatible API and config format. However:

- Full Mihomo feature parity is **not** claimed or guaranteed.
- Some Nikki / Mihomo-specific config fields (e.g., `auto-redirect`, `auto-detect-interface`, `disable-icmp-forwarding`) are not supported by Chimera and will cause validation errors.
- SIGHUP-based hot reload is not supported. Config changes require a full restart.
- TProxy and Redirect modes are not implemented in milestone 1.

## Roadmap

### Milestone 1 (current)

- [x] Architecture / artifact matrix
- [x] `chimera-core` prebuilt package
- [x] `openchimera` UCI schema and runtime
- [ ] SDK compile QA
- [ ] Runtime lifecycle QA
- [ ] Mixed port and TUN runtime QA

### Later milestones

- [ ] aarch64 musl support (pending upstream artifact)
- [ ] LuCI web interface
- [ ] TProxy / Redirect transparent proxy modes
- [ ] Subscription / profile scheduler
- [ ] Release feed and CI/CD workflow
- [ ] Rust source compilation within SDK (optional)

## Dependencies

### chimera-core

- None at runtime (self-contained binary)

### openchimera

- `chimera-core` (or any package providing `mihomo` virtual provider)
- `ca-bundle`
- `curl`
- `yq`
- `kmod-tun`

## License

[GNU Affero General Public License v3.0](LICENSE)
