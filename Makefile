# Compiler settings
ASM = nasm

# Directory settings
SRC_DIR = src
BUILD_DIR = build
INSTALL_DIR = .install

.PHONY: all install-deps

# Default target: build the bootable floppy image
all: $(BUILD_DIR)/bootable_floppy.img

# Install dependencies
install-deps:
	@chmod +x $(INSTALL_DIR)/install-deps.sh
	@./$(INSTALL_DIR)/install-deps.sh

# Create floppy disk image (1.44 MB) containing the bootloader
# This simulates a physical 3.5" floppy disk for emulation
$(BUILD_DIR)/bootable_floppy.img: $(BUILD_DIR)/bootloader.bin
	@cp $(BUILD_DIR)/bootloader.bin $(BUILD_DIR)/bootable_floppy.img
	@truncate -s 1440k $(BUILD_DIR)/bootable_floppy.img

# Compile bootloader assembly to raw binary (no ELF header)
# -f bin means raw binary format (not object file)
$(BUILD_DIR)/bootloader.bin: $(SRC_DIR)/bootloader.asm
	@mkdir -p $(BUILD_DIR)
	@$(ASM) $(SRC_DIR)/bootloader.asm -f bin -o $(BUILD_DIR)/bootloader.bin
