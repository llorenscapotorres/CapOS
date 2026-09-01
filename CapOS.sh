#!/bin/bash
set -e

# Verify if nasm and qemu are installed
if ! command -v nasm &> /dev/null || ! command -v qemu-system-i386 &> /dev/null; then
    echo "Instalando dependencias..."
    make install-deps
fi

# Execute OS

make 

qemu-system-i386 -fda build/bootable_floppy.img -boot a
