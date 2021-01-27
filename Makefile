# Makefile
#
# Build a TinyCore Linux kernel, modules, and firmware extensions
#
# Usage:
#		make kernel extensions os
# 	make all

MODULES ?= all base filesystems ipv6-netfilter mtd raid-dm scsi input-joystick alsa-modules
KERNEL ?= 5.8.9
KERNEL_ARCH ?= x86_64
KERNEL_SOURCE ?= https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.8.9.tar.xz
KERNEL_SHA256 ?= 99d8bc1b82f17d7d79f9af4a94af4c0e3772159e9e6e278761bde8569f93e15f
OSDIR ?= /opt/tinycore/11.x/x86_64/release/distribution_files
WORKDIR ?= /tmp/tinycore-kernel-build

curdir   	:= $(realpath .)
filename 	:= $(notdir $(KERNEL_SOURCE))
kerneldir := $(WORKDIR)/linux-$(KERNEL)

ifeq ($(KERNEL_ARCH),x86_64)
	ostype := 64
	osfile := corepure64
	kernelname := $(KERNEL)-tinycore$(ostype)
	arch := x86_64
else
	ostype :=
	osfile := core
	kernelname := $(KERNEL)-tinycore
	arch := i386
endif

.PHONY: all clean kernel extensions verify-kernel build-kernel compress-modules pkg-modules os

all:
	$(MAKE) kernel
	$(MAKE) extensions

kernel:
	$(MAKE) $(WORKDIR)/$(filename)
	$(MAKE) verify-kernel
	$(MAKE) build-kernel

extensions:
	$(MAKE) compress-modules
	$(MAKE) pkg-modules

$(WORKDIR)/$(filename):
	mkdir -p $(WORKDIR) && \
	cd $(WORKDIR) && \
	wget $(KERNEL_SOURCE)

verify-kernel:
	cd $(WORKDIR) && \
	echo -n "$(KERNEL_SHA256)  $(filename)" | sha256sum -c -

build-kernel:
	rm -rf $(kerneldir)
	cd $(WORKDIR) && \
	tar -Jxf $(filename) -C $(WORKDIR)
	cp -v $(curdir)/kernels/config-$(kernelname) $(kerneldir)/.config
	$(MAKE) -C $(kerneldir) ARCH=$(arch) oldconfig
	$(MAKE) -C $(kerneldir) ARCH=$(arch) bzImage
	$(MAKE) -C $(kerneldir) ARCH=$(arch) modules
	$(MAKE) -C $(kerneldir) ARCH=$(arch) INSTALL_MOD_PATH=$(WORKDIR)/modules-$(KERNEL) modules_install
	cp -v $(kerneldir)/arch/x86/boot/bzImage $(WORKDIR)/vmlinuz$(ostype)

compress-modules:
	mkdir -p $(WORKDIR) && \
	cd $(WORKDIR)/modules-$(KERNEL) && \
	find . -type f -name "*.ko" -exec strip --strip-unneeded {} \; && \
	find . -type f -name "*.ko" -exec gzip {} \;

$(WORKDIR)/%-$(kernelname).tcz:
	cd $(WORKDIR) && \
	rm -rf modules-$* && \
	mkdir -p modules-$*/usr/local/lib/modules/$(kernelname)
	cd $(WORKDIR)/modules-$(KERNEL)/lib/modules/$(kernelname) && \
	for i in `cat $(curdir)/modules/$(kernelname)/$*.txt`; do \
		cp -v --parents $$i $(WORKDIR)/modules-$*/usr/local/lib/modules/$(kernelname)/; \
	done

	cd $(WORKDIR) && \
	mksquashfs modules-$* $@ -b 4096

pkg-modules:
	for module in $(MODULES); do \
		[ -f "$(curdir)/modules/$(kernelname)/$$module.txt" ] && $(MAKE) $(WORKDIR)/$$module-$(kernelname).tcz || { >&2 echo "Missing module file: $(curdir)/modules/$(kernelname)/$$module.txt"; exit 127; }; \
	done

os:
	rm -rf $(WORKDIR)/os-$(osfile)
	mkdir -p $(WORKDIR)/os-$(osfile)
	cd $(WORKDIR)/os-$(osfile) && \
	gunzip -c $(OSDIR)/$(osfile).gz | cpio -id && \
	rm -rf lib/modules/* && \
	mkdir -p lib/modules/$(kernelname) && \
	cp -rp $(WORKDIR)/modules-base/usr/local/lib/modules/$(kernelname)/kernel lib/modules/$(kernelname)/
	cd $(WORKDIR)/modules-$(KERNEL)/lib/modules/$(kernelname) && \
	cp modules.alias modules.dep $(WORKDIR)/os-$(osfile)/lib/modules/$(kernelname)/
	mv $(WORKDIR)/os-$(osfile)/usr/local/lib/modules/5.4.3-tinycore64 $(WORKDIR)/os-$(osfile)/usr/local/lib/modules/$(kernelname)
	ln -sf /usr/local/lib/modules/$(kernelname)/kernel $(WORKDIR)/os-$(osfile)/lib/modules/$(kernelname)/kernel.tclocal
	cd $(WORKDIR)/os-$(osfile)/lib/modules/$(kernelname) && \
	sed -i 's/.ko/.ko.gz/g' modules.dep
	$(MAKE) $(WORKDIR)/$(osfile)

$(WORKDIR)/$(osfile):
	cd $(WORKDIR)/os-$(osfile) && \
	find | sort | cpio -o -H newc > $(WORKDIR)/$(osfile)
	$(MAKE) $(WORKDIR)/$(osfile).gz

$(WORKDIR)/$(osfile).gz:
	cd $(WORKDIR) && \
	gzip -c $(osfile) > $(osfile).gz

clean:
	rm -rf $(kerneldir) $(WORKDIR)/$(filename) $(WORKDIR)/modules-* $(WORKDIR)/vmlinuz$(ostype) $(WORKDIR)/*$(kernelname).tcz $(WORKDIR)/$(osfile)* $(WORKDIR)/os-$(osfile)
