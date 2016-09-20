PROJDIRS = src/kernel/boot src/kernel/include src/kernel/init

# Adds all source files in the subdirs referenced by PROJDIRS
SRCFILES := $(shell find $(PROJDIRS) -mindepth 1 -maxdepth 3 -name "*.c")
HDRFILES := $(shell find $(PROJDIRS) -mindepth 1 -maxdepth 3 -name "*.h")
ASMFILES := $(shell find $(PROJDIRS) -mindepth 1 -maxdepth 3 -name "*.s")
OBJFILES := $(patsubst %.s,%.o,$(ASMFILES)) $(patsubst %.c,%.o,$(SRCFILES))
DEPFILES := $(patsubst %.c,%.d,$(SRCFILES))
ALLFILES := $(SRCFILES) $(HDRFILES) $(ASMFILES) 

# Generated files that should be deleted by make clean
GENFILES := kernel kernel.map bootable.iso efi_i386.disk efi_x64.disk grub-2.00.tar.xz grub grub_* \
			iso bios_*.bin OVMF-*

# Toolflags
AS=nasm
CC=gcc
CFLAGS=-DNDEBUG -nostdlib -nostdinc -fno-builtin -fno-stack-protector -std=c99 -I./include
LDFLAGS=-m elf_i386 -Tsrc/kernel/link.ld
ASFLAGS=-felf

all: kernel

kernel: $(OBJFILES)
	@echo " LD	kernel"
	@ld $(LDFLAGS) -Map kernel.map -o kernel $(OBJFILES)
	
qemu-kernel: kernel
	@qemu-system-x86_64 -kernel kernel

grub:
	wget ftp://ftp.gnu.org/gnu/grub/grub-2.00.tar.xz
	tar Jxf grub-2.00.tar.xz
	mv grub-2.00 grub
	cp tools/patch1 tools/patch2 tools/patch3 grub/
	cd grub && \
	patch -p0 < patch1 && \
	patch -p0 < patch2 && \
	patch -p0 < patch3

grub_i386: grub
	cp -r grub grub_i386
	cd grub_i386 && \
	./configure --prefix=`pwd` --target=i386 && \
	make
	-cd grub_i386 && make install

grub_i386_efi: grub
	cp -r grub grub_i386_efi
	cd grub_i386_efi && \
	./configure --with-platform=efi --prefix=`pwd` --target=i386 && \
	make
	-cd grub_i386_efi && make install

grub_x64_efi: grub
	cp -r grub grub_x64_efi
	cd grub_x64_efi && \
	./configure --with-platform=efi --prefix=`pwd` --target=x86_64 && \
	make
	-cd grub_x64_efi && make install

bootable.iso: kernel grub_i386
	mkdir -p iso/boot/grub
	cp tools/grub.cfg iso/boot/grub/grub.cfg
	cp kernel iso/boot/kernel
	grub_i386/grub-mkrescue -o bootable.iso iso

qemu-bios: bootable.iso
	qemu-system-i386 -cdrom bootable.iso

grub_i386_efi/grub-core/grub.efi: grub_i386_efi
	cd grub_i386_efi/grub-core && \
	../grub-mkimage -O i386-efi -d . -o grub.efi -p "" part_gpt part_msdos ntfs ntfscomp \
	hfsplus fat ext2 normal chain boot configfile linux multiboot

grub_x64_efi/grub-core/grub.efi: grub_x64_efi
	cd grub_x64_efi/grub-core && \
	../grub-mkimage -O x86_64-efi -d . -o grub.efi -p "" part_gpt part_msdos ntfs ntfscomp \
	hfsplus fat ext2 normal chain boot configfile linux multiboot

efi_i386.disk: grub_i386_efi/grub-core/grub.efi
	dd if=/dev/zero of=efi_i386.disk bs=1024 count=32768
	losetup /dev/loop0 efi_i386.disk
	mkdosfs -F 12 /dev/loop0
	mount /dev/loop0 /mnt
	mkdir -p /mnt/efi/boot
	mkdir -p /mnt/boot
	cd grub_i386_efi/grub-core && \
	cp grub.efi /mnt/efi/boot/bootia32.efi && \
	cp *.mod *.lst /mnt/efi/boot
	cp tools/grub.cfg /mnt/efi/boot/grub.cfg
	cp kernel /mnt/boot/kernel
	umount /mnt
	losetup -d /dev/loop0

efi_x64.disk: kernel grub_x64_efi/grub-core/grub.efi
	dd if=/dev/zero of=efi_x64.disk bs=1024 count=32768
	losetup /dev/loop0 efi_x64.disk
	mkdosfs -F 12 /dev/loop0
	mount /dev/loop0 /mnt
	mkdir -p /mnt/efi/boot
	mkdir -p /mnt/boot
	cd grub_x64_efi/grub-core && \
	cp grub.efi /mnt/efi/boot/bootx64.efi && \
	cp *.mod *.lst /mnt/efi/boot
	cp tools/grub.cfg /mnt/efi/boot/grub.cfg
	cp kernel /mnt/boot/kernel
	umount /mnt
	losetup -d /dev/loop0

bios_ia32.bin:
	wget https://sourceforge.net/projects/edk2/files/OVMF/OVMF-IA32-r15214.zip
	unzip OVMF-IA32-r15214.zip -d OVMF-IA32
	cp OVMF-IA32/OVMF.fd bios_ia32.bin

bios_x64.bin:
	wget https://sourceforge.net/projects/edk2/files/OVMF/OVMF-X64-r15214.zip
	unzip OVMF-X64-r15214.zip -d OVMF-X64
	cp OVMF-X64/OVMF.fd bios_x64.bin

qemu-efi-i386: bios_ia32.bin efi_i386.disk
	qemu-system-i386 -bios bios_ia32.bin -cdrom efi_i386.disk

qemu-efi-x64: bios_x64.bin efi_x64.disk
	qemu-system-x86_64 -bios bios_x64.bin -cdrom efi_x64.disk

TARGET_DEV=/dev/sdb
usb-efi-x64: kernel grub_x64_efi/grub-core/grub.efi
	# funziona su hw.
	echo "o\ny\nn\n\n\n\nef00\nw\ny\n" | gdisk $(TARGET_DEV)
	mkdosfs -F 12 $(TARGET_DEV)1
	mount -t vfat -o rw,users $(TARGET_DEV)1 /mnt
	mkdir -p /mnt/efi/boot
	mkdir -p /mnt/boot
	cd grub_x64_efi/grub-core && \
	cp grub.efi /mnt/efi/boot/bootx64.efi && \
	cp *.mod *.lst /mnt/efi/boot
	cp tools/grub.cfg /mnt/efi/boot/grub.cfg
	cp kernel /mnt/boot/kernel
	umount /mnt

clean:
	-@for file in $(OBJFILES) $(DEPFILES) $(GENFILES); do if [ -e $$file ]; then rm -r $$file; fi; done
	
	
-include $(DEPFILES)

%.o: %.s Makefile
	@echo " AS	$(patsubst functions/%,%,$@)"
	@nasm $(ASFLAGS) -o $@ $<

%.o: %.c
	@echo " CC	$(patsubst functions/%,%,$@)"
	@$(CC) $(CFLAGS) -m32 -MMD -MP -MT "$*.d $*.t" -g -c $< -o $@
