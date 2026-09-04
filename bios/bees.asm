; Creating my own BIOS, or in Esperanto, my own BEES

; Assemble for 16-bit real mode
bits 16

; Addresses are calculated relative to file start
org 0x0000

start:
    ; Disable interrupts: no Interrupt Descriptor Table is set up yet,
    ; so an interrupt firing now would jump to garbage and crash the CPU
    ;
    ; In real mode, every interrupt (hardware or software) looks up its handler address
    ; in a table called the IVT (Interrupt Vector Table), normally located at 0x0000:0x0000.
    ; Since this BIOS just started, that table isn't initialized with valid values yet.
    cli

    xor ax, ax ; Set ax = 0
    mov ds, ax ; Data Segment = 0
    mov es, ax ; Extra Segment = 0
    mov ss, ax ; Stack Segment = 0
    mov sp, 0x7C00 ; Stack Pointer, grows downward from 0x7C00

    call setup_ivt
    call load_bootloader
    ; jump to the bootloader we just loaded, remember it started at 0x7C00
    jmp 0x0000:0x7C00 ; address = 0x0000 * 16 + 0x7C00 = 0x7C00

; ==============================================================================
; setup_ivt
;
; Configure the Interrupt Vector Table (IVT) at 0x0000:0x0000
; Each interrupt entry = 4 bytes (offset + segment).
; INT 0x00 entry is at memory address 0x0000:0x0000
; We make it point to our custom print handler.
; ==============================================================================
setup_ivt:
    mov ax, 0
    mov ds, ax

    ; INT 0x00 vector: pointer to our print handler
    ; Handler will be placed at 0x0000:0x0500 (after IVT + BIOS data area)
    ;
    ; IVT: 0x0000:0x0000 - 0x0000:0x03FF (1024 bytes) --> 256 interrupts + 4 = 1024 bytes
    ; BDA (BIOS Data Area): 0x0000:0x0400 - 0x0000:0x04FF (256 bytes)
    ; 0x0000:0x0500 upfront is free for applications

    ; When CPU executes "int 0x00", then CPU computes:
    ;   direction IVT = 0x00 + 4 = 0x0000
    mov word [0x0000], 0x0500 ; offset of handler
    mov word [0x0002], 0xF000 ; segment: handler lives in the BIOS ROM itself,
                               ; which QEMU maps at segment 0xF000.
                               ; It is never copied down to RAM, so the IVT
                               ; must point at 0xF000:0x0500, not 0x0000:0x0500.

    ret

; ==============================================================================
; load_bootloader
;
; Reads sector 0 (LBA 0) from the primary IDE hard disk using PIO mode.
; Places the 512 bytes at memory address 0x7C00 (standard bootloader location).
;
; This function communicates directly with the IDE (ATA) disk controller via
; I/O port writes and reads. No BIOS interrupts are used because this code
; IS the BIOS - interrupts don't exist yet.
;
; IDE/ATA Architecture:
; - The primary IDE controller is mapped to I/O ports 0x1F0-0x1F7
; - Secondary IDE controller would be at 0x170-0x177
; - Each controller can have 2 drives: master and slave
; - We're reading from the master drive of the primary controller
;
; ATA/IDE Communication Protocol (Simplified):
; 1. Check if drive is not busy (BSY bit)
; 2. Write parameters to control/status registers (sector, drive, mode)
; 3. Send a command (READ SECTORS = 0x20)
; 4. Wait for DRQ bit (data ready)
; 5. Read data from the data port (16 bit at a time)
; ==============================================================================
load_bootloader:
    ; ==============================================================================
    ; STEP 1: Check if drive is ready
    ; ==============================================================================
    ; Before we can issue any command to the drive, we must wait until it's not busy.
    ; The drive might be doing internal housekeeping from power-on, or might still be
    ; recovering from the last command. 
    ; This is defined in ATA spec section 5.2: "Status Register"
    call wait_bsy_clear

    ; ==============================================================================
    ; STEP 2: Select drive and set addressing mode (LBA vs CHS)
    ; ==============================================================================
    ; Port 0x1F6: Device/Head Register
    ; This register tells the drive which drive to use (master/slave) and which
    ; addressing mode (CHS = Cylinder/Head/Sector or LBA = Logical Block Address)
    ;
    ; Register layout (from ATA specification, section 7.15):
    ;   Bit 7: = 1 (always)
    ;   Bit 6: L (LBA mode: 1 = LBA, 0 = CHS)
    ;   Bit 5: 1 (always, for compatibility)
    ;   Bit 4: DRV (0 = master, 1 = slave)
    ;   Bits 3-0: for LBA mode, these are bits 24-27 of the LBA address
    ;
    ; We use: 1110_0000 = 0xE0
    ;   - Bit 7 = 1 (required)
    ;   - Bit 6 = 1 (LBA mode enabled)
    ;   - Bit 5 = 1 (required)
    ;   - Bit 4 = 0 (master drive)
    ;   - Bits 3-0 = 0000 (LBA bits 24-27 = 0, since we're reading LBA 0)

    mov dx, 0x1F6 ; Device/Head register
    mov al, 0xE0 ; 1110_0000 = LBA mode, master drive
    out dx, al

    ; After selecting the drive, it may take a moment to respond,
    ; so we wait again before issuing the next commands
    call wait_bsy_clear

    ; ==============================================================================
    ; STEP 3: Set how many sectors to read
    ; ==============================================================================
    ; Port 0x1F2: Sector Count Register
    ; Specifies how many sectors (each = 512 bytes) to read in this operation.
    ; Valid range: 1-255. We're reading only 1 sector (the bootloader).
    ; ATA spec section 7.11

    mov dx, 0x1F2 ; Sector Count register
    mov al, 1 ; Read 1 sector = 512 bytes
    out dx, al

    ; ==============================================================================
    ; STEP 4: Set the LBA (Logical Block Address)
    ; ==============================================================================
    ; The LBA is a 28-bit address (in LBA28 mode) that uniquely identifies a sector
    ; on the disk. It's divided across three 8-bit registers:
    ;   - Port 0x1F3: LBA bits 0-7 (low byte)
    ;   - Port 0x1F4: LBA bits 8-15 (middle byte)
    ;   - Port 0x1F5: LBA bits 16-23 (high byte)
    ;   - Port 0x1F6 bits 3-0: LBA bits 24-27 (already set above to 0)
    ;
    ; LBA 0 = the very first sector of the disk (boot sector)
    ; Binary: 0000_0000_0000_0000_0000_0000_0000_0000
    ; So we write 0 to all three registers.
    ; ATA spec section 7.8, 7.9, 7.10

    mov dx, 0x1F3 ; LBA bits 0-7
    mov al, 0
    out dx, al

    mov dx, 0x1F4 ; LBA bits 8-15
    mov al, 0
    out dx, al

    mov dx, 0x1F5 ; LBA bits 16-23
    mov al, 0
    out dx, al

    ; ==============================================================================
    ; STEP 5: Issue the READ SECTORS command
    ; ==============================================================================
    ; Port 0x1F7: Command Register (when writing)
    ; Commands are single-byte codes that tell the drive what operation to perform.
    ; 0x20 = READ SECTORS (PIO mode)
    ; Other common commands: 0x30 = WRITE SECTORS, 0xEC = IDENTIFY SEVICE, etc.
    ;
    ; After we write the command, the drive begins executing:
    ;   - It seeks the read head to the correct position
    ;   - It waits for the correct data to rotate under the head
    ;   - It reads the sector data from the disk
    ;   - It fills its internal buffer with those 512 bytes
    ;   - It signals that data is ready (DRQ bit) so we can read it
    ; ATA spec section 8.20

    mov dx, 0x1F7 ; Command Register
    mov al, 0x20 ; READ SECTORS command
    out dx, al ; Issue the command to the drive

    ; After issuing the command, the drive is busy (BSY bit set).
    ; We wait until it's done reading the sector from disk and has
    ; the adata ready in its buffer (BSY will be clear).
    call wait_bsy_clear

    ; ==============================================================================
    ; STEP 6: Wait for DRQ (Data Request) - the drive signals data is ready
    ; ==============================================================================
    ; Port 0x1F7: Status Register (when reading, same port as Command)
    ; After the drive reads the sector, it sets the DRQ bit (bit 3) to signal:
    ; "I have data in my buffer, come and read it from port 0x1F0"
    ;
    ; Status register bits (ATA spec section 7.16):
    ;   Bit 7: BSY (busy) = 1 means drive is executing a command
    ;   Bit 6: DRDY (drive ready) = 1 means drive is ready for commands
    ;   Bit 5: DF (device fault) = 1 means an error ocurred
    ;   Bit 4: DSC (seek complete) = 1 means seek operation completed
    ;   Bit 3: DRQ (data request) = 1 means data is ready to transfer
    ;   Bit 2: CORR (corrected data) = 1 if soft error was corrected
    ;   Bit 1: IDX (index) = normally 0
    ;   Bit 0: ERR (error) = 1 if command failed
    ;
    ; We poll (repeatedly check) this register until DRQ is set.
    ; This is necessary because the drive's performance is unpredictable: reading from disk takes variable
    ; time dependending on disk speed and current head position. Polling avoids assumptions about timing.

.wait_ready:
    in al, dx ; Read status from 0x1FT (dx still = 0x1F7)
    ; test: sets zero flag if (al AND 0x08) == 0
    test al, 0x08 ; Check bit 3 (DRQ), remember 0x08 == 0000_1000
    jz .wait_ready ; If zero flag is set, DRQ is 0, so loop again

    ; If we reach here, DRQ is 1, meaning 512 bytes of sector data are
    ; waiting in the drive's buffer to be read.

    ; ==============================================================================
    ; STEP 7: Read the 512-byte sector into memory at 0x7C00
    ; ==============================================================================
    ; Port 0x1F0: Data Register
    ; This is the only port where we actually read the disk's data.
    ; Each read returns 16 bit (1 word), not 8 bits.
    ; So a 512-byte sector = 256 words = 256 reads from this port.
    ;
    ; Memory location 0x7C00:
    ; This is the conventional location where the BIOS loads the bootloader.
    ; Defined by IBM PC BIOS standard, still used by x86 systems today.
    ; At 0x7C00, there's 512 bytes of free space before interrupts or other
    ; critical data, so it's a safe place for boot code.

    mov dx, 0x1F0 ; Data port
    mov di, 0x7C00 ; Destination address (bootloader location)
    mov cx, 256 ; Counter: read 256 words (= 512 bytes)

.read_word:
    ; Loop: read one 16-bit word at a time and store it
    
    ; Read one word (16 bit) from the data port into register ax
    in ax, dx
    ; Store Word: writes ax to [es:di], then increments di by 2.
    ; Since es = 0, this writes to linear address [di].
    ; So first iteration: ax --> [0x7C00]
    ;   second iteration: ax --> [0x7C02]
    ;   third iteration: ax --> [0x7C04], etc.
    stosw
    ; Loop function decrements cx, and verifies if cx != 0, then jump back to .read_word
    ; So this loop repeats 256 times total.
    loop .read_word

    ; After the loop, we've read all 512 bytes of sector 0 into memory
    ; starting at 0x7C00. The bootloader is now in RAM and ready to execute.
    ret ; Return to caller (start function)

; =========================================================================
; wait_bsy_clear
;
; Polling subroutine: repeatedly reads the status register (0x1F7) until
; the BSY bit (bit 7) is 0. When BSY = 0, the drive is not processing
; and is ready to accept a new command or is done with re current one.
;
; This function is essential for synchronization with the drive. Without it,
; we might send a command while the drive is still busy, which causes errors.
;
; Polling vs Interrupts:
; - Interrupts: drive rises an IRQ when ready (would require IDT setup)
; - Polling: we keep checking status ourselves (simpler for bootcode, used
;   by BIOS and some drivers)
;
; ATA spec section 7.16: Status Register
; =========================================================================
wait_bsy_clear:
    mov dx, 0x1F7 ; Status register address

.poll:
    in al, dx ; Read status byte from port 0x1F7 into al
    test al, 0x80 ; Check bit 7 (BSY), remember 0x80 = 0100_0000
    ; If BSY bit is set (result != 0), loop again
    jnz .poll ; jnz = "jump if not zero"

    ; If we get here, BSY is 0, so the drive is not busy and ready
    ret

; Fill to offset 0x0500 where out handler starts
times 0x0500 - ($ - $$) db 0

; =========================================================================
; int_print_handler
;
; Custom interrupt handler at 0x0000:0x0500
; Called from bootloader with: int 0x00
; Params:
;   - ah = 0x0E (teletype print mode)
;   - al = character to print
;   - bh = page number (we ignore this, always use page 0)
; =========================================================================
int_print_handler:
    ; Save registers
    push ax
    push bx
    push di
    push ds
    push es

    ; Check if this is a print request (AH = 0x0E)
    cmp ah, 0x0E
    jne .not_implemented

    ; =========================================================================
    ; Print character to VGA memory
    ; VGA text mode: memory at 0xB8000
    ; Each character = 2 bytes (char + attribute)
    ;
    ; The BIOS ROM is read-only, so the cursor position can't live next to this
    ; code - it's kept as a word in RAM, in the (otherwise unused by this BIOS)
    ; BIOS Data Area, so it survives between calls to this handler.
    ; =========================================================================

    xor bx, bx
    mov ds, bx ; ds = 0, so we can read/write the cursor variable below

    mov bx, 0xB800 ; VGA memory segment (0xB800 >> 4)
    mov es, bx

    ; al already contains the character
    mov ah, 0x07 ; white text on black background
    ; [es:di] = physical address 0xB8000 + di
    stosw ; write character + attribute to VGA, di += 2

.not_implemented:
    ; Restore registers
    pop es
    pop ds
    pop di
    pop bx
    pop ax

    ; Return from interrupt (restore IP and flags from stack)
    iret

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