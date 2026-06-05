#!/bin/sh

# OpenChimera installation script
#
# Installs chimera-core and openchimera packages on an OpenWrt device.
#
# Milestone 1 uses local .ipk / .apk files (built via the OpenWrt SDK).
# A hosted opkg/apk feed is planned for a later milestone.
#
# Usage:
#   # Install from local files (milestone 1 — primary method)
#   ./install.sh /path/to/chimera-core_*.ipk /path/to/openchimera_*.ipk
#
#   # Show help
#   ./install.sh --help

set -e

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS] [PACKAGE_FILES...]

Install chimera-core and openchimera on an OpenWrt device.

Options:
  --help       Show this help message and exit

Arguments:
  PACKAGE_FILES  Paths to local .ipk or .apk package files.
                 If provided, these files are installed directly.
                 If omitted, the script prints setup instructions
                 for the SDK build method.

Milestone 1:
  A hosted opkg/apk feed is not yet available. To build packages
  locally, use the OpenWrt SDK:

    1. Download the x86_64 SDK from https://downloads.openwrt.org/
    2. Follow the instructions in docs/sdk-build.md
    3. Copy the resulting .ipk files to the device and run:
       $(basename "$0") /tmp/chimera-core_*.ipk /tmp/openchimera_*.ipk

  A hosted feed will be added in a future milestone.

Environment:
  This script must be run on an OpenWrt device with opkg or apk.
EOF
}

# Handle --help
case "${1:-}" in
	--help)
		usage
		exit 0
		;;
	-*)
		echo "Error: unknown option: $1" >&2
		usage >&2
		exit 1
		;;
esac

# Check that we are on an OpenWrt device
if [ ! -f /etc/openwrt_release ]; then
	echo "Error: /etc/openwrt_release not found — this script must be run on an OpenWrt device." >&2
	exit 1
fi

# Source release info
. /etc/openwrt_release

arch="${DISTRIB_ARCH:-unknown}"
release="${DISTRIB_RELEASE:-unknown}"

echo "OpenChimera installer"
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
echo ""

# Determine mode: local files provided or informational mode
if [ "$#" -gt 0 ]; then
	# Local file installation mode
	echo "Installing from local package files..."
	echo ""

	# Ensure all files exist
	for f in "$@"; do
		if [ ! -f "$f" ]; then
			echo "Error: file not found: $f" >&2
			exit 1
		fi
	done

	if [ "$PKG_MGR" = "opkg" ]; then
		# Verify that files have .ipk extension
		for f in "$@"; do
			case "$f" in
				*.ipk) ;;
				*)
					echo "Warning: '$f' does not have a .ipk extension — opkg may reject it." >&2
					;;
			esac
		done

		echo "Updating opkg package lists..."
		opkg update

		echo "Installing packages..."
		opkg install "$@"
	elif [ "$PKG_MGR" = "apk" ]; then
		# Verify that files have .apk extension
		for f in "$@"; do
			case "$f" in
				*.apk) ;;
				*)
					echo "Warning: '$f' does not have a .apk extension — apk may reject it." >&2
					;;
			esac
		done

		echo "Updating apk package lists..."
		apk update

		echo "Installing packages..."
		# apk add can install local files directly
		apk add "$@"
	fi

	echo ""
	echo "Installation complete."
	echo ""
else
	# No files provided — print informational message
	echo "No package files provided."
	echo ""
	echo "In milestone 1, build chimera-core and openchimera using the"
	echo "OpenWrt SDK, copy the .ipk files to this device, then run:"
	echo ""
	echo "  $(basename "$0") /path/to/chimera-core_*.ipk /path/to/openchimera_*.ipk"
	echo ""
	echo "See docs/sdk-build.md for full SDK build instructions."
	echo ""
	echo "A hosted opkg/apk feed is planned for a later milestone."
	echo ""
	echo "Once the hosted feed is available, installation will be:"
	echo "  wget -O - https://github.com/MFSGA/OpenChimera/raw/main/feed.sh | ash"
	echo "  opkg install chimera-core openchimera"
	echo ""
fi

# Print post-install instructions
echo "============================================================"
echo "  Post-installation quick start"
echo "============================================================"
echo ""
echo "  1. Enable the service:"
echo "     uci set openchimera.config.enabled=1"
echo "     uci commit openchimera"
echo ""
echo "  2. (Optional) Set the proxy mixed port:"
echo "     uci set openchimera.mixin.mixed_port=7890"
echo "     uci commit openchimera"
echo ""
echo "  3. Start the service:"
echo "     /etc/init.d/openchimera start"
echo ""
echo "  4. Verify the proxy is running:"
echo "     curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10"
echo ""
echo "  5. Check logs:"
echo "     cat /var/log/openchimera/core.log"
echo ""
echo "  For full documentation:"
echo "    https://github.com/MFSGA/OpenChimera"
echo "============================================================"
