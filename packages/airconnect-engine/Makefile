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

# Upstream ships prebuilt ELF binaries named after short architecture tokens
# (aarch64, x86_64, arm, ...). OpenWrt ARCH values are sometimes the same
# (x86_64) and sometimes not: ARM targets leak non-normalized subtarget names
# such as aarch64_generic, aarch64_cortex-a53 or arm_cortex-a7_neon-vfpv4.
# Normalize explicitly instead of assuming $(ARCH) is a valid file name, so a
# future architecture is enabled by extending one list here, not by hunting
# through the recipe. This release only ships and supports aarch64/x86_64, so
# an unmapped ARCH is a hard build error rather than a silently wrong binary.
AIRCONNECT_ARCH := $(ARCH)
# The known-good list intentionally keeps armv7 and armv6 as their own upstream
# tokens: upstream ships a separate armv7 build, distinct from the older arm
# (ARMv5/ARMv6) build, so neither is silently collapsed onto "arm".
ifeq ($(filter $(ARCH),x86_64 aarch64 arm armv7 armv6 mips mipsel mips64 mips64el),)
  ifneq ($(filter aarch64%,$(ARCH)),)
    AIRCONNECT_ARCH := aarch64
  else ifneq ($(filter arm%,$(ARCH)),)
    AIRCONNECT_ARCH := arm
  else ifneq ($(filter mips64el%,$(ARCH)),)
    AIRCONNECT_ARCH := mips64el
  else ifneq ($(filter mips64%,$(ARCH)),)
    AIRCONNECT_ARCH := mips64
  else ifneq ($(filter mipsel%,$(ARCH)),)
    AIRCONNECT_ARCH := mipsel
  else ifneq ($(filter mips%,$(ARCH)),)
    AIRCONNECT_ARCH := mips
  endif
endif

# Only aarch64 and x86_64 are shipped by the 1.12.4 release, but the mapping
# above also normalizes the documented ARM/MIPS family so a future release or
# device can opt in by extending one list. A value that survives the mapping
# unchanged AND is not a known token is genuinely unmapped (e.g. riscv64).
#
# The check is gated on ARCH being non-empty on purpose: the SDK's package
# scanner sources every Makefile with DUMP=1 and an unset ARCH to build the
# package index, and an unconditional $(error) there aborts the scan, so the
# package never registers and `make package/airconnect-engine/compile` fails
# with "No rule to make target" instead of a useful message. An empty ARCH
# therefore skips the gate, and the same condition is re-asserted inside
# Build/Prepare where ARCH is guaranteed to be set, turning an unsupported
# architecture into a real build failure rather than a bogus binary.
AIRCONNECT_SUPPORTED_ARCHS := aarch64 x86_64 arm armv7 armv6 mips mipsel mips64 mips64el
ifneq ($(ARCH),)
  ifeq ($(AIRCONNECT_ARCH),$(ARCH))
    ifeq ($(filter $(ARCH),$(AIRCONNECT_SUPPORTED_ARCHS)),)
      $(error airconnect-engine: unsupported ARCH=$(ARCH) -- the 1.12.4 release ships aarch64/x86_64 only)
    endif
  endif
endif

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

# Extract the whole archive into a scratch area and move only the two expected
# binaries into place. On a name mismatch the archive listing is printed to
# stderr so the real names are visible instead of guessing. The extraction
# logic lives in files/extract-engines.sh so it can be exercised on the host
# without the OpenWrt toolchain.
#
# ARCH is guaranteed to be set here, so this is where an unsupported target is
# refused for real. The package-level gate above had to skip an empty ARCH to
# keep the SDK scan working.
define Build/Prepare
	$(if $(filter $(AIRCONNECT_ARCH),$(AIRCONNECT_SUPPORTED_ARCHS)),,$(error airconnect-engine: unsupported ARCH=$(ARCH)))
	$(if $(filter aarch64 x86_64,$(AIRCONNECT_ARCH)),,$(error airconnect-engine: the 1.12.4 release ships aarch64/x86_64 only, got $(AIRCONNECT_ARCH)))
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	./files/extract-engines.sh $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR) $(AIRCONNECT_ARCH)
endef

# Verify the extracted files are non-empty ELF binaries. The loop lives in
# files/verify-engines.sh rather than inline: OpenWrt expands Build/Compile
# through several nested macros, and an inline body containing $f is re-expanded
# as a make variable on the way through, producing "empty: " instead of the path.
# A real script removes that failure mode and is testable on the host.
define Build/Compile
	./files/verify-engines.sh $(PKG_BUILD_DIR)/airupnp-linux-$(AIRCONNECT_ARCH)-static $(PKG_BUILD_DIR)/aircast-linux-$(AIRCONNECT_ARCH)-static
endef

define Package/airconnect-engine/install
	$(INSTALL_DIR) $(1)/usr/libexec/airconnect $(1)/usr/share/airconnect
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/airupnp-linux-$(AIRCONNECT_ARCH)-static $(1)/usr/libexec/airconnect/airupnp
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aircast-linux-$(AIRCONNECT_ARCH)-static $(1)/usr/libexec/airconnect/aircast
	$(INSTALL_DATA) ./files/UPSTREAM-LICENSE $(1)/usr/share/airconnect/UPSTREAM-LICENSE
endef

$(eval $(call BuildPackage,airconnect-engine))
