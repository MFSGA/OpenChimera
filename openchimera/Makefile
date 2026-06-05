include $(TOPDIR)/rules.mk

PKG_NAME:=openchimera
PKG_VERSION:=2026.06.06
PKG_RELEASE:=1

PKG_LICENSE:=GPL3.0+
PKG_MAINTAINER:=OpenChimera Contributors

include $(INCLUDE_DIR)/package.mk

define Package/openchimera
  SECTION:=net
  CATEGORY:=Network
  TITLE:=OpenChimera management layer for Chimera client
  URL:=https://github.com/MFSGA/OpenChimera
  # Runtime dependencies for OpenChimera management layer:
  # - mihomo: Virtual provider — satisfied by chimera-core (or mihomo-meta/alpha)
  # - curl: For config download/subscription fetch and HTTP QA checks
  # - yq: For YAML manipulation (mixin, profile editing)
  # - coreutils-base64: For base64 encoding/decoding in config handling
  # Note: ca-bundle is pulled transitively via the mihomo provider dependency
  DEPENDS:=+mihomo +curl +yq +coreutils-base64
endef

define Package/openchimera/conffiles
/etc/config/openchimera
endef

define Package/openchimera/install
	$(INSTALL_DIR) $(1)/etc/openchimera
	$(INSTALL_DIR) $(1)/etc/openchimera/run
	$(INSTALL_DIR) $(1)/etc/openchimera/profiles

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/openchimera.conf $(1)/etc/config/openchimera

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/openchimera.init $(1)/etc/init.d/openchimera

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(CURDIR)/files/debug.sh $(1)/usr/bin/openchimera-debug
	$(INSTALL_BIN) $(CURDIR)/files/config_gen.sh $(1)/usr/bin/openchimera-config-gen

	# Install default configuration for first-run / fallback
	$(INSTALL_DATA) $(CURDIR)/files/config.yaml.default $(1)/etc/openchimera/config.yaml.default

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) $(CURDIR)/files/openchimera.upgrade $(1)/lib/upgrade/keep.d/openchimera
endef

define Build/Compile

endef

$(eval $(call BuildPackage,openchimera))
