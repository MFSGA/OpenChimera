# SDK Build — OpenChimera

Build `chimera-core` and `openchimera` using the OpenWrt x86_64 SDK.

> **Milestone 1**: x86_64 only. No hosted opkg feed is available yet — the SDK build
> is the primary installation method.

## Prerequisites

- **OpenWrt SDK** for `x86_64` — download from
  [downloads.openwrt.org](https://downloads.openwrt.org/releases/):
  - OpenWrt 24.10 or later recommended
  - Look for `openwrt-sdk-x86_64-*.tar.zst` (e.g.,
    `openwrt-sdk-x86_64-gcc-13.x_musl.Linux-x86_64.tar.xz`)
- **Linux host** with standard build tools:
  - `gcc`, `g++`, `make`, `patch`, `git`, `wget`, `xz-utils`, `zstd`
  - On Debian/Ubuntu: `sudo apt install build-essential libncurses-dev zlib1g-dev`
  - On Fedora/RHEL: `sudo dnf install gcc gcc-c++ make ncurses-devel zlib-devel`
- **At least 10 GB** free disk space (the SDK + build artifacts are large)

### SDK setup

```shell
# Extract the SDK (adjust the filename to match your download)
tar -xf openwrt-sdk-x86_64-gcc-13.x_musl.Linux-x86_64.tar.xz
cd openwrt-sdk-*/

# Verify the SDK is functional
make info | head -5
```

## Feed setup

Add the OpenChimera feed to the SDK's `feeds.conf.default`:

```shell
echo "src-git openchimera https://github.com/MFSGA/OpenChimera.git;main" >> "feeds.conf.default"
```

> **What this does**: `src-git` tells the OpenWrt build system to clone the
> OpenChimera repository as a feed. The `;main` suffix pins to the `main` branch.
> The feed automatically registers both `chimera-core` and `openchimera` packages.

## Update and install feeds

```shell
./scripts/feeds update -a
./scripts/feeds install -a
```

- `update -a` fetches all feeds listed in `feeds.conf.default` (including the
  newly added OpenChimera feed).
- `install -a` symlinks all package Makefiles from each feed into the SDK's
  `package/` tree, making them available for compilation.

## Compile packages

Build both packages individually:

```shell
# Build chimera-core (prebuilt binary download)
make package/chimera-core/compile V=s

# Build openchimera (management layer depends on chimera-core's mihomo provider)
make package/openchimera/compile V=s
```

> The `V=s` flag enables verbose output so you can monitor progress and diagnose
> issues. Omit `V=s` for quieter builds once everything works.

### Build order notes

- `chimera-core` and `openchimera` can technically be built in any order because
  the dependency (`mihomo` virtual provider) is resolved at install time, not
  build time. However, building `chimera-core` first is recommended so both
  `.ipk` files are available at the end.

### Cleaning and rebuilding

```shell
# Clean a single package
make package/chimera-core/clean
make package/openchimera/clean

# Rebuild after cleaning
make package/chimera-core/compile V=s
make package/openchimera/compile V=s
```

## Package output

Compiled `.ipk` files appear under:

```
bin/packages/x86_64/openchimera/
```

List them:

```shell
ls -la bin/packages/x86_64/openchimera/
```

Typical output:

```
chimera-core_0.20.2-1_x86_64.ipk
openchimera_2026.06.06-1_x86_64.ipk
```

## Installation on device

Copy the `.ipk` files to your OpenWrt device and install:

```shell
# On the build host (scp to the router)
scp bin/packages/x86_64/openchimera/*.ipk root@192.168.1.1:/tmp/

# On the OpenWrt device
opkg install /tmp/chimera-core_*.ipk /tmp/openchimera_*.ipk
```

> Dependencies (`ca-bundle`, `curl`, `yq`, `kmod-tun`, `ip-full`, etc.) are
> resolved from the standard OpenWrt repositories. Your device needs network
> access to `downloads.openwrt.org` (or a configured mirror).

## Build notes

### Network access required

- `chimera-core` downloads a prebuilt `clash_chimera` binary from
  `github.com/MFSGA/Chimera_Client` during the build step. The build host must
  have internet access.
- The SDK itself may also download source archives and dependencies on first
  build.

### No Rust toolchain needed

- `chimera-core` uses a **prebuilt binary** — no Rust compiler or Cargo
  dependencies are required inside the SDK.
- `openchimera` is a collection of shell scripts, UCI config files, and init
  scripts — no compilation step at all.

### x86_64 only

- Milestone 1 targets `x86_64` (musl) exclusively.
- Hosted artifacts from upstream Chimera_Client are only available for
  `x86_64-unknown-linux-musl` at this time.
- Other architectures (aarch64, etc.) are deferred to later milestones.

### First build time

The first SDK build can take a while because:
1. The SDK may need to download toolchain and target packages.
2. `chimera-core` downloads the upstream binary (~15 MB).
3. Subsequent builds are much faster — only the package directories are recompiled.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `feeds update` fails with "Could not resolve host" | No network access | Check internet connectivity and DNS resolution |
| `chimera-core` fails with "Download failed" | Upstream release URL changed | Verify the tag in `chimera-core/Makefile` matches an existing release on the upstream repo |
| `openchimera` fails with "Package mihomo is missing" | `chimera-core` not built yet, or feed not installed | Run `./scripts/feeds install -a` then build `chimera-core` first |
| `make` fails with "No rule to make target" | Feed not installed | Ensure `./scripts/feeds install -a` ran without errors |
| `.ipk` not found in output | Package compile failed silently | Re-run with `V=s` and check for error messages |
