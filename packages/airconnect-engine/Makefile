# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs

include $(TOPDIR)/rules.mk

PKG_NAME:=airconnect-engine
PKG_VERSION:=1.12.4
PKG_RELEASE:=1

PKG_SOURCE:=AirConnect-$(PKG_VERSION).zip
PKG_SOURCE_URL:=https://github.com/philippe44/AirConnect/releases/download/$(PKG_VERSION)/
PKG_HASH:=ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903
PKG_BUILD_DIR:=$(BUILD_DIR)/airconnect-engine-$(PKG_VERSION)

# This describes upstream AirConnect, not a blanket license for its dependencies.
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/airconnect-engine
  SECTION:=multimedia
  CATEGORY:=Multimedia
  TITLE:=Upstream AirConnect audio bridge engines
  URL:=https://github.com/philippe44/AirConnect
  DEPENDS:=@(aarch64||x86_64)
endef

define Package/airconnect-engine/description
  Pinned upstream airupnp and aircast engines, without configuration or services.
  The static binaries isolate OpenWrt musl from upstream dynamic dependencies.
  The manager package is responsible for service and device configuration.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	unzip -q -j $(DL_DIR)/$(PKG_SOURCE) \
		airupnp-linux-$(ARCH)-static aircast-linux-$(ARCH)-static \
		-d $(PKG_BUILD_DIR)
endef

define Build/Compile
	test -s $(PKG_BUILD_DIR)/airupnp-linux-$(ARCH)-static
	test -s $(PKG_BUILD_DIR)/aircast-linux-$(ARCH)-static
endef

define Package/airconnect-engine/install
	$(INSTALL_DIR) $(1)/usr/libexec/airconnect $(1)/usr/share/airconnect
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/airupnp-linux-$(ARCH)-static $(1)/usr/libexec/airconnect/airupnp
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aircast-linux-$(ARCH)-static $(1)/usr/libexec/airconnect/aircast
	$(INSTALL_DATA) ./files/UPSTREAM-LICENSE $(1)/usr/share/airconnect/UPSTREAM-LICENSE
endef

$(eval $(call BuildPackage,airconnect-engine))
