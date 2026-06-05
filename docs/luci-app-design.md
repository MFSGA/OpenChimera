# LuCI App Design — `luci-app-openchimera`

> **Status**: Deferred — not part of milestone 1. Milestone 1 is CLI-only.
> This document is a **design and scaffold plan** for a later milestone.
> No LuCI files are implemented yet.

## Table of Contents

1. [Overview](#1-overview)
2. [Package Structure](#2-package-structure)
3. [Menu & Navigation](#3-menu--navigation)
4. [Controller Layer (RPC / ucode)](#4-controller-layer-rpc--ucode)
5. [View Layer](#5-view-layer)
6. [I18N / Localisation](#6-i18n--localisation)
7. [ACL & Permissions](#7-acl--permissions)
8. [Integration Points](#8-integration-points)
9. [Implementation Notes](#9-implementation-notes)
10. [Appendices](#10-appendices)

---

## 1. Overview

`luci-app-openchimera` provides a web-based management interface for the
OpenChimera proxy core on OpenWrt. It is implemented as a LuCI JavaScript
application (LuCI JS — the modern JS template framework, not legacy lua).

### Goals

- **Status & Overview** — show core running state, version info, quick actions
  (start/stop/restart), and key runtime metrics.
- **Settings** — full CRUD over all `openchimera` UCI sections (config, mixin,
  routing, proxy) via LuCI form framework.
- **Log Viewer** — real-time tail of both the application log and the core log
  with clear/scroll controls.
- **Config Preview** — read-only YAML preview of the generated
  `/etc/openchimera/run/config.yaml` that the core actually runs with.
- **Config Generation** — trigger config re-generation and service restart from
  the web UI.

### Runtime requirements

- **LuCI JS** (JavaScript-based, not lua-based) — modern OpenWrt 24.10+
- **ucode RPC daemon** (`rpcd`) for privileged operations
- **ubus** for service status queries via `rc` object
- **OpenChimera UCI config** at `/etc/config/openchimera`

---

## 2. Package Structure

The `luci-app-openchimera` package lives at the repository root alongside
`chimera-core/` and `openchimera/`:

```
luci-app-openchimera/
├── Makefile
├── htdocs/
│   └── luci-static/
│       └── resources/
│           ├── tools/
│           │   └── openchimera.js          # Shared utility module (RPC wrappers, path constants)
│           └── view/
│               └── openchimera/
│                   ├── overview.js          # Status dashboard (main landing)
│                   ├── settings.js          # UCI settings form (config, mixin, routing, proxy)
│                   ├── logs.js              # Log viewer (app log, core log, debug)
│                   └── config_preview.js    # Generated YAML preview
├── root/
│   └── usr/
│       └── share/
│           ├── luci/
│           │   └── menu.d/
│           │       └── luci-app-openchimera.json   # Menu entries
│           └── rpcd/
│               ├── acl.d/
│               │   └── luci-app-openchimera.json   # ACL rules
│               └── ucode/
│                   └── luci.openchimera            # ucode RPC methods
└── po/
    ├── templates/
    │   └── openchimera.pot                 # I18N template
    ├── zh_Hans/
    │   └── openchimera.po                  # Simplified Chinese
    ├── zh_Hant/
    │   └── openchimera.po                  # Traditional Chinese
    └── ...                                 # Additional languages (future)
```

### 2.1 File-by-file purpose

| File | Purpose |
|---|---|
| `Makefile` | OpenWrt package definition, declares deps: `+luci-base +openchimera` |
| `tools/openchimera.js` | Shared JS module: RPC declarations, path constants, helper methods |
| `view/openchimera/overview.js` | Status dashboard: service state, version, start/stop/restart buttons |
| `view/openchimera/settings.js` | Settings form: all UCI sections and fields |
| `view/openchimera/logs.js` | Log viewer: tabbed display of app/core/debug logs with polling |
| `view/openchimera/config_preview.js` | Read-only YAML preview of generated config |
| `menu.d/luci-app-openchimera.json` | LuCI menu registration (under Services) |
| `acl.d/luci-app-openchimera.json` | RPCD ACL: UCI read/write, file read, ubus access |
| `ucode/luci.openchimera` | ucode RPC backend: version, service control, config gen |
| `po/templates/openchimera.pot` | I18N message template |
| `po/zh_Hans/openchimera.po` | Simplified Chinese translations |
| `po/zh_Hant/openchimera.po` | Traditional Chinese translations |

### 2.2 Makefile template

```makefile
include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0

LUCI_TITLE:=LuCI Support for OpenChimera
LUCI_DEPENDS:=+luci-base +openchimera

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
```

Key points:

- `LUCI_DEPENDS` must include `+openchimera` to ensure the management layer
  and its dependencies are installed.
- Version should track the OpenChimera release cycle (or be independent).

---

## 3. Menu & Navigation

### 3.1 Menu hierarchy

The app registers under **Services** → **OpenChimera** with sub-pages:

```
Services
└── OpenChimera                      # Top-level category (firstchild redirect)
    ├── Overview      (order: 10)    # Status dashboard
    ├── Settings      (order: 20)    # UCI configuration form
    ├── Logs          (order: 30)    # Log viewer
    └── Config Preview (order: 40)   # Generated YAML preview
```

### 3.2 Menu JSON (`menu.d/luci-app-openchimera.json`)

```json
{
    "admin/services/openchimera": {
        "title": "OpenChimera",
        "action": {
            "type": "firstchild"
        },
        "depends": {
            "acl": [ "luci-app-openchimera" ],
            "uci": { "openchimera": true }
        }
    },
    "admin/services/openchimera/overview": {
        "title": "Overview",
        "order": 10,
        "action": {
            "type": "view",
            "path": "openchimera/overview"
        }
    },
    "admin/services/openchimera/settings": {
        "title": "Settings",
        "order": 20,
        "action": {
            "type": "view",
            "path": "openchimera/settings"
        }
    },
    "admin/services/openchimera/logs": {
        "title": "Logs",
        "order": 30,
        "action": {
            "type": "view",
            "path": "openchimera/logs"
        }
    },
    "admin/services/openchimera/config_preview": {
        "title": "Config Preview",
        "order": 40,
        "action": {
            "type": "view",
            "path": "openchimera/config_preview"
        }
    }
}
```

**Design notes:**

- `depends.acl` references the ACL name; LuCI hides the menu if the user lacks
  permissions.
- `depends.uci` checks that the `openchimera` UCI package exists on the system.
- `type: "firstchild"` on the parent makes LuCI redirect to the first
  sub-page (Overview), avoiding a blank parent page.

---

## 4. Controller Layer (RPC / ucode)

### 4.1 Architecture

LuCI JS views cannot execute shell commands or access the filesystem directly
with elevated privileges. Instead, they communicate with `rpcd` via ubus.
A ucode RPC script (`ucode/luci.openchimera`) exposes privileged operations
as ubus methods.

```
Browser (JS View)
    │  XML-RPC / ubus
    ▼
rpcd ──► ucode/luci.openchimera  (privileged operations)
    │       ├── version()          → app & core version
    │       ├── status()           → service running state (procd)
    │       ├── start()            → start service
    │       ├── stop()             → stop service
    │       ├── restart()          → restart service
    │       ├── config_preview()   → read generated config.yaml
    │       └── regenerate()       → trigger config gen + restart
    │
    └── ubus ──► rc (procd)        (service lifecycle)
```

The JS tool module (`tools/openchimera.js`) declares RPC stubs for each ubus
method and provides a clean async API for view code.

### 4.2 ucode RPC methods (`ucode/luci.openchimera`)

```ucode
#!/usr/bin/ucode

'use strict';

import { popen, readfile, writefile } from 'fs';

const methods = {
    version: {
        call: function() {
            let app_ver = '';
            let core_ver = '';

            let proc = popen('opkg list-installed luci-app-openchimera | cut -d " " -f 3');
            if (proc) { app_ver = trim(proc.read('all')); proc.close(); }

            proc = popen('/usr/bin/mihomo -v | head -1 | cut -d " " -f 3');
            if (proc) { core_ver = trim(proc.read('all')); proc.close(); }

            return { app: app_ver, core: core_ver };
        }
    },
    status: {
        call: function() {
            let running = false;
            let proc = popen('/etc/init.d/openchimera running');
            if (proc) {
                running = (proc.close() == 0);
            }
            return { running: running };
        }
    },
    start: {
        call: function() {
            let ok = (system('/etc/init.d/openchimera start') == 0);
            return { success: ok };
        }
    },
    stop: {
        call: function() {
            let ok = (system('/etc/init.d/openchimera stop') == 0);
            return { success: ok };
        }
    },
    restart: {
        call: function() {
            let ok = (system('/etc/init.d/openchimera restart') == 0);
            return { success: ok };
        }
    },
    config_preview: {
        call: function() {
            let yaml = readfile('/etc/openchimera/run/config.yaml');
            return { config: yaml ?? '' };
        }
    },
    regenerate: {
        call: function() {
            let ok = (system('/usr/bin/openchimera-config-gen') == 0);
            if (ok) {
                system('/etc/init.d/openchimera restart');
            }
            return { success: ok };
        }
    }
};

return { 'luci.openchimera': methods };
```

### 4.3 JS tool module (`tools/openchimera.js`)

```javascript
'use strict';
'require baseclass';
'require uci';
'require fs';
'require rpc';

const callRCInit = rpc.declare({
    object: 'rc',
    method: 'init',
    params: ['name', 'action'],
    expect: { '': {} }
});

const callOCVersion = rpc.declare({
    object: 'luci.openchimera',
    method: 'version',
    expect: { '': {} }
});

const callOCStatus = rpc.declare({
    object: 'luci.openchimera',
    method: 'status',
    expect: { '': {} }
});

const callOCStart = rpc.declare({
    object: 'luci.openchimera',
    method: 'start',
    expect: { '': {} }
});

const callOCStop = rpc.declare({
    object: 'luci.openchimera',
    method: 'stop',
    expect: { '': {} }
});

const callOCRestart = rpc.declare({
    object: 'luci.openchimera',
    method: 'restart',
    expect: { '': {} }
});

const callOCConfigPreview = rpc.declare({
    object: 'luci.openchimera',
    method: 'config_preview',
    expect: { '': {} }
});

const callOCRegenerate = rpc.declare({
    object: 'luci.openchimera',
    method: 'regenerate',
    expect: { '': {} }
});

const logDir = '/var/log/openchimera';
const appLogPath = logDir + '/app.log';
const coreLogPath = logDir + '/core.log';

return baseclass.extend({
    version: function() { return callOCVersion(); },
    status:  function() { return callOCStatus(); },
    start:   function() { return callOCStart(); },
    stop:    function() { return callOCStop(); },
    restart: function() { return callOCRestart(); },
    configPreview: function() { return callOCConfigPreview(); },
    regenerate:    function() { return callOCRegenerate(); },

    // Direct fs access for log reading (non-privileged)
    getAppLog:  function() { return L.resolveDefault(fs.read_direct(appLogPath), ''); },
    getCoreLog: function() { return L.resolveDefault(fs.read_direct(coreLogPath), ''); },
    clearAppLog:  function() { return fs.write(appLogPath, ''); },
    clearCoreLog: function() { return fs.write(coreLogPath, ''); }
});
```

**Note**: Log files are read via `fs.read_direct` (unprivileged) because the
LuCI user (`root`) has direct filesystem access. The config preview is served
through the ucode RPC because it may need to access files outside the web root.

---

## 5. View Layer

### 5.1 Overview (`view/openchimera/overview.js`)

**Purpose**: Status dashboard — the default landing page.

**Layout (LuCI form.Map with TableSection + NamedSection)**:

```
┌─────────────────────────────────────────────┐
│  OpenChimera — Overview                      │
│  Proxy core management for OpenWrt           │
├─────────────────────────────────────────────┤
│  Status                                      │
│  ┌─────────────────────────────────────────┐ │
│  │ App Version       │ 2026.06.06         │ │
│  │ Core Version      │ v0.20.2            │ │
│  │ Core Status       │ ● Running (green)   │ │
│  │                   │   Not Running (red) │ │
│  ├─────────────────────────────────────────┤ │
│  │ [Start]  [Stop]  [Restart]             │ │
│  └─────────────────────────────────────────┘ │
│                                              │
│  Proxy Ports (from active config)            │
│  ┌─────────────────────────────────────────┐ │
│  │ Mixed Port  │ 7890                     │ │
│  │ SOCKS Port  │ 1080                     │ │
│  │ HTTP Port   │ 8080                     │ │
│  │ API         │ [::]:9090                │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Key implementation details:**

- Uses `poll.add()` to poll `status()` every 5 seconds and update the core
  status indicator dynamically.
- Version info is loaded once on page load (unchanging at runtime).
- Service buttons call the ucode methods: `start()`, `stop()`, `restart()`.
- Proxy port info comes from UCI (loaded on page init) — read-only display.

**Template:**

```javascript
'use strict';
'require form';
'require view';
'require uci';
'require poll';
'require tools.openchimera as openchimera';

function renderStatus(running) {
    return updateStatus(
        E('input', {
            id: 'core_status',
            style: 'border:unset;font-style:italic;font-weight:bold;',
            readonly: ''
        }),
        running
    );
}

function updateStatus(el, running) {
    if (el) {
        el.style.color = running ? 'green' : 'red';
        el.value = running ? _('Running') : _('Not Running');
    }
    return el;
}

return view.extend({
    load: function() {
        return Promise.all([
            uci.load('openchimera'),
            openchimera.version(),
            openchimera.status()
        ]);
    },
    render: function(data) {
        var appVer = data[1].app || '';
        var coreVer = data[1].core || '';
        var running = data[2];  // boolean

        // ... build status table with form.Value and form.DummyValue
        // ... poll for status every 5s
        // ... start/stop/restart buttons via form.Button
        // ... read-only port display from UCI sections

        return m.render();
    }
});
```

### 5.2 Settings (`view/openchimera/settings.js`)

**Purpose**: Full UCI configuration form covering all sections.

**Sections mapped to UCI:**

| UCI Section | Tab / Section name | Key fields |
|---|---|---|
| `config` | General | `enabled` (flag), `log_level` (list: debug/info/warning/error), `log_file` (path) |
| `mixin` | Mixin | `mixed_port`, `socks_port`, `port`, `api_listen`, `secret`, `tun_enabled`, `tun_device`, `tun_dns_hijack` |
| `proxy` | Proxy | `enabled` (flag) |
| `routing` | Routing | `tun_route_table` |

**Layout (multi-section form.Map):**

```
┌─────────────────────────────────────────────┐
│  Settings — OpenChimera                      │
├─────────────────────────────────────────────┤
│ ┌─ General ──┬─ Mixin ──┬─ Proxy ──┬─ Routing ┐ │
│ │             │          │          │          │ │
│ │ ☑ Enabled   │ Mixed    │ ☑ Enabled│ Route    │ │
│ │             │ Port:    │          │ Table:   │ │
│ │ Log Level:  │ [7890]   │          │ [81]    │ │
│ │ [warning ▼] │          │          │          │ │
│ │             │ SOCKS:   │          │          │ │
│ │ Log File:   │ [1080]   │          │          │ │
│ │ /var/log/.. │          │          │          │ │
│ │             │ HTTP:    │          │          │ │
│ │             │ [8080]   │          │          │ │
│ │             │          │          │          │ │
│ │             │ API:     │          │          │ │
│ │             │ [::]:9090│          │          │ │
│ │             │          │          │          │ │
│ │             │ Secret:  │          │          │ │
│ │             │ [·······]│          │          │ │
│ │             │          │          │          │ │
│ │             │ ☑ TUN    │          │          │ │
│ │             │ Device:  │          │          │ │
│ │             │ [nikki]  │          │          │ │
│ │             │ ☑ DNS    │          │          │ │
│ │             │   Hijack │          │          │ │
│ └─────────────┴──────────┴──────────┴──────────┘ │
│                                                   │
│ [Save] [Save & Apply]                             │
└─────────────────────────────────────────────────┘
```

**Implementation approach:**

Each UCI section becomes a `form.NamedSection` with tabs for logical grouping.
Use `form.Flag` for booleans, `form.Value` for text/numbers, `form.ListValue`
for enums (log_level), and `form.DynamicList` where appropriate.

```javascript
// Structure pseudocode:
m = new form.Map('openchimera', _('Settings'));

// Tab: General (config section)
s = m.section(form.NamedSection, 'config', 'config', _('General'));
o = s.option(form.Flag, 'enabled', _('Enabled'));
o = s.option(form.ListValue, 'log_level', _('Log Level'));
    o.value('debug', 'debug');
    o.value('info', 'info');
    o.value('warning', 'warning');
    o.value('error', 'error');
o = s.option(form.Value, 'log_file', _('Log File'));

// Tab: Mixin (mixin section)
s = m.section(form.NamedSection, 'mixin', 'mixin', _('Mixin'));
o = s.option(form.Value, 'mixed_port', _('Mixed Port'));
o.datatype = 'port';
// ... (socks_port, port, api_listen, secret, etc.)
o = s.option(form.Flag, 'tun_enabled', _('TUN Enabled'));
o = s.option(form.Value, 'tun_device', _('TUN Device'));
o = s.option(form.Flag, 'tun_dns_hijack', _('TUN DNS Hijack'));

// Tab: Proxy (proxy section)
s = m.section(form.NamedSection, 'proxy', 'proxy', _('Proxy'));
o = s.option(form.Flag, 'enabled', _('Enabled'));

// Tab: Routing (routing section)
s = m.section(form.NamedSection, 'routing', 'routing', _('Routing'));
o = s.option(form.Value, 'tun_route_table', _('TUN Route Table'));
o.datatype = 'uinteger';
```

### 5.3 Logs (`view/openchimera/logs.js`)

**Purpose**: Real-time log viewer with tabbed display.

**Layout:**

```
┌─────────────────────────────────────────────┐
│  Logs — OpenChimera                          │
├─────────────────────────────────────────────┤
│ ┌─ App Log ──┬─ Core Log ─┬─ Log Config ──┐ │
│ │             │            │               │ │
│ │ [Clear]     │ [Clear]    │ Log Level:    │ │
│ │             │            │ [warning ▼]   │ │
│ │ ┌─────────┐ │ ┌────────┐ │               │ │
│ │ │ 2026-06 │ │ │ 2026-06│ │ Log File:     │ │
│ │ │ 01 ..    │ │ │ 01 ..  │ │ /var/log/..   │ │
│ │ │          │ │ │        │ │               │ │
│ │ │          │ │ │        │ │ [Save]        │ │
│ │ └─────────┘ │ └────────┘ │               │ │
│ │ [Scroll ↓]  │ [Scroll ↓] │               │ │
│ └─────────────┴────────────┴───────────────┘ │
└─────────────────────────────────────────────┘
```

**Key implementation details:**

- Three tabs: App Log, Core Log, Log Config.
- App Log and Core Log use `form.TextValue` with `rows: 25`, `wrap: false`
  (monospace log display).
- `poll.add()` polls every 3 seconds and replaces the textarea content.
- Clear button calls `clearAppLog()` / `clearCoreLog()`.
- Scroll to bottom button programmatically scrolls the textarea.
- Log Config tab re-uses the `log_level` and `log_file` fields from settings
  for quick access (or links to the Settings page).

```javascript
// Polling pattern (from Nikki reference):
poll.add(L.bind(function() {
    var option = this;
    return L.resolveDefault(openchimera.getAppLog()).then(function(log) {
        option.getUIElement('log').setValue(log);
    });
}, o));
```

### 5.4 Config Preview (`view/openchimera/config_preview.js`)

**Purpose**: Read-only display of the YAML config that the core is running with.

**Layout:**

```
┌─────────────────────────────────────────────┐
│  Config Preview — OpenChimera                │
├─────────────────────────────────────────────┤
│  Generated config: /etc/openchimera/run/config.yaml │
│                                               │
│  ┌─────────────────────────────────────────┐ │
│  │ # Generated by OpenChimera config_gen   │ │
│  │ # Source: UCI package 'openchimera'     │ │
│  │ mixed-port: 7890                        │ │
│  │ external-controller: 0.0.0.0:9090      │ │
│  │ log-level: warning                      │ │
│  │                                         │ │
│  │ tun:                                    │ │
│  │   enable: true                          │ │
│  │   device: nikki                         │ │
│  │   route-table: 81                       │ │
│  └─────────────────────────────────────────┘ │
│                                               │
│  [Regenerate & Restart]                       │
└─────────────────────────────────────────────┘
```

**Key implementation details:**

- Load data via `openchimera.configPreview()` (ucode RPC call).
- Display in a read-only `form.TextValue` with monospace font and YAML syntax
  coloring (optional, can be plain monospace for simplicity).
- "Regenerate & Restart" button calls `openchimera.regenerate()` which runs
  `openchimera-config-gen` followed by an init script restart.

```javascript
o = s.taboption('preview', form.TextValue, '_config_yaml');
o.rows = 30;
o.wrap = false;
o.load = function(section_id) {
    return configYaml;
};
o.write = function(section_id, formvalue) {
    return true;  // read-only
};
```

---

## 6. I18N / Localisation

### 6.1 Location

```
po/
├── templates/
│   └── openchimera.pot
├── en/
│   └── openchimera.po          (optional — English is the template)
├── zh_Hans/
│   └── openchimera.po
├── zh_Hant/
│   └── openchimera.po
└── .../
    └── openchimera.po
```

### 6.2 Translation workflow

1. All translatable strings in JS views are wrapped with `_('...')`.
2. The `.pot` template is extracted by scanning the JS source files.
3. Translators create `.po` files for each locale.
4. LuCI build system compiles `.po` → `.mo` and packages them.

### 6.3 Required translations

The following strings need translations for **English** (base/template) and
**Simplified Chinese (zh_Hans)**. Traditional Chinese (zh_Hant) is recommended
but can be deferred.

| String | Context |
|---|---|
| `OpenChimera` | Menu title, page title |
| `Overview` | Tab / menu |
| `Settings` | Tab / menu |
| `Logs` | Tab / menu |
| `Config Preview` | Tab / menu |
| `Status` | Section heading |
| `App Version` | Status field |
| `Core Version` | Status field |
| `Core Status` | Status field |
| `Running` | Status value |
| `Not Running` | Status value |
| `Start` | Button |
| `Stop` | Button |
| `Restart` | Button |
| `General` | Settings tab |
| `Mixin` | Settings tab |
| `Proxy` | Settings tab |
| `Routing` | Settings tab |
| `Enabled` | Flag label |
| `Log Level` | Dropdown label |
| `Log File` | Text field label |
| `Mixed Port` | Port field label |
| `SOCKS Port` | Port field label |
| `HTTP Port` | Port field label |
| `API Listen` | Address field label |
| `Secret` | Password field label |
| `TUN Enabled` | Flag label |
| `TUN Device` | Text field label |
| `TUN DNS Hijack` | Flag label |
| `TUN Route Table` | Numeric field label |
| `App Log` | Tab label |
| `Core Log` | Tab label |
| `Log Config` | Tab label |
| `Clear Log` | Button |
| `Scroll To Bottom` | Button |
| `Regenerate & Restart` | Button |
| `Save` | Button |
| `Save & Apply` | Button |
| `Config Preview` | Section label |
| `Generated config:` | Label prefix |
| `Proxy ports` | Section label |

Estimated total: **~50 message strings**.

---

## 7. ACL & Permissions

### 7.1 RPCD ACL (`acl.d/luci-app-openchimera.json`)

```json
{
    "luci-app-openchimera": {
        "description": "Grant access to openchimera procedures",
        "read": {
            "uci": [ "openchimera" ],
            "ubus": {
                "rc": [ "*" ],
                "luci.openchimera": [ "*" ]
            },
            "file": {
                "/etc/openchimera/run/config.yaml": ["read"],
                "/var/log/openchimera/*.log": ["read"]
            }
        },
        "write": {
            "uci": [ "openchimera" ],
            "ubus": {
                "luci.openchimera": [ "start", "stop", "restart", "regenerate" ]
            },
            "file": {
                "/var/log/openchimera/*.log": ["write"]
            }
        }
    }
}
```

**ACL scoping notes:**

- **read.uci**: Allows reading all `openchimera` UCI sections (config, mixin,
  proxy, routing). Used by all views.
- **write.uci**: Allows modifying UCI. Used by the Settings view for Save.
- **read.file**: Grants access to the generated config.yaml for the Config
  Preview view, plus log files.
- **write.file**: Log clearing needs write access to log files.
- **ubus**: The `rc` object allows checking service status via procd.
  The `luci.openchimera` object exposes privileged operations.

---

## 8. Integration Points

### 8.1 UCI config (`/etc/config/openchimera`)

The primary data source. All LuCI views read/write the following sections:

| Section | Type | Used by |
|---|---|---|
| `config` | config | Settings (General tab), Logs (Log Config tab), Overview (indirectly) |
| `mixin` | config | Settings (Mixin tab), Overview (port display) |
| `proxy` | config | Settings (Proxy tab) |
| `routing` | config | Settings (Routing tab) |
| `status` | config | (reserved — runtime status, not user-writable) |

See [`openchimera/files/openchimera.conf`](../openchimera/files/openchimera.conf)
for the full UCI schema.

### 8.2 Init script (`/etc/init.d/openchimera`)

Service lifecycle integration:

| Action | How LuCI triggers it |
|---|---|
| `status` | ucode RPC → `openchimera.status` → init script `running` command |
| `start` | ucode RPC → `openchimera.start` → init script `start` |
| `stop` | ucode RPC → `openchimera.stop` → init script `stop` |
| `restart` | ucode RPC → `openchimera.restart` → init script `restart` |
| config change | Save in Settings → UCI commit → manual "Restart" needed |

**Note**: OpenChimera does NOT support SIGHUP hot reload. Config changes
always require a full service restart. The UI must make this clear.

### 8.3 Generated config (`/etc/openchimera/run/config.yaml`)

Preview via ucode RPC (`openchimera.config_preview()` → reads file directly).
Regeneration via ucode RPC (`openchimera.regenerate()` → runs `/usr/bin/openchimera-config-gen`
and then restarts the service).

### 8.4 Log files (`/var/log/openchimera/`)

| File | Purpose | View |
|---|---|---|
| `core.log` | Core (mihomo) process stdout/stderr | Logs → Core Log tab |
| `app.log` | OpenChimera app-level logging (future) | Logs → App Log tab |

Log files are world-readable (or group-readable) so that the LuCI web server
can read them via `fs.read_direct()`.

### 8.5 procd service status

The ucode RPC uses the init script's `running` command:

```sh
/etc/init.d/openchimera running
# Returns exit code 0 if running, non-zero if not
```

Alternatively, the `rc` ubus object can be queried directly:

```javascript
const callRCList = rpc.declare({
    object: 'rc',
    method: 'list',
    params: ['name'],
    expect: { '': {} }
});
// callRCList('openchimera') returns { openchimera: { running: true/false } }
```

Using the `rc` ubus object is preferred — it avoids shelling out for status
checks and integrates natively with LuCI's polling mechanism.

### 8.6 Dashboard / external controller

The Overview page should display the API listen address (`api_listen` from the
mixin section) and provide a link to open the external controller dashboard
(if configured). The Chimera core serves a REST API and a web dashboard UI
at the configured `external-controller` address.

---

## 9. Implementation Notes

### 9.1 Order of implementation (suggested)

1. **Package scaffolding** — `Makefile`, directory structure, menu JSON, ACL JSON
2. **ucode RPC** — `luci.openchimera` with all methods
3. **JS tool module** — `tools/openchimera.js`
4. **Overview view** — simplest view, establishes patterns
5. **Settings view** — most complex form, all UCI sections
6. **Logs view** — polling, tabbed layout
7. **Config Preview view** — read-only display, regenerate action
8. **I18N** — `.pot` template, `.po` files for zh_Hans (and zh_Hant)

### 9.2 LuCI JS patterns to follow

- Use `form.Map` for all page layouts (not raw HTML).
- Use `form.NamedSection` bound to UCI section types.
- Use `form.TableSection` for status displays.
- Use `form.Button` for actions, `form.Flag` for booleans, `form.Value` for
  text, `form.ListValue` for dropdowns.
- Reading UCI: `uci.load('openchimera')` then `uci.sections(...)`.
- Writing UCI: LuCI form framework handles this automatically on Save.
- Polling: `poll.add()` with lambda that updates DOM elements by ID.
- I18N: `_('string')` everywhere — never hardcode UI strings.
- Module imports: `'require tools.openchimera as openchimera'`.

### 9.3 Differences from Nikki reference

While the Nikki luci-app provides a good reference, OpenChimera's app will be
**simpler** in several ways:

| Aspect | Nikki | OpenChimera |
|---|---|---|
| Transparent proxy modes | Redirect, TPROXY, TUN | TUN only (in milestone 1) |
| Subscription management | Full (add/update/remove) | Deferred to later milestone |
| Profile / Mixin system | YAML mixin, editor, profiles | Deferred |
| Access control | Per-device ACL, cgroup | Deferred |
| Scheduled operations | Restart, log clear, GeoX update | Deferred |
| Config complexity | ~15 UCI sections | 4 sections (config, mixin, proxy, routing) |
| Core API integration | Full dashboard proxy | Basic status + link to dashboard |

The deferred features can be added incrementally in later milestones.

### 9.4 Code style

- Follow LuCI JS conventions (see Nikki reference).
- Use `'use strict'` in all modules.
- Use `'require ...'` declarations, not ES module `import`.
- Use `var` (LuCI JS environment), not `let`/`const` (for compatibility).
- All user-facing strings must use `_('...')`.
- All RPC methods should return `{ key: value }` objects, not bare values.

### 9.5 Testing

- LuCI apps are difficult to unit test. Rely on manual QA in the OpenWrt
  browser environment.
- Use the browser's developer console to inspect ubus calls and responses.
- Verify menu entries appear under Services → OpenChimera.
- Verify all UCI fields load and save correctly.
- Verify status polling updates the indicator in real time.
- Verify log tails update and clear buttons work.

---

## 10. Appendices

### A. Reference: UCI schema (`/etc/config/openchimera`)

```
config status 'status'

config config 'config'
    option enabled '0'
    option log_level 'warning'
    option log_file '/var/log/openchimera/core.log'

config core 'core'

config mixin 'mixin'
    option mixed_port '7890'
    option socks_port '1080'
    option port '8080'
    option api_listen '[::]:9090'
    option secret ''
    option tun_enabled '0'
    option tun_device 'nikki'
    option tun_dns_hijack '0'

config proxy 'proxy'
    option enabled '1'

config routing 'routing'
    option tun_route_table '81'
```

### B. Reference: Runtime paths

| Path | Purpose |
|---|---|
| `/etc/config/openchimera` | UCI configuration file |
| `/etc/openchimera/run/` | Runtime directory (config.yaml location) |
| `/etc/openchimera/run/config.yaml` | Generated YAML config for the core |
| `/etc/openchimera/profiles/` | Profile storage (future use) |
| `/var/log/openchimera/core.log` | Core (mihomo) process log |
| `/var/log/openchimera/app.log` | OpenChimera app log (future) |
| `/usr/bin/mihomo` | Core binary (via alternatives) |
| `/usr/bin/openchimera-config-gen` | Config generator script |
| `/usr/bin/openchimera-debug` | Debug info collector |
| `/etc/init.d/openchimera` | procd init script |

### C. Reference: Nikki luci-app file listing

```
luci-app-nikki/
├── Makefile
├── htdocs/luci-static/resources/
│   ├── tools/nikki.js
│   └── view/nikki/
│       ├── app.js          # Status + app config + procd config
│       ├── profile.js      # Subscription/profile management
│       ├── mixin.js        # Mixin YAML config editor
│       ├── proxy.js        # Transparent proxy settings
│       ├── editor.js       # YAML file editor
│       └── log.js          # Log viewer
├── root/usr/share/
│   ├── luci/menu.d/luci-app-nikki.json
│   └── rpcd/
│       ├── acl.d/luci-app-nikki.json
│       └── ucode/luci.nikki
└── po/
    ├── templates/nikki.pot
    ├── zh_Hans/nikki.po
    └── .../nikki.po
```

### D. Reference: LuCI app naming conventions

| Component | Naming pattern | Example |
|---|---|---|
| Package directory | `luci-app-<name>` | `luci-app-openchimera` |
| Makefile PKG_NAME | `luci-app-<name>` | `luci-app-openchimera` |
| Menu JSON file | `luci-app-<name>.json` | `luci-app-openchimera.json` |
| ACL JSON file | `luci-app-<name>.json` | `luci-app-openchimera.json` |
| ucode RPC file | `luci.<name>` | `luci.openchimera` |
| View directory | `<name>/` | `openchimera/` |
| JS tool module | `tools/<name>.js` | `tools/openchimera.js` |
| I18N POT file | `<name>.pot` | `openchimera.pot` |
| I18N PO file | `<name>.po` | `openchimera.po` |
| LuCI menu path | `admin/services/<name>` | `admin/services/openchimera` |
| View paths | `<name>/<view>` | `openchimera/overview` |

---

> **End of document.** This design is a scaffold for a deferred milestone.
> Implementation should begin only after milestone 1 (CLI integration) is
> complete and verified.
