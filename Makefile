PROJDIRS = src/kernel/boot src/kernel/include src/kernel/init

# Adds all source files in the subdirs referenced by PROJDIRS
SRCFILES := $(shell find $(PROJDIRS) -mindepth 1 -maxdepth 3 -name "*.c")
HDRFILES := $(shell find $(PROJDIRS) -mindepth 1 -maxdepth 3 -name "*.h")
ASMFILES := $(shell find $(PROJDIRS) -mindepth 1 -maxdepth 3 -name "*.s")
OBJFILES := $(patsubst %.s,%.o,$(ASMFILES)) $(patsubst %.c,%.o,$(SRCFILES))
DEPFILES := $(patsubst %.c,%.d,$(SRCFILES))
ALLFILES := $(SRCFILES) $(HDRFILES) $(ASMFILES) 

# Generated files that should be deleted by make clean
GENFILES := kernel kernel.map bootable.iso efi.disk grub-2.00.tar.xz grub grub_i386 \
			grub_i386_efi iso bios_ia32.bin OVMF-IA32 OVMF-IA32-r15214.zip

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
	make && \
	make install

grub_i386_efi: grub
	cp -r grub grub_i386_efi
	cd grub_i386_efi && \
	./configure --with-platform=efi --prefix=`pwd` --target=i386 && \
	make && \
	make install


qemu-bios: kernel grub_i386
	mkdir -p iso/boot/grub
	cp tools/grub.cfg iso/boot/grub/grub.cfg
	cp kernel iso/boot/kernel
	grub_i386/grub-mkrescue -o bootable.iso iso
	qemu-system-i386 -cdrom bootable.iso
	

grub_i386_efi/grub-core/grub.efi: grub_i386_efi
	cd grub_i386_efi/grub-core && \
	../grub-mkimage -O i386-efi -d . -o grub.efi -p "" part_gpt part_msdos ntfs ntfscomp \
	hfsplus fat ext2 normal chain boot configfile linux multiboot	

efi.disk: grub_i386_efi/grub-core/grub.efi
	dd if=/dev/zero of=efi.disk bs=1024 count=32768
	losetup /dev/loop0 efi.disk
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

bios_ia32.bin:
	wget https://sourceforge.net/projects/edk2/files/OVMF/OVMF-IA32-r15214.zip
	unzip OVMF-IA32-r15214.zip -d OVMF-IA32
	cp OVMF-IA32/OVMF.fd bios_ia32.bin

qemu-efi: bios_ia32.bin efi.disk
	qemu-system-i386 -bios bios_ia32.bin -cdrom efi.disk

usb-bios:
	echo
	
usb-efi:
	echo

clean:
	-@for file in $(OBJFILES) $(DEPFILES) $(GENFILES); do if [ -e $$file ]; then rm -r $$file; fi; done
	
	
-include $(DEPFILES)

%.o: %.s Makefile
	@echo " AS	$(patsubst functions/%,%,$@)"
	@nasm $(ASFLAGS) -o $@ $<

%.o: %.c
	@echo " CC	$(patsubst functions/%,%,$@)"
	@$(CC) $(CFLAGS) -m32 -MMD -MP -MT "$*.d $*.t" -g -c $< -o $@
