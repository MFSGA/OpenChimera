# OpenChimera Mixed Port Runtime QA Plan

> **Target**: x86_64 OpenWrt 24.10+ with firewall4  
> **Package**: `openchimera` management layer with `chimera-core` provider  
> **Evidence naming**: `.omo/evidence/task-15/{scenario-slug}.txt` (see §6)  
> **Execution**: 100% agent-automated — zero manual confirmation  
> **Scope**: Milestone 1 — mixed-port HTTP proxy validation only. TProxy/Redirect are deferred.

---

## Table of Contents

1. [Scope & Definitions](#1-scope--definitions)
2. [Pre-Flight Checks](#2-pre-flight-checks)
3. [Scenario MP1: Mixed Port Accepts HTTP Proxy Request](#3-scenario-mp1-mixed-port-accepts-http-proxy-request)
4. [Scenario MP2: Mixed Port Rejects Unreachable Target (Daemon Must Not Crash)](#4-scenario-mp2-mixed-port-rejects-unreachable-target-daemon-must-not-crash)
5. [Scenario MP3: Direct Connection (No Proxy) Reaches Different Endpoint](#5-scenario-mp3-direct-connection-no-proxy-reaches-different-endpoint)
6. [Scenario MP4: Port Listening Verification](#6-scenario-mp4-port-listening-verification)
7. [Scenario MP5: No TProxy/Redirect Rules Installed (Negative)](#7-scenario-mp5-no-tproxyredirect-rules-installed-negative)
8. [Scenario MP6: Mixed Port Handle CONNECT Method (HTTPS Tunnel)](#8-scenario-mp6-mixed-port-handle-connect-method-https-tunnel)
9. [Evidence Naming Convention](#9-evidence-naming-convention)
10. [QA-Id to Scenario Mapping](#10-qa-id-to-scenario-mapping)

---

## 1. Scope & Definitions

### 1.1 What This Plan Covers

- **Mixed port** (`mixed-port: 7890`) accepts HTTP proxy requests on a single TCP port that handles both HTTP and HTTPS CONNECT tunneling.
- Service must remain stable under normal and failure proxy request conditions.
- Port binding is confirmed via `ss` / `netstat`.
- No transparent proxy (TProxy/Redirect) mechanisms are installed by milestone 1.
- Daemon does **not** crash on unreachable upstream targets.

### 1.2 What This Plan Does NOT Cover

- TProxy or Redirect rule verification (handled in separate TUN QA plan and deferred to later milestones).
- SOCKS-port or HTTP-port specific behavior (those ports are optional; mixed-port handles both).
- TUN device or routing table verification (covered in `task-15-tun-qa.md`).
- Service lifecycle (start/stop/restart — covered in Task 14).

### 1.3 Key Files

| File | Path | Role |
|---|---|---|
| Generated config | `/etc/openchimera/run/config.yaml` | Runtime config containing `mixed-port` |
| Core binary | `/usr/libexec/chimera` | Chimera_Client daemon |
| Alternative | `/usr/bin/mihomo → /usr/libexec/chimera` | OpenWrt alternatives symlink |
| Service log | `/var/log/openchimera/core.log` | Daemon stdout/stderr |
| UCI config | `/etc/config/openchimera` | Persistent configuration |

### 1.4 UCI Section Reference

The mixed port value is read from UCI section `mixin`:

```bash
# Read current mixed-port value
uci get openchimera.mixin.mixed_port    # default: 7890

# Change value
uci set openchimera.mixin.mixed_port=7890
uci commit openchimera

# Restart service for change to take effect
/etc/init.d/openchimera restart
```

> **Note**: Changing `mixed-port` requires a full restart. Chimera does not support SIGHUP hot reload in milestone 1.

### 1.5 Default Port Value

From `config_gen.sh` line 101:
```bash
yaml_kv "mixed-port" "${mixed_port:-7890}"
```

From `openchimera.conf` line 15:
```
option mixed_port '7890'
```

Default mixed port is **7890** unless overridden in UCI.

---

## 2. Pre-Flight Checks

Before executing any mixed-port scenario, verify:

```bash
# 1. Service is running and enabled
ssh root@<target-ip> "/etc/init.d/openchimera status"
# Expected: "running" with PID

# 2. Mixed port is configured to 7890
ssh root@<target-ip> "uci get openchimera.mixin.mixed_port"
# Expected: 7890

# 3. Generated config contains mixed-port
ssh root@<target-ip> "grep 'mixed-port:' /etc/openchimera/run/config.yaml"
# Expected: mixed-port: 7890

# 4. Core binary responds to version check
ssh root@<target-ip> "/usr/bin/mihomo -V"
# Expected: version string, exit 0

# 5. Target has basic network reachability
ssh root@<target-ip> "ping -c 1 -W 3 example.com 2>&1 || true"
# Expected: ping succeeds or captured for context
```

All pre-flight commands and their output MUST be captured to:
`.omo/evidence/task-15/task-15-mixed-port-preflight.txt`

---

## 3. Scenario MP1: Mixed Port Accepts HTTP Proxy Request

**QA-IDs**: QA-20 (from `docs/qa-checklist.md`)  
**Evidence file**: `task-15/task-15-mp1-http-proxy.txt`

### 3.1 Description

Verify that the Chimera daemon listening on `mixed-port: 7890` accepts an HTTP proxy request sent via `curl -x`. This is the primary happy-path test for the mixed port.

### 3.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running (Task 14 S3 passed) | `pgrep -f 'mihomo\|chimera'` returns a PID |
| P2 | `mixed-port: 7890` is in generated config | `grep 'mixed-port: 7890' /etc/openchimera/run/config.yaml` |
| P3 | Target has internet access or controlled HTTP endpoint | `ping -c 1 -W 3 example.com` (or alternative reachable endpoint) |
| P4 | `curl` is installed on target | `which curl` |
| P5 | Service log is accessible | `ls -la /var/log/openchimera/core.log` |

### 3.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Record PID before test: `PID_BEFORE=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID=$PID_BEFORE"` | Non-empty numeric PID |
| 2 | **Issue HTTP proxy request**: `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10` | Exit 0 |
| 3 | Capture HTTP response status: `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10 -s \| head -5` | Contains `HTTP/1.1 200 OK` or similar success status |
| 4 | Verify daemon is still alive: `PID_AFTER=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID_AFTER=$PID_AFTER"` | Same PID as before |
| 5 | Check service log for proxy activity: `tail -20 /var/log/openchimera/core.log` | Log may contain request-related entries (not required but captured for evidence) |
| 6 | Verify daemon exit code from curl perspective: `echo "Curl exit code: $?"` | Exit code 0 (captured from step 2) |

### 3.4 Expected Results

- `curl -x` exits 0
- HTTP response headers are returned (e.g., `HTTP/1.1 200 OK`)
- Daemon PID is unchanged after the request (no crash, no restart)
- Service continues to run after the request completes

### 3.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Curl exit non-zero | `curl: (7) Failed to connect` | Mixed port not listening; service not started |
| Curl exit non-zero | `curl: (28) Connection timed out` | Firewall blocking; daemon stuck |
| Curl exit non-zero | `curl: (52) Empty reply from server` | Daemon accepted conn but crashed |
| PID changed after request | `PID_AFTER != PID_BEFORE` | Daemon crashed and was respawned by procd |
| No HTTP response headers | curl returns data but no status line | Response format unexpected |

### 3.6 Robustness Notes

- If `example.com` is unreachable from the target, substitute with a known-valid HTTP endpoint (e.g., `http://httpbin.org/get`).
- Use `--max-time 10` to prevent curl from hanging indefinitely.
- If `--max-time` is not supported on the target's curl version, use `--connect-timeout 5 --max-time 10`.

### 3.7 Evidence Collection Script

```bash
evidence_file=".omo/evidence/task-15/task-15-mp1-http-proxy.txt"
{
    echo "=== MP1: Mixed Port Accepts HTTP Proxy Request ==="
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Target: $(hostname)"
    echo ""
    
    echo "--- Step 1: Record PID before test ---"
    PID_BEFORE=$(pgrep -f 'mihomo|chimera' | head -1)
    echo "PID_BEFORE=$PID_BEFORE"
    echo ""
    
    echo "--- Step 2: curl HTTP proxy request ---"
    curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10
    echo "exit: $?"
    echo ""
    
    echo "--- Step 3: Captured HTTP response ---"
    curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10 -s | head -5
    echo ""
    
    echo "--- Step 4: Verify daemon alive ---"
    PID_AFTER=$(pgrep -f 'mihomo|chimera' | head -1)
    echo "PID_AFTER=$PID_AFTER"
    if [ "$PID_BEFORE" = "$PID_AFTER" ]; then
        echo "RESULT: PID unchanged (daemon stable)"
    else
        echo "RESULT: PID CHANGED (possible crash+respawn)"
    fi
    echo ""
    
    echo "--- Step 5: Service log tail ---"
    tail -20 /var/log/openchimera/core.log 2>/dev/null || echo "Log not accessible"
    echo ""
    
    echo "--- Summary ---"
    echo "Result: PASS / FAIL"
} 2>&1 | tee "$evidence_file"
```

---

## 4. Scenario MP2: Mixed Port Rejects Unreachable Target (Daemon Must Not Crash)

**QA-IDs**: QA-21 (from `docs/qa-checklist.md`)  
**Evidence file**: `task-15/task-15-mp2-unreachable-target.txt`

### 4.1 Description

When a proxy request targets an unreachable/ nonexistent host, the daemon MUST NOT crash. The request may time out or fail with a connection error, but the daemon process must survive and continue serving subsequent requests.

This is a **negative / resilience test**.

### 4.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running (same as MP1 P1) | `pgrep -f 'mihomo\|chimera'` returns PID |
| P2 | `mixed-port: 7890` is listening | `ss -tlnp \| grep 7890` |
| P3 | Target DNS resolution works (or fails as expected) | `host nonexistent.invalid` (expected: failure) |

### 4.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Record PID: `PID_BEFORE=$(pgrep -f 'mihomo\|chimera' \| head -1)` | Non-empty PID |
| 2 | **Issue request to unreachable host**: `curl -x http://127.0.0.1:7890 http://nonexistent.invalid --max-time 5` | Exit non-zero (connection error) |
| 3 | Capture curl error: `curl -x http://127.0.0.1:7890 http://nonexistent.invalid --max-time 5 -v 2>&1 \| tail -10` | Contains error like "Could not resolve host" or "Connection timed out" |
| 4 | **Verify daemon still alive**: `PID_AFTER=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID_AFTER=$PID_AFTER"` | PID unchanged from before |
| 5 | Verify service still functional: `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10` | Exit 0 (follow-up request succeeds) |
| 6 | Check service log for errors: `tail -20 /var/log/openchimera/core.log` | No crash trace; error logged gracefully |

### 4.4 Expected Results

- `curl` to nonexistent target exits non-zero (connection error)
- Daemon PID is **unchanged** after the failed request
- A subsequent valid HTTP proxy request succeeds (exit 0)
- Service log does NOT contain a crash/panic trace
- The daemon is resilient — one bad request does not take down the process

### 4.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Daemon crashes | PID changed or daemon unreachable | Chimera crashes on upstream resolution failure |
| Daemon hangs | Subsequent valid request also fails | Daemon stuck in connection attempt |
| Valid request fails after bad request | Curl exit non-zero to example.com | Daemon state corrupted by bad request |
| No error in log | Log tail shows nothing | Daemon silently swallowed failure (acceptable but note it) |

### 4.6 Key Assertion Logic

```bash
# Core assertions
PID_BEFORE=$(pgrep -f 'mihomo|chimera' | head -1)
curl -x http://127.0.0.1:7890 http://nonexistent.invalid --max-time 5
[ $? -ne 0 ] || { echo "FAIL: expected non-zero exit"; exit 1; }
PID_AFTER=$(pgrep -f 'mihomo|chimera' | head -1)
[ "$PID_BEFORE" = "$PID_AFTER" ] && echo "PASS: daemon stable" || { echo "FAIL: PID changed"; exit 1; }
```

### 4.7 Note on DNS Resolution

If the target's DNS resolver returns a synthetic IP for `nonexistent.invalid` (some ISPs do), use a private-range IP instead:
```bash
curl -x http://127.0.0.1:7890 http://10.255.255.1 --max-time 5
```

---

## 5. Scenario MP3: Direct Connection (No Proxy) Reaches Different Endpoint

**QA-ID**: QA-22 (new)  
**Evidence file**: `task-15/task-15-mp3-direct-connect.txt`

### 5.1 Description

Verify that a direct HTTP connection (without the proxy) to the same target reaches the endpoint through the default gateway, not through the proxy daemon. This confirms the proxy is not acting as a transparent proxy or intercepting non-proxy traffic.

### 5.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running | `pgrep -f 'mihomo\|chimera'` returns PID |
| P2 | Network has a non-proxied path to example.com | `ping -c 1 example.com` |

### 5.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | **Direct HTTP request (no proxy)**: `curl http://example.com -I --max-time 10` | Exit 0 (goes through default gateway) |
| 2 | Capture response headers: `curl http://example.com -I --max-time 10 -s \| head -5` | HTTP response from endpoint |
| 3 | Verify proxy is still running: `pgrep -f 'mihomo\|chimera'` | PID present |
| 4 | Compare with proxied response (optional): `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10 -s \| head -5` | Response body may differ (proxied vs direct) |

### 5.4 Expected Results

- Direct `curl` succeeds (exit 0)
- Proxy is not interfering with non-proxy traffic
- The response may have different headers (e.g., `Via` header added by proxy) but both work

### 5.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Direct connection fails | Curl exit non-zero | Firewall blocks outbound; proxy is required for all traffic (not expected in milestone 1) |
| Proxy not running after direct test | PID missing | Unrelated crash |

---

## 6. Scenario MP4: Port Listening Verification

**QA-ID**: QA-23 (new)  
**Evidence file**: `task-15/task-15-mp4-port-listening.txt`

### 6.1 Description

Confirm that the Chimera daemon is actually listening on TCP port 7890 before issuing any proxy requests. This is a pre-requisite check formalized as its own scenario.

### 6.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running | `pgrep -f 'mihomo\|chimera'` returns PID |

### 6.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Check listening port with `ss`: `ss -tlnp \| grep 7890` | Socket displayed; process matches mihomo/chimera |
| 2 | Check listening port with `netstat` (fallback): `netstat -tlnp 2>/dev/null \| grep 7890 \|\| echo "netstat not available"` | If available, shows listening socket |
| 3 | Verify process ownership: `ss -tlnp \| grep 7890 \| head -1` | Shows `pid=<PID>, ...` matching Chimera PID |
| 4 | Verify only one listener on 7890: `ss -tlnp \| grep -c 7890` | Exactly 1 (no port conflicts) |
| 5 | Confirm mixed-port is NOT on a TProxy/TPROXY socket: `ss -tlnp \| grep 7890 \| grep -o 'tproxy\|TPROXY' \|\| echo "No TProxy flag"` | TProxy flag absent |

### 6.4 Expected Results

- `ss` shows TCP listening on 0.0.0.0:7890 or [::]:7890
- Process field matches Chimera PID
- No TProxy flag on the socket (confirms plain TCP proxy, not transparent)

### 6.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Port not listening | `ss` returns empty | Service not started; config has different port |
| Wrong PID owner | PID does not match Chimera | Another process on port 7890 (conflict) |
| TProxy flag present | `tproxy` in socket flags | Mixed port acting as transparent proxy (unexpected in milestone 1) |

---

## 7. Scenario MP5: No TProxy/Redirect Rules Installed (Negative)

**QA-ID**: QA-24 (new)  
**Evidence file**: `task-15/task-15-mp5-no-tproxy-rules.txt`

### 7.1 Description

Milestone 1 does **not** implement TProxy or Redirect transparent proxy modes. This scenario verifies that no TProxy/Redirect nftables rules, iptables rules, or routing policies have been installed by the `openchimera` package or init script. This is a **critical guardrail check**.

### 7.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running or stopped (either is fine) | — |
| P2 | `nft` command available (OpenWrt firewall4) | `which nft \|\| echo "nft not available"` |
| P3 | `iptables` command available (legacy fallback) | `which iptables \|\| echo "iptables not available"` |
| P4 | `ip rule` and `ip route` available | `which ip` |

### 7.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | **Check nftables for TProxy rules**: `nft list ruleset 2>/dev/null \| grep -i 'tproxy\|redirect' \|\| echo "No tproxy/redirect rules in nftables"` | No TProxy/Redirect rules present |
| 2 | **Check iptables for TProxy/Redirect rules**: `iptables -t mangle -L PREROUTING 2>/dev/null \| grep -i 'tproxy\|redirect' \|\| echo "No tproxy/redirect in mangle/PREROUTING"` | No TProxy/Redirect rules present |
| 3 | Check iptables NAT table: `iptables -t nat -L PREROUTING 2>/dev/null \| grep -i 'tproxy\|redirect\|7890' \|\| echo "No redirect rules in nat/PREROUTING"` | No redirect rules to port 7890 |
| 4 | **Check for policy routing rules**: `ip rule show 2>/dev/null \| grep -i 'tun\|chimera\|mihomo\|7890' \|\| echo "No additional routing policy rules"` | No extra routing rules (beyond system defaults) |
| 5 | **Check for Chimera-specific nftables chains**: `nft list ruleset 2>/dev/null \| grep -i 'chimera\|mihomo\|openchimera' \|\| echo "No Chimera-specific nftables chains"` | No Chimera-managed nftables chains |
| 6 | **Search init script for TProxy/Redirect references**: `grep -rn 'tproxy\|redirect\|nft\|tcp\|divert' /etc/init.d/openchimera /usr/bin/openchimera* 2>/dev/null \|\| echo "No TProxy/Redirect references in scripts"` | No TProxy/Redirect implementation code |
| 7 | Verify the only open port for proxy traffic is the mixed port: `ss -tlnp \| grep -E '7890\|1080\|8080'` | Only configured proxy ports are listening |

### 7.4 Expected Results

- `nft list ruleset` does NOT contain any `tproxy` or `redirect` statements
- `iptables -t mangle -L PREROUTING` does NOT contain TProxy rules
- `iptables -t nat -L PREROUTING` does NOT contain REDIRECT rules to port 7890
- `ip rule show` does NOT contain Chimera-specific routing policy rules
- No Chimera-managed nftables chains exist
- The init script and config generator contain no TProxy/Redirect logic
- Only the configured proxy ports (mixed-port, optionally socks-port, port) are listening

### 7.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| TProxy rule present | `nft list ruleset` shows `tproxy` | TProxy implementation prematurely added |
| Redirect rule present | `iptables -t nat` shows REDIRECT to 7890 | Redirect implementation prematurely added |
| Extra routing policy | `ip rule show` shows non-default rules | Policy routing for TUN misapplied |
| Chimera nftables chain | Custom chain named `chimera*` | nftables integration added in milestone 1 |
| TProxy code in scripts | Grep finds TProxy code | Implementation leaked into milestone 1 scripts |

### 7.6 Key Assertion Logic

```bash
# Core assertions — all MUST pass for milestone 1 guardrail
ERRORS=0

# Check nftables
if nft list ruleset 2>/dev/null | grep -qi 'tproxy\|redirect'; then
    echo "FAIL: TProxy/Redirect rules found in nftables"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: No TProxy/Redirect rules in nftables"
fi

# Check iptables mangle
if iptables -t mangle -L PREROUTING 2>/dev/null | grep -qi 'tproxy'; then
    echo "FAIL: TProxy rules found in iptables mangle table"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: No TProxy rules in iptables mangle"
fi

# Check iptables nat
if iptables -t nat -L PREROUTING 2>/dev/null | grep -qi 'redirect.*7890'; then
    echo "FAIL: REDIRECT rules found in iptables nat table"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: No REDIRECT rules in iptables nat"
fi

# Final
if [ "$ERRORS" -eq 0 ]; then
    echo "PASS: Milestone 1 has no TProxy/Redirect implementation"
else
    echo "FAIL: $ERRORS guardrail violations found"
    exit 1
fi
```

---

## 8. Scenario MP6: Mixed Port Handle CONNECT Method (HTTPS Tunnel)

**QA-ID**: QA-25 (new)  
**Evidence file**: `task-15/task-15-mp6-https-connect.txt`

### 8.1 Description

The mixed port must also handle HTTPS CONNECT tunnel requests. Verify that curl can establish a tunnel through the proxy to an HTTPS endpoint.

### 8.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | Service is running | `pgrep -f 'mihomo\|chimera'` returns PID |
| P2 | `mixed-port: 7890` is in generated config | `grep 'mixed-port: 7890' /etc/openchimera/run/config.yaml` |
| P3 | HTTPS endpoint is reachable | `curl -o /dev/null -s -w '%{http_code}' https://example.com --max-time 10 \|\| echo "HTTPS may not be reachable directly"` |

### 8.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Record PID: `PID_BEFORE=$(pgrep -f 'mihomo\|chimera' \| head -1)` | Non-empty PID |
| 2 | **Issue HTTPS CONNECT via proxy**: `curl -x http://127.0.0.1:7890 https://example.com -I --max-time 15` | Exit 0 (tunnel established) |
| 3 | Capture response code: `curl -x http://127.0.0.1:7890 https://example.com -I --max-time 15 -s \| head -5` | Contains `HTTP/2 200` or similar |
| 4 | Verify daemon alive: `PID_AFTER=$(pgrep -f 'mihomo\|chimera' \| head -1)` | PID unchanged |
| 5 | Check for CONNECT entries in log: `grep -i 'connect\|tunnel' /var/log/openchimera/core.log 2>/dev/null \|\| echo "No CONNECT entries in log"` | May be empty (depends on log level) |

### 8.4 Expected Results

- `curl -x` with HTTPS target exits 0
- HTTP response headers returned from the HTTPS endpoint
- `CONNECT` tunnel is established through the mixed port
- Daemon PID unchanged (no crash)
- Service continues running after the HTTPS request

### 8.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| CONNECT fails | Curl returns `Received HTTP code 4xx` from proxy | Mixed port not handling CONNECT |
| TLS error | Curl returns SSL/TLS error | Chimera TLS interception or upstream TLS issue |
| Timeout | `curl: (28) Connection timed out` after 15s | CONNECT handshake hung |
| PID changed | Daemon restarted | Crash during CONNECT tunnel setup |

---

## 9. Evidence Naming Convention

### 9.1 Pattern

```
.omo/evidence/task-15/{scenario-slug}.txt
```

| Scenario | Evidence File | QA-IDs |
|---|---|---|
| Pre-flight checks | `task-15-mixed-port-preflight.txt` | — |
| HTTP proxy request (happy path) | `task-15-mp1-http-proxy.txt` | QA-20 |
| Unreachable target (resilience) | `task-15-mp2-unreachable-target.txt` | QA-21 |
| Direct connection (no proxy) | `task-15-mp3-direct-connect.txt` | QA-22 |
| Port listening | `task-15-mp4-port-listening.txt` | QA-23 |
| No TProxy/Redirect rules | `task-15-mp5-no-tproxy-rules.txt` | QA-24 |
| HTTPS CONNECT tunnel | `task-15-mp6-https-connect.txt` | QA-25 |
| Summary results | `task-15-mixed-port-summary.txt` | All |

### 9.2 Evidence Content Rules

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

### 9.3 Summary Evidence

After all MP scenarios are executed, create a consolidated summary:

```
.omo/evidence/task-15/task-15-mixed-port-summary.txt
```

Format:

```
=== Mixed Port QA Summary ===
Date: <ISO-8601 timestamp>
Target: <target-hostname>

| Scenario | Result | Evidence File |
|---|---|---|
| MP1: HTTP proxy request | PASS | task-15-mp1-http-proxy.txt |
| MP2: Unreachable target resilience | PASS | task-15-mp2-unreachable-target.txt |
| MP3: Direct connection | PASS | task-15-mp3-direct-connect.txt |
| MP4: Port listening | PASS | task-15-mp4-port-listening.txt |
| MP5: No TProxy/Redirect rules | PASS | task-15-mp5-no-tproxy-rules.txt |
| MP6: HTTPS CONNECT tunnel | PASS | task-15-mp6-https-connect.txt |

Overall Mixed Port QA Result: PASS
```

---

## 10. QA-Id to Scenario Mapping

| QA-ID | Description | Scenario | Evidence File |
|---|---|---|---|
| QA-20 | Mixed port handles HTTP proxy request | MP1 | `task-15-mp1-http-proxy.txt` |
| QA-21 | Mixed port handles bad request without crashing daemon | MP2 | `task-15-mp2-unreachable-target.txt` |
| QA-22 | Direct (non-proxy) connection works independently | MP3 | `task-15-mp3-direct-connect.txt` |
| QA-23 | Port listening verified on configured mixed port | MP4 | `task-15-mp4-port-listening.txt` |
| QA-24 | No TProxy/Redirect rules installed (negative guardrail) | MP5 | `task-15-mp5-no-tproxy-rules.txt` |
| QA-25 | Mixed port handles HTTPS CONNECT tunnel | MP6 | `task-15-mp6-https-connect.txt` |

---

## Appendix A: Quick-Reference Commands

```bash
# Check mixed-port in generated config
grep 'mixed-port' /etc/openchimera/run/config.yaml

# Verify port listening
ss -tlnp | grep 7890

# HTTP proxy request
curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10

# HTTPS CONNECT via proxy
curl -x http://127.0.0.1:7890 https://example.com -I --max-time 15

# Check daemon PID
pgrep -f 'mihomo|chimera'

# Check nftables for TProxy
nft list ruleset | grep -i 'tproxy\|redirect'

# Check iptables mangle for TProxy
iptables -t mangle -L PREROUTING

# Check iptables nat for REDIRECT
iptables -t nat -L PREROUTING
```

## Appendix B: Troubleshooting

| Issue | Likely Cause | Fix |
|---|---|---|
| `curl: (7) couldn't connect to host` | Mixed port not listening | Verify service is running; check `ss -tlnp \| grep 7890` |
| `curl: (28) connection timed out` | Firewall blocking or daemon hung | Check `nft list ruleset` for firewall rules; check daemon log |
| `curl: (56) Failure when receiving data` | Connection dropped mid-transfer | Check daemon stability; look for crash in logs |
| `pgrep` returns empty | Service not running | `/etc/init.d/openchimera status`; check `logread` |
| `nft: not found` | firewall4 not installed | Install `nftables` package |
| Mixed port shows wrong value | UCI or config not updated | `uci get openchimera.mixin.mixed_port`; `grep mixed-port config.yaml` |

---

*End of Mixed Port QA Plan — OpenChimera Milestone 1*
