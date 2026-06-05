#!/bin/sh
# OpenChimera diagnostic script
# Dumps version info, UCI config (with secrets redacted), process status, and log paths.

ECHO=/usr/bin/echo
DATE=/bin/date
OPKG=/bin/opkg
UCI=/sbin/uci
PS=/bin/ps
GREP=/bin/grep
SED=/bin/sed
LS=/bin/ls
CAT=/bin/cat
HEAD=/usr/bin/head
TAIL=/usr/bin/tail

"$ECHO" "============================================"
"$ECHO" "  OpenChimera Debug Information"
"$ECHO" "  $("$DATE" -u '+%Y-%m-%d %H:%M:%S UTC')"
"$ECHO" "============================================"
"$ECHO"

# ---------------------------------------------------------------------------
# 1. Package version
# ---------------------------------------------------------------------------
"$ECHO" "--- Package Version ---"
if "$OPKG" list-installed 2>/dev/null | "$GREP" -E '^openchimera '; then
	:
else
	"$ECHO" "  openchimera: not installed (opkg unavailable or package not found)"
fi
"$ECHO"

# ---------------------------------------------------------------------------
# 2. Core (mihomo) version
# ---------------------------------------------------------------------------
"$ECHO" "--- Core Version ---"
if command -v mihomo >/dev/null 2>&1; then
	mihomo -V 2>&1
else
	"$ECHO" "  mihomo binary not found in PATH"
fi
"$ECHO"

# ---------------------------------------------------------------------------
# 3. UCI configuration (redacted — secrets replaced with ****)
# ---------------------------------------------------------------------------
"$ECHO" "--- UCI Configuration (REDACTED) ---"
"$UCI" show openchimera 2>/dev/null | \
	"$SED" "s/\(openchimera\.[^.]*\.secret='\)[^']*'/\1****'/g" | \
	"$SED" 's/\(openchimera\.[^.]*\.secret="\)[^"]*"/\1****"/g'
if [ $? -ne 0 ]; then
	"$ECHO" "  (UCI not available or openchimera config not found)"
fi
"$ECHO"

# ---------------------------------------------------------------------------
# 4. Process status
# ---------------------------------------------------------------------------
"$ECHO" "--- Process Status ---"
"$PS" 2>/dev/null | "$GREP" -E '(chimera|mihomo)' | "$GREP" -v grep || \
	"$ECHO" "  No chimera/mihomo process found"
"$ECHO"

# ---------------------------------------------------------------------------
# 5. Runtime directory contents
# ---------------------------------------------------------------------------
"$ECHO" "--- Runtime Directory (/etc/openchimera/) ---"
if [ -d /etc/openchimera ]; then
	"$LS" -la /etc/openchimera/ 2>/dev/null || "$ECHO" "  (cannot list)"
else
	"$ECHO" "  Directory does not exist"
fi
"$ECHO"

# ---------------------------------------------------------------------------
# 6. Log files
# ---------------------------------------------------------------------------
"$ECHO" "--- Log Files ---"
"$ECHO" "  Log directory: /var/log/openchimera/"
if [ -d /var/log/openchimera ]; then
	"$LS" -la /var/log/openchimera/ 2>/dev/null || "$ECHO" "  (cannot list)"
	"$ECHO"
	for f in /var/log/openchimera/*.log; do
		[ -f "$f" ] || continue
		"$ECHO" "  --- $(basename "$f") (last 20 lines) ---"
		"$TAIL" -n 20 "$f" 2>/dev/null || "$HEAD" -n 20 "$f" 2>/dev/null || "$ECHO" "  (cannot read)"
		"$ECHO"
	done
else
	"$ECHO" "  (directory does not exist)"
fi
"$ECHO"

# ---------------------------------------------------------------------------
# 7. UCI config file contents (for reference, redacted)
# ---------------------------------------------------------------------------
"$ECHO" "--- Config File (/etc/config/openchimera, redacted) ---"
if [ -f /etc/config/openchimera ]; then
	"$SED" 's/\(option secret\s\+\)[^ ]*/\1****/' /etc/config/openchimera 2>/dev/null || \
		"$ECHO" "  (cannot read config file)"
else
	"$ECHO" "  Config file not found"
fi
"$ECHO"

"$ECHO" "============================================"
"$ECHO" "  End of OpenChimera Debug Information"
"$ECHO" "============================================"
