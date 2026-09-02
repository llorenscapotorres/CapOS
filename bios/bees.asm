; Creating my own BIOS, or in Esperanto, my own BEES

; Assemble for 16-bit real mode
bits 16

; Addresses are calculated relative to file start
org 0x0000

start:
    cli ; ESTO AUN NO SE PARA QUE SIRVE 

    xor ax, ax ; Set ax = 0
    mov ds, ax ; Data Segment = 0
    mov es, ax ; Extra Segment = 0
    mov ss, ax ; Stack Segment = 0
    mov sp, 0x7C00 ; Stack Pointer, grows downward from 0x7C00

    call load_bootloader
    ; jump to the bootloader we just loaded, remember it started at 0x7C00
    jmp 0x0000:0x7C00 ; address = 0x0000 * 16 + 0x7C00 = 0x7C00 

; =========================================================================
; load_bootloader
; Reads sector 0 (LBA 0) from the primary IDE hard disk using PIO mode,
; and places it at memory address 0x7C00 (the conventional bootloader address).
; We talk to the disk controller directly via I/O ports.
; =========================================================================
load_bootloader:
    ; --- Wait until the drive is not busy before doing anything ---
    ; BSY (bit 7 of the status register) means the drive is processing
    ; something internally and is not ready to accept a new command yet.
    call wait_bsy_clear

    ; --- Select drive and set LBA mode ---
    ; Port 0x1F6: bits 7-4 = 1110 (LBA mode, master drive)
    ;             bits 3-0 = LBA bits 24-27 (0 here, since LBA = 0)
    mov dx, 0x1F6
    mov al, 0xE0 ; 1110_0000 = LBA mode, master, LBA bits 24-27 = 0
    out dx, al

    ; --- Wait again: after selecting the drive, it may briefly assert BSY ---
    call wait_bsy_clear

    ; --- Sector count = 1 ---
    mov dx, 0x1F2
    mov al, 1
    out dx, al

    ; --- LBA address = 0 (we want the very first sector) ---
    mov dx, 0x1F3 ; LBA bits 0-7
    mov al, 0
    out dx, al

    mov dx, 0x1F4 ; LBA bits 8-15
    mov al, 0
    out dx, al

    mov dx, 0x1F5 ; LBA bits 16-23
    mov al, 0
    out dx, al

    ; --- Send READ SECTORS command (0x20) ---
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al

    ; --- Wait until the drive is done processing the command ---
    call wait_bsy_clear

; --- Wait until the drive signals data is ready ---
; We poll the status register (same port 0x1F7) until bit 3 (DRQ) is set.
; DRQ = "Data Request" = the drive has data waiting for us to read.
.wait_ready:
    in al, dx ; dx is still 0x1F7 (status register)
    test al, 0x08 ; check bit 3 (DRQ)
    jz .wait_ready ; keep polling until it's set

    ; --- Read 512 bytes (256 words) from the data port into 0x7C00 ---
    mov dx, 0x1F0 ; data port
    mov di, 0x7C00 ; destination address (bootloader location)
    mov cx, 256 ; 256 words = 512 bytes

.read_word:
    in ax, dx ; read one 16-bit word from disk
    stosw ; store it at [es:di], then di += 2
    loop .read_word

    ret

; =========================================================================
; wait_bsy_clear
; Polls the status register (0x1F7) until BSY (bit 7) is 0,
; meaning the drive is free to accept a new command.
; =========================================================================
wait_bsy_clear:
    mov dx, 0x1F7
.poll:
    in al, dx
    test al, 0x80 ; check bit 7 (BSY)
    jnz .poll ; keep polling while BSY is set
    ret

; Fill with zeros up to offset 0xFFF0
times 0xFFF0 - ($ - $$) db 0

; CPU reset vector
; On power-on, the CPU hardware always sets CS=0xF000, IP=0xFFF0.
; Real mode physical address = (segment * 16) + offset
;   0xF000 * 16 + 0xFFF0 = 0xFFFF0 <-- this is where execution begins
; This far jump forces CS=0xF000 explicitly, so the segment is
; guaranteed regardless of what the CPU/emulator set it to.
jmp 0xF000:start

; Fill remaining bytes to reach exactly 64KB
times 0x10000 - ($ - $$) db 0