include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for AirConnect Manager
LUCI_DEPENDS:=+airconnect-manager +luci-base
LUCI_PKGARCH:=all
PKG_LICENSE:=MIT

# The luci feed is installed into package/feeds/luci, so from this package's
# directory it is two levels up. $(TOPDIR) is deliberately not used here: the
# SDK's package scanner sources this Makefile with an unset TOPDIR to build the
# package index, and $(TOPDIR)/feeds/luci/luci.mk then resolves to
# /feeds/luci/luci.mk, the dump fails, and the package never registers --
# `make defconfig` silently drops CONFIG_PACKAGE_luci-app-airconnect-manager and
# the build stops with "no APK". The relative include resolves against luci.mk's
# own directory, which is what the in-feed packages (luci-app-acl and friends)
# do too, and it works both during the scan and during a real build.
include ../../feeds/luci/luci.mk

# The SDK's package scanner (include/scan.mk) discovers packages by grepping each
# Makefile for `call BuildPackage`. luci.mk supplies that macro's definition but
# not the call, so without this line the scanner never sees this package, it is
# absent from tmp/.packageinfo and tmp/.config-package.in, and `make defconfig`
# silently drops CONFIG_PACKAGE_luci-app-airconnect-manager -- the build then
# reports "no APK produced" with no useful error. The in-feed packages such as
# luci-app-acl all end with this same line, so it is the expected convention.
$(eval $(call BuildPackage,luci-app-airconnect-manager))
