# RusticOS Development Environment Makefile
# Builds MBR, VBR, loader, and 32-bit kernel; creates partitioned disk image and can flash USB

# Tools
NASM = nasm
LD = ld
OBJCOPY = objcopy
CC = gcc
CXX = g++

IMG = os.img
BUILD = build

all: image

# --- Kernel build ---
$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/crt0.o: src/crt0.s | $(BUILD)
	$(CC) -c -m32 -ffreestanding -fno-stack-protector -fno-pie -O2 -Wall -Wextra $< -o $@

$(BUILD)/kernel.o: src/kernel.cpp | $(BUILD)
	$(CXX) -c -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11 $< -o $@

$(BUILD)/terminal.o: src/terminal.cpp | $(BUILD)
	$(CXX) -c -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11 $< -o $@

$(BUILD)/command.o: src/command.cpp | $(BUILD)
	$(CXX) -c -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11 $< -o $@

$(BUILD)/filesystem.o: src/filesystem.cpp | $(BUILD)
	$(CXX) -c -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11 $< -o $@

$(BUILD)/virtual_disk.o: src/virtual_disk.cpp | $(BUILD)
	$(CXX) -c -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11 $< -o $@

$(BUILD)/kernel.elf: $(BUILD)/crt0.o $(BUILD)/kernel.o $(BUILD)/terminal.o $(BUILD)/command.o $(BUILD)/filesystem.o $(BUILD)/virtual_disk.o linker.ld | $(BUILD)
	$(LD) -nostdlib -melf_i386 -T linker.ld -o $@ $(BUILD)/crt0.o $(BUILD)/kernel.o $(BUILD)/terminal.o $(BUILD)/command.o $(BUILD)/filesystem.o $(BUILD)/virtual_disk.o

$(BUILD)/kernel.bin: $(BUILD)/kernel.elf | $(BUILD)
	$(OBJCOPY) -O binary $< $@

# --- Boot components ---
boot/mbr.bin: boot/mbr.asm
	$(NASM) -f bin $< -o $@
	printf '\x80\x00\x01\x00\x83\x00\x01\x00\x01\x00\x00\x00\x00\x00\x02\x00' | dd of=$@ bs=1 seek=446 conv=notrunc

boot/loader.bin: boot/loader.asm $(BUILD)/kernel.bin
	$(NASM) -f bin -DKERNEL_SIZE_BYTES=$$(stat -c%s $(BUILD)/kernel.bin) $< -o $@

boot/loader_sectors.inc: boot/loader.bin
	@echo "%ifndef LOADER_SECTORS" > $@
	@echo "LOADER_SECTORS equ $$(( ( $$(stat -c%s boot/loader.bin) + 511 ) / 512 ))" >> $@
	@echo "%endif" >> $@

boot/vbr.bin: boot/bootloader.asm boot/loader_sectors.inc
	$(NASM) -f bin $< -o $@

# --- Image creation ---
image: boot/mbr.bin boot/vbr.bin boot/loader.bin boot/loader_sectors.inc
	dd if=boot/mbr.bin of=$(IMG) bs=512 count=1 conv=notrunc
	dd if=boot/vbr.bin of=$(IMG) bs=512 seek=1 conv=notrunc
	dd if=boot/loader.bin of=$(IMG) bs=512 seek=2 count=$$(awk '/LOADER_SECTORS/{print $$3}' boot/loader_sectors.inc | tr -d '"' | tr -d '\r\n') conv=notrunc

run: image
	qemu-system-x86_64 -m 256M -drive file=$(IMG),format=raw,if=ide -boot c -serial stdio

clean:
	rm -f boot/mbr.bin boot/vbr.bin boot/loader.bin boot/loader_sectors.inc $(IMG) $(BUILD)/*.o $(BUILD)/kernel.elf $(BUILD)/kernel.bin
