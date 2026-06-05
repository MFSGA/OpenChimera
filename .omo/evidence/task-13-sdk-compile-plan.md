# Task 13 — SDK Compile QA Plan

## Overview

Verify that `chimera-core` and `openchimera` compile successfully using the
x86_64 OpenWrt SDK. This plan documents the exact procedure, expected outputs,
and verification steps.

> **Status**: Plan only (SDK not executed in this environment).
> **Target architecture**: `x86_64` (musl) — Milestone 1.
> **aarch64**: NOT included in milestone 1 (deferred).
> **Upstream release**: `v0.20.2` — pinned in `chimera-core/Makefile`.

---

## 1. Prerequisites

### 1.1 OpenWrt SDK

| Item | Value |
|---|---|
| SDK archive | `openwrt-sdk-x86_64-gcc-13.x_musl.Linux-x86_64.tar.xz` |
| Source | https://downloads.openwrt.org/releases/24.10/targets/x86/64/ |
| Host OS | Linux (Debian/Ubuntu or Fedora/RHEL recommended) |
| Free disk space | ≥ 10 GB |

### 1.2 Host packages

**Debian/Ubuntu:**
```
sudo apt install build-essential libncurses-dev zlib1g-dev
```

**Fedora/RHEL:**
```
sudo dnf install gcc gcc-c++ make ncurses-devel zlib-devel
```

General requirements: `gcc`, `g++`, `make`, `patch`, `git`, `wget`, `xz-utils`, `zstd`.

### 1.3 Network access

- Required — the SDK downloads toolchain packages on first build.
- `chimera-core` downloads a prebuilt binary (~15 MB) from GitHub Releases.
- Git clone of `https://github.com/MFSGA/OpenChimera.git` for feed setup.

### 1.4 No Rust toolchain needed

- `chimera-core` uses a **prebuilt binary** (`clash_chimera-x86_64-unknown-linux-musl`).
- `openchimera` is shell scripts, UCI config, and init scripts — no compilation.
- Rust/Cargo are NOT required inside the SDK.

---

## 2. Package Source Details

### 2.1 chimera-core (`chimera-core/Makefile`)

| Field | Value |
|---|---|
| `PKG_NAME` | `chimera-core` |
| `PKG_VERSION` | `0.20.2` |
| `PKG_SOURCE` | `clash_chimera-x86_64-unknown-linux-musl` |
| `PKG_SOURCE_URL` | `https://github.com/MFSGA/Chimera_Client/releases/download/v0.20.2` |
| `PKG_HASH` | `532166cad0154158d9a23272341acb6a5256bf750ab35454cdb571608ff11df4` |
| `PKG_SOURCE_VERSION` | `v0.20.2` |
| `PROVIDES` | `mihomo` (virtual provider) |

### 2.2 PKG_HASH verification

The SHA-256 hash `532166cad...` is computed from the upstream binary artifact
`clash_chimera-x86_64-unknown-linux-musl`. The OpenWrt build system
automatically verifies the hash after download via the `Download/Verify` step.

To verify the hash manually (outside the SDK):
```shell
sha256sum clash_chimera-x86_64-unknown-linux-musl
# Expected: 532166cad0154158d9a23272341acb6a5256bf750ab35454cdb571608ff11df4
```

### 2.3 openchimera (`openchimera/Makefile`)

| Field | Value |
|---|---|
| `PKG_NAME` | `openchimera` |
| `PKG_VERSION` | `2026.06.06` |
| `PKG_RELEASE` | `1` |
| `DEPENDS` | `+mihomo +curl +yq +coreutils-base64` |
| Conffiles | `/etc/config/openchimera` |

---

## 3. Step-by-Step Build Procedure

### Step 3.1 — Extract SDK

```shell
tar -xf openwrt-sdk-x86_64-gcc-13.x_musl.Linux-x86_64.tar.xz
cd openwrt-sdk-*/
```

**Expected result**: Directory `openwrt-sdk-*/` exists with `scripts/feeds`,
`Makefile`, `package/`, etc.

**Verification**:
```shell
ls scripts/feeds   # should exist
make info | head -5   # should print target/subtarget/Linux version
```

### Step 3.2 — Add OpenChimera feed

```shell
echo "src-git openchimera https://github.com/MFSGA/OpenChimera.git;main" >> "feeds.conf.default"
```

**Expected result**: A new line is appended to `feeds.conf.default`.

**Verification**:
```shell
tail -1 feeds.conf.default
# Output: src-git openchimera https://github.com/MFSGA/OpenChimera.git;main
```

### Step 3.3 — Update feeds

```shell
./scripts/feeds update -a
```

**Expected result**: The `openchimera` feed is cloned. Output includes:
```
Update feed 'openchimera' from https://github.com/MFSGA/OpenChimera.git;main ...
```

**Expected exit code**: `0`

**Verification**: Check feed directory exists:
```shell
ls feeds/openchimera/
# Should show: chimera-core/  openchimera/  README.md  ...
```

### Step 3.4 — Install feeds

```shell
./scripts/feeds install -a
```

**Expected result**: Package Makefiles are symlinked into `package/feeds/openchimera/`.

**Expected exit code**: `0`

**Verification**:
```shell
ls package/feeds/openchimera/
# Should show: chimera-core/  openchimera/
ls package/feeds/openchimera/chimera-core/Makefile   # should exist
ls package/feeds/openchimera/openchimera/Makefile     # should exist
```

### Step 3.5 — Compile chimera-core

```shell
make package/chimera-core/compile V=s
```

**What happens**:
1. `Download` step: fetches `clash_chimera-x86_64-unknown-linux-musl` from
   `https://github.com/MFSGA/Chimera_Client/releases/download/v0.20.2/`
2. `Verify` step: SHA-256 hash check against `PKG_HASH`.
3. `Prepare` step: copies the binary into `$(PKG_BUILD_DIR)/chimera`.
4. `Install` step: creates `/usr/libexec/chimera` in staging dir.
5. Package index step: generates `.ipk`.

**Expected exit code**: `0`

**Expected output (end of build)**:
```
Package chimera-core is compiled
```

### Step 3.6 — Compile openchimera

**Precondition**: `chimera-core` must be built first (or at least downloaded),
because `openchimera` depends on `mihomo` (provided by `chimera-core`).

```shell
make package/openchimera/compile V=s
```

**What happens**:
1. No download step (no remote sources).
2. Installs files from `openchimera/files/` into staging dir.
3. Generates `.ipk`.

**Expected exit code**: `0`

**Expected output (end of build)**:
```
Package openchimera is compiled
```

### Step 3.7 — Verify .ipk output

```shell
ls -la bin/packages/x86_64/openchimera/
```

**Expected output** (two `.ipk` files + package index):
```
chimera-core_0.20.2-1_x86_64.ipk
openchimera_2026.06.06-1_x86_64.ipk
Packages.gz
Packages.manifest
Packages.sig
```

**Verification**:
```shell
# Check file types
file bin/packages/x86_64/openchimera/chimera-core_0.20.2-1_x86_64.ipk
# Expected: gzip compressed data

# Check package metadata
tar -xzf bin/packages/x86_64/openchimera/chimera-core_0.20.2-1_x86_64.ipk -O ./control.tar.gz | tar -tz
# Expected: control, conffiles, etc.
```

### Step 3.8 — Clean and rebuild (optional)

```shell
make package/chimera-core/clean
make package/openchimera/clean
make package/chimera-core/compile V=s
make package/openchimera/compile V=s
```

---

## 4. Expected Output Paths

| Artifact | Path |
|---|---|
| chimera-core .ipk | `bin/packages/x86_64/openchimera/chimera-core_0.20.2-1_x86_64.ipk` |
| openchimera .ipk | `bin/packages/x86_64/openchimera/openchimera_2026.06.06-1_x86_64.ipk` |
| Package index | `bin/packages/x86_64/openchimera/Packages.gz` |
| Package manifest | `bin/packages/x86_64/openchimera/Packages.manifest` |
| Package signature | `bin/packages/x86_64/openchimera/Packages.sig` |

---

## 5. Verification Checklist

| # | Check | Method | Expected |
|---|---|---|---|
| 1 | SDK extracts cleanly | `tar -xf` | Exit 0, directory created |
| 2 | SDK is functional | `make info \| head -5` | Prints target info, no errors |
| 3 | Feed added to config | `tail -1 feeds.conf.default` | `src-git openchimera https://github.com/MFSGA/OpenChimera.git;main` |
| 4 | Feeds update succeeds | `./scripts/feeds update -a` | Exit 0, feed cloned |
| 5 | Feeds install succeeds | `./scripts/feeds install -a` | Exit 0, symlinks created |
| 6 | chimera-core compile succeeds | `make package/chimera-core/compile V=s` | Exit 0, "is compiled" message |
| 7 | openchimera compile succeeds | `make package/openchimera/compile V=s` | Exit 0, "is compiled" message |
| 8 | chimera-core .ipk exists | `ls -la bin/packages/x86_64/openchimera/chimera-core_*.ipk` | File exists, non-zero size |
| 9 | openchimera .ipk exists | `ls -la bin/packages/x86_64/openchimera/openchimera_*.ipk` | File exists, non-zero size |
| 10 | Package index exists | `ls bin/packages/x86_64/openchimera/Packages.gz` | File exists |
| 11 | No build errors in V=s log | `grep -i "error\|fail\|missing"` on build output | No unexpected errors |

---

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `feeds update` fails with "Could not resolve host" | No network access | Check internet connectivity and DNS resolution |
| `chimera-core` fails with "Download failed" or hash mismatch | Upstream release URL changed, or PKG_HASH outdated | Verify the tag in `chimera-core/Makefile` matches an existing release on `github.com/MFSGA/Chimera_Client/releases`; re-compute `sha256sum` and update `PKG_HASH` if binary changed |
| `openchimera` fails with "Package mihomo is missing" | `chimera-core` not built yet, or feed not installed | Run `./scripts/feeds install -a` then build `chimera-core` first |
| `make` fails with "No rule to make target" | Feed not installed | Ensure `./scripts/feeds install -a` ran without errors |
| `.ipk` not found in output | Package compile failed silently | Re-run with `V=s` and check for error messages; look for "ERROR" or "make[3]" failure lines |
| Hash mismatch on chimera-core | Upstream artifact changed (new build with same tag) | Recompute hash: `wget <url> && sha256sum <file>`; update `PKG_HASH` in `chimera-core/Makefile` |

---

## 7. Architecture Notes

- **x86_64 (musl)**: ✅ Supported (Milestone 1).
- **aarch64 (musl)**: ⏳ **NOT included** in milestone 1. Deferred until upstream
  publishes `aarch64-unknown-linux-musl` artifacts.
- **x86_64 (gnu)**: ❌ Excluded — glibc-linked binaries cannot run on OpenWrt musl.
- **aarch64 (gnu)**: ❌ Excluded — glibc-linked binaries cannot run on OpenWrt musl.

---

## 8. References

- [OpenWrt SDK documentation](https://openwrt.org/docs/guide-developer/using_the_sdk)
- [docs/sdk-build.md](../../docs/sdk-build.md) — Full SDK build instructions
- [chimera-core/Makefile](../../chimera-core/Makefile) — PKG_HASH, PKG_SOURCE_URL
- [openchimera/Makefile](../../openchimera/Makefile) — Package metadata
- [Chimera_Client releases](https://github.com/MFSGA/Chimera_Client/releases) — Upstream v0.20.2
