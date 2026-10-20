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
# unchanged AND is not a known token is genuinely unmapped (e.g. riscv64) and
# must fail loudly rather than produce a bogus download path.
ifeq ($(AIRCONNECT_ARCH),$(ARCH))
  ifeq ($(filter $(ARCH),aarch64 x86_64 arm armv7 armv6 mips mipsel mips64 mips64el),)
    $(error airconnect-engine: unsupported ARCH=$(ARCH) -- the 1.12.4 release ships aarch64/x86_64 only)
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
define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	./files/extract-engines.sh $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR) $(AIRCONNECT_ARCH)
endef

# Verify the extracted files are non-empty ELF binaries. Prefer `file` when it
# is present, and fall back to an ELF magic header byte check so the check also
# works inside a minimal SDK container. Fail naming the file and what was found.
define Build/Compile
	for f in $(PKG_BUILD_DIR)/airupnp-linux-$(AIRCONNECT_ARCH)-static $(PKG_BUILD_DIR)/aircast-linux-$(AIRCONNECT_ARCH)-static; do \
		test -s "$$f" || { echo "airconnect-engine: empty: $$f" >&2; exit 1; }; \
		if command -v file >/dev/null 2>&1; then \
			case "$$(file -- "$$f")" in \
				*ELF*) ;; \
				*) echo "airconnect-engine: not an ELF binary: $$f ($$(file -- "$$f"))" >&2; exit 1 ;; \
			esac; \
		else \
			case "$$(od -An -tx1 -N4 "$$f")" in \
				' 7f 45 4c 46'*) ;; \
				*) echo "airconnect-engine: not an ELF binary: $$f ($$(od -An -tx1 -N4 "$$f"))" >&2; exit 1 ;; \
			esac; \
		fi; \
	done
endef

define Package/airconnect-engine/install
	$(INSTALL_DIR) $(1)/usr/libexec/airconnect $(1)/usr/share/airconnect
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/airupnp-linux-$(AIRCONNECT_ARCH)-static $(1)/usr/libexec/airconnect/airupnp
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aircast-linux-$(AIRCONNECT_ARCH)-static $(1)/usr/libexec/airconnect/aircast
	$(INSTALL_DATA) ./files/UPSTREAM-LICENSE $(1)/usr/share/airconnect/UPSTREAM-LICENSE
endef

$(eval $(call BuildPackage,airconnect-engine))
