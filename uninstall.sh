#!/bin/sh

# OpenChimera uninstaller
#
# Removes chimera-core and openchimera packages and cleans up
# all configuration, runtime, and log directories.
#
# Usage:
#   ./uninstall.sh           # Remove packages and clean up
#   ./uninstall.sh --dry-run # Show what would be removed
#   ./uninstall.sh --help    # Show this help message

set -e

DRY_RUN=false

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Remove chimera-core and openchimera packages and clean up associated files.

Options:
  --help       Show this help message and exit
  --dry-run    Show what would be removed without actually removing anything

Note:
  A hosted opkg/apk feed is not yet available for milestone 1.
  If a feed was previously registered, its entries are also removed.

Environment:
  This script must be run on an OpenWrt device with opkg or apk.
EOF
}

# Handle flags
for arg in "$@"; do
	case "$arg" in
		--help)
			usage
			exit 0
			;;
		--dry-run)
			DRY_RUN=true
			;;
		-*)
			echo "Error: unknown option: $arg" >&2
			usage >&2
			exit 1
			;;
	esac
done

# Check that we are on an OpenWrt device
if [ ! -f /etc/openwrt_release ]; then
	echo "Error: /etc/openwrt_release not found — this script must be run on an OpenWrt device." >&2
	exit 1
fi

# Source release info
. /etc/openwrt_release

arch="${DISTRIB_ARCH:-unknown}"
release="${DISTRIB_RELEASE:-unknown}"

echo "OpenChimera uninstaller"
echo "  Architecture: $arch"
echo "  Release:      $release"
echo ""

# Detect package manager
if [ -x /bin/opkg ]; then
	PKG_MGR="opkg"
elif [ -x /usr/bin/apk ]; then
	PKG_MGR="apk"
else
	echo "Error: neither opkg nor apk found — this script requires an OpenWrt device." >&2
	exit 1
fi

echo "  Package manager: $PKG_MGR"
if [ "$DRY_RUN" = true ]; then
	echo "  Mode: dry-run (no changes will be made)"
fi
echo ""

# --- Package removal ---
echo "--- Package removal ---"

# Define packages to remove (reverse dependency order: openchimera first, then chimera-core)
PACKAGES="openchimera chimera-core"

if [ "$PKG_MGR" = "opkg" ]; then
	for pkg in $PACKAGES; do
		if opkg list-installed "$pkg" >/dev/null 2>&1; then
			echo "  [remove] $pkg"
			if [ "$DRY_RUN" = false ]; then
				opkg remove "$pkg"
			fi
		else
			echo "  [skip]   $pkg (not installed)"
		fi
	done
elif [ "$PKG_MGR" = "apk" ]; then
	for pkg in $PACKAGES; do
		if apk info --installed "$pkg" >/dev/null 2>&1; then
			echo "  [remove] $pkg"
			if [ "$DRY_RUN" = false ]; then
				apk del "$pkg"
			fi
		else
			echo "  [skip]   $pkg (not installed)"
		fi
	done
fi

echo ""

# --- File cleanup ---
echo "--- File cleanup ---"

# Config
if [ -f /etc/config/openchimera ]; then
	echo "  [remove] /etc/config/openchimera"
	if [ "$DRY_RUN" = false ]; then
		rm -f /etc/config/openchimera
	fi
else
	echo "  [skip]   /etc/config/openchimera (not found)"
fi

# Runtime directory
if [ -d /etc/openchimera ]; then
	echo "  [remove] /etc/openchimera/ (runtime directory)"
	if [ "$DRY_RUN" = false ]; then
		rm -rf /etc/openchimera
	fi
else
	echo "  [skip]   /etc/openchimera/ (not found)"
fi

# Log directory
if [ -d /var/log/openchimera ]; then
	echo "  [remove] /var/log/openchimera/ (log directory)"
	if [ "$DRY_RUN" = false ]; then
		rm -rf /var/log/openchimera
	fi
else
	echo "  [skip]   /var/log/openchimera/ (not found)"
fi

# Runtime state directory
if [ -d /var/run/openchimera ]; then
	echo "  [remove] /var/run/openchimera/ (runtime state)"
	if [ "$DRY_RUN" = false ]; then
		rm -rf /var/run/openchimera
	fi
else
	echo "  [skip]   /var/run/openchimera/ (not found)"
fi

# Upgrade keep file
if [ -f /lib/upgrade/keep.d/openchimera ]; then
	echo "  [remove] /lib/upgrade/keep.d/openchimera"
	if [ "$DRY_RUN" = false ]; then
		rm -f /lib/upgrade/keep.d/openchimera
	fi
else
	echo "  [skip]   /lib/upgrade/keep.d/openchimera (not found)"
fi

echo ""

# --- Feed cleanup ---
echo "--- Feed cleanup ---"

if [ "$PKG_MGR" = "opkg" ] && [ -f /etc/opkg/customfeeds.conf ]; then
	if grep -q openchimera /etc/opkg/customfeeds.conf 2>/dev/null; then
		echo "  [remove] openchimera feed entries from /etc/opkg/customfeeds.conf"
		if [ "$DRY_RUN" = false ]; then
			sed -i '/openchimera/d' /etc/opkg/customfeeds.conf
		fi
	else
		echo "  [skip]   no openchimera feed entries in /etc/opkg/customfeeds.conf"
	fi
elif [ "$PKG_MGR" = "apk" ] && [ -f /etc/apk/repositories.d/customfeeds.list ]; then
	if grep -q openchimera /etc/apk/repositories.d/customfeeds.list 2>/dev/null; then
		echo "  [remove] openchimera feed entries from /etc/apk/repositories.d/customfeeds.list"
		if [ "$DRY_RUN" = false ]; then
			sed -i '/openchimera/d' /etc/apk/repositories.d/customfeeds.list
		fi
	else
		echo "  [skip]   no openchimera feed entries in /etc/apk/repositories.d/customfeeds.list"
	fi
else
	echo "  [skip]   no feed configuration file found"
fi

echo ""
echo "OpenChimera has been removed from the system."
echo ""
echo "Note: A hosted opkg/apk feed is not yet available in milestone 1."
echo "To reinstall, build packages via the SDK and copy the .ipk files:"
echo "  https://github.com/MFSGA/OpenChimera"
