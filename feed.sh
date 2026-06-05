#!/bin/sh

# OpenChimera feed registration script
#
# This script registers the OpenChimera opkg feed on a running OpenWrt device.
# It is designed for use with a future hosted feed. For milestone 1, use the
# SDK build method instead (see docs/sdk-build.md).
#
# Usage:
#   wget -O - https://github.com/MFSGA/OpenChimera/raw/main/feed.sh | ash
#   ./feed.sh --help

set -e

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Register the OpenChimera opkg feed on an OpenWrt device.

Options:
  --help       Show this help message and exit

Note:
  A hosted opkg feed is not yet available for milestone 1.
  This script is a placeholder for future use.

  To build OpenChimera packages locally, use the SDK build method:
    See docs/sdk-build.md

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

echo "OpenChimera feed registration"
echo "  Architecture: $arch"
echo "  Release:      $release"
echo ""
echo "A hosted OpenChimera opkg feed is not yet available."
echo ""
echo "For milestone 1, build packages locally using the OpenWrt SDK:"
echo "  1. Download the x86_64 SDK from https://downloads.openwrt.org/"
echo "  2. Follow the instructions in docs/sdk-build.md"
echo ""
echo "Once the hosted feed is available, this script will register it automatically."
