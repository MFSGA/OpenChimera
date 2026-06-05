# OpenChimera QA Environment Checklist & Evidence Layout

> **Policy**: ZERO human intervention. ALL verification is agent-executed.
> Every verification step MUST use command/tool execution — no manual confirmation or vague "verify it works" language.

---

## 1. QA Environment

### 1.1 SDK Build Environment (x86_64)

| Property | Value |
|---|---|
| SDK target | `x86_64` (OpenWrt musl) |
| SDK image | `openwrt/gh-action-sdk@main` (matching CI pattern from `.ref/`) |
| Host OS | `ubuntu-latest` (or any Linux with Docker) |
| Feed name | `openchimera` |
| SDK branches | `openwrt-24.10`, `openwrt-25.12`, `SNAPSHOT` (milestone 1 = `openwrt-24.10`) |
| Package output path | `bin/packages/x86_64/openchimera/` |

**SDK build commands:**

```bash
# Add feed
echo "src-git openchimera https://github.com/MFSGA/OpenChimera.git;main" >> feeds.conf.default

# Update & install feeds
./scripts/feeds update -a
./scripts/feeds install -a

# Compile packages
make package/chimera-core/compile V=s
make package/openchimera/compile V=s

# Expected output files
ls -la bin/packages/x86_64/openchimera/*.ipk
```

### 1.2 Runtime Test Environment (OpenWrt x86_64)

| Property | Value |
|---|---|
| Target arch | `x86_64` musl |
| OS | OpenWrt 24.10+ with firewall4 |
| Package manager | `opkg` (primary), `apk` (documented but optional for milestone 1) |
| Dependencies | `ca-bundle`, `curl`, `yq`, `firewall4`, `ip-full`, `kmod-tun`, `kmod-dummy` |
| Core runtime path | `/usr/libexec/chimera` |
| Alternative path | `/usr/bin/mihomo` → `/usr/libexec/chimera` |
| Config directory | `/etc/openchimera/`, `/etc/openchimera/run/`, `/etc/openchimera/profiles/` |
| Log directory | `/var/log/openchimera/` |
| UCI config | `/etc/config/openchimera` |

**Runtime install commands:**

```bash
opkg install chimera-core_*.ipk openchimera_*.ipk
```

---

## 2. Evidence Naming Convention

All QA evidence MUST be saved to `.omo/evidence/` following this pattern:

```
.omo/evidence/task-{N}-{scenario-slug}.txt
```

Where:
- `{N}` = task number (e.g., `6`, `13`, `14`)
- `{scenario-slug}` = lowercase hyphenated scenario name (e.g., `sdk-build`, `invalid-config`, `mixed-port-curl`)

**Examples:**

```
.omo/evidence/task-6-qa-checklist.txt
.omo/evidence/task-13-sdk-build.txt
.omo/evidence/task-14-init-lifecycle.txt
.omo/evidence/task-15-mixed-port-curl.txt
.omo/evidence/task-6-no-manual-qa.txt
```

**Evidence content rules:**
- Capture raw command output (stdout + stderr)
- Include exit codes
- Include relevant file listings or log excerpts
- Annotate with brief pass/fail summary
- MUST NOT contain placeholder text like "TODO" or "TBD"

---

## 3. Required Test Scenarios (Milestone 1)

Each scenario MUST be executed by an agent and evidence saved per Section 2.

### 3.1 SDK Build

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-01 | chimera-core SDK compile | `make package/chimera-core/compile V=s` | Exit 0; `chimera-core_*.ipk` produced under `bin/packages/` | `task-13-sdk-build.txt` |
| QA-02 | openchimera SDK compile | `make package/openchimera/compile V=s` | Exit 0; `openchimera_*.ipk` produced under `bin/packages/` | `task-13-sdk-build.txt` |
| QA-03 | Package files exist | `ls -la bin/packages/x86_64/openchimera/*.ipk` | Both `.ipk` files present | `task-13-sdk-build.txt` |

### 3.2 Package Installation

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-04 | Install chimera-core | `opkg install chimera-core_*.ipk` | Installed with no dependency errors | `task-14-init-lifecycle.txt` |
| QA-05 | Install openchimera | `opkg install openchimera_*.ipk` | Installed with no dependency errors | `task-14-init-lifecycle.txt` |

### 3.3 Version Check

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-06 | Version output | `/usr/bin/mihomo -V` | Prints Chimera/clash-rs version string; exit 0 | `task-12-alternatives-version.txt` |

### 3.4 Alternatives Check

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-07 | Alternative resolves to Chimera | `ls -la /usr/bin/mihomo` | Symlink or alternative points to `/usr/libexec/chimera` | `task-12-alternatives-version.txt` |
| QA-08 | Alternative binary runs | `/usr/bin/mihomo --help` | Binary executes without error | `task-12-alternatives-version.txt` |

### 3.5 Config Validation

#### 3.5.1 Valid Config

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-09 | Valid config passes test | `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml` | Exit 0; "configuration file test successful" or equivalent | `task-8-valid-config-test.txt` |

#### 3.5.2 Invalid Config (Negative Test)

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-10 | Invalid config fails test | Write `mixed-port: not-a-number` to config; run `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml` | Exit non-zero; error message about invalid config | `task-8-valid-config-test.txt` |
| QA-11 | Malformed YAML fails test | Write `{{{{{` to config; run `/usr/bin/mihomo -t -d /etc/openchimera/run -c config.yaml` | Exit non-zero; YAML parse error | `task-14-failure-paths.txt` |

### 3.6 Service Lifecycle (start / stop / restart)

| ID | Scenario | Command(s) | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-12 | Start enabled service | `uci set openchimera.main.enabled=1`; `/etc/init.d/openchimera start`; `pgrep -f '/usr/bin/mihomo\|/usr/libexec/chimera'` | Process running; PID captured | `task-14-init-lifecycle.txt` |
| QA-13 | Stop running service | `/etc/init.d/openchimera stop`; `pgrep -f '/usr/bin/mihomo\|/usr/libexec/chimera'` | No process remains | `task-14-init-lifecycle.txt` |
| QA-14 | Restart changes PID | Capture PID; run `/etc/init.d/openchimera restart`; capture PID again | PID changed or process cleanly restarted | `task-14-init-lifecycle.txt` |

#### 3.6.1 Negative: Disabled Service (Negative Test)

| ID | Scenario | Command(s) | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-15 | Disabled service does not start | `uci set openchimera.main.enabled=0`; `/etc/init.d/openchimera start`; `pgrep -f '/usr/bin/mihomo\|/usr/libexec/chimera'` | No Chimera process spawned | `task-14-failure-paths.txt` |

#### 3.6.2 Negative: Invalid Config Blocks Start (Negative Test)

| ID | Scenario | Command(s) | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-16 | Invalid config prevents daemon start | `uci set openchimera.main.enabled=1`; write invalid config; `/etc/init.d/openchimera start`; `pgrep -f '/usr/bin/mihomo\|/usr/libexec/chimera'` | No process running | `task-14-failure-paths.txt` |
| QA-17 | Validation failure is logged | Inspect `/var/log/openchimera/core.log` or service log | Log contains "config" and "failed" or equivalent error | `task-14-failure-paths.txt` |

### 3.7 Log Check

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-18 | Log file created after start | `ls -la /var/log/openchimera/core.log` | File exists with non-zero size | `task-9-log-created.txt` |
| QA-19 | Log contains startup message | `head -20 /var/log/openchimera/core.log` | Contains startup/runtime initialization text | `task-9-log-created.txt` |

### 3.8 Mixed Port Check

| ID | Scenario | Command | Expected Result | Evidence File |
|---|---|---|---|---|
| QA-20 | Mixed port accepts proxy request | `curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10` | Exit 0; HTTP response headers returned | `task-15-mixed-port-curl.txt` |
| QA-21 | Mixed port rejects bad request | `curl -x http://127.0.0.1:7890 http://nonexistent.invalid --max-time 5` | Non-zero exit (connection error expected, daemon should not crash) | `task-15-mixed-port-curl.txt` |

### 3.9 Summary: Complete Checklist

- [ ] QA-01: chimera-core SDK compile (exit 0, .ipk produced)
- [ ] QA-02: openchimera SDK compile (exit 0, .ipk produced)
- [ ] QA-03: Package .ipk files exist in `bin/packages/`
- [ ] QA-04: chimera-core opkg install succeeds
- [ ] QA-05: openchimera opkg install succeeds
- [ ] QA-06: `/usr/bin/mihomo -V` prints version
- [ ] QA-07: `/usr/bin/mihomo` alternative resolves to `/usr/libexec/chimera`
- [ ] QA-08: Alternative binary runs (`--help`)
- [ ] QA-09: Valid config passes `mihomo -t` (exit 0)
- [ ] QA-10: **Invalid config** fails `mihomo -t` (exit non-zero) — **NEGATIVE TEST**
- [ ] QA-11: **Malformed YAML** fails `mihomo -t` (exit non-zero) — **NEGATIVE TEST**
- [ ] QA-12: Enabled service starts (PID captured)
- [ ] QA-13: Service stop removes process
- [ ] QA-14: Restart changes PID or cleanly restarts
- [ ] QA-15: **Disabled service** does not start — **NEGATIVE TEST**
- [ ] QA-16: **Invalid config blocks start** (no process) — **NEGATIVE TEST**
- [ ] QA-17: **Validation failure is logged** — **NEGATIVE TEST**
- [ ] QA-18: Log file exists after start
- [ ] QA-19: Log contains startup message
- [ ] QA-20: Mixed port handles proxy request (curl exit 0)
- [ ] QA-21: Mixed port handles bad request without crashing daemon

---

## 4. Negative / Failure Scenario Requirements

All failure scenarios are **MANDATORY** — passing only the happy path constitutes incomplete QA.

| # | Failure Scenario | What to Prove |
|---|---|---|
| F1 | Invalid config value | Generated config with `mixed-port: not-a-number` must fail `mihomo -t` |
| F2 | Malformed YAML | Config with syntax error must fail `mihomo -t` |
| F3 | Disabled service | `enabled=0` must NOT spawn a Chimera process on `start` |
| F4 | Invalid config on start | Daemon must NOT start when config validation fails |
| F5 | Validation failure log | Service must emit a clear error message when config is invalid |
| F6 | Mixed port bad request | Daemon must not crash when a proxy request target is unreachable |

Each failure scenario MUST:
1. Be executed by an agent (no manual interpretation)
2. Produce saved evidence with exit codes and relevant output
3. Assert the specific failure mode (not just "it doesn't work")

---

## 5. Forbidden Patterns

The following are **NOT ACCEPTABLE** in QA evidence or scenario descriptions:

| Forbidden Pattern | Reason |
|---|---|
| "Verify it works" | Vague — must specify exact command + expected output |
| "Manual confirmation required" | All QA is agent-executed; no human-in-the-loop |
| "Check visually" | Must use command-line assertions |
| "Should be obvious" | Must assert specific exit codes, file presence, or output text |
| "TBD" / "TODO" in evidence files | Evidence must be concrete or absent if not yet executed |

---

## 6. Evidence Directory Structure

```
.omo/evidence/
├── task-1/
├── task-3/
├── task-6/
│   ├── task-6-qa-checklist.txt
│   └── task-6-no-manual-qa.txt
├── task-7/
├── task-8/
├── task-9/
├── task-12/
├── task-13/
├── task-14/
├── task-15/
└── final-qa/
```

Each task directory stores the evidence files matching `task-{N}-{scenario-slug}.txt`.

---

## 7. QA Execution Protocol

1. **Prepare**: Ensure SDK or target environment is ready per Section 1.
2. **Execute**: Run each scenario using Bash/curl/SSH commands.
3. **Capture**: Save stdout + stderr + exit code to evidence file.
4. **Assert**: Compare output against expected result.
5. **Fail**: If assertion fails, capture the failure output and flag it.
6. **Evidence path**: `.omo/evidence/task-{N}-{scenario-slug}.txt`
