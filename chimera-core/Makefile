include $(TOPDIR)/rules.mk

PKG_NAME:=chimera-core
PKG_VERSION:=0.20.2
PKG_SOURCE_VERSION:=v$(PKG_VERSION)

PKG_SOURCE:=clash_chimera-x86_64-unknown-linux-musl
PKG_SOURCE_URL:=https://github.com/MFSGA/Chimera_Client/releases/download/$(PKG_SOURCE_VERSION)
PKG_HASH:=532166cad0154158d9a23272341acb6a5256bf750ab35454cdb571608ff11df4

PKG_LICENSE:=GPL3.0+
PKG_MAINTAINER:=OpenChimera Team

PKG_BUILD_FLAGS:=no-mips16

include $(INCLUDE_DIR)/package.mk

define Package/chimera-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Chimera Client core (clash-rs) prebuilt binary
  URL:=https://github.com/MFSGA/Chimera_Client
  # Runtime dependencies for the Chimera_Client (clash-rs) binary:
  # - ca-bundle: SSL/TLS certificate bundle for HTTPS connections
  # - ip-full: Full iproute2 for policy routing in TUN mode
  # - kmod-tun: TUN/TAP kernel module for TUN proxy mode
  # Note: kmod-inet-diag is NOT needed (diagnostic-only, not required by Chimera)
  #       kmod-nft-tproxy/kmod-nft-socket deferred to post-milestone-1 (TProxy/Redirect)
  DEPENDS:=+ca-bundle +ip-full +kmod-tun
  PROVIDES:=mihomo
  CONFLICTS:=mihomo-meta mihomo-alpha
  ALTERNATIVES:=\
    300:/usr/bin/mihomo:/usr/libexec/chimera
endef

define Package/chimera-core/description
  Chimera Client prebuilt binary package for OpenWrt.
  Provides /usr/libexec/chimera with /usr/bin/mihomo alternative.
  Built from MFSGA/Chimera_Client (clash-rs).
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR)/chimera
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/chimera-core/install
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/chimera $(1)/usr/libexec/chimera
endef

$(eval $(call BuildPackage,chimera-core))
