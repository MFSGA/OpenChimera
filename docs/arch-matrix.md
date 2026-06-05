# OpenChimera Architecture / Artifact Matrix

> **Pinned Upstream Release**: [`Chimera_Client v0.21.1`](https://github.com/MFSGA/Chimera_Client/releases/tag/v0.21.1)
>
> **Policy**: All milestone references use a pinned semver tag. The moving `latest` tag is never used as a stable reference.

## Scope

This document maps OpenWrt target architectures to upstream `Chimera_Client` release artifacts for OpenChimera packaging. It is the single source of truth for what is supported, what is blocked, and what is excluded.

## Milestone 1 Architecture Matrix

| Rust Target | musl/gnu | OpenWrt Compatible (M1) | Status |
|---|---|---|---|
| `x86_64-unknown-linux-musl` | musl | ✅ Supported | Milestone 1 primary target |
| `x86_64-unknown-linux-gnu` | gnu | ❌ Excluded | Not OpenWrt musl-compatible |
| `aarch64-unknown-linux-gnu` | gnu | ❌ Excluded | Not OpenWrt musl-compatible |
| `aarch64-unknown-linux-musl` | musl | ⏳ Deferred | Blocked — no upstream musl artifact confirmed |

### Legend

| Icon | Meaning |
|---|---|
| ✅ Supported | Build target is tested and included in milestone 1. |
| ⏳ Deferred | Target is identified but blocked; will be enabled once upstream artifact is verified. |
| ❌ Excluded | Target will not be packaged — inherently incompatible with OpenWrt's musl libc requirement. |

## Target Details

### `x86_64-unknown-linux-musl` (Milestone 1)

- **Status**: Supported
- **OpenWrt arch**: `x86_64`
- **libc**: musl
- **Upstream artifact**: `clash_chimera-x86_64-unknown-linux-musl` (prebuilt binary)
- **Package**: `chimera-core` installs to `/usr/libexec/chimera`
- **Alternatives**: `/usr/bin/mihomo` → `/usr/libexec/chimera` (priority 300)

### `aarch64-unknown-linux-musl` (Deferred)

- **Status**: Blocked
- **OpenWrt arch**: `aarch64_cortex-a53` / `aarch64_generic`
- **libc**: musl
- **Upstream artifact**: `aarch64-unknown-linux-musl` — **not confirmed in upstream CI**
- **Reason**: Metis research found that upstream CI only publishes `aarch64-unknown-linux-gnu` artifacts. A musl variant must exist before OpenChimera can support aarch64.
- **Path to enablement**:
  1. Upstream adds `aarch64-unknown-linux-musl` to CI artifact matrix.
  2. Artifact is downloaded and verified (hash, runtime test).
  3. `chimera-core` Makefile is updated to add aarch64 musl download block.
  4. SDK compile QA confirms the package for aarch64 OpenWrt target.

### GNU Targets (Excluded)

The following targets produce glibc-linked binaries incompatible with OpenWrt's musl-based libc:

| Target | Why Excluded |
|---|---|
| `x86_64-unknown-linux-gnu` | glibc-linked — cannot run on OpenWrt musl |
| `aarch64-unknown-linux-gnu` | glibc-linked — cannot run on OpenWrt musl |

OpenChimera will **never** package gnu-linked binaries as OpenWrt-compatible. If the upstream CI only provides gnu artifacts for a given architecture, that architecture is considered blocked until a musl variant is published.

## Upstream Release Reference

- **Repository**: [MFSGA/Chimera_Client](https://github.com/MFSGA/Chimera_Client)
- **Pinned version**: `v0.21.1`
- **Version field pattern** (per OpenWrt convention, after `.ref/OpenWrt-nikki/mihomo-meta/Makefile`):
  ```makefile
  PKG_VERSION:=0.21.1
  PKG_SOURCE_VERSION:=v0.21.1
  ```
- **Artifact naming convention**: `clash_chimera-{rust-target}`

## Version Pinning Policy

1. Every release of `chimera-core` references a specific pinned `PKG_VERSION` / `PKG_SOURCE_VERSION`.
2. The `latest` tag is never used — all references are immutable semver tags (`v0.21.1`, etc.).
3. Version bumps require:
   - New upstream release tag exists
   - Artifact hashes are verified
   - SDK compile QA passes for all supported architectures

## Appendix: CI Artifact Matrix (Upstream)

Per upstream `.github/workflows/ci.yml`, the following artifacts are published:

| Rust Target | Present in CI | musl/gnu |
|---|---|---|
| `x86_64-unknown-linux-musl` | ✅ Yes | musl |
| `x86_64-unknown-linux-gnu` | ✅ Yes | gnu |
| `aarch64-unknown-linux-gnu` | ✅ Yes | gnu |
| `aarch64-unknown-linux-musl` | ❌ No | musl (absent) |

This confirms that `aarch64-unknown-linux-musl` is not currently produced upstream, blocking aarch64 support until upstream CI is updated.
