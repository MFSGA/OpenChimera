# OpenChimera Install/Init Lifecycle QA Plan

> **Target**: x86_64 OpenWrt 24.10+ with firewall4  
> **Packages**: `chimera-core` + `openchimera`  
> **Evidence naming**: `.omo/evidence/task-14/{scenario-slug}.txt` (see §5)  
> **Execution**: 100% agent-automated — zero manual confirmation

---

## Table of Contents

1. [Scope & Definitions](#1-scope--definitions)
2. [Pre-Flight Checks](#2-pre-flight-checks)
3. [Lifecycle Scenario S1: Package Install](#3-lifecycle-scenario-s1-package-install)
4. [Lifecycle Scenario S2: Disabled Service Start (Negative)](#4-lifecycle-scenario-s2-disabled-service-start-negative)
5. [Lifecycle Scenario S3: Enabled Service Start](#5-lifecycle-scenario-s3-enabled-service-start)
6. [Lifecycle Scenario S4: Service Restart](#6-lifecycle-scenario-s4-service-restart)
7. [Lifecycle Scenario S5: Service Stop](#7-lifecycle-scenario-s5-service-stop)
8. [Lifecycle Scenario S6: Invalid Config Blocks Start (Negative)](#8-lifecycle-scenario-s6-invalid-config-blocks-start-negative)
9. [Evidence Naming Convention](#9-evidence-naming-convention)
10. [QA-Id to Scenario Mapping](#10-qa-id-to-scenario-mapping)

---

## 1. Scope & Definitions

### 1.1 Lifecycle State Machine

```
                      ┌──────────────┐
                      │  NOT INSTALLED│
                      └──────┬───────┘
                             │ opkg install
                             ▼
                      ┌──────────────┐
                  ┌──►│   INSTALLED  │◄──────────────┐
                  │   │ (enabled=0)  │                │
                  │   └──────┬───────┘                │
                  │          │ uci set enabled=1      │
                  │          ▼                        │
                  │   ┌──────────────┐                │
                  │   │   ENABLED    │                │
                  │   │ (enabled=1)  │                │
                  │   └──────┬───────┘                │
                  │          │ /etc/init.d/ start     │
                  │          ▼                        │
                  │   ┌──────────────┐   restart      │
                  │   │   RUNNING    │────────────────│
                  │   │  (PID alive) │                │
                  │   └──────┬───────┘                │
                  │          │ stop                   │
                  │          ▼                        │
                  │   ┌──────────────┐                │
                  └───┤   STOPPED    │────────────────┘
                      │  (no PID)    │
                      └──────────────┘

  FAILURE PATHS:
    enabled=0 → start → NO process (S2)
    invalid config → start → NO process, logged error (S6)
```

### 1.2 Key Components

| Component | Path | Role |
|---|---|---|
| Core binary | `/usr/libexec/chimera` | Chimera_Client (clash-rs) daemon |
| Alternative | `/usr/bin/mihomo → /usr/libexec/chimera` | OpenWrt alternatives symlink |
| Config generator | `/usr/bin/openchimera-config-gen` | Reads UCI, writes `/etc/openchimera/run/config.yaml` |
| Init script | `/etc/init.d/openchimera` | procd service lifecycle |
| UCI config | `/etc/config/openchimera` | Persistent configuration |
| Log file | `/var/log/openchimera/core.log` | Daemon stdout/stderr |
| Runtime dir | `/etc/openchimera/run/` | Generated config + core runtime |
| Debug script | `/usr/bin/openchimera-debug` | Diagnostic dump |

### 1.3 UCI Section Reference

The init script reads from section name `config` (not `main`).  
Correct UCI paths for lifecycle QA:

```bash
# Enable/disable (read via config_get_bool in init)
uci set openchimera.config.enabled=1    # enable
uci set openchimera.config.enabled=0    # disable

# Log path
uci set openchimera.config.log_file='/var/log/openchimera/core.log'

# Log level
uci set openchimera.config.log_level='warning'

# Ports (section: mixin)
uci set openchimera.mixin.mixed_port='7890'

# Always commit after UCI changes
uci commit openchimera
```

> ⚠️ **Note**: The QA checklist in task-6 references `openchimera.main.enabled`.
> The actual UCI section name is `config`, not `main`. Use `openchimera.config.enabled`
> for all lifecycle commands. The init script confirms this at line 26:
> `config_get_bool enabled config enabled 0`.

### 1.4 Init Script Behavior Summary

From `/etc/init.d/openchimera`:

| Condition | Behavior |
|---|---|
| `enabled=0` | Logs "Service disabled", returns 1, **no process** |
| Binary missing | Logs error, returns 1 |
| Config gen fails | Logs "Config generation failed", returns 1 |
| `mihomo -t` fails | Logs "Configuration validation failed", returns 1, **no process** |
| All checks pass | Launches via procd: `mihomo --compatibility -d WORK_DIR -c CONFIG_FILE --log-file LOG_FILE` |
| `stop_service()` | Empty (`:`) — procd handles SIGTERM |
| `reload_service()` | Calls `stop` then `start` |

---

## 2. Pre-Flight Checks

Before executing any lifecycle scenario, verify:

```bash
# 1. Target reachable (SSH)
ssh root@<target-ip> "uptime"

# 2. Packages not yet installed
ssh root@<target-ip> "opkg list-installed | grep -E 'chimera-core|openchimera'"
# Expected: empty output (or not found)

# 3. No stale Chimera process
ssh root@<target-ip> "pgrep -f 'mihomo|chimera'; echo 'exit: $?'"
# Expected: no PID output; exit 1

# 4. No stale runtime directory
ssh root@<target-ip> "ls -la /etc/openchimera/run/ 2>&1 || echo 'dir not found'"

# 5. No stale log directory
ssh root@<target-ip> "ls -la /var/log/openchimera/ 2>&1 || echo 'dir not found'"
```

All pre-flight commands and their output MUST be captured to:
`.omo/evidence/task-14/task-14-preflight.txt`

---

## 3. Lifecycle Scenario S1: Package Install

**QA-IDs**: QA-04, QA-05  
**Evidence file**: `task-14/task-14-install-opkg.txt`

### 3.1 Description

Both `chimera-core` and `openchimera` `.ipk` packages are transferred to the
target and installed via `opkg`. This establishes the baseline installed state
for all subsequent lifecycle scenarios.

### 3.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | SDK build completed (Task 13) | `.ipk` files exist in SDK output |
| P2 | `.ipk` files transferred to target | `scp bin/packages/x86_64/openchimera/*.ipk root@<target>:/tmp/` |
| P3 | Target is x86_64 OpenWrt 24.10+ | `cat /proc/cpuinfo | grep -q 'GenuineIntel\|AuthenticAMD' && echo ok` |
| P4 | Target has internet or local feed access | `opkg update` succeeds (or packages in `/tmp/`) |

### 3.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | `opkg install /tmp/chimera-core_*.ipk` | Exit 0; "Package chimera-core installed" |
| 2 | `opkg install /tmp/openchimera_*.ipk` | Exit 0; "Package openchimera installed" |
| 3 | `opkg list-installed \| grep -E 'chimera-core\|openchimera'` | Both packages listed with version |
| 4 | `ls -la /usr/libexec/chimera` | File exists, executable |
| 5 | `ls -la /usr/bin/mihomo` | Symlink/file exists (alternatives) |
| 6 | `ls -la /etc/config/openchimera` | UCI config file exists |
| 7 | `ls -la /etc/init.d/openchimera` | Init script exists, executable |
| 8 | `ls -la /usr/bin/openchimera-config-gen` | Config gen exists, executable |
| 9 | `ls -la /usr/bin/openchimera-debug` | Debug script exists, executable |
| 10 | `ls -d /etc/openchimera/run/` | Runtime directory exists |
| 11 | `ls -d /etc/openchimera/profiles/` | Profiles directory exists |
| 12 | `/usr/bin/mihomo -V` | Prints version string; exit 0 |
| 13 | `readlink -f /usr/bin/mihomo` | Resolves to `/usr/libexec/chimera` |
| 14 | `uci show openchimera` | All config sections present; `openchimera.config.enabled='0'` |
| 15 | `ls -la /etc/openchimera/config.yaml.default` | Default config file present |

### 3.4 Expected Results

- All 15 steps produce exit code 0 and valid output
- `chimera-core` and `openchimera` are listed by `opkg list-installed`
- `/usr/bin/mihomo` exists and resolves to `/usr/libexec/chimera`
- `/etc/config/openchimera` contains defaults from `openchimera.conf`
- `openchimera.config.enabled` defaults to `'0'` (disabled)
- All runtime directories (`run/`, `profiles/`) exist
- Helper scripts (`openchimera-config-gen`, `openchimera-debug`) are present

### 3.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| `opkg` dependency error | "Failed to depend on ..." | Missing feed or kernel module |
| `opkg` architecture error | "has no valid architecture" | Wrong SDK target arch |
| Binary missing | `ls: /usr/libexec/chimera: No such file or directory` | chimera-core install failed |
| No alternatives symlink | `/usr/bin/mihomo` not found | `update-alternatives` step failed |
| UCI file missing | `uci: Entry not found` | openchimera install failed |
| Config gen missing | `/usr/bin/openchimera-config-gen` not found | openchimera install failure |

### 3.6 Rollback / Cleanup

```bash
# If install fails, reset state:
opkg remove openchimera chimera-core --force-removal-of-dependent-packages
rm -rf /etc/openchimera/
rm -rf /var/log/openchimera/
rm -f /etc/config/openchimera
```

---

## 4. Lifecycle Scenario S2: Disabled Service Start (Negative)

**QA-ID**: QA-15  
**Evidence file**: `task-14/task-14-disabled-start.txt`

### 4.1 Description

With `openchimera.config.enabled=0` (the default after install), calling
`/etc/init.d/openchimera start` MUST NOT spawn a Chimera process. The init
script MUST log "Service disabled" and return non-zero.

### 4.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | S1 completed (packages installed) | S1 evidence saved |
| P2 | `openchimera.config.enabled` is `'0'` | `[ "$(uci get openchimera.config.enabled)" = "0" ]` |
| P3 | No stale Chimera process | `pgrep -f 'mihomo\|chimera'` returns exit 1 |
| P4 | `logread` accessible for logger output | `logread -l 5 \| head -5` succeeds |

### 4.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | `uci get openchimera.config.enabled` | `0` |
| 2 | `pgrep -f 'mihomo\|chimera'`; `echo "exit: $?"` | No output; exit 1 |
| 3 | `/etc/init.d/openchimera start`; `echo "exit: $?"` | Exit non-zero (likely 1) |
| 4 | `pgrep -f 'mihomo\|chimera'`; `echo "exit: $?"` | No output; exit 1 (no process spawned) |
| 5 | `pidof mihomo`; `echo "exit: $?"` | Empty; exit 1 |
| 6 | `logread -l 20 \| grep openchimera \| tail -5` | Contains "Service disabled" message |
| 7 | `/etc/init.d/openchimera status`; `echo "exit: $?"` | Exit non-zero; "not running" or similar |
| 8 | `ls -la /etc/openchimera/run/ 2>&1` | Directory may exist but empty or no config.yaml |
| 9 | `ls -la /var/log/openchimera/ 2>&1` | Log directory may not exist (not created) |

### 4.4 Expected Results

- `start` command exits non-zero (does NOT daemonize)
- `pgrep` / `pidof` return no PID (exit 1)
- `logread` shows `openchimera: Service disabled (openchimera.config.enabled=0)`
- No `config.yaml` generated (config gen not reached)
- No process spawned under any circumstances

### 4.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Process started despite disabled | `pgrep` returns a PID | init script ignores `enabled` check |
| No log message | `logread` shows no openchimera entry | init script exits before logging |
| Exit code 0 | `/etc/init.d/openchimera start` returns 0 | procd returns success despite disabled |

### 4.6 Key Assertion Logic

```bash
# Core assertion — must produce:
#   pgrep exit code = 1
#   logread contains "Service disabled"
pgrep -f 'mihomo|chimera' && { echo "FAIL: process found when disabled"; exit 1; }
logread -l 20 | grep -q "Service disabled" && echo "PASS: disabled message logged"
```

---

## 5. Lifecycle Scenario S3: Enabled Service Start

**QA-IDs**: QA-12, QA-18, QA-19  
**Evidence file**: `task-14/task-14-enabled-start.txt`

### 5.1 Description

With `openchimera.config.enabled=1`, calling `/etc/init.d/openchimera start`
MUST spawn a Chimera daemon process via procd. A PID MUST be captured, the
log file MUST exist after startup, and the log MUST contain a startup message.

### 5.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | S2 completed (disabled start verified) | S2 evidence saved |
| P2 | Service is stopped / no stale PID | `pgrep -f 'mihomo\|chimera'` returns exit 1 |
| P3 | `enabled=1` set and committed | `uci set openchimera.config.enabled=1 && uci commit openchimera` |
| P4 | Core binary present and executable | `[ -x /usr/bin/mihomo ]` |
| P5 | Dependencies present | `which curl yq` |

### 5.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | `uci set openchimera.config.enabled=1 && uci commit openchimera` | Exit 0; no error |
| 2 | `uci get openchimera.config.enabled` | `1` |
| 3 | `/etc/init.d/openchimera start`; `echo "exit: $?"` | Exit 0 |
| 4 | `sleep 2` (allow daemon init) | — |
| 5 | `pgrep -f 'mihomo\|chimera'` | Returns at least one PID |
| 6 | `pidof mihomo` | Returns PID (same as pgrep) |
| 7 | `PID=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID=$PID"` | Non-empty numeric PID |
| 8 | `ps -p $PID -o pid,comm,args 2>/dev/null` | Process details show `mihomo --compatibility -d /etc/openchimera/run ...` |
| 9 | `/etc/init.d/openchimera status`; `echo "exit: $?"` | Exit 0; "running" with PID |
| 10 | `ls -la /var/log/openchimera/core.log` | File exists, size > 0 |
| 11 | `head -20 /var/log/openchimera/core.log` | Contains Chimera startup/runtime init text |
| 12 | `ls -la /etc/openchimera/run/config.yaml` | Config file exists, size > 0 |
| 13 | `head -5 /etc/openchimera/run/config.yaml` | YAML header with "Generated by OpenChimera" |
| 14 | `logread -l 20 \| grep openchimera \| tail -5` | Contains "Config generation successful" and "Configuration validation passed" |
| 15 | `readlink -f /proc/$PID/exe 2>/dev/null` | Resolves to `/usr/libexec/chimera` |

### 5.4 Expected Results

- `start` exits 0
- `pgrep` returns a numeric PID (1+ matches)
- `pidof mihomo` returns same PID
- `ps` shows the full `mihomo --compatibility -d /etc/openchimera/run ...` command line
- `/etc/init.d/openchimera status` reports "running"
- `/var/log/openchimera/core.log` exists with non-zero size
- Log contains Chimera startup messages (daemon initialized, ports listening)
- `/etc/openchimera/run/config.yaml` exists with valid YAML
- `logread` shows config generation and validation pass messages
- `/proc/$PID/exe` resolves to `/usr/libexec/chimera`

### 5.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| `start` fails | Exit non-zero | Binary missing, config gen fails, or validation fails |
| No PID after start | `pgrep` returns empty | procd failed to spawn; check `logread` |
| Log file not created | `ls` shows no file | Log dir not created; binary failed before first write |
| Config not generated | `config.yaml` missing | `openchimera-config-gen` failed |
| Wrong command line | `ps` shows wrong args | Init script procd params incorrect |
| Validation not logged | `logread` no validation message | `start_service()` returned early |
| Core binary wrong | `/proc/PID/exe` not chimera | Alternative not set up correctly |

### 5.6 PID Capture for Subsequent Scenarios

```bash
# Capture to variable for S4 (restart) and S5 (stop)
PID_BEFORE=$(pgrep -f 'mihomo|chimera' | head -1)
echo "PID_BEFORE=$PID_BEFORE" > /tmp/chimera-pid-before.txt
```

---

## 6. Lifecycle Scenario S4: Service Restart

**QA-ID**: QA-14  
**Evidence file**: `task-14/task-14-restart-pid.txt`

### 6.1 Description

Calling `/etc/init.d/openchimera restart` MUST result in either:
- (a) a **new PID** (preferred — clean restart), or
- (b) the same process cleanly restarting with the same PID (acceptable fallback).

Evidence MUST capture PIDs before and after restart, and verify the process
is functional after restart.

### 6.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | S3 completed (service running) | PID_BEFORE from S3 is alive |
| P2 | `PID_BEFORE` captured and non-empty | `[ -n "$PID_BEFORE" ]` |
| P3 | Service is functional | `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10` succeeds (or port is listening) |

### 6.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | `PID_BEFORE=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID_BEFORE=$PID_BEFORE"` | Non-empty PID |
| 2 | `ps -p $PID_BEFORE -o etime,pid,args 2>/dev/null` | Process running, record start time |
| 3 | `/etc/init.d/openchimera restart`; `echo "exit: $?"` | Exit 0 |
| 4 | `sleep 3` (allow daemon restart) | — |
| 5 | `PID_AFTER=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID_AFTER=$PID_AFTER"` | Non-empty PID |
| 6 | `ps -p $PID_AFTER -o etime,pid,args 2>/dev/null` | Process running, note start time |
| 7 | `echo "PID_BEFORE=$PID_BEFORE PID_AFTER=$PID_AFTER"` | — |
| 8 | Compare PIDs: `if [ "$PID_BEFORE" != "$PID_AFTER" ]; then echo "PASS: PID changed (clean restart)"; else echo "WARN: PID unchanged (same process)"; fi` | Either PASS or WARN is acceptable |
| 9 | `/etc/init.d/openchimera status`; `echo "exit: $?"` | Exit 0; "running" |
| 10 | `ls -la /var/log/openchimera/core.log` | File exists, size may have grown |
| 11 | `tail -10 /var/log/openchimera/core.log` | New startup messages after restart |
| 12 | `logread -l 20 \| grep openchimera \| tail -5` | Contains restart/reload log entries |
| 13 | `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10` | Exit 0; service still functional |

### 6.4 Expected Results

- `restart` exits 0
- `PID_AFTER` is non-empty (process exists after restart)
- PID comparison result recorded (change preferred but not required)
- Service status shows "running"
- Log shows new startup messages
- Proxy port still responds to curl (service is functional)

### 6.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| No PID after restart | `pgrep` returns empty | Daemon crashed on restart |
| Same PID without restart evidence | PID unchanged, no new log messages | procd used respawn instead of restart |
| Service not functional | curl fails | Port not listening after restart |
| Restart command fails | Exit non-zero | Config validation on restart failed |

### 6.6 Edge Cases

| Edge Case | What to Check |
|---|---|
| Rapid restart | Call `restart` twice in succession; both should succeed |
| Restart with active connections | Existing TCP connections may drop (expected) |
| Restart from stopped state | `stop` then `restart` should start fresh |

---

## 7. Lifecycle Scenario S5: Service Stop

**QA-ID**: QA-13  
**Evidence file**: `task-14/task-14-stop-process.txt`

### 7.1 Description

Calling `/etc/init.d/openchimera stop` MUST terminate the Chimera daemon
process. After stop, `pgrep` and `pidof` MUST return no PID.

### 7.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | S3 or S4 completed (service running) | `pgrep -f 'mihomo\|chimera'` returns a PID |
| P2 | PID captured for before/after comparison | `PID_BEFORE=$(pgrep -f 'mihomo\|chimera' \| head -1)` |

### 7.3 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | `PID_BEFORE=$(pgrep -f 'mihomo\|chimera' \| head -1)`; `echo "PID_BEFORE=$PID_BEFORE"` | Non-empty PID |
| 2 | `/etc/init.d/openchimera stop`; `echo "exit: $?"` | Exit 0 |
| 3 | `sleep 1` (allow SIGTERM to propagate) | — |
| 4 | `pgrep -f 'mihomo\|chimera'`; `echo "exit: $?"` | No output; exit 1 |
| 5 | `pidof mihomo`; `echo "exit: $?"` | Empty; exit 1 |
| 6 | `/etc/init.d/openchimera status`; `echo "exit: $?"` | Exit non-zero; "not running" or "inactive" |
| 7 | `ps \| grep -E 'mihomo\|chimera' \| grep -v grep` | Empty (no process) |
| 8 | `kill -0 $PID_BEFORE 2>&1` | "No such process" error; exit 1 |
| 9 | `ls -la /var/log/openchimera/core.log 2>&1` | Log file still exists (persistent) |
| 10 | `tail -5 /var/log/openchimera/core.log 2>/dev/null` | May contain shutdown messages |
| 11 | `logread -l 20 \| grep openchimera \| tail -5` | May contain procd stop notification |
| 12 | `ls -la /etc/openchimera/run/config.yaml 2>&1` | Config file persists (not deleted on stop) |

### 7.4 Expected Results

- `stop` exits 0
- `pgrep` / `pidof` return no PID (exit 1)
- `status` shows "not running" or equivalent
- `kill -0` confirms process is gone
- Log file persists (stop does NOT delete logs)
- Config file persists (stop does NOT delete generated config)
- No dangling processes (verify with `ps`)

### 7.5 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Process survives stop | `pgrep` still returns PID | procd not managing this process; SIGTERM ignored |
| Stop exits non-zero | Exit code != 0 | Init script error or procd timeout |
| Dangling child process | `pgrep` shows child but not parent | Core binary forks unexpectedly |
| Log file deleted | `ls` fails | Stop handler incorrectly cleans up logs |
| Config file deleted | `config.yaml` missing | Stop handler incorrectly cleans up config |

### 7.6 Force Stop Fallback

```bash
# If graceful stop fails, force kill:
kill -TERM $PID_BEFORE 2>/dev/null
sleep 1
kill -KILL $PID_BEFORE 2>/dev/null  # if still alive

# Verify dead:
pgrep -f 'mihomo|chimera' || echo "PASS: process terminated"
```

---

## 8. Lifecycle Scenario S6: Invalid Config Blocks Start (Negative)

**QA-IDs**: QA-16, QA-17  
**Evidence file**: `task-14/task-14-invalid-config-start.txt`

### 8.1 Description

When the generated `config.yaml` fails validation (`mihomo -t` exit non-zero),
the init script MUST refuse to start the daemon. A clear error MUST be logged.
No Chimera process MAY be spawned under any circumstances.

This scenario tests the **config validation guard** in `start_service()` at
lines 61-65 of the init script.

### 8.2 Preconditions

| # | Condition | Verification |
|---|---|---|
| P1 | S5 completed (service stopped) | `pgrep -f 'mihomo\|chimera'` returns exit 1 |
| P2 | Service is enabled | `uci get openchimera.config.enabled` = `1` |
| P3 | Config gen script present | `[ -x /usr/bin/openchimera-config-gen ]` |
| P4 | `openchimera-debug` present | `[ -x /usr/bin/openchimera-debug ]` |

### 8.3 Config Tamper Methods

Two methods to produce an invalid config:

**Method A — UCI value that generates invalid config.yaml** (preferred):
The config generator may produce valid YAML with an invalid Chimera value,
causing `mihomo -t` to fail.

```bash
# Set a value that config_gen.sh emits but Chimera rejects
# e.g., mixed-port with non-numeric value
uci set openchimera.mixin.mixed_port='not-a-number'
uci commit openchimera
```

> **Note**: The config generator (`config_gen.sh`) passes values through
> without Chimera-specific validation — it just emits them as YAML values.
> An invalid `mixed-port: not-a-number` will be written verbatim to
> `config.yaml`, and `mihomo -t` should reject it.

**Method B — Direct config tamper** (backup, if UCI method passes validation):
If Method A's `not-a-number` value is somehow rejected by the YAML generator
itself (unlikely), directly edit the generated config after a clean start:

```bash
# First generate a valid config
/etc/init.d/openchimera start
/etc/init.d/openchimera stop

# Then corrupt it
sed -i 's/mixed-port: [0-9]*/mixed-port: BADSEDVALUE/' /etc/openchimera/run/config.yaml
```

Use Method A first. Fall back to Method B only if `mihomo -t` unexpectedly
passes with the invalid UCI value.

### 8.4 Steps

| Step | Command | Expected Result |
|---|---|---|
| 1 | Verify no stale PID: `pgrep -f 'mihomo\|chimera'`; `echo "exit: $?"` | Exit 1 (no process) |
| 2 | Verify enabled: `uci get openchimera.config.enabled` | `1` |
| 3 | **Inject invalid UCI value**: `uci set openchimera.mixin.mixed_port='not-a-number' && uci commit openchimera` | Exit 0 |
| 4 | Verify UCI change: `uci get openchimera.mixin.mixed_port` | `not-a-number` |
| 5 | **Attempt start**: `/etc/init.d/openchimera start`; `echo "exit: $?"` | Exit non-zero (1) |
| 6 | `sleep 2` | — |
| 7 | **Verify no process**: `pgrep -f 'mihomo\|chimera'`; `echo "exit: $?"` | No output; exit 1 |
| 8 | **Verify no process (pidof)**: `pidof mihomo`; `echo "exit: $?"` | Empty; exit 1 |
| 9 | **Verify log contains error**: `logread -l 50 \| grep openchimera \| tail -10` | Contains "Configuration validation failed" |
| 10 | **Check validation output in log**: `cat /var/log/openchimera/core.log 2>/dev/null \| tail -20` | Contains validation error details from `mihomo -t` |
| 11 | **Verify generated config exists**: `ls -la /etc/openchimera/run/config.yaml 2>&1` | File exists (config gen ran before validation) |
| 12 | **Inspect generated config**: `cat /etc/openchimera/run/config.yaml` | Contains `mixed-port: not-a-number` |
| 13 | **Verify service status**: `/etc/init.d/openchimera status`; `echo "exit: $?"` | Exit non-zero; "not running" |
| 14 | **Run manual validation for reference**: `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml 2>&1`; `echo "exit: $?"` | Exit non-zero; error about invalid port value |

### 8.5 Expected Results

- `start` exits non-zero
- `pgrep` / `pidof` return no PID (exit 1) — daemon MUST NOT start
- `logread` contains "Configuration validation failed - refusing to start"
- `core.log` contains the `mihomo -t` error output (the validation failure details
  are redirected to the log file via `>> "$LOG_FILE" 2>&1`)
- `config.yaml` exists (generated before validation; gen itself does not fail
  on invalid port values, it's just YAML emission)
- Manual `mihomo -t` also fails with the same error
- Service status reports "not running"

### 8.6 Failure Indicators

| Failure | Symptom | Likely Cause |
|---|---|---|
| Daemon starts despite invalid config | `pgrep` returns PID | Config validation guard bypassed or `mihomo -t` passed unexpectedly |
| Config gen fails before validation | `openchimera-config-gen` exits non-zero | Generator validates values (it shouldn't — it just emits YAML) |
| No validation error in logread | `logread` shows no openchimera entries | Init script exits before validation step |
| `mihomo -t` passes with bad value | Manual validation exits 0 | Chimera accepts `not-a-number` as mixed-port (update expected behavior) |
| Config.yaml not generated | File missing | Config gen did not run before validation check |

### 8.7 Cleanup / Restore Valid Config

```bash
# After S6 test, restore valid port
uci set openchimera.mixin.mixed_port='7890'
uci commit openchimera

# Verify restored
uci get openchimera.mixin.mixed_port  # must be '7890'
```

---

## 9. Evidence Naming Convention

### 9.1 Pattern

```
.omo/evidence/task-14/{scenario-slug}.txt
```

Where `{scenario-slug}` matches the scenario:

| Scenario | Evidence File | QA-IDs |
|---|---|---|
| Pre-flight checks | `task-14-preflight.txt` | — |
| Package install | `task-14-install-opkg.txt` | QA-04, QA-05 |
| Disabled service start (negative) | `task-14-disabled-start.txt` | QA-15 |
| Enabled service start | `task-14-enabled-start.txt` | QA-12, QA-18, QA-19 |
| Service restart | `task-14-restart-pid.txt` | QA-14 |
| Service stop | `task-14-stop-process.txt` | QA-13 |
| Invalid config blocks start (negative) | `task-14-invalid-config-start.txt` | QA-16, QA-17 |
| Summary results | `task-14-summary.txt` | All |

### 9.2 Evidence Content Rules

Each evidence file MUST contain:

```
=== <SCENARIO NAME> ===
Date: <ISO-8601 timestamp>
Target: <target-ip>

--- Step <N>: <command> ---
<raw stdout + stderr>
exit: <exit code>

--- Assertions ---
- [PASS|FAIL] <assertion description>
- [PASS|FAIL] <assertion description>

--- Summary ---
Result: PASS / FAIL
```

### 9.3 Evidence Collection Script Pattern

```bash
evidence_file=".omo/evidence/task-14/task-14-enabled-start.txt"
{
    echo "=== Enabled Service Start ==="
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    
    echo "--- Step: uci set enabled=1 ---"
    uci set openchimera.config.enabled=1 && uci commit openchimera
    echo "exit: $?"
    echo ""
    
    echo "--- Step: /etc/init.d/openchimera start ---"
    /etc/init.d/openchimera start
    echo "exit: $?"
    echo ""
    
    echo "--- Step: pgrep after start ---"
    pgrep -f 'mihomo|chimera'
    echo "exit: $?"
    echo ""
    
    # ... all steps ...
    
    echo "--- Summary ---"
    echo "Result: PASS"
} 2>&1 | tee "$evidence_file"
```

---

## 10. QA-Id to Scenario Mapping

| QA-ID | Description | Scenario | Evidence File |
|---|---|---|---|
| QA-04 | chimera-core opkg install | S1: Package Install | `task-14-install-opkg.txt` |
| QA-05 | openchimera opkg install | S1: Package Install | `task-14-install-opkg.txt` |
| QA-12 | Enabled service starts (PID captured) | S3: Enabled Service Start | `task-14-enabled-start.txt` |
| QA-13 | Service stop removes process | S5: Service Stop | `task-14-stop-process.txt` |
| QA-14 | Restart changes PID or cleanly restarts | S4: Service Restart | `task-14-restart-pid.txt` |
| QA-15 | Disabled service does not start (NEGATIVE) | S2: Disabled Service Start | `task-14-disabled-start.txt` |
| QA-16 | Invalid config prevents daemon start (NEGATIVE) | S6: Invalid Config Blocks Start | `task-14-invalid-config-start.txt` |
| QA-17 | Validation failure is logged (NEGATIVE) | S6: Invalid Config Blocks Start | `task-14-invalid-config-start.txt` |
| QA-18 | Log file created after start | S3: Enabled Service Start | `task-14-enabled-start.txt` |
| QA-19 | Log contains startup message | S3: Enabled Service Start | `task-14-enabled-start.txt` |

---

## Appendix A: Quick-Reference UCI State Table

| State | `enabled` | Expected on `start` | Expected on `stop` |
|---|---|---|---|
| Installed (default) | `0` | No process; "Service disabled" logged | N/A (not running) |
| Enabled | `1` | Process spawns; PID captured | Process terminated |
| Running | `1` | N/A (already running) | Process terminated |
| Invalid config | `1` + bad UCI | No process; validation error logged | N/A (not running) |

## Appendix B: Key File Paths

```
Package files:
  /usr/libexec/chimera                        # Core daemon binary
  /usr/bin/mihomo → /usr/libexec/chimera      # Alternatives symlink
  /etc/init.d/openchimera                     # Init script
  /etc/config/openchimera                     # UCI config
  /usr/bin/openchimera-config-gen              # Config generator
  /usr/bin/openchimera-debug                   # Debug script
  
Runtime:
  /etc/openchimera/run/config.yaml             # Generated config
  /var/log/openchimera/core.log                # Daemon log

Evidence:
  .omo/evidence/task-14/task-14-{scenario}.txt  # Per §9
```

## Appendix C: Common Errors & Troubleshooting

| Error | Likely Fix |
|---|---|
| `opkg: not found` | Target is not OpenWrt; verify `cat /etc/openwrt_release` |
| `uci: Entry not found` | Packages not installed; run S1 first |
| `pgrep: not found` | Install `procps-ng-pgrep` or use `ps \| grep` fallback |
| `/etc/init.d/openchimera: not found` | openchimera package not installed (S1) |
| `logread: not found` | Use `logread -l 50` or `cat /var/log/messages` |
| `/usr/bin/mihomo -t` passes with bad value | Update expected behavior for this Chimera version |
| `mkdir: Read-only file system` | Run on actual OpenWrt (not a snapshot overlay) |

---

*End of QA Plan — OpenChimera Milestone 1 Lifecycle Verification*
