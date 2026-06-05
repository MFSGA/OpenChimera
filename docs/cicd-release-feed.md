# CI/CD Release Feed — Design Document

> **Status**: Design proposal — deferred to later milestone
> **Milestone**: Post-M1 (not in milestone 1 scope)
> **References**:
> - [SDK Build](sdk-build.md) — local SDK build workflow
> - [Architecture Matrix](arch-matrix.md) — target architecture planning
> - [aarch64 Enablement](aarch64-enablement.md) — aarch64 path
> - [feed.sh](../feed.sh) — feed registration placeholder script
> - [Nikki reference workflow](../.ref/OpenWrt-nikki/.github/workflows/build-packages.yml)
> - [openwrt/gh-action-sdk](https://github.com/openwrt/gh-action-sdk) — official SDK CI action

---

## 1. Overview

This document describes the design for an automated CI/CD pipeline that builds
OpenChimera packages and publishes them as a hosted OpenWrt opkg feed.

The pipeline eliminates the current manual SDK build workflow (documented in
[sdk-build.md](sdk-build.md)) by:

1. Automatically building `chimera-core` and `openchimera` on tag pushes and
   manual dispatch.
2. Producing a standards-compliant opkg feed directory with `Packages.gz`,
   `Packages.sig`, and `.ipk` artifacts.
3. Publishing the feed to a publicly accessible HTTPS endpoint so users can
   install OpenChimera via `opkg install` directly on their OpenWrt devices.

### 1.1 Design principles

| Principle | Rationale |
|-----------|-----------|
| **Feed-first** | The primary artifact is a usable opkg feed, not individual `.ipk` downloads. Users add one line to `customfeeds.conf` and get updates automatically. |
| **Reproducible** | Tag builds pin the upstream `chimera-core` binary version. Every tag produces a deterministic feed with verifiable hashes. |
| **Secure by default** | Feed index is signed with a usign key. Users verify package integrity before installation. |
| **Incremental architecture** | Start with `x86_64`; add `aarch64` and other targets in later iterations. |
| **Low infrastructure** | Use GitHub Actions for build, GitHub Releases + GitHub Pages for hosting. No external servers required. |

### 1.2 Relationship to milestone 1

Milestone 1 provides a **local SDK build** workflow. The CI/CD feed is a
quality-of-life improvement that makes installation trivial for end users.
It is intentionally deferred because:

- The SDK build workflow is functional and well-documented.
- The package set is small (two packages) — the overhead of a hosted feed is
  not justified until the user base grows or more architectures are supported.
- Feed hosting requires additional CI secrets management (signing keys) and
  a hosting decision that should be informed by real usage patterns.

---

## 2. GitHub Actions Workflow Structure

### 2.1 Workflow file

The pipeline lives in a single workflow file:

```
.github/workflows/release-feed.yml
```

### 2.2 Trigger configuration

```yaml
on:
  push:
    tags:
      - 'v*'                # e.g., v0.1.0, v0.2.0
  workflow_dispatch:        # manual trigger for testing
    inputs:
      openwrt_branch:
        description: 'OpenWrt branch (e.g., openwrt-24.10, SNAPSHOT)'
        required: true
        default: 'openwrt-24.10'
      architectures:
        description: 'Space-separated arch list (e.g., x86_64)'
        required: true
        default: 'x86_64'
```

**Rationale**:

- **Tag push (`v*`)**: The primary release trigger. A new tag means a new
  release. The workflow builds all supported architectures for that release.
- **`workflow_dispatch`**: Allows maintainers to build a test feed from any
  branch without creating a tag. Useful for testing SDK compatibility before
  cutting a release.
- **No `push` on `main`**: Building on every commit would waste CI minutes and
  generate feed churn. Only tag pushes produce canonical feeds.

### 2.3 Job architecture

```
release-feed.yml
│
├── job: build-matrix
│   ├── strategy.matrix.arch = [x86_64]           # milestone 2
│   │        later: [x86_64, aarch64_cortex-a53, ...]
│   ├── strategy.matrix.branch = [openwrt-24.10]  # milestone 2
│   │        later: [openwrt-24.10, openwrt-25.12, SNAPSHOT]
│   ├── uses: openwrt/gh-action-sdk@main
│   ├── env:
│   │   ├── ARCH = ${{ matrix.arch }}-${{ matrix.branch }}
│   │   ├── FEEDNAME = openchimera
│   │   ├── PACKAGES = chimera-core openchimera
│   │   ├── INDEX = 1
│   │   ├── KEY_BUILD = ${{ secrets.OPKG_SIGN_KEY }}
│   │   └── NO_REFRESH_CHECK = true
│   ├── upload: bin/packages/${{ matrix.arch }}/openchimera/  ← artifact
│   └── upload: Packages.gz, Packages.sig, public.key         ← feed artifacts
│
└── job: publish-feed (needs: build-matrix)
    ├── aggregates all matrix artifacts
    ├── generates combined feed index
    ├── publishes to hosting target
    └── creates GitHub Release with .ipk files
```

### 2.4 Build matrix design

#### Milestone 2 (initial)

| Dimension | Values | Notes |
|-----------|--------|-------|
| `arch` | `x86_64` | Only architecture with upstream musl artifacts |
| `branch` | `openwrt-24.10` | Target LTS release |
| Total combinations | 1 | Single build per release |

#### Later milestones

| Dimension | Values | Notes |
|-----------|--------|-------|
| `arch` | `x86_64`, `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_generic` | Depends on upstream musl artifact availability |
| `branch` | `openwrt-24.10`, `openwrt-25.12`, `SNAPSHOT` | Per OpenWrt release cadence |
| Total combinations | ~12 | Full matrix when all targets are supported |

#### Matrix exclusion rules

```yaml
exclude:
  # aarch64 excluded from 24.10 until upstream publishes musl artifacts
  - arch: aarch64_cortex-a53
    branch: openwrt-24.10
  - arch: aarch64_cortex-a72
    branch: openwrt-24.10
  - arch: aarch64_generic
    branch: openwrt-24.10
```

### 2.5 SDK action environment variables

The workflow uses [`openwrt/gh-action-sdk`](https://github.com/openwrt/gh-action-sdk)
with the following configuration:

| Variable | Value | Purpose |
|----------|-------|---------|
| `ARCH` | `${{ matrix.arch }}-${{ matrix.branch }}` | Selects the correct SDK Docker container |
| `FEEDNAME` | `openchimera` | Namespace for the feed inside `bin/packages/` |
| `PACKAGES` | `chimera-core openchimera` | Build only these two packages (not all packages in feed) |
| `INDEX` | `1` | Generate `Packages.gz` index after build |
| `KEY_BUILD` | `${{ secrets.OPKG_SIGN_KEY }}` | Signing key for `Packages.sig` |
| `NO_REFRESH_CHECK` | `true` | Skip patch refresh check (no patches in either package) |
| `V` | `s` | Verbose build output for debugging |

> **Note on `INDEX=1`**: When enabled, the SDK action runs `make package/index`
> after all packages are compiled. This produces:
> - `Packages` — plaintext index
> - `Packages.gz` — compressed index (consumed by `opkg update`)
> - `Packages.sig` — usign signature over `Packages` (requires `KEY_BUILD`)

### 2.6 Step-by-step workflow (conceptual)

```
1. Trigger: tag push v* or workflow_dispatch
   │
2. Checkout repository
   │
3. [Matrix loop] For each (arch, branch) combination:
   │   ├── Run openwrt/gh-action-sdk
   │   │   ├── Download SDK container (openwrt/sdk:{arch}-{branch})
   │   │   ├── Add openchimera feed (from checked-out repo)
   │   │   ├── Update & install feeds
   │   │   ├── make defconfig
   │   │   ├── Build chimera-core + openchimera
   │   │   ├── make package/index (generates Packages.gz)
   │   │   └── Sign index with KEY_BUILD
   │   │
   │   └── Upload artifacts:
   │       ├── *.ipk files
   │       ├── Packages, Packages.gz, Packages.sig
   │       └── public.key (extracted from signing key)
   │
4. [Aggregate] Combine all matrix artifacts
   │
5. [Publish] Deploy feed to hosting target
   │
6. [Release] Create GitHub Release with .ipk attachments
```

---

## 3. Feed Structure

### 3.1 Directory layout

The hosted feed follows the standard OpenWrt opkg feed layout:

```
https://<feed-base-url>/
├── openwrt-24.10/
│   ├── x86_64/
│   │   ├── Packages              # Plaintext package index
│   │   ├── Packages.gz           # Gzip-compressed index (opkg consumes this)
│   │   ├── Packages.sig          # usign signature (ECDSA over SHA-256)
│   │   ├── public.key            # Public signing key (for user import)
│   │   ├── chimera-core_0.20.2-1_x86_64.ipk
│   │   ├── chimera-core_0.21.0-1_x86_64.ipk
│   │   ├── openchimera_2026.06.06-1_x86_64.ipk
│   │   └── openchimera_2026.07.15-1_x86_64.ipk
│   └── all/                      # Architecture-independent packages (future)
│       └── luci-app-openchimera_*.ipk
├── openwrt-25.12/
│   └── x86_64/
│       └── ...                   # Same structure for 25.12 builds
├── SNAPSHOT/
│   └── x86_64/
│       └── ...
└── openchimera.ked               # Repository metadata (optional, APK future)
```

### 3.2 Multiple versions per feed

A single feed directory contains all historically published versions of each
package. `opkg` resolves the latest compatible version during `opkg update`.
This means users always get the newest package without changing their feed
configuration.

**Note**: Old `.ipk` files are **not** removed when new ones are added. This
preserves the ability to downgrade and maintains reproducible build archives.
A feed cleanup policy (e.g., keep last N versions) can be added later.

### 3.3 Feed registration on device

Users register the feed by running `feed.sh` (see [feed.sh](../feed.sh)) or
manually:

```shell
# On the OpenWrt device:
echo "src/gz openchimera https://<feed-base-url>/openwrt-24.10/x86_64" \
  >> /etc/opkg/customfeeds.conf

# Import the public signing key
wget -qO /tmp/openchimera.pub https://<feed-base-url>/openwrt-24.10/x86_64/public.key
opkg-key add /tmp/openchimera.pub

# Update and install
opkg update
opkg install chimera-core openchimera
```

### 3.4 Feed index format

The `Packages` file follows the standard opkg format. Each package entry
contains:

```
Package: chimera-core
Version: 0.20.2-1
Depends: +ca-bundle +ip-full +kmod-tun
Provides: mihomo
Conflicts: mihomo-meta mihomo-alpha
Status: unknown ok not-installed
Section: net
Architecture: x86_64
Maintainer: OpenChimera Team
Size: 12345678
Filename: chimera-core_0.20.2-1_x86_64.ipk
SHA256sum: abcdef0123456789...
Source: https://github.com/MFSGA/Chimera_Client
License: GPL3.0+
Description: Chimera Client prebuilt binary package for OpenWrt.
```

```
Package: openchimera
Version: 2026.06.06-1
Depends: +mihomo +curl +yq +coreutils-base64
Status: unknown ok not-installed
Section: net
Architecture: x86_64
Maintainer: OpenChimera Contributors
Size: 12345
Filename: openchimera_2026.06.06-1_x86_64.ipk
SHA256sum: 0123456789abcdef...
Source: https://github.com/MFSGA/OpenChimera
License: GPL3.0+
Description: OpenChimera management layer for Chimera client.
```

The `Packages.gz` is simply `gzip -c Packages > Packages.gz`.
The `Packages.sig` is the usign signature: `usign -S -m Packages -s key-build -x Packages.sig`.

---

## 4. Release Flow

### 4.1 Tag → Build → Publish lifecycle

```
┌──────────────────┐
│  Developer tags  │  git tag -a v0.1.0 -m "Release v0.1.0"
│  a release       │  git push origin v0.1.0
└────────┬─────────┘
         │
         ▼
┌───────────────────┐
│  GitHub Actions   │  Triggered by push tag v*
│  release-feed.yml │
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Build matrix     │  SDK build for each (arch, branch)
│  (SDK action)     │  Currently: x86_64 / openwrt-24.10 only
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Sign & index     │  INDEX=1 → Packages.gz + Packages.sig
│  feed             │  KEY_BUILD → usign signature
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Upload artifacts │  GitHub Actions artifact storage
│  (per matrix)     │  ipk files + Packages.gz + .sig + public.key
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Aggregate &      │  Combine all matrix artifacts into a
│  deploy feed      │  single feed tree, deploy to hosting
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  GitHub Release   │  Create release with:
│                   │  - Release notes (auto-generated or manual)
│                   │  - Per-architecture .ipk assets
│                   │  - Public key attachment
│                   │  - SHA256SUMS file
└───────────────────┘
```

### 4.2 Versioning strategy

| Component | Version source | Example |
|-----------|---------------|---------|
| Git tag | Manual / release | `v0.1.0` |
| `chimera-core` | Upstream `PKG_VERSION` in Makefile | `0.20.2` |
| `openchimera` | Date-based `PKG_VERSION` in Makefile | `2026.06.06` |
| Feed URL path | Git tag | `.../v0.1.0/openwrt-24.10/x86_64/...` |

The **Git tag** is the canonical release identifier. The feed is published
under a path that includes the tag so that:
- Users on a specific release pin to a stable tag path.
- The "latest" feed (under an unversioned path like `release/`) points to the
  most recent tag build.
- Historical feeds remain accessible for downgrade.

### 4.3 Snapshot / nightly builds

In addition to tag-based releases, a **nightly** or **snapshot** feed may be
useful for early adopters:

```yaml
on:
  schedule:
    - cron: '0 6 * * *'   # Daily at 06:00 UTC
  workflow_dispatch:        # Manual trigger
```

The snapshot feed publishes to a `snapshot/` path and:
- Builds from the `main` branch HEAD.
- Uses a version string like `2026.06.06-<git-short-hash>`.
- Is **not** signed with the release key (uses a separate snapshot key).
- Is **not** auto-registered via `feed.sh` (users opt in explicitly).

### 4.4 Version pinning during build

When a tag triggers the build, the checked-out `chimera-core/Makefile`
references a specific upstream tag (e.g., `v0.20.2`):

```makefile
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
# This resolves to: https://github.com/MFSGA/Chimera_Client/releases/download/v0.20.2/
```

The `PKG_HASH` in the Makefile ensures the downloaded binary matches the
expected checksum. This means the CI build is **deterministic** — the same tag
always produces the same `.ipk` files (assuming the upstream release doesn't
move its artifacts, which is prevented by the hash check).

---

## 5. Signing and Security

### 5.1 Signing key management

OpenWrt opkg feeds use **usign** (a derivative of OpenBSD signify) for
ECDSA-based feed signing.

```
┌─────────────────────────────┐
│  Generate signing key pair  │  usign -G -s key-build -p key-build.pub
│  (one time, per feed)       │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Store private key in       │  GitHub Actions secret:
│  GitHub Secrets             │  OPKG_SIGN_KEY (contents of key-build)
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  CI workflow uses           │  env.KEY_BUILD = ${{ secrets.OPKG_SIGN_KEY }}
│  KEY_BUILD env var          │  → SDK action signs Packages index
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Public key published       │  public.key at feed root
│  alongside feed             │  Users import via opkg-key add
└─────────────────────────────┘
```

**Key generation** (run locally by a maintainer):

```shell
# Install usign if not present
opkg install usign   # on OpenWrt, or
apt install usign    # on Debian/Ubuntu

# Generate key pair
usign -G -s key-build -p key-build.pub -c "OpenChimera Release Signing Key"

# Add to GitHub Secrets as OPKG_SIGN_KEY
cat key-build
# → copy entire contents into GitHub repo → Settings → Secrets → Actions
```

**Security requirements**:
- The private key **must never** be committed to the repository.
- Regenerate keys periodically (annually recommended).
- Rotate keys if a compromise is suspected — publish a new `public.key` and
  notify users.
- Use separate keys for release vs. snapshot feeds.

### 5.2 Feed verification flow

When a user runs `opkg update` with a signed feed, the verification flow is:

```
1. opkg downloads Packages.gz and Packages.sig
2. opkg decompresses Packages.gz → Packages (plaintext)
3. opkg verifies Packages.sig against Packages using trusted public key
   stored in /etc/opkg/keys/
4. If signature is invalid → feed is rejected, warning displayed
5. If signature is valid → opkg reads package index and caches it
6. During install, opkg verifies:
   a. .ipk file size matches Packages entry
   b. .ipk SHA-256 hash matches Packages entry
7. Only after all checks pass → package is installed
```

### 5.3 Without signing (unsigned feed)

For testing or private feeds, users can disable signature checking:

```
# /etc/opkg.conf
option check_signature 0
```

The CI workflow should support building without `KEY_BUILD` for test runs,
producing an unsigned index (no `Packages.sig`).

### 5.4 Supply chain security considerations

| Concern | Mitigation |
|---------|------------|
| **Compromised upstream binary** | `PKG_HASH` in `chimera-core/Makefile` pins the expected SHA-256. CI build fails if hash doesn't match. |
| **Compromised CI runner** | Use `actions/attest-build-provenance` to generate SLSA provenance attestations for `.ipk` artifacts (see §7). |
| **Compromised signing key** | Key rotation procedure documented. Old public key retained for historical feed verification. |
| **Feed CDN compromise** | End-to-end verification via usign signature + SHA-256 in index. CDN serves data but cannot tamper undetectably. |
| **Man-in-the-middle on opkg download** | `Packages.gz` is authenticated via usign. `.ipk` is verified against SHA-256 in the authenticated index. HTTPS adds transport-layer protection. |

---

## 6. Hosted Feed Options

### 6.1 Evaluation criteria

| Criterion | Importance | Notes |
|-----------|------------|-------|
| HTTPS support | Required | `opkg` requires HTTPS for signature verification |
| Static file hosting | Required | Feed is a static directory tree |
| Custom domain | Nice-to-have | e.g., `feed.openchimera.org` |
| CDN / global edge | Nice-to-have | Users worldwide benefit from low-latency `opkg update` |
| Bandwidth cost | Consider | `.ipk` files are ~15 MB per download |
| Build deployment | Important | Must integrate with GitHub Actions deploy step |

### 6.2 Option comparison

| Option | HTTPS | Static | Custom domain | CDN | Cost | Deploy integration |
|--------|-------|--------|---------------|-----|------|-------------------|
| **GitHub Releases** | ✅ | ✅ | ❌ (URL is github.com) | ❌ | Free | `softprops/action-gh-release` |
| **GitHub Pages** | ✅ | ✅ | ✅ | ✅ (Fastly) | Free | `peaceiris/actions-gh-pages` |
| **Cloudflare Pages** | ✅ | ✅ | ✅ | ✅ (Cloudflare global) | Free tier | `cloudflare/wrangler-action` |
| **Cloudflare R2** | ✅ | ✅ | ✅ | ✅ (via CF) | Free tier (10 GB) | `aws-actions/configure-aws-credentials` + rclone |
| **Netlify** | ✅ | ✅ | ✅ | ✅ | Free tier | `nwtgck/actions-netlify` |
| **Vercel** | ✅ | ✅ | ✅ | ✅ | Free tier | `amondnet/vercel-action` |
| **Self-hosted (VPS)** | ✅ | ✅ | ✅ | ❌ (unless reverse proxy) | Server cost | Custom SSH rsync |
| **Raw S3 bucket** | ✅ | ✅ | ✅ (via Route53) | ❌ (unless CF) | Pay per GB | `aws-actions/configure-aws-credentials` |

### 6.3 Recommended: GitHub Pages (primary)

**Why**: Zero additional infrastructure, built-in Actions deploy integration,
HTTPS with custom domain support, global CDN via Fastly.

**Deployment approach**:

```yaml
- name: Deploy feed to GitHub Pages
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./release-feed
    destination_dir: feed        # publishes to <username>.github.io/<repo>/feed/
    keep_files: false            # replace all files on each deploy
```

**Resulting URL structure**:
```
https://MFSGA.github.io/OpenChimera/feed/
├── v0.1.0/
│   ├── openwrt-24.10/
│   │   └── x86_64/
│   │       ├── Packages.gz
│   │       ├── Packages.sig
│   │       ├── public.key
│   │       └── chimera-core_0.20.2-1_x86_64.ipk
│   └── ...
├── v0.2.0/
│   └── ...
└── latest/                     # Symlink or copy of latest tagged release
    └── ...
```

**Custom domain** (optional): Configure `CNAME` via GitHub Pages settings:
```
feed.openchimera.org → MFSGA.github.io (CNAME)
```
Then add `CNAME` file to the published directory.

### 6.4 Alternative: Cloudflare Pages

Choose this if:
- The project already uses Cloudflare for DNS.
- Global CDN performance is a priority.
- More generous free tier bandwidth is needed.

**Deployment approach**:

```yaml
- name: Deploy to Cloudflare Pages
  uses: cloudflare/wrangler-action@v3
  with:
    apiToken: ${{ secrets.CF_API_TOKEN }}
    accountId: ${{ secrets.CF_ACCOUNT_ID }}
    command: pages deploy ./release-feed --project-name=openchimera-feed
```

### 6.5 Hybrid approach: GitHub Releases + Pages

A practical middle ground:

1. **GitHub Releases** holds the canonical release artifacts (`.ipk` files,
   `SHA256SUMS`, `Packages.gz`, `Packages.sig`).
2. **GitHub Pages** hosts the structured feed directory for `opkg` consumption.

This separates concerns:
- Releases are immutable and available via the Releases UI.
- The Pages feed is regenerated on each release for `opkg update` convenience.

```
workflow:
  ...
  - name: Create Release
    uses: softprops/action-gh-release@v2
    with:
      files: release-feed/**/*.ipk
      body: "See changelog for details"

  - name: Deploy feed to Pages
    uses: peaceiris/actions-gh-pages@v3
    with:
      publish_dir: ./release-feed
```

### 6.6 Feed URL in feed.sh

Once hosting is set up, update [`feed.sh`](../feed.sh) to register the live
feed URL instead of showing the placeholder message:

```shell
# (future implementation)
FEED_BASE="https://MFSGA.github.io/OpenChimera/feed"
OPENWRT_RELEASE="openwrt-24.10"
ARCH="x86_64"

echo "src/gz openchimera ${FEED_BASE}/${OPENWRT_RELEASE}/${ARCH}" \
  >> /etc/opkg/customfeeds.conf

wget -qO - "${FEED_BASE}/${OPENWRT_RELEASE}/${ARCH}/public.key" | opkg-key add
opkg update
```

---

## 7. Build Attestation and Provenance

### 7.1 SLSA provenance

For supply-chain security, the workflow should generate
[SLSA Build L2](https://slsa.dev/spec/v1.0/levels) provenance attestations
using the official GitHub Action:

```yaml
- name: Generate build provenance
  uses: actions/attest-build-provenance@v1
  with:
    subject-path: 'release-feed/**/*.ipk'
```

This generates a signed attestation linking each `.ipk` file to the exact
GitHub Actions workflow run that produced it. Users (or automated tooling) can
verify:

```shell
gh attestation verify chimera-core_0.20.2-1_x86_64.ipk \
  --owner MFSGA --repo OpenChimera
```

### 7.2 SHA256SUMS file

Each release should include a `SHA256SUMS` file listing all `.ipk` hashes:

```yaml
- name: Generate SHA256SUMS
  run: |
    cd release-feed
    find . -name '*.ipk' -exec sha256sum {} \; > SHA256SUMS
    sha256sum -c SHA256SUMS   # verify
```

This file should be attached to the GitHub Release and optionally GPG-signed
with a maintainer key.

---

## 8. Feed Cleanup Policy

Over time, the feed accumulates old versions. Define a cleanup policy:

| Scope | Retention | Rationale |
|-------|-----------|-----------|
| **GitHub Releases** | Keep all | Releases are permanent records |
| **GitHub Pages feed** | Latest 3 versions per major.minor | Keeps `opkg update` fast; downgrade possible within 3 versions |
| **Old `.ipk` files** | Delete from feed after N versions | Reduce storage and CDN bandwidth |
| **Snapshot/nightly** | Keep last 7 days | Nightlies are ephemeral by nature |

The cleanup job runs as a separate step after the new build is deployed:

```yaml
- name: Prune old feed versions
  run: |
    # Keep last 3 versions per architecture per branch
    python3 scripts/prune-feed.py \
      --feed-dir release-feed \
      --keep-latest 3 \
      --dry-run          # remove --dry-run to actually delete
```

> **Note**: Cleanup is a **later optimization**. For the first several
> releases, retaining all versions is acceptable (the feed is small).

---

## 9. Migration Path from Milestone 1

### 9.1 Prerequisites for CI/CD enablement

Before the CI/CD feed can be operational, the following must be in place:

1. [ ] **Signing key pair** generated and `OPKG_SIGN_KEY` added to GitHub Secrets.
2. [ ] **Hosting platform** chosen and configured (GitHub Pages enabled on repo).
3. [ ] **feed.sh** updated with the live feed URL (replacing the placeholder).
4. [ ] **README** updated with feed-based installation instructions.
5. [ ] **Release tag convention** established (e.g., `v0.1.0`, `v0.2.0`, ...).
6. [ ] **Workflow file** created at `.github/workflows/release-feed.yml`.
7. [ ] **Test run** performed via `workflow_dispatch` before cutting first tag.

### 9.2 Future enhancements

| Enhancement | Triggers | Description |
|-------------|----------|-------------|
| **Multi-arch build** | Upstream musl artifacts for aarch64 | Expand build matrix |
| **Multi-branch build** | OpenWrt 25.12 stable release | Add `openwrt-25.12` to matrix |
| **Snapshot/nightly feed** | Schedule + push to main | Daily snapshot builds |
| **LuCI app** | LuCI package added | Add `luci-app-openchimera` to PACKAGES |
| **APK format** | OpenWrt 25.12+ APK migration | Dual publish opkg + apk feeds |
| **Custom domain** | DNS configuration | Point `feed.openchimera.org` to hosting |
| **Automated feed test** | After each deploy | Verify feed with `opkg update` on test device |
| **Slack/Discord notification** | Release success/failure | Notify maintainers of build status |

### 9.3 Effort estimation

| Component | Estimated effort | Dependencies |
|-----------|-----------------|--------------|
| Workflow file (tag + dispatch) | 1-2 hours | SDK action documentation |
| Signing key setup | 30 minutes | Local usign installation |
| GitHub Pages deployment step | 30 minutes | Pages enabled on repo |
| feed.sh update | 15 minutes | Feed URL known |
| Test run + debug | 1-2 hours | All of the above working |
| Documentation update (README) | 30 minutes | Workflow complete |
| **Total** | **~4-6 hours** | |

---

## 10. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-06 | Deferred to post-M1 milestone | SDK build is sufficient for current scope; feed adds CI complexity without proportional benefit for a 2-package project |
| 2026-06-06 | GitHub Pages as primary hosting | Zero cost, built-in Actions integration, HTTPS, CDN. No external accounts needed. |
| 2026-06-06 | usign (not GPG) for feed signing | OpenWrt standard. `opkg` expects usign/signify format. GPG is not supported by `opkg` for feed index verification. |
| 2026-06-06 | Pinned tag feeds (not moving "latest") | Reproducibility. Users pin to `v0.1.0` feed and get stable versions. A `latest` symlink can be added later for convenience. |
| 2026-06-06 | `INDEX=1` in SDK action (not custom indexing script) | The SDK action's built-in index generation produces the correct OpenWrt-compatible `Packages.gz`. No need to reimplement. |
