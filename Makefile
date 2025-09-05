# RusticOS Development Environment Makefile
# Supports both 16-bit bootloader and 32-bit C++ kernel

# Compiler and assembler
NASM = nasm
QEMU = qemu-system-x86_64

# Use system GCC with 32-bit support
CC = gcc
CXX = g++
LD = ld
OBJCOPY = objcopy

# Flags
NASM_FLAGS = -f bin
# QEMU flags for hard disk
QEMU_FLAGS = -machine pc -boot c -drive file=$(OS_IMAGE),if=ide,format=raw
# Parallel build helper
NPROCS := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# C++ compilation flags
CXXFLAGS = -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11
CFLAGS = -m32 -ffreestanding -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c99
LDFLAGS = -nostdlib -T linker.ld -melf_i386

# Files
OUT_DIR = out
BOOTLOADER = $(OUT_DIR)/bootloader.bin
LOADER = $(OUT_DIR)/loader.bin
KERNEL_ELF = $(OUT_DIR)/kernel.elf
KERNEL_BIN = $(OUT_DIR)/kernel.bin
OS_IMAGE = $(OUT_DIR)/os.img
ISO_IMAGE = $(OUT_DIR)/rusticOS.iso

# Directories
BUILD_DIR = build
SRC_DIR = src
BOOT_DIR = boot

print-kernel-info: $(KERNEL_BIN)
	@echo "Kernel size: $(shell stat -c%s $(KERNEL_BIN)) bytes"
	@echo "Kernel sectors: $(KERNEL_SECTORS)"

# Default target
all: $(OS_IMAGE) os.img

# Create build/output directories
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
$(OUT_DIR):
	mkdir -p $(OUT_DIR)

# === Build rules for RusticOS ===

# Compute loader/kernel sector counts
LOADER_SECTORS = $(shell if [ -f out/loader.bin ]; then s=$$(stat -c%s out/loader.bin); echo $$(( ($$s + 511) / 512 )); else echo 2; fi)
KERNEL_SECTORS = $(shell if [ -f out/kernel.bin ]; then s=$$(stat -c%s out/kernel.bin); echo $$(( ($$s + 511) / 512 )); else echo 11; fi)

# 1. Build bootloader (MBR, 16-bit)
# Compute loader sectors and provide to both bootloader and image layout
$(BOOTLOADER): $(BOOT_DIR)/bootloader.asm $(LOADER) | $(OUT_DIR)
	$(NASM) $(NASM_FLAGS) -DLOADER_SECTORS=$(LOADER_SECTORS) -o $@ $<

# 2. Build second-stage loader (loads kernel, switches to protected mode)
# Ensure the loader gets an accurate sector count computed from the built kernel.
# Depend on $(KERNEL_BIN) so the size is available, and pass -DKERNEL_SECTORS to NASM.
$(LOADER): $(BOOT_DIR)/loader.asm $(KERNEL_BIN) | $(OUT_DIR)
	$(NASM) $(NASM_FLAGS) -DKERNEL_SIZE_BYTES=$(shell stat -c%s $(KERNEL_BIN)) -DLOADER_SECTORS=$(LOADER_SECTORS) -o $@ $<

# 3. Build kernel startup (crt0), kernel, drivers, and terminal
$(BUILD_DIR)/crt0.o: $(SRC_DIR)/crt0.s | $(BUILD_DIR)
	$(CC) -c $(CFLAGS) $< -o $@
$(BUILD_DIR)/kernel.o: $(SRC_DIR)/kernel.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $< -o $@
$(BUILD_DIR)/keyboard.o: $(SRC_DIR)/keyboard.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $< -o $@
$(BUILD_DIR)/terminal.o: $(SRC_DIR)/terminal.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $< -o $@

# 4. Link kernel ELF (entry at 0x100000)
$(KERNEL_ELF): $(BUILD_DIR)/crt0.o $(BUILD_DIR)/kernel.o $(BUILD_DIR)/keyboard.o $(BUILD_DIR)/terminal.o linker.ld | $(OUT_DIR)
	$(LD) $(LDFLAGS) -o $@ $(BUILD_DIR)/crt0.o $(BUILD_DIR)/kernel.o $(BUILD_DIR)/keyboard.o $(BUILD_DIR)/terminal.o

# 5. Convert kernel ELF to raw binary for disk image
$(KERNEL_BIN): $(KERNEL_ELF) | $(OUT_DIR)
	$(OBJCOPY) -O binary $< $@

# 6. Generate loader include files (guarded to allow -D override)

boot/loader_sectors.inc: $(LOADER)
	@echo "%ifndef LOADER_SECTORS" > $@
	@echo "LOADER_SECTORS equ $(LOADER_SECTORS)" >> $@
	@echo "%endif" >> $@

# Write kernel sector count for loader
boot/kernel_sectors.inc: $(KERNEL_BIN)
	@echo "%ifndef KERNEL_SECTORS" > $@
	@echo "KERNEL_SECTORS equ $(KERNEL_SECTORS)" >> $@
	@echo "%endif" >> $@

# 7. Create OS image (bootloader, loader, kernel)
$(OS_IMAGE): $(BOOTLOADER) $(LOADER) $(KERNEL_BIN) | $(OUT_DIR)
	@echo "\033[1;34m[INFO]\033[0m Creating OS image..."
	@LS=$$(stat -c%s $(LOADER)); KS=$$(stat -c%s $(KERNEL_BIN)); \
	 LSEC=$$(echo $$LS | awk '{printf "%d", int( ($$1+511)/512 ) }'); \
	 KSEC=$$(echo $$KS | awk '{printf "%d", int( ($$1+511)/512 ) }'); \
	 echo "\033[1;34m[INFO]\033[0m LOADER_SECTORS=$$LSEC KERNEL_SECTORS=$$KSEC"; \
	 dd if=/dev/zero of=$(OS_IMAGE) bs=1M count=10 conv=notrunc; \
	 dd if=$(BOOTLOADER) of=$(OS_IMAGE) bs=512 seek=0 count=1 conv=notrunc; \
	 dd if=$(LOADER) of=$(OS_IMAGE) bs=512 seek=1 count=$$LSEC conv=notrunc; \
	 dd if=$(KERNEL_BIN) of=$(OS_IMAGE) bs=512 seek=$$(($$LSEC + 1)) count=$$KSEC conv=notrunc; \
	 echo "\033[1;32m[SUCCESS]\033[0m OS image created: $(OS_IMAGE)"

# After building out/os.img, copy to project root for QEMU
os.img: out/os.img
	cp out/os.img os.img

# ======================
# Run the OS in QEMU with VNC display (default)
run: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU with VNC display (127.0.0.1:0)..."
	$(QEMU) $(QEMU_FLAGS) -display vnc=127.0.0.1:0

# Run in QEMU headless (no display)
run-headless: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU headless..."
	$(QEMU) $(QEMU_FLAGS) -nographic

# Run in QEMU with curses display (if available)
run-curses: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU with curses display..."
	$(QEMU) $(QEMU_FLAGS) -display curses

# Debug mode with QEMU
# ======================
debug: $(OS_IMAGE)
	@echo "\033[1;33m[DEBUG]\033[0m Starting QEMU in debug mode..."
	$(QEMU) $(QEMU_FLAGS) -display vnc=127.0.0.1:0 -s -S

# Fast build wrapper (uses available CPU cores)
fast:
	@echo "\033[1;34m[INFO]\033[0m Building in parallel with -j$(NPROCS)"
	$(MAKE) -j$(NPROCS) all

# Build only the kernel (for development)
kernel: $(KERNEL_ELF)

# Build only the boot components
boot: $(BOOTLOADER) $(LOADER)

# Build check: Ensure loader.bin does not start with ASCII 'S' (0x53)
check-loader:
	hexdump -C $(LOADER) | head -n 1 | grep -q '53' && \
	  (echo "[ERROR] loader.bin starts with ASCII 'S' (0x53)!"; exit 1) || \
	  echo "[OK] loader.bin does not start with ASCII 'S' (0x53)"

# Clean build files
clean:
	rm -rf $(OUT_DIR) $(BUILD_DIR)

# Show help
help:
	@echo "Available targets:"
	@echo "  all         - Build the complete OS image"
	@echo "  boot        - Build only bootloader and loader"
	@echo "  kernel      - Build only the 32-bit kernel"
	@echo "  run         - Build and run with VNC display (127.0.0.1:0)"
	@echo "  run-headless- Build and run without display (headless)"
	@echo "  run-curses  - Build and run with curses display"
	@echo "  debug       - Build and run in QEMU debug mode"
	@echo "  fast        - Build using parallel jobs (auto-detected core count)"
	@echo "  clean       - Remove build files"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "To view VNC output:"
	@echo "  Install a VNC client and connect to 127.0.0.1:0"
	@echo "  Or use: vncviewer 127.0.0.1:0"
	@echo ""
	@echo "System GCC with 32-bit support is used for compilation"

.PHONY: all boot kernel run run-headless run-curses debug clean help fast

boot-qemu:
	qemu-system-x86_64 -drive file=os.img,format=raw

iso: $(OS_IMAGE)
	@echo "\033[1;34m[INFO]\033[0m Creating bootable ISO..."
	mkdir -p $(OUT_DIR)/isofs/boot
	cp os.img $(OUT_DIR)/isofs/boot/os.img
	@if command -v genisoimage >/dev/null 2>&1; then \
		genisoimage -quiet -V "RUSTICOS" -input-charset iso8859-1 -o $(ISO_IMAGE) -b boot/os.img -no-emul-boot -boot-load-size 4 -boot-info-table $(OUT_DIR)/isofs; \
	elif command -v mkisofs >/dev/null 2>&1; then \
		mkisofs -quiet -V "RUSTICOS" -input-charset iso8859-1 -o $(ISO_IMAGE) -b boot/os.img -no-emul-boot -boot-load-size 4 -boot-info-table $(OUT_DIR)/isofs; \
	elif command -v xorriso >/dev/null 2>&1; then \
		xorriso -as mkisofs -quiet -V "RUSTICOS" -input-charset iso8859-1 -o $(ISO_IMAGE) -b boot/os.img -no-emul-boot -boot-load-size 4 -boot-info-table $(OUT_DIR)/isofs; \
	else \
		echo "\033[1;31m[ERROR]\033[0m No ISO creation tool found (genisoimage/mkisofs/xorriso)." && exit 1; \
	fi
	@echo "\033[1;32m[SUCCESS]\033[0m ISO created: $(ISO_IMAGE)"

run-vnc1: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU on VNC :1..."
	$(QEMU) $(QEMU_FLAGS) -display vnc=127.0.0.1:1
