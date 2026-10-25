# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs

include $(TOPDIR)/rules.mk

PKG_NAME:=airconnect-manager
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

# Adapter only: nothing is downloaded, ./files is the whole payload.
PKG_LICENSE:=MIT
PKG_MAINTAINER:=AirConnect OpenWrt maintainers

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/airconnect-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AirConnect management adapter
  URL:=https://github.com/philippe44/AirConnect
  DEPENDS:=@(aarch64||x86_64) +airconnect-engine +ucode +ucode-mod-fs +ucode-mod-socket +ucode-mod-ubus +ucode-mod-uci +rpcd +rpcd-mod-ucode +curl
endef

define Package/airconnect-manager/description
  UCI configuration, generated runtime XML and procd supervision for the
  upstream AirConnect engines. Persistent settings live in a single UCI file,
  the engine XML under /var/etc is regenerated from it, and one procd instance
  is registered per enabled engine. The engine binaries themselves are shipped
  by airconnect-engine. Installing this package never starts broadcasting. The
  init script is enabled at boot by OpenWrt's default_postinst, but start_service
  publishes no procd instance while the UCI 'enabled' option is 0, which is the
  shipped default. Opting in is setting that option to 1, not enabling the init
  script.
endef

define Package/airconnect-manager/conffiles
/etc/config/airconnect-manager
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

# rpcd loads every regular, non-world-writable file in /usr/share/rpcd/ucode and
# skips anything else, so the plugin is installed with INSTALL_BIN (regular,
# 0755). It is both the RPC provider and its own scan worker.
define Package/airconnect-manager/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/share/airconnect-manager
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_CONF) ./files/etc/config/airconnect-manager $(1)/etc/config/airconnect-manager
	$(INSTALL_BIN) ./files/etc/init.d/airconnect-manager $(1)/etc/init.d/airconnect-manager
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-airconnect-manager $(1)/etc/uci-defaults/90-airconnect-manager
	$(INSTALL_DATA) ./files/usr/share/airconnect-manager/config.uc $(1)/usr/share/airconnect-manager/config.uc
	$(INSTALL_DATA) ./files/usr/share/airconnect-manager/discovery.uc $(1)/usr/share/airconnect-manager/discovery.uc
	$(INSTALL_DATA) ./files/usr/share/airconnect-manager/broadcast.uc $(1)/usr/share/airconnect-manager/broadcast.uc
	$(INSTALL_DATA) ./files/usr/share/airconnect-manager/state.uc $(1)/usr/share/airconnect-manager/state.uc
	$(INSTALL_DATA) ./files/usr/share/airconnect-manager/files.uc $(1)/usr/share/airconnect-manager/files.uc
	$(INSTALL_DATA) ./files/usr/share/airconnect-manager/VERSION $(1)/usr/share/airconnect-manager/VERSION
	$(INSTALL_BIN) ./files/usr/share/airconnect-manager/runtime.uc $(1)/usr/share/airconnect-manager/runtime.uc
	$(INSTALL_BIN) ./files/usr/share/rpcd/ucode/airconnect-manager $(1)/usr/share/rpcd/ucode/airconnect-manager
endef

$(eval $(call BuildPackage,airconnect-manager))
