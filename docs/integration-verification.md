# Integration Verification: `chimera-core` ↔ `openchimera`

**Date:** 2026-06-06
**Scope:** Alternatives chain, dependency resolution, binary path consistency, service lifecycle
**Status:** Verified (1 minor inconsistency flagged)

---

## 1. PROVIDES / ALTERNATIVES Chain

### Provider: `chimera-core`

File: `chimera-core/Makefile`

```makefile
PROVIDES:=mihomo
CONFLICTS:=mihomo-meta mihomo-alpha
ALTERNATIVES:=\
  300:/usr/bin/mihomo:/usr/libexec/chimera
```

| Directive | Value | Purpose |
|-----------|-------|---------|
| `PROVIDES:=mihomo` | `mihomo` | Declares the `mihomo` virtual provider so other packages can `DEPENDS:=+mihomo` without caring which concrete package satisfies it. |
| `CONFLICTS:=mihomo-meta mihomo-alpha` | `mihomo-meta`, `mihomo-alpha` | Prevents co-installation with other packages that also `PROVIDES:=mihomo`. Only one provider can be installed at a time. |
| `ALTERNATIVES: 300:/usr/bin/mihomo:/usr/libexec/chimera` | priority `300`, symlink target `/usr/libexec/chimera` | Registers `/usr/bin/mihomo` as an alternatives-managed symlink. At priority 300, it points to `/usr/libexec/chimera`. |

The actual binary is installed to `/usr/libexec/chimera`:

```makefile
define Package/chimera-core/install
    $(INSTALL_DIR) $(1)/usr/libexec
    $(INSTALL_BIN) $(PKG_BUILD_DIR)/chimera $(1)/usr/libexec/chimera
endef
```

### Reference Pattern: `mihomo-meta` (upstream)

File: `.ref/OpenWrt-nikki/mihomo-meta/Makefile`

```makefile
PROVIDES:=mihomo
CONFLICTS:=mihomo-alpha
ALTERNATIVES:=\
  300:/usr/bin/mihomo:/usr/libexec/mihomo
```

The reference uses the identical pattern:
- Same `PROVIDES:=mihomo` virtual provider name
- Same alternatives priority `300`
- Same alternatives path `/usr/bin/mihomo`
- Same install destination pattern (`/usr/libexec/<binary>`)

**Verdict:** `chimera-core` correctly follows the upstream `mihomo-meta` convention. The only difference is the real binary destination (`/usr/libexec/chimera` vs `/usr/libexec/mihomo`), which is intentional and correct — OpenChimera wraps a different upstream project (Chimera_Client / clash-rs).

### OpenWrt Alternatives Mechanism

When `chimera-core` is installed, OpenWrt's alternatives system:

1. Registers the alternative in `/usr/lib/opkg/alternatives/mihomo` with content:
   ```
   /usr/bin/mihomo
   /usr/libexec/chimera 300
   ```
2. Creates (or updates) a symlink: `/usr/bin/mihomo → /usr/libexec/chimera`
3. On removal, if no other package provides the alternative at equal or higher priority, the symlink is removed.

**Documentation reference:** See OpenWrt package development docs for `ALTERNATIVES` format:  
`<priority>:<link-path>:<target-path>` where multiple alternatives for the same link are separated by spaces.

---

## 2. DEPENDS Chain

### Consumer: `openchimera`

File: `openchimera/Makefile`

```makefile
DEPENDS:=+mihomo +curl +yq +coreutils-base64
```

| Dependency | Type | Resolution |
|------------|------|------------|
| `+mihomo` | Virtual provider (`+` = auto-select) | Resolved at `opkg install` time. `opkg` selects `chimera-core` (or `mihomo-meta`/`mihomo-alpha`) based on available packages and feed configuration. The `+` prefix means it's pulled automatically without `--force-depends`. |
| `+curl` | Concrete package | Pulled from standard OpenWrt feeds |
| `+yq` | Concrete package | Pulled from standard OpenWrt feeds |
| `+coreutils-base64` | Concrete package | Pulled from standard OpenWrt feeds |

### Resolution Flow

```
openchimera DEPENDS on +mihomo
    └─ opkg resolves "mihomo" to a package PROVIDING it
         ├─ chimera-core (PROVIDES:=mihomo) ← intended for OpenChimera
         ├─ mihomo-meta   (PROVIDES:=mihomo) ← upstream alternative
         └─ mihomo-alpha  (PROVIDES:=mihomo) ← upstream alternative
```

If `chimera-core` and `mihomo-meta` are both present in the feed, `opkg` selects based on its default solver behavior (typically the first matching package found). The `CONFLICTS` declarations ensure only one can be installed.

**Verdict:** Correct. `openchimera` depends on the virtual `mihomo` provider, not on `chimera-core` directly. This means `openchimera` would also work with `mihomo-meta` or `mihomo-alpha` if desired, though the config generation is tuned for Chimera (clash-rs) and would likely generate unsupported fields for Mihomo cores.

---

## 3. Binary Path Consistency

### All References in `openchimera/`

| File | Line | Reference | Resolves Via |
|------|------|-----------|--------------|
| `files/openchimera.init` | 10 | `PROG=/usr/bin/mihomo` | Alternatives symlink → `/usr/libexec/chimera` |
| `files/config_gen.sh` | 18 | `PROG="${PROG:-/usr/bin/mihomo}"` | Alternatives symlink (env-overridable) |
| `files/debug.sh` | 38–39 | `command -v mihomo` then `mihomo -V` | PATH lookup (no hardcoded path) |
| `files/debug.sh` | 61 | `grep -E '(chimera\|mihomo)'` | Process table string match |

### All References in `chimera-core/`

| File | Line | Reference | Purpose |
|------|------|-----------|---------|
| `Makefile` | 33 | `300:/usr/bin/mihomo:/usr/libexec/chimera` | ALTERNATIVES registration |
| `Makefile` | 38 | `Provides /usr/libexec/chimera with /usr/bin/mihomo alternative.` | Package description |
| `Makefile` | 55 | `$(INSTALL_BIN) ... $(1)/usr/libexec/chimera` | Binary install destination |

### Strategy Analysis

Three distinct strategies are used across the codebase, all **consistent** and **correct**:

1. **Hardcoded `/usr/bin/mihomo`** (init, config_gen.sh default) — relies on the alternatives system to resolve to the real binary. This is the canonical approach: `openchimera` should reference the "public" alternatives-managed path, not the private implementation path.

2. **PATH lookup via `command -v mihomo`** (debug.sh) — appropriate for a diagnostic tool that should work regardless of how the binary is installed. This is the most flexible approach.

3. **Direct `/usr/libexec/chimera`** (chimera-core Makefile) — only used in the provider package itself, which owns the real binary. External packages should never reference this path directly.

**Important:** No file in `openchimera/` references `/usr/libexec/chimera` directly. This is correct — the consumer should always go through the alternatives-managed `/usr/bin/mihomo` path.

### Comparison with Upstream Pattern

The upstream `mihomo-meta` installs its binary to `/usr/libexec/mihomo` and exposes it as `/usr/bin/mihomo`.  
`chimera-core` installs to `/usr/libexec/chimera` and exposes it as `/usr/bin/mihomo`.

Both expose the same consumer-facing path (`/usr/bin/mihomo`), making them drop-in replacements from the perspective of `openchimera` or any other management package.

---

## 4. Service Lifecycle Path

### Complete Flow

```
/etc/init.d/openchimera start
  │
  ├─ 1. Load UCI (config_load openchimera)
  ├─ 2. Check enabled (config_get_bool enabled → default: 0)
  │      └─ Return 1 if disabled
  ├─ 3. Create runtime directory (/etc/openchimera/run/)
  ├─ 4. Create log directory (/var/log/openchimera/)
  ├─ 5. Verify PROG exists and is executable
  │      └─ [ -x /usr/bin/mihomo ] || return 1
  │
  ├─ 6. Generate config: /usr/bin/openchimera-config-gen
  │      │
  │      │   config_gen.sh internals:
  │      │     ├─ Read UCI → build config.yaml
  │      │     ├─ Validate generated config with:
  │      │     │   $PROG -t -d $WORK_DIR -c $CONFIG_FILE
  │      │     │   └─ exit 1 on failure
  │      │     └─ exit 0 on success
  │      │
  │      └─ Return 1 if config generation/validation fails
  │
  ├─ 7. Validate config AGAIN (see §4a):
  │      └─ "$PROG" -t -d "$WORK_DIR" -c "$CONFIG_FILE"
  │          └─ Return 1 on failure
  │
  └─ 8. Launch via procd:
         procd_set_param command "$PROG" \
           --compatibility -d "$WORK_DIR" -c "$CONFIG_FILE" \
           --log-file "$LOG_FILE"
         procd_set_param respawn
```

### 4a. Note: Duplicate Validation

The init script performs **two identical `$PROG -t` validation calls** in sequence:

1. **Inside config_gen.sh** (line 147): validates the generated config
2. **In openchimera.init** (line 62): validates the config again after config_gen.sh returns

Since `config_gen.sh` already exits non-zero on validation failure (line 155: `exit 1`), the init script's validation at line 62 is **dead code** — it can only succeed because if validation had failed, `config_gen.sh` would have already caused the init script to return 1 at line 57.

**Impact:** None on correctness. The second `$PROG -t` call is redundant but harmless.

### Version Check

File: `openchimera/files/debug.sh` (lines 38–42)

```shell
if command -v mihomo >/dev/null 2>&1; then
    mihomo -V 2>&1
else
    "$ECHO" "  mihomo binary not found in PATH"
fi
```

The `mihomo -V` command (equivalent to `/usr/bin/mihomo -V` via PATH resolution) prints the core version string. This is wired into the debug.sh diagnostic tool installed as `/usr/bin/openchimera-debug`.

### Config Test

The `mihomo -t -d <dir> -c <file>` pattern is consistent across two locations:

| File | Command | Purpose |
|------|---------|---------|
| `config_gen.sh:147` | `"$PROG" -t -d "$WORK_DIR" -c "$CONFIG_FILE"` | Validate generated config before writing |
| `openchimera.init:62` | `"$PROG" -t -d "$WORK_DIR" -c "$CONFIG_FILE"` | Validate config before daemon launch (redundant; see §4a) |

Both use `$PROG` (which defaults to `/usr/bin/mihomo`) and pass the working directory and config file name as arguments. The procd launch command on line 70 passes the same three parameters (`--compatibility -d "$WORK_DIR" -c "$CONFIG_FILE"`), ensuring the daemon uses the exact same config that was validated.

---

## 5. Inconsistencies Found

### 5.1. Typo in config_gen.sh Comment (Minor)

**File:** `openchimera/files/config_gen.sh`, line 13

```
# Called from init script: /etc/init.d/openchimica start
                                                ^^^^^^^^^^
```

Should be `openchimera` (not `openchimica`). This is a comment-only typo with no runtime impact.

### 5.2. Duplicate Config Validation (Design Observation)

As documented in §4a, the init script validates the config immediately after `config_gen.sh` returns, even though `config_gen.sh` already validates and exits with error upon failure. The second validation is dead code.

**Recommendation:** Consider removing the validation step from `openchimera.init` (lines 60–66) and relying solely on `config_gen.sh`'s validation, OR move validation to the init script exclusively and remove it from `config_gen.sh`. Either approach eliminates the redundancy. This is noted as a low-priority simplification opportunity, not a bug.

---

## 6. Summary

| Aspect | Status | Notes |
|--------|--------|-------|
| `chimera-core` PROVIDES `mihomo` | ✅ Correct | Matches upstream `mihomo-meta` convention |
| `chimera-core` ALTERNATIVES | ✅ Correct | Priority 300, `/usr/bin/mihomo` → `/usr/libexec/chimera` |
| `chimera-core` CONFLICTS | ✅ Correct | Conflicts with `mihomo-meta` and `mihomo-alpha` |
| `openchimera` DEPENDS on `+mihomo` | ✅ Correct | Virtual provider resolved by opkg |
| Binary path in init script | ✅ Correct | Uses `/usr/bin/mihomo` (alternatives-resolved) |
| Binary path in config_gen.sh | ✅ Correct | Uses `${PROG:-/usr/bin/mihomo}` (env-overridable) |
| Binary path in debug.sh | ✅ Correct | Uses `command -v mihomo` (PATH lookup) |
| No direct `/usr/libexec/chimera` in consumer | ✅ Correct | Consumer never references implementation path |
| Version check (`mihomo -V`) | ✅ Wired | Via debug.sh (installed as `openchimera-debug`) |
| Config test (`mihomo -t`) | ✅ Wired | Via config_gen.sh (and redundantly in init) |
| Typo in config_gen.sh comment | ⚠️ Minor | Line 13: "openchimica" → "openchimera" |
| Duplicate validation | ⚠️ Observation | Init re-validates after config_gen.sh already validates |

**Overall: The integration is consistent and correct.** All binary path references resolve through the alternatives chain appropriately, the virtual provider dependency is wired correctly, and the service lifecycle follows a logical sequence. Two minor items are flagged for awareness but neither affects runtime behavior.
