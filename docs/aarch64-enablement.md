# aarch64 Enablement Path

> **Status**: Planning
> **Current state**: `aarch64-unknown-linux-musl` artifacts are **not published** by upstream CI.
> All aarch64 support in OpenChimera is blocked until upstream delivers musl-linked binaries.
>
> **See also**:
> - [`docs/arch-matrix.md`](arch-matrix.md) — current architecture support matrix
> - [`docs/qa-checklist.md`](qa-checklist.md) — x86_64 QA patterns (extend for aarch64)
> - [`chimera-core/Makefile`](../chimera-core/Makefile) — current x86_64-only download

---

## Overview

Enabling aarch64 support in OpenChimera requires coordinated changes across three
independent tiers. Each tier is a hard prerequisite for the next.

```
Tier 1 (Upstream CI)
  └─ aarch64-unknown-linux-musl artifact is compiled and published
       │
       ▼
Tier 2 (Package Makefile)
  └─ chimera-core/Makefile gains aarch64 PKG_SOURCE / PKG_HASH
       │
       ▼
Tier 3 (QA Verification)
  └─ SDK compile, install, and runtime tests pass on aarch64
```

---

## Tier 1 — Upstream CI Changes (Chimera_Client)

### Current State

The upstream [`ci.yml`](https://github.com/MFSGA/Chimera_Client/blob/master/.github/workflows/ci.yml)
build matrix includes these Linux targets:

| Rust Target | Tool | musl/gnu | Present in CI |
|---|---|---|---|
| `x86_64-unknown-linux-gnu` | `cross` | gnu | ✅ |
| `x86_64-unknown-linux-musl` | `cross` | musl | ✅ |
| `i686-unknown-linux-musl` | `cross` | musl | ✅ |
| `aarch64-unknown-linux-gnu` | `cross` + `zig: "2.17"` | gnu | ✅ |
| `armv7-unknown-linux-gnueabi` | `cross` | gnu | ✅ |
| `armv7-unknown-linux-gnueabihf` | `cross` + `zig: "2.17"` | gnu | ✅ |
| **`aarch64-unknown-linux-musl`** | **N/A** | **musl** | **❌ Missing** |

**Confirmed by**: [`ci.yml`](https://github.com/MFSGA/Chimera_Client/blob/master/.github/workflows/ci.yml) matrix `include:` section.
The block for `aarch64-unknown-linux-musl` simply does not exist.

### What Must Change Upstream

#### 1.1 Add CI Build Matrix Entry

Add the following entry to the `strategy.matrix.include` list in `ci.yml`:

```yaml
- os: ubuntu-latest
  target: aarch64-unknown-linux-musl
  tool: cross
  extra-args: -F "perf"
  zig: "2.17"
```

**Rationale**: The existing `aarch64-unknown-linux-gnu` entry already demonstrates
that aarch64 cross-compilation works with `cross` + `zig`. The musl variant needs
the same treatment. The `perf` feature flag is used for the musl build
(consistent with the x86_64-musl entry), as opposed to `plus` used for gnu targets.

**Key differences from the gnu entry**:
- `extra-args`: Use `-F "perf"` instead of `-F "plus"` (matching x86_64-musl convention)
- The musl target links against musl libc instead of glibc, which may require
  different `cross` Docker images or zig toolchain settings
- If `zig: "2.17"` alone is insufficient for musl, the build may need `CROSS_BUILD_ZIG`
  combined with a cross-compilation Docker image that includes musl cross-toolchains
  (see [`cross-rs/cross`](https://github.com/cross-rs/cross) — musl targets use
  the `ghcr.io/cross-rs/aarch64-unknown-linux-musl:<toolchain>` image)

#### 1.2 Verify Artifact Upload

The existing CI pipeline already handles artifact upload generically:
- The `Upload binaries` step uploads every matrix entry's binary.
- The `release` job merges, hashes, and publishes all artifacts.

**No pipeline changes needed** for artifact publication — the new matrix entry
will automatically be included in the release assets.

#### 1.3 Artifact Naming

The resulting artifact will follow the existing convention:

```
clash_chimera-aarch64-unknown-linux-musl
```

**Expected location** (for tag `vX.Y.Z`):
```
https://github.com/MFSGA/Chimera_Client/releases/download/vX.Y.Z/clash_chimera-aarch64-unknown-linux-musl
```

### How to Verify Tier 1 Is Complete

1. A new release (or the `latest` pre-release) includes the file
   `clash_chimera-aarch64-unknown-linux-musl`.
2. The file is executable on an `aarch64` Linux system with musl libc.
3. `file clash_chimera-aarch64-unknown-linux-musl` reports:
   `ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked`
   (or dynamically linked against musl, not glibc).
4. `sha256sum` of the artifact is recorded for downstream verification.

---

## Tier 2 — Package Makefile Changes (OpenChimera)

### Current State

`chimera-core/Makefile` currently has a single download target:

```makefile
PKG_SOURCE:=clash_chimera-x86_64-unknown-linux-musl
PKG_SOURCE_URL:=https://github.com/MFSGA/Chimera_Client/releases/download/$(PKG_SOURCE_VERSION)
PKG_HASH:=850c949dc0176da3d5b57cb78f2e903cbe8823703c819c402f02ca16dea434d0
```

This approach works for x86_64 only because OpenWrt's `PKG_SOURCE` does not
natively support per-architecture source selection. The current Makefile has no
conditional logic for different targets.

### What Must Change in the Makefile

#### 2.1 Add Per-Architecture Source/Hash Logic

The Makefile must detect the target architecture at build time and select the
correct artifact. OpenWrt provides `$(ARCH)` (e.g., `x86_64`, `aarch64`) and
`$(SUBTARGET)` (e.g., `cortex-a53`, `generic`) variables.

**Recommended approach**: Use a `ifneq ($(filter aarch64%,$(ARCH)),)` conditional
to set architecture-specific variables:

```makefile
# --- Per-architecture artifact selection ---
# x86_64 (musl) — default
PKG_SOURCE:=clash_chimera-x86_64-unknown-linux-musl
PKG_HASH:=850c949dc0176da3d5b57cb78f2e903cbe8823703c819c402f02ca16dea434d0

# aarch64 (musl) — enable once upstream artifact is verified
# ifneq ($(filter aarch64%,$(ARCH)),)
#   PKG_SOURCE:=clash_chimera-aarch64-unknown-linux-musl
#   PKG_HASH:=<SHA256_HASH_GOES_HERE>
# endif
# ---
```

**Note**: The aarch64 block is **commented out** — it must remain commented until
a verified upstream artifact is published and its hash is confirmed.

#### 2.2 Dual Download Approach (Alternative)

If the upstream CI acquires multiple architectures over time, an alternative
pattern uses OpenWrt's `Package/chimera-core` `DEPENDS` and per-architecture
`Package/chimera-core-$(ARCH)` variants. However, the `PKG_SOURCE` conditional
approach above is simpler and matches how other OpenWrt prebuilt-binary packages
handle multi-architecture downloads (e.g., `mihomo-meta`, `v2ray-core`).

#### 2.3 Update Package Metadata

No changes to `Package/chimera-core/description`, `PROVIDES`, or `ALTERNATIVES`
are needed — the binary is installed to the same paths (`/usr/libexec/chimera`,
exposed as `/usr/bin/mihomo`) regardless of architecture.

### What Must NOT Change

- **Do NOT uncomment or activate the aarch64 block** until the upstream artifact
  is verified (Tier 1 complete + hash confirmed).
- **Do NOT remove the x86_64 default** — x86_64 remains the primary supported
  architecture even after aarch64 is enabled.
- **Do NOT change `PKG_SOURCE_URL`** — the URL pattern is the same for all
  architectures; only the filename and hash differ.

### AARCH64_README

A placeholder `AARCH64_README` file (or a comment block in the Makefile) should
be added to document:

```
# aarch64 enablement (deferred):
#   1. Upstream CI must add aarch64-unknown-linux-musl to the build matrix
#      (see docs/aarch64-enablement.md for details)
#   2. Compute SHA256 of the published artifact
#   3. Uncomment the aarch64 block below and insert the hash
#   4. Run SDK compile QA for aarch64 OpenWrt target
#   5. Run install + runtime QA on an aarch64 OpenWrt device
```

---

## Tier 3 — QA Verification (OpenChimera)

Once Tiers 1 and 2 are complete, aarch64 support must be verified through the
same QA pipeline that x86_64 uses, adapted for the aarch64 target.

### 3.1 SDK Build (aarch64)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.1.1 | Obtain OpenWrt SDK for `aarch64` (e.g., `openwrt-sdk-aarch64_cortex-a53-*.tar.xz`) | SDK extracts and `make info` succeeds |
| 3.1.2 | Add OpenChimera feed, `feeds update -a`, `feeds install -a` | Feeds install without errors |
| 3.1.3 | `make package/chimera-core/compile V=s` | Exit 0; downloads aarch64 musl binary |
| 3.1.4 | `make package/openchimera/compile V=s` | Exit 0; produces `.ipk` |
| 3.1.5 | `ls bin/packages/aarch64_*/openchimera/*.ipk` | Both `.ipk` files present |

**Evidence**: Save output per `docs/qa-checklist.md` Section 2 convention.

### 3.2 Package Install (aarch64 OpenWrt Device)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.2.1 | Copy `.ipk` files to aarch64 OpenWrt device | Files transferred |
| 3.2.2 | `opkg install chimera-core_*.ipk` | Installed; no dependency errors |
| 3.2.3 | `opkg install openchimera_*.ipk` | Installed; no dependency errors |

### 3.3 Binary Verification

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.3.1 | `file /usr/libexec/chimera` | `ELF 64-bit LSB executable, ARM aarch64` |
| 3.3.2 | `ldd /usr/libexec/chimera` (if dynamic) | Links against musl, NOT glibc |
| 3.3.3 | `/usr/bin/mihomo -V` | Prints Chimera/clash-rs version string |
| 3.3.4 | `ls -la /usr/bin/mihomo` | Symlinks to `/usr/libexec/chimera` |

### 3.4 Config Validation

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.4.1 | Write valid config; `/usr/bin/mihomo -t -d <dir> -c <file>` | Exit 0; test successful |
| 3.4.2 | Write invalid config; run test | Exit non-zero; error message |
| 3.4.3 | Write malformed YAML; run test | Exit non-zero; parse error |

### 3.5 Service Lifecycle

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.5.1 | Enable, start service | Process runs; PID captured |
| 3.5.2 | Stop service | Process terminates |
| 3.5.3 | Restart service | PID changes or process cleanly restarts |
| 3.5.4 | Disabled → start | No process spawned |
| 3.5.5 | Invalid config → start | No process; error logged |

### 3.6 Proxy Functionality

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.6.1 | `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10` | Exit 0; HTTP response returned |
| 3.6.2 | Bad request (`nonexistent.invalid`) | Daemon does not crash |

### 3.7 SDK Branch Coverage

The aarch64 QA should be repeated across at least the primary OpenWrt SDK branch:

| SDK Branch | Priority | Reason |
|------------|----------|--------|
| `openwrt-24.10` | Required | Primary milestone target |
| `openwrt-25.12` | Recommended | Next stable |
| `SNAPSHOT` | Optional | Latest toolchain |

---

## Risk Assessment

### R1: Different musl Version

**Risk**: The upstream CI uses `cross-rs/cross` Docker images with a specific musl
toolchain version. The OpenWrt SDK ships its own musl cross-toolchain
(musl-targeting `gcc`). If the musl versions differ significantly, the compiled
binary may exhibit ABI mismatches or runtime issues.

**Mitigation**:
- Confirm that the upstream binary is **statically linked** where possible
  (musl supports static linking well). If static, musl version mismatch is
  irrelevant — the binary carries its own libc.
- If dynamically linked, verify `ldd` output on the target OpenWrt device shows
  only musl-linked dependencies.
- Test critical features (DNS resolution, TLS, TUN) on an aarch64 OpenWrt device
  before releasing.

**Severity**: Medium

### R2: Different Kernel Headers

**Risk**: The upstream CI builds against Linux kernel headers from the `cross`
Docker image (typically recent Ubuntu). OpenWrt devices may run older kernels
(e.g., 5.15, 6.1, 6.6). If the binary uses kernel features not present in older
kernels, it may fail at runtime.

**Mitigation**:
- Upstream should target the oldest reasonable kernel for cross-compilation
  (e.g., `--kernel 5.10` or use musl's `__OLDKERNEL` if applicable).
- Runtime QA on a representative aarch64 OpenWrt device (kernel 6.1 or 6.6)
  should catch any compatibility issues.

**Severity**: Low

### R3: TUN Compatibility

**Risk**: TUN proxy mode on aarch64 may behave differently due to:
- Different endianness behavior in TUN packet parsing
- Different alignment requirements for packet headers
- Kernel module availability (`kmod-tun` is available for aarch64, but
  architecture-specific issues may exist)

**Mitigation**:
- Run the TUN proxy test from the QA checklist on an aarch64 device.
- Verify that `kmod-tun` is loadable and functional.
- Test with both `tun_enabled=0` (non-TUN) and `tun_enabled=1`.

**Severity**: Low-Medium

### R4: Cross-Compilation Toolchain Upstream

**Risk**: Adding `aarch64-unknown-linux-musl` to the upstream CI matrix may
require a `cross` Docker image that doesn't exist yet. The `cross-rs/cross`
project maintains prebuilt images for many targets, but `aarch64-unknown-linux-musl`
needs confirmation.

**Status**: The `cross` project does provide:
- `ghcr.io/cross-rs/aarch64-unknown-linux-musl:main` — confirmed available for
  `cross`-based musl cross-compilation to aarch64.

So this risk is **low**, but the specific zig version compatibility needs
verification.

**Severity**: Low

### R5: Performance Differences

**Risk**: aarch64 builds may have different performance characteristics than
x86_64. Memory usage, throughput, and latency should be benchmarked if
performance is a requirement.

**Mitigation**: Not a blocker for enablement, but document as a known variable.
Add a performance benchmark step if aarch64 is expected to be a primary platform.

**Severity**: Low (informational)

---

## Concrete Action Checklist

### Tier 1 — Upstream (Chimera_Client repo)

- [ ] **1a**: Add `aarch64-unknown-linux-musl` to `ci.yml` build matrix with
      `tool: cross`, `extra-args: -F "perf"`, `zig: "2.17"`
- [ ] **1b**: Verify CI build passes for the new matrix entry
- [ ] **1c**: Confirm artifact `clash_chimera-aarch64-unknown-linux-musl` appears
      in release assets
- [ ] **1d**: Record `sha256sum` of the published artifact
- [ ] **1e**: Confirm binary is musl-linked (`ldd` shows no glibc references;
      `file` shows ARM aarch64)

### Tier 2 — Package (OpenChimera repo)

- [ ] **2a**: Add conditional aarch64 block in `chimera-core/Makefile`
      (commented out initially)
- [ ] **2b**: Insert verified `PKG_HASH` for `clash_chimera-aarch64-unknown-linux-musl`
- [ ] **2c**: Uncomment the aarch64 block
- [ ] **2d**: Update `docs/arch-matrix.md` to change aarch64-musl status from
      ⏳ Deferred to ✅ Supported
- [ ] **2e**: Update `openchimera/arch-matrix.md` to match (if still maintained)
- [ ] **2f**: Update `README.md` architecture support table

### Tier 3 — QA (OpenChimera repo)

- [ ] **3a**: Obtain aarch64 OpenWrt SDK (`openwrt-sdk-aarch64_*-*.tar.xz`)
- [ ] **3b**: Run SDK compile QA (build both packages for aarch64)
- [ ] **3c**: Install `.ipk` files on aarch64 OpenWrt device
- [ ] **3d**: Verify binary identity (`file`, `ldd`, `-V`)
- [ ] **3e**: Run config validation tests (valid, invalid, malformed)
- [ ] **3f**: Run service lifecycle tests (start, stop, restart, disabled, invalid)
- [ ] **3g**: Run mixed-port proxy test
- [ ] **3h**: Run TUN mode test (if applicable)
- [ ] **3i**: Save all QA evidence per `docs/qa-checklist.md` convention
- [ ] **3j**: Add aarch64 QA scenarios to `docs/qa-checklist.md`

---

## Appendix A: Reference Artifacts

### Current x86_64-musl Reference (v0.21.1)

| Property | Value |
|----------|-------|
| Artifact | `clash_chimera-x86_64-unknown-linux-musl` |
| SHA256 | `850c949dc0176da3d5b57cb78f2e903cbe8823703c819c402f02ca16dea434d0` |
| Size | 14.8 MB |
| URL | `https://github.com/MFSGA/Chimera_Client/releases/download/v0.21.1/clash_chimera-x86_64-unknown-linux-musl` |

### Current aarch64-gnu Reference (v0.21.1)

| Property | Value |
|----------|-------|
| Artifact | `clash_chimera-aarch64-unknown-linux-gnu` |
| SHA256 | (to be re-verified when aarch64 is enabled) |
| Size | (to be re-verified) |
| URL | `https://github.com/MFSGA/Chimera_Client/releases/download/v0.21.1/clash_chimera-aarch64-unknown-linux-gnu` |
| **⚠️ gnu-linked** | **Incompatible with OpenWrt musl** — do not use |

### Target aarch64-musl (when available)

| Property | Value |
|----------|-------|
| Artifact | `clash_chimera-aarch64-unknown-linux-musl` |
| SHA256 | **TBD** — record from upstream release |
| Size | **TBD** |
| URL | `https://github.com/MFSGA/Chimera_Client/releases/download/vX.Y.Z/clash_chimera-aarch64-unknown-linux-musl` |

---

## Appendix B: OpenWrt SDK Targets for aarch64

The OpenWrt build system uses `ARCH` and `SUBTARGET` variables that map to
specific toolchain configurations. The following aarch64 targets are relevant:

| OpenWrt Target | `ARCH` | `SUBTARGET` | Notes |
|----------------|--------|-------------|-------|
| `aarch64_generic` | `aarch64` | `generic` | Broadest compatibility; no arch-specific optimizations |
| `aarch64_cortex-a53` | `aarch64` | `cortex-a53` | Optimized for Cortex-A53 (RPi 3/4, many routers) |
| `aarch64_cortex-a72` | `aarch64` | `cortex-a72` | Optimized for Cortex-A72 (RPi 4B, higher-end) |
| `aarch64_cortex-a76` | `aarch64` | `cortex-a76` | Optimized for Cortex-A76 (newer devices) |

**Recommendation**: Start with `aarch64_generic` for maximum compatibility.
Subtarget-specific optimizations can be added later.

The Makefile conditional should match on `ARCH` only (`aarch64`), not on
`SUBTARGET`, since the upstream artifact is a generic aarch64 binary:

```makefile
ifneq ($(filter aarch64%,$(ARCH)),)
  # aarch64 (any subtarget) uses the generic aarch64 musl artifact
  PKG_SOURCE:=clash_chimera-aarch64-unknown-linux-musl
  PKG_HASH:=<confirmed-sha256>
endif
```

---

## Appendix C: CI YAML Reference (Upstream)

Relevant section of upstream `ci.yml` for context. The `matrix.include` list
grows by one entry when aarch64-musl is added:

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      # ... existing entries ...

      # NEW: aarch64 musl (blocked — add when ready)
      # - os: ubuntu-latest
      #   target: aarch64-unknown-linux-musl
      #   tool: cross
      #   extra-args: -F "perf"
      #   zig: "2.17"
```

The `Release` job does not need modification — it merges and publishes all
artifacts from the compile matrix generically.
