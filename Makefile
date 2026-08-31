# Compiler settings
ASM = nasm

SRC_DIR = src
BUILD_DIR = build

# Create floppy disk image (1.44 MB) containing the bootloader
# This simulates a physical 3.5" floppy disk for emulation
$(BUILD_DIR)/main_floppy.img: $(BUILD_DIR)/bootloader.bin
	# Copy the bootloader binary act as the floppy disk image
	cp $(BUILD_DIR)/bootloader.bin $(BUILD_DIR)/bootable_floppy.img
	# Expand the image to exactly 1.44 MB (standard floppy size)
	# First 512 bytes: bootloader | Rest: zeros
	truncate -s 1440k $(BUILD_DIR)/bootable_floppy.img

# Compile bootloader assembly to raw binary (no ELF header)
# -f bin means raw binary format (not object file)
$(BUILD_DIR)/bootloader.bin: $(SRC_DIR)/bootloader.asm
	$(ASM) $(SRC_DIR)/bootloader.asm -f bin -o $(BUILD_DIR)/bootloader.bin
