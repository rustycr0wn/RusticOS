# RusticOS Development Environment Makefile
# ==========================================
# Build and run the OS, with clear targets and output

# Tools
NASM = nasm
QEMU = qemu-system-x86_64
CC = gcc
CXX = g++
LD = ld
OBJCOPY = objcopy

# Flags
NASM_FLAGS = -f bin
CFLAGS = -m32 -ffreestanding -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c99
CXXFLAGS = -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pie -O2 -Wall -Wextra -std=c++11
LDFLAGS = -nostdlib -T linker.ld -melf_i386
QEMU_FLAGS = -machine pc -boot c -drive file=$(OS_IMAGE),if=ide,format=raw
NPROCS := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Directories and Files
OUT_DIR = out
BUILD_DIR = build
SRC_DIR = src
BOOT_DIR = boot
BOOTLOADER = $(OUT_DIR)/bootloader.bin
LOADER = $(OUT_DIR)/loader.bin
KERNEL_ELF = $(OUT_DIR)/kernel.elf
KERNEL_BIN = $(OUT_DIR)/kernel.bin
OS_IMAGE = $(OUT_DIR)/os.img
OUT_LOADER_PAD = $(OUT_DIR)/loader.pad
OUT_KERNEL_PAD = $(OUT_DIR)/kernel.pad

# Default target
all: $(OS_IMAGE) os.img

# Create build/output directories
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
$(OUT_DIR):
	@mkdir -p $(OUT_DIR)

# Build bootloader (MBR, 16-bit)
$(BOOTLOADER): $(BOOT_DIR)/bootloader.asm boot/loader_sectors.inc | $(OUT_DIR)
	$(NASM) $(NASM_FLAGS) -o $@ $<

# Build loader (second stage)
$(LOADER): $(BOOT_DIR)/loader.asm $(KERNEL_BIN) | $(OUT_DIR)
	$(NASM) $(NASM_FLAGS) -DKERNEL_SIZE_BYTES=$(shell stat -c%s $(KERNEL_BIN)) -o $@ $<

# Build kernel startup and kernel
$(BUILD_DIR)/crt0.o: $(SRC_DIR)/crt0.s | $(BUILD_DIR)
	$(CC) -c $(CFLAGS) $< -o $@
$(BUILD_DIR)/kernel.o: $(SRC_DIR)/kernel.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $< -o $@
$(BUILD_DIR)/keyboard.o: $(SRC_DIR)/keyboard.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $< -o $@
$(BUILD_DIR)/terminal.o: $(SRC_DIR)/terminal.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $< -o $@

# Link kernel ELF
$(KERNEL_ELF): $(BUILD_DIR)/crt0.o $(BUILD_DIR)/kernel.o $(BUILD_DIR)/keyboard.o $(BUILD_DIR)/terminal.o linker.ld | $(OUT_DIR)
	$(LD) $(LDFLAGS) -o $@ $(BUILD_DIR)/crt0.o $(BUILD_DIR)/kernel.o $(BUILD_DIR)/keyboard.o $(BUILD_DIR)/terminal.o

# Convert kernel ELF to raw binary
$(KERNEL_BIN): $(KERNEL_ELF) | $(OUT_DIR)
	$(OBJCOPY) -O binary $< $@

# Ensure loader and kernel binaries are padded to full sectors before writing to image
$(OUT_LOADER_PAD): $(LOADER)
	dd if=$(LOADER) of=$(OUT_LOADER_PAD) bs=512 conv=sync

$(OUT_KERNEL_PAD): $(KERNEL_BIN)
	dd if=$(KERNEL_BIN) of=$(OUT_KERNEL_PAD) bs=512 conv=sync

# Generate loader/kernel sector count includes
boot/loader_sectors.inc: $(OUT_LOADER_PAD)
	@echo "%ifndef LOADER_SECTORS" > $@
	@echo "LOADER_SECTORS equ $(shell stat -c%s $(OUT_LOADER_PAD) | awk '{printf \"%d\", int( ($$1+511)/512 ) }')" >> $@
	@echo "%endif" >> $@
boot/kernel_sectors.inc: $(OUT_KERNEL_PAD)
	@echo "%ifndef KERNEL_SECTORS" > $@
	@echo "KERNEL_SECTORS equ $(shell stat -c%s $(OUT_KERNEL_PAD) | awk '{printf \"%d\", int( ($$1+511)/512 ) }')" >> $@
	@echo "%endif" >> $@

# Create OS image (bootloader, loader, kernel)
$(OS_IMAGE): $(BOOTLOADER) $(OUT_LOADER_PAD) $(OUT_KERNEL_PAD) | $(OUT_DIR)
	@echo "\033[1;34m[INFO]\033[0m Creating OS image..."
	dd if=/dev/zero of=$(OS_IMAGE) bs=1M count=10 conv=notrunc
	dd if=$(BOOTLOADER) of=$(OS_IMAGE) bs=512 seek=0 count=1 conv=notrunc
	dd if=$(OUT_LOADER_PAD) of=$(OS_IMAGE) bs=512 seek=1 count=$(shell stat -c%s $(OUT_LOADER_PAD) | awk '{printf "%d", int( ($$1+511)/512 ) }') conv=notrunc
	dd if=$(OUT_KERNEL_PAD) of=$(OS_IMAGE) bs=512 seek=$(shell echo $$(($(shell stat -c%s $(OUT_LOADER_PAD) | awk '{printf "%d", int( ($$1+511)/512 ) }')+1))) count=$(shell stat -c%s $(OUT_KERNEL_PAD) | awk '{printf "%d", int( ($$1+511)/512 ) }') conv=notrunc
	@echo "\033[1;32m[SUCCESS]\033[0m OS image created: $(OS_IMAGE)"

# Copy image to project root for QEMU
os.img: $(OS_IMAGE)
	cp $(OS_IMAGE) os.img

# Run targets
run: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU with VNC display (127.0.0.1:0)..."
	$(QEMU) $(QEMU_FLAGS) -display vnc=127.0.0.1:0
run-headless: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU headless..."
	$(QEMU) $(QEMU_FLAGS) -nographic
run-curses: $(OS_IMAGE)
	@echo "\033[1;36m[RUN]\033[0m Starting QEMU with curses display..."
	$(QEMU) $(QEMU_FLAGS) -display curses
debug: $(OS_IMAGE)
	@echo "\033[1;33m[DEBUG]\033[0m Starting QEMU in debug mode..."
	$(QEMU) $(QEMU_FLAGS) -display vnc=127.0.0.1:0 -s -S

# Fast build
fast:
	@echo "\033[1;34m[INFO]\033[0m Building in parallel with -j$(NPROCS)"
	$(MAKE) -j$(NPROCS) all

# Build only kernel
kernel: $(KERNEL_ELF)

# Build only boot components
boot: $(BOOTLOADER) $(LOADER)

# Clean
clean:
	rm -rf $(OUT_DIR) $(BUILD_DIR) os.img

# Help
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
