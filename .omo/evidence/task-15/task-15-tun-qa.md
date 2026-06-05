# OpenChimera Basic TUN Config Runtime QA Plan

> **Target**: x86_64 OpenWrt 24.10+ with firewall4  
> **Package**: `openchimera` management layer with `chimera-core` provider  
> **Evidence naming**: `.omo/evidence/task-15/{scenario-slug}.txt` (see §7)  
> **Execution**: 100% agent-automated — zero manual confirmation  
> **Scope**: Milestone 1 — TUN config generation and device verification only. TUN traffic forwarding / full TUN tunnel testing is out of scope for config-only verification.

---

## Table of Contents

1. [Scope & Definitions](#1-scope--definitions)
2. [Pre-Flight Checks](#2-pre-flight-checks)
3. [Scenario TUN1: TUN-Enabled Config Generation](#3-scenario-tun1-tun-enabled-config-generation)
4. [Scenario TUN2: TUN-Disabled Config Omits TUN Block (Negative)](#4-scenario-tun2-tun-disabled-config-omits-tun-block-negative)
5. [Scenario TUN3: TUN Device Presence](#5-scenario-tun3-tun-device-presence)
6. [Scenario TUN4: No Nikki-Only Fields in Generated Config (Negative)](#6-scenario-tun4-no-nikki-only-fields-in-generated-config-negative)
7. [Scenario TUN5: No TProxy/Redirect Rules (Negative Guardrail)](#7-scenario-tun5-no-tproxyredirect-rules-negative-guardrail)
8. [Scenario TUN6: Route Table Verification](#8-scenario-tun6-route-table-verification)
9. [Scenario TUN7: TUN DNS Hijack Conditional (if enabled)](#9-scenario-tun7-tun-dns-hijack-conditional-if-enabled)
10. [Evidence Naming Convention](#10-evidence-naming-convention)
11. [QA-Id to Scenario Mapping](#11-qa-id-to-scenario-mapping)

---

## 1. Scope & Definitions

### 1.1 What This Plan Covers

- **Config generation**: Verify that when `tun_enabled=1` in UCI, the generated `/etc/openchimera/run/config.yaml` includes an explicit `tun:` block with `enable: true`, `device`, and `route-table`.
- **Config omission**: Verify that when `tun_enabled=0` (default), the generated config has **no** `tun:` block.
- **Device presence**: Verify that the TUN device (`nikki` by default) appears in `ip link show` when TUN is enabled and the daemon is running.
- **Nikki exclusion**: Verify that Chimera-unsupported fields (`auto-redirect`, `auto-detect-interface`, `disable-icmp-forwarding`) are **never** present in the generated config.
- **TProxy/Redirect absence**: Verify milestone 1 does not install TProxy/Redirect nftables rules.
- **Route table**: Verify that `tun.route-table` is set to `81` (the default) and that the corresponding routing table is present.

### 1.2 What This Plan Does NOT Cover

- **Full TUN traffic forwarding verification** (all traffic routed through TUN, DNS resolution through TUN). Milestone 1 validates config generation and device creation only.
- **TProxy or Redirect transparent proxy modes** (deferred to later milestones).
- **Performance or throughput testing** of the TUN interface.
- **Multiple TUN device configurations** (only `device: nikki` is tested).

### 1.3 Key Config Generation Logic

From `config_gen.sh` (lines 125-137):

```bash
# --- TUN block (only if enabled) ---
if [ "${tun_enabled}" = "1" ]; then
    echo ""
    echo "tun:"
    echo "  enable: true"
    yaml_kv "  device"      "${tun_device:-nikki}"
    yaml_kv "  route-table" "${tun_route_table:-81}"

    if [ "${tun_dns_hijack}" = "1" ]; then
        echo "  dns-hijack:"
        echo '    - "0.0.0.0/0"'
        echo '    - "::/0"'
    fi
fi
```

Key behaviors:
- TUN block is **only** emitted when `tun_enabled=1`
- Default TUN device name: `nikki`
- Default route table: `81` (from UCI section `routing`, not `mixin`)
- DNS hijack is **optional** and only emitted when `tun_dns_hijack=1`
- Nikki-only fields are **never** emitted

### 1.4 UCI Section Reference

```bash
# Enable TUN (section: mixin)
uci set openchimera.mixin.tun_enabled=1

# TUN device name (section: mixin)
uci set openchimera.mixin.tun_device='nikki'

# TUN DNS hijack (section: mixin)
uci set openchimera.mixin.tun_dns_hijack=0

# Route table (section: routing — NOT mixin)
uci set openchimera.routing.tun_route_table=81

# Always commit after UCI changes
uci commit openchimera

# Restart service
/etc/init.d/openchimera restart
```

> ⚠️ **Note**: `tun_route_table` is in section `routing`, NOT `mixin`. This is intentional — routing configuration is separated from port/feature toggling.

### 1.5 Default Values

| UCI Path | Default | Source |
|---|---|---|
| `openchimera.mixin.tun_enabled` | `0` (disabled) | `openchimera.conf` line 20 |
| `openchimera.mixin.tun_device` | `nikki` | `openchimera.conf` line 21 |
| `openchimera.mixin.tun_dns_hijack` | `0` (disabled) | `openchimera.conf` line 22 |
| `openchimera.routing.tun_route_table` | `81` | `openchimera.conf` line 28 |

---

## 2. Pre-Flight Checks

Before executing any TUN scenario, verify:

```bash
# 1. Service is running (for scenarios that need active daemon)
ssh root@<target-ip> "/etc/init.d/openchimera status"

# 2. kmod-tun is loaded
ssh root@<target-ip> "lsmod | grep tun || echo 'tun module not loaded'"

# 3. Config generator is present
ssh root@<target-ip> "[ -x /usr/bin/openchimera-config-gen ] && echo 'config-gen present'"

# 4. ip tool is available (for device/route checks)
ssh root@<target-ip> "which ip && ip link show"

# 5. Record initial TUN device state (should be absent before TUN-enabled start)
ssh root@<target-ip> "ip link show | grep -i nikki || echo 'no nikki device present'"

# 6. Check current UCI TUN settings
ssh root@<target-ip> "uci show openchimera.mixin.tun_enabled"
ssh root@<target-ip> "uci show openchimera.mixin.tun_device"
ssh root@<target-ip> "uci show openchimera.routing.tun_route_table"
```

All pre-flight commands and their output MUST be captured to:
`.omo/evidence/task-15/task-15-tun-preflight.txt`

---

## 3. Scenario TUN1: TUN-Enabled Config Generation

**QA-ID**: QA-30 (new)  
**Evidence file**: `task-15/task-15-tun1-config-generated.txt`

### 3.1 Description

When `openchimera.mixin.tun_enabled=1`, the config generator MUST produce a `tun:` block in `/etc/openchimera/run/config.yaml` with `enable: true`, explicit `device`, and explicit `route-table`. This is the primary happy-path test for TUN config generation.

### 3.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is stopped (to regenerate config cleanly) | `pgrep -f 'mihomo\|chimera'` returns exit 1 |
| P2 | TUN is enabled in UCI | `uci get openchimera.mixin.tun_enabled` = `1` |
| P3 | TUN device name is configured | `uci get openchimera.mixin.tun_device` = `nikki` (or custom) |
| P4 | Route table is configured | `uci get openchimera.routing.tun_route_table` = `81` (or custom) |
| P5 | Config generator script present | `[ -x /usr/bin/openchimera-config-gen ]` |

### 3.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Verify UCI TUN settings: `uci show openchimera.mixin.tun_enabled` and `uci show openchimera.mixin.tun_device` and `uci show openchimera.routing.tun_route_table` | All show expected values |
| 2 | **Manually run config generator** (to inspect config without starting daemon): `openchimera-config-gen` | Exit 0 |
| 3 | **Read generated config**: `cat /etc/openchimera/run/config.yaml` | File exists with content |
| 4 | **Verify tun.enable**: `grep -A 10 '^tun:' /etc/openchimera/run/config.yaml` | Contains `enable: true` |
| 5 | **Verify tun.device**: `grep -A 10 '^tun:' /etc/openchimera/run/config.yaml \| grep 'device'` | Contains `device: nikki` |
| 6 | **Verify tun.route-table**: `grep -A 10 '^tun:' /etc/openchimera/run/config.yaml \| grep 'route-table'` | Contains `route-table: 81` |
| 7 | Verify the tun block structure is valid YAML: `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml` (if daemon not running) | Exit 0 (or use `yq eval` if available) |
| 8 | **Verify config passes Chimera validation**: `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml >/dev/null 2>&1; echo $?` | Exit 0 (if no other config issues) |
| 9 | **Start service with TUN**: `/etc/init.d/openchimera start` | Exit 0 |

### 3.4 Expected Results

- `openchimera-config-gen` exits 0
- `/etc/openchimera/run/config.yaml` contains:
  ```yaml
  tun:
    enable: true
    device: nikki
    route-table: 81
  ```
- The `tun:` block has exactly these fields (no extra, no missing)
- Generated config passes `mihomo -t` validation
- Service starts successfully with TUN enabled

### 3.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| No tun block in config | `grep '^tun:'` returns empty | `tun_enabled` not set to 1; config gen not run |
| Missing `enable: true` | `enable:` not under tun block | Config gen regression |
| Missing `device` key | `device:` not present | Config gen emits wrong field name |
| Missing `route-table` key | `route-table:` not present | Config gen emits wrong field name |
| Wrong device name | `device: wrongname` | UCI value different from expected |
| Wrong route table | `route-table: N` where N != 81 | UCI `routing.tun_route_table` not committed |
| `mihomo -t` fails | Validation error on tun block | Chimera rejects config format (check exact YAML indentation) |
| Service fails to start | `/etc/init.d/openchimera start` returns non-zero | Config validation failed; check `logread` |

### 3.6 Evidence Collection Script

```bash
evidence_file=".omo/evidence/task-15/task-15-tun1-config-generated.txt"
{
    echo "=== TUN1: TUN-Enabled Config Generation ==="
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Target: $(hostname)"
    echo ""
    
    echo "--- UCI Settings ---"
    echo "tun_enabled=$(uci get openchimera.mixin.tun_enabled 2>/dev/null)"
    echo "tun_device=$(uci get openchimera.mixin.tun_device 2>/dev/null)"
    echo "tun_dns_hijack=$(uci get openchimera.mixin.tun_dns_hijack 2>/dev/null)"
    echo "tun_route_table=$(uci get openchimera.routing.tun_route_table 2>/dev/null)"
    echo ""
    
    echo "--- Step: Running config generator ---"
    /usr/bin/openchimera-config-gen
    echo "exit: $?"
    echo ""
    
    echo "--- Generated config.yaml ---"
    cat /etc/openchimera/run/config.yaml
    echo ""
    
    echo "--- TUN block extraction ---"
    grep -A 10 '^tun:' /etc/openchimera/run/config.yaml || echo "NO TUN BLOCK FOUND"
    echo ""
    
    echo "--- Assertions ---"
    if grep -q '^tun:' /etc/openchimera/run/config.yaml; then
        echo "[PASS] tun: block present"
    else
        echo "[FAIL] tun: block missing"
    fi
    if grep -A 10 '^tun:' /etc/openchimera/run/config.yaml | grep -q 'enable: true'; then
        echo "[PASS] tun.enable: true"
    else
        echo "[FAIL] tun.enable missing or not true"
    fi
    if grep -A 10 '^tun:' /etc/openchimera/run/config.yaml | grep -q 'device:'; then
        echo "[PASS] tun.device present"
        grep -A 10 '^tun:' /etc/openchimera/run/config.yaml | grep 'device:'
    else
        echo "[FAIL] tun.device missing"
    fi
    if grep -A 10 '^tun:' /etc/openchimera/run/config.yaml | grep -q 'route-table:'; then
        echo "[PASS] tun.route-table present"
        grep -A 10 '^tun:' /etc/openchimera/run/config.yaml | grep 'route-table:'
    else
        echo "[FAIL] tun.route-table missing"
    fi
    
    echo ""
    echo "--- Validation ---"
    if /usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml >/dev/null 2>&1; then
        echo "[PASS] Config validation passed"
    else
        echo "[FAIL] Config validation failed"
        /usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml 2>&1
    fi
    
    echo ""
    echo "--- Summary ---"
    echo "Result: PASS / FAIL"
} 2>&1 | tee "$evidence_file"
```

---

## 4. Scenario TUN2: TUN-Disabled Config Omits TUN Block (Negative)

**QA-ID**: QA-31 (new)  
**Evidence file**: `task-15/task-15-tun2-config-omitted.txt`

### 4.1 Description

When `openchimera.mixin.tun_enabled=0` (the default), the config generator MUST **NOT** produce a `tun:` block in the generated config. This confirms that TUN is opt-in only.

### 4.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is stopped | `pgrep -f 'mihomo\|chimera'` returns exit 1 |
| P2 | TUN is disabled in UCI | `uci get openchimera.mixin.tun_enabled` = `0` |
| P3 | Config generator script present | `[ -x /usr/bin/openchimera-config-gen ]` |

### 4.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Verify UCI: `uci get openchimera.mixin.tun_enabled` | `0` |
| 2 | **Run config generator**: `/usr/bin/openchimera-config-gen` | Exit 0 |
| 3 | **Check for tun block**: `grep '^tun:' /etc/openchimera/run/config.yaml` | **No output** (tun block absent) |
| 4 | Check for tun-related keys: `grep -E '^\s+enable|^\s+device|^\s+route-table' /etc/openchimera/run/config.yaml` | No tun-related keys outside of tun block |
| 5 | Verify config still valid (minimal config): `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml >/dev/null 2>&1; echo $?` | Exit 0 |
| 6 | Start service with TUN disabled: `/etc/init.d/openchimera start` | Exit 0 (should work without TUN) |

### 4.4 Expected Results

- Generated config has **no** `tun:` block
- `grep '^tun:'` returns empty
- Config is valid (passes `mihomo -t`)
- Service starts successfully without TUN

### 4.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| TUN block present when disabled | `grep '^tun:'` returns content | `tun_enabled` not respected by config gen |
| Config invalid without TUN | `mihomo -t` fails | Config missing required fields unrelated to TUN |

### 4.6 Key Assertion Logic

```bash
# Run config gen
/usr/bin/openchimera-config-gen

# Verify no tun block
if grep -q '^tun:' /etc/openchimera/run/config.yaml; then
    echo "FAIL: tun: block present when tun_enabled=0"
    exit 1
else
    echo "PASS: No tun block in disabled config"
fi
```

---

## 5. Scenario TUN3: TUN Device Presence

**QA-ID**: QA-32 (new)  
**Evidence file**: `task-15/task-15-tun3-device-presence.txt`

### 5.1 Description

When the Chimera daemon runs with TUN enabled, it SHOULD create a TUN network device (default name `nikki`). This scenario verifies the device appears in `ip link show` after the service starts. If the device does not appear, this serves as actionable compatibility evidence.

### 5.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running with TUN enabled | TUN1 completed and service started |
| P2 | TUN device name is `nikki` | `uci get openchimera.mixin.tun_device` = `nikki` |
| P3 | `kmod-tun` kernel module is loaded | `lsmod | grep tun` shows tun module |
| P4 | `ip` tool is available | `which ip` |

### 5.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Wait for TUN device creation: `sleep 3` | Give daemon time to create device |
| 2 | **List all network interfaces**: `ip link show` | TUN device `nikki` appears in list |
| 3 | **Show device details**: `ip -d link show nikki` | Device type `tun`; state UP or DOWN; flags include `NO-CARRIER` or `UP` |
| 4 | **Check device state**: `ip link show nikki \| grep -o 'state [A-Z]*'` | State may be `UNKNOWN` (typical for TUN) |
| 5 | Check device flags: `ip link show nikki \| grep -o '<[^>]*>'` | Contains `UP` if interface is active |
| 6 | **Verify process owns the device**: `ls -la /proc/$(pgrep -f 'mihomo\|chimera' \| head -1)/fd/ 2>/dev/null \| grep tun \|\| echo "cannot determine fd ownership"` | If accessible, shows fd pointing to tun device |
| 7 | **Start daemon check**: Verify daemon PID matches the PID that should own the TUN device: `pgrep -f 'mihomo\|chimera'` | PID present |
| 8 | **Stop service**: `/etc/init.d/openchimera stop` | Exit 0 |
| 9 | **Verify device removed on stop**: `ip link show nikki 2>&1 \|\| echo "Device removed"` | Device no longer exists (daemon cleans up TUN on stop) |

### 5.4 Expected Results

- `ip link show` lists `nikki` as a TUN interface (if kernel supports TUN and daemon creates it)
- `ip -d link show nikki` confirms type `tun` (or `tun` driver)
- Daemon PID is running
- **After stop**: TUN device `nikki` is removed (daemon cleans up)

### 5.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| TUN device not created | `ip link show nikki` returns `Device not found` | `kmod-tun` not loaded; daemon not starting TUN; config TUN block missing |
| Device type is not TUN | `ip -d link show nikki` shows `type ether` or other | Device name collision with non-TUN interface |
| Device persists after stop | `ip link show nikki` still shows device after stop | Daemon did not clean up; stale device |
| Daemon not running | `pgrep` returns empty | Service didn't start; check logs for errors |

### 5.6 Note on TUN Device Creation

Chimera (clash-rs) creates the TUN device internally when it starts with TUN enabled in the config. The device is created and managed by the daemon process. If `kmod-tun` is not loaded, the device creation will fail silently or with an error in the daemon log.

If the TUN device does not appear:
1. Verify `kmod-tun` is loaded: `lsmod | grep tun`
2. Check daemon log for TUN errors: `grep -i tun /var/log/openchimera/core.log`
3. Verify the generated config has valid TUN block (TUN1)
4. Consider that the daemon may not support TUN on this platform

### 5.7 Key Assertion Logic

```bash
# Wait and check for TUN device
sleep 3
if ip link show nikki >/dev/null 2>&1; then
    echo "PASS: TUN device 'nikki' exists"
    ip link show nikki
    ip -d link show nikki
else
    echo "FAIL: TUN device 'nikki' not found"
    echo "Check kmod-tun: $(lsmod | grep tun || echo 'tun module not loaded')"
    echo "Check daemon log for TUN errors:"
    grep -i tun /var/log/openchimera/core.log 2>/dev/null || echo "No tun entries in log"
fi
```

---

## 6. Scenario TUN4: No Nikki-Only Fields in Generated Config (Negative)

**QA-ID**: QA-33 (new)  
**Evidence file**: `task-15/task-15-tun4-no-nikki-fields.txt`

### 6.1 Description

Chimera (clash-rs) does NOT support the following Nikki/Mihomo-only config fields:
- `auto-redirect`
- `auto-detect-interface`
- `disable-icmp-forwarding`

If any of these fields appear in the generated config, `mihomo -t` validation will fail and the daemon will refuse to start. This scenario verifies these fields are **never** emitted by `openchimera-config-gen`.

### 6.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Config generator script present | `[ -x /usr/bin/openchimera-config-gen ]` |
| P2 | TUN is enabled (to exercise TUN config path) | `uci get openchimera.mixin.tun_enabled` = `1` |
| P3 | Config can be generated (service may be stopped) | — |

### 6.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Run config generator: `/usr/bin/openchimera-config-gen` | Exit 0 |
| 2 | **Check for auto-redirect**: `grep -c 'auto-redirect' /etc/openchimera/run/config.yaml` | **0** (field absent) |
| 3 | **Check for auto-detect-interface**: `grep -c 'auto-detect-interface' /etc/openchimera/run/config.yaml` | **0** (field absent) |
| 4 | **Check for disable-icmp-forwarding**: `grep -c 'disable-icmp-forwarding' /etc/openchimera/run/config.yaml` | **0** (field absent) |
| 5 | **Check for any Nikki-only TUN fields**: `grep -c -E 'auto-redirect|auto-detect-interface|disable-icmp-forwarding' /etc/openchimera/run/config.yaml` | **0** (all absent) |
| 6 | Verify config passes validation: `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml >/dev/null 2>&1; echo $?` | Exit 0 |
| 7 | Also check the config generator script itself for Nikki-only fields: `grep -n 'auto-redirect\|auto-detect-interface\|disable-icmp-forwarding' /usr/bin/openchimera-config-gen || echo "No Nikki fields in generator script"` | No matches |
| 8 | Check the default config template: `grep -c -E 'auto-redirect|auto-detect-interface|disable-icmp-forwarding' /etc/openchimera/config.yaml.default || echo "No Nikki fields in default config"` | No matches |

### 6.4 Expected Results

- `auto-redirect` is NOT present in generated config
- `auto-detect-interface` is NOT present in generated config
- `disable-icmp-forwarding` is NOT present in generated config
- Config passes `mihomo -t` validation
- Config generator script does NOT emit these fields
- Default config template does NOT contain these fields

### 6.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| `auto-redirect` found | `grep` returns count > 0 | Nikki field leaked into config generator |
| `auto-detect-interface` found | `grep` returns count > 0 | Nikki field leaked into config generator |
| `disable-icmp-forwarding` found | `grep` returns count > 0 | Nikki field leaked into config generator |
| Config validation fails | `mihomo -t` exits non-zero | Nikki fields present cause validation rejection |

### 6.6 Key Assertion Logic

```bash
CONFIG=/etc/openchimera/run/config.yaml
ERRORS=0

for field in auto-redirect auto-detect-interface disable-icmp-forwarding; do
    if grep -q "$field" "$CONFIG"; then
        echo "FAIL: Nikki-only field '$field' found in generated config"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: Nikki-only field '$field' absent"
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    echo "PASS: No Nikki-only fields in generated config"
else
    echo "FAIL: $ERRORS Nikki-only field(s) found"
    exit 1
fi
```

---

## 7. Scenario TUN5: No TProxy/Redirect Rules (Negative Guardrail)

**QA-ID**: QA-34 (new)  
**Evidence file**: `task-15/task-15-tun5-no-tproxy-rules.txt`

### 7.1 Description

Milestone 1 explicitly defers TProxy and Redirect transparent proxy modes. This scenario verifies that even with TUN enabled, the `openchimera` package does **not** install any TProxy/Redirect nftables rules, iptables rules, or routing policy rules.

This is a **critical milestone guardrail** — TUN config generation is NOT a substitute for TProxy/Redirect implementation.

### 7.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running with TUN enabled | TUN3 passed or service active |
| P2 | `nft` command available | `which nft` |
| P3 | `iptables` available | `which iptables` |
| P4 | `ip rule` and `ip route` available | `which ip` |

### 7.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | **Check nftables for TProxy rules**: `nft list ruleset 2>/dev/null \| grep -i 'tproxy' \|\| echo "No TProxy rules in nftables"` | No TProxy rules present |
| 2 | **Check nftables for REDIRECT rules**: `nft list ruleset 2>/dev/null \| grep -i 'redirect' \|\| echo "No redirect rules in nftables"` | No redirect rules present |
| 3 | **Check iptables mangle table for TProxy**: `iptables -t mangle -L PREROUTING 2>/dev/null \| grep -i 'tproxy' \|\| echo "No TProxy in mangle/PREROUTING"` | No TProxy rules |
| 4 | **Check iptables nat table for REDIRECT**: `iptables -t nat -L PREROUTING 2>/dev/null \| grep -i 'redirect' \|\| echo "No REDIRECT in nat/PREROUTING"` | No REDIRECT rules |
| 5 | **Check for TUN-specific policy routing**: `ip rule show 2>/dev/null \| grep -i 'tun\|81\|nikki\|mihomo\|chimera' \|\| echo "No TUN-specific policy rules"` | No extra routing policy rules |
| 6 | **Check for Chimera-managed nftables chains**: `nft list ruleset 2>/dev/null \| grep -E 'chain.*(mihomo|chimera|openchimera|nikki)' \|\| echo "No Chimera-managed nftables chains"` | No custom chains |
| 7 | **Check for TProxy-related kernel modules loaded**: `lsmod 2>/dev/null \| grep -E 'nft_tproxy|nft_socket|xt_TPROXY' \|\| echo "No TProxy kernel modules loaded by milestone 1"` | TProxy kernel modules NOT loaded |
| 8 | **Search init script code for TProxy/Redirect**: `grep -rn 'tproxy\|redirect\|nft\|nftables\|iptables\|tcp\|divert\|mark' /etc/init.d/openchimera /usr/bin/openchimera-config-gen /usr/bin/openchimera-debug 2>/dev/null \| grep -v 'logger\|log\|log_file\|log_path\|log_level' \|\| echo "No TProxy/Redirect code in scripts"` | No TProxy/Redirect implementation code |

### 7.4 Expected Results

- `nft list ruleset` has NO `tproxy` or `redirect` statements
- `iptables -t mangle -L PREROUTING` has NO TProxy rules
- `iptables -t nat -L PREROUTING` has NO REDIRECT rules
- `ip rule show` has NO Chimera/TUN-specific policy rules
- No custom nftables chains for Chimera exist
- No TProxy kernel modules (`nft_tproxy`, `nft_socket`, `xt_TPROXY`) are loaded by milestone 1
- Init and helper scripts contain no TProxy/Redirect implementation code

### 7.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| TProxy rule in nftables | `nft list ruleset` shows tproxy | TProxy implementation prematurely added |
| Redirect rule in nftables/iptables | Redirect rule to proxy port | Redirect implementation prematurely added |
| TProxy kernel module loaded | `lsmod` shows nft_tproxy | TProxy module installed and loaded |
| Chimera-specific routing policy | `ip rule show` has non-default entries | TUN policy routing implemented (deferred to later milestone) |
| TProxy code in scripts | `grep` finds TProxy logic | Implementation leaked into milestone 1 |

### 7.6 Key Assertion Logic

```bash
ERRORS=0

# nftables check
if nft list ruleset 2>/dev/null | grep -qi 'tproxy\|redirect'; then
    echo "FAIL: TProxy/Redirect rules in nftables"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: No TProxy/Redirect in nftables"
fi

# iptables mangle check
if iptables -t mangle -L PREROUTING 2>/dev/null | grep -qi 'tproxy'; then
    echo "FAIL: TProxy in iptables mangle"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: No TProxy in iptables mangle"
fi

# iptables nat check
if iptables -t nat -L PREROUTING 2>/dev/null | grep -qi 'redirect.*7890\|redirect.*1080\|redirect.*8080'; then
    echo "FAIL: REDIRECT in iptables nat"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: No REDIRECT in iptables nat"
fi

# Kernel module check
for mod in nft_tproxy nft_socket xt_TPROXY; do
    if lsmod 2>/dev/null | grep -q "$mod"; then
        echo "WARN: TProxy module '$mod' loaded (may be from outside OpenChimera)"
    fi
done

# Final
if [ "$ERRORS" -eq 0 ]; then
    echo "PASS: Milestone 1 TUN has no TProxy/Redirect implementation"
else
    echo "FAIL: $ERRORS guardrail violations"
    exit 1
fi
```

---

## 8. Scenario TUN6: Route Table Verification

**QA-ID**: QA-35 (new)  
**Evidence file**: `task-15/task-15-tun6-route-table.txt`

### 8.1 Description

Verify that route table `81` (the default TUN route table) is present in the system routing tables when TUN is enabled and the Chimera daemon is running. Chimera adds routes to table 81 for traffic to be routed through the TUN interface.

### 8.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running with TUN enabled | TUN1 + TUN3 passed |
| P2 | Route table ID 81 is configured | `uci get openchimera.routing.tun_route_table` = `81` |
| P3 | `ip route` command available | `which ip` |

### 8.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | **Show route table 81**: `ip route show table 81 2>&1` | Table exists (may be empty) or shows routes via `nikki` |
| 2 | **List all route tables**: `ip route show table all 2>/dev/null \| head -20` | Table 81 appears in list |
| 3 | **Check for routes via nikki device**: `ip route show table 81 2>/dev/null \| grep -i nikki \|\| echo "No nikki routes in table 81"` | May be empty (Chimera adds routes dynamically) or shows default via nikki |
| 4 | **Check rule referencing table 81**: `ip rule show \| grep 81 \|\| echo "No rule referencing table 81"` | May be present if Chimera added policy rule |
| 5 | **Record route table info for evidence**: `ip route show table 81 2>/dev/null; ip rule show 2>/dev/null \| grep 81 || echo "Table 81 present but empty"` | Evidence of table state |

### 8.4 Expected Results

- Route table `81` exists in the system
- If Chimera adds routes, they appear via the `nikki` TUN device
- Table 81 may be empty at rest (Chimera adds routes on-demand)
- The presence of the table itself confirms config alignment

### 8.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Table 81 does not exist | `ip route show table 81` returns `Error: table 81 not found` | Chimera did not create the table; TUN not actually enabled |
| No policy rule for table 81 | `ip rule show \| grep 81` empty | Chimera may not add policy rules (depends on implementation) |

### 8.6 Note on Route Table Behavior

Chimera (clash-rs) manages its own routing table. The table may only contain routes when there is active traffic being routed through TUN. An empty table at rest is not necessarily a failure — the table's existence confirms the config value `route-table: 81` is being respected.

---

## 9. Scenario TUN7: TUN DNS Hijack Conditional (if enabled)

**QA-ID**: QA-36 (new)  
**Evidence file**: `task-15/task-15-tun7-dns-hijack.txt`

### 9.1 Description

When `tun_dns_hijack=1` in UCI, the generated config should include a `dns-hijack` section within the TUN block that captures all DNS traffic. When `tun_dns_hijack=0` (default), the `dns-hijack` section must NOT appear.

### 9.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is stopped (to regenerate config) | `pgrep -f 'mihomo\|chimera'` returns exit 1 |
| P2 | TUN is enabled | `uci get openchimera.mixin.tun_enabled` = `1` |

### 9.3 Steps — DNS Hijack Enabled

| Step | Command | Expected Result |
|---|---|---|
| 1 | Enable DNS hijack: `uci set openchimera.mixin.tun_dns_hijack=1 && uci commit openchimera` | Exit 0 |
| 2 | Run config generator: `/usr/bin/openchimera-config-gen` | Exit 0 |
| 3 | Check for dns-hijack in TUN block: `grep -A 15 '^tun:' /etc/openchimera/run/config.yaml \| grep 'dns-hijack'` | Entry present |
| 4 | Verify hijack targets: `grep -A 5 'dns-hijack' /etc/openchimera/run/config.yaml` | Contains `0.0.0.0/0` and `::/0` |

### 9.4 Steps — DNS Hijack Disabled

| Step | Command | Expected Result |
|---|---|---|
| 5 | Disable DNS hijack: `uci set openchimera.mixin.tun_dns_hijack=0 && uci commit openchimera` | Exit 0 |
| 6 | Run config generator: `/usr/bin/openchimera-config-gen` | Exit 0 |
| 7 | Verify dns-hijack absent: `grep -c 'dns-hijack' /etc/openchimera/run/config.yaml` | **0** (absent) |
| 8 | Restore DNS hijack to default: `uci set openchimera.mixin.tun_dns_hijack=0 && uci commit openchimera` | Exit 0 |

### 9.5 Expected Results

- With `tun_dns_hijack=1`: `dns-hijack:` block present under `tun:` with targets `0.0.0.0/0` and `::/0`
- With `tun_dns_hijack=0`: `dns-hijack:` block absent from config
- Config remains valid in both states

### 9.6 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| DNS hijack not emitted when enabled | `grep` for dns-hijack empty | Config generator ignores tun_dns_hijack |
| DNS hijack emitted when disabled | `grep` shows dns-hijack with tun_dns_hijack=0 | Config gen always emits dns-hijack |

---

## 10. Evidence Naming Convention

### 10.1 Pattern

```
.omo/evidence/task-15/{scenario-slug}.txt
```

| Scenario | Evidence File | QA-IDs |
|---|---|---|
| Pre-flight checks | `task-15-tun-preflight.txt` | — |
| TUN-enabled config generation | `task-15-tun1-config-generated.txt` | QA-30 |
| TUN-disabled config omission (negative) | `task-15-tun2-config-omitted.txt` | QA-31 |
| TUN device presence | `task-15-tun3-device-presence.txt` | QA-32 |
| No Nikki-only fields (negative) | `task-15-tun4-no-nikki-fields.txt` | QA-33 |
| No TProxy/Redirect rules (negative) | `task-15-tun5-no-tproxy-rules.txt` | QA-34 |
| Route table verification | `task-15-tun6-route-table.txt` | QA-35 |
| DNS hijack conditional | `task-15-tun7-dns-hijack.txt` | QA-36 |
| Summary results | `task-15-tun-summary.txt` | All |

### 10.2 Evidence Content Rules

Each evidence file MUST contain:

```
=== <SCENARIO NAME> ===
Date: <ISO-8601 timestamp>
Target: <target-hostname>

--- Step <N>: <command> ---
<raw stdout + stderr>
exit: <exit code>

--- Assertions ---
- [PASS|FAIL] <assertion description>
- [PASS|FAIL] <assertion description>

--- Summary ---
Result: PASS / FAIL
```

### 10.3 Summary Evidence

After all TUN scenarios are executed, create a consolidated summary:

```
.omo/evidence/task-15/task-15-tun-summary.txt
```

Format:

```
=== TUN QA Summary ===
Date: <ISO-8601 timestamp>
Target: <target-hostname>

| Scenario | Result | Evidence File |
|---|---|---|
| TUN1: TUN-enabled config generation | PASS | task-15-tun1-config-generated.txt |
| TUN2: TUN-disabled config omission | PASS | task-15-tun2-config-omitted.txt |
| TUN3: TUN device presence | PASS | task-15-tun3-device-presence.txt |
| TUN4: No Nikki-only fields | PASS | task-15-tun4-no-nikki-fields.txt |
| TUN5: No TProxy/Redirect rules | PASS | task-15-tun5-no-tproxy-rules.txt |
| TUN6: Route table verification | PASS | task-15-tun6-route-table.txt |
| TUN7: DNS hijack conditional | PASS | task-15-tun7-dns-hijack.txt |

Overall TUN QA Result: PASS
```

---

## 11. QA-Id to Scenario Mapping

| QA-ID | Description | Scenario | Evidence File |
|---|---|---|---|
| QA-30 | TUN-enabled config includes explicit device and route-table | TUN1 | `task-15-tun1-config-generated.txt` |
| QA-31 | TUN-disabled config omits TUN block (negative) | TUN2 | `task-15-tun2-config-omitted.txt` |
| QA-32 | TUN device (`nikki`) appears in `ip link show` | TUN3 | `task-15-tun3-device-presence.txt` |
| QA-33 | Nikki-only fields absent from generated config (negative) | TUN4 | `task-15-tun4-no-nikki-fields.txt` |
| QA-34 | No TProxy/Redirect rules installed (negative guardrail) | TUN5 | `task-15-tun5-no-tproxy-rules.txt` |
| QA-35 | Route table 81 present and verified | TUN6 | `task-15-tun6-route-table.txt` |
| QA-36 | DNS hijack conditional behavior (enabled/disabled toggle) | TUN7 | `task-15-tun7-dns-hijack.txt` |

---

## Appendix A: Quick-Reference Commands

```bash
# UCI: Enable TUN
uci set openchimera.mixin.tun_enabled=1
uci commit openchimera

# UCI: Set TUN device name
uci set openchimera.mixin.tun_device='nikki'
uci commit openchimera

# UCI: Set route table
uci set openchimera.routing.tun_route_table=81
uci commit openchimera

# UCI: Enable DNS hijack
uci set openchimera.mixin.tun_dns_hijack=1
uci commit openchimera

# Regenerate config (without restart)
/usr/bin/openchimera-config-gen

# Inspect generated config
cat /etc/openchimera/run/config.yaml

# Check TUN block
grep -A 10 '^tun:' /etc/openchimera/run/config.yaml

# Check TUN device
ip link show nikki
ip -d link show nikki

# Check route table 81
ip route show table 81

# Check for TProxy rules
nft list ruleset | grep -i 'tproxy\|redirect'
iptables -t mangle -L PREROUTING
iptables -t nat -L PREROUTING

# Validate config
/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml
```

## Appendix B: Config Templates

### Expected TUN-Enabled Config (dns-hijack disabled)

```yaml
mixed-port: 7890
external-controller: 0.0.0.0:9090
log-level: info

tun:
  enable: true
  device: nikki
  route-table: 81
```

### Expected TUN-Enabled Config (dns-hijack enabled)

```yaml
mixed-port: 7890
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

### Expected TUN-Disabled Config

```yaml
mixed-port: 7890
external-controller: 0.0.0.0:9090
log-level: info
```

## Appendix C: Troubleshooting

| Issue | Likely Cause | Fix |
|---|---|---|
| TUN device not created | `kmod-tun` not loaded | `opkg install kmod-tun && modprobe tun` |
| `mihomo -t` fails when TUN enabled | Chimera may need capabilities | Check if binary has `CAP_NET_ADMIN`; run as root |
| TUN block missing in config | `tun_enabled` not `1` | `uci get openchimera.mixin.tun_enabled` |
| Wrong device name in config | UCI `tun_device` not committed | `uci set openchimera.mixin.tun_device=nikki && uci commit` |
| Wrong route table in config | UCI `routing.tun_route_table` not set | `uci set openchimera.routing.tun_route_table=81 && uci commit` |
| `ip link show` shows device but state DOWN | TUN device created but not UP | Daemon manages state; may be normal for TUN |
| Route table 81 not found | Chimera hasn't created it | May only be created on active traffic; check `ip rule` |
| Nikki fields appearing in config | Config generator regression | Immediately fix — these cause validation failures |

---

*End of TUN QA Plan — OpenChimera Milestone 1*
