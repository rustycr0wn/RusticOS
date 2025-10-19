# Makefile for rusticOSboot with bootloader.asm and loader.asm

# Assembler and tools
NASM = nasm
DD = dd
QEMU = qemu-system-x86_64

# Directories
BOOT_DIR = boot
BUILD_DIR = build

# Source files
BOOTLOADER_SRC = $(BOOT_DIR)/bootloader.asm
LOADER_SRC = $(BOOT_DIR)/loader.asm

# Output files
BOOTLOADER_BIN = $(BUILD_DIR)/bootloader.bin
LOADER_BIN = $(BUILD_DIR)/loader.bin
DISK_IMG = $(BUILD_DIR)/disk.img

# Kernel settings (you'll need to adjust these based on your kernel)
KERNEL_SIZE_BYTES ?= 32768
LOADER_SECTORS = 2

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build bootloader (MBR)
$(BOOTLOADER_BIN): $(BOOTLOADER_SRC) | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $< -DKERNEL_SIZE_BYTES=$(KERNEL_SIZE_BYTES)

# Build loader
$(LOADER_BIN): $(LOADER_SRC) | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $< -DKERNEL_SIZE_BYTES=$(KERNEL_SIZE_BYTES)

# Create disk image
$(DISK_IMG): $(BOOTLOADER_BIN) $(LOADER_BIN) | $(BUILD_DIR)
	# Create 1MB disk image
	$(DD) if=/dev/zero of=$@ bs=1024 count=1024
	# Write MBR (bootloader) to sector 0
	$(DD) if=$(BOOTLOADER_BIN) of=$@ bs=512 count=1 conv=notrunc
	# Write loader starting at sector 1
	$(DD) if=$(LOADER_BIN) of=$@ bs=512 seek=1 conv=notrunc

# Build everything
all: $(DISK_IMG)

# Clean build files
clean:
	rm -rf $(BUILD_DIR)

# Run in QEMU
run: $(DISK_IMG)
	$(QEMU) -drive format=raw,file=$< -m 512M

# Debug in QEMU
debug: $(DISK_IMG)
	$(QEMU) -drive format=raw,file=$< -m 512M -s -S

.PHONY: all clean run debug