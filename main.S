; FAT32 Bootloader - Loads BLDR file from EFI partition
; Assemble with: nasm -f bin -o main.bin main.S
;
; Error codes (prints "E" + digit): E1=no EFI partition, E2=no FAT32,
; E3=no BLDR file, E4=no DAP support (BIOS), E5=read error.

[BITS 16]
[ORG 0x7C00]

DAP_ADDR equ 0x0600
LOAD_SEG equ 0x1000           ; Load file at 0x10000

start:
    ; Setup segments
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Save boot drive
    mov [boot_drive], dl

    ; Check INT 13h extended read (DAP) support
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .no_dap
    cmp bx, 0xAA55
    jne .no_dap

    ; Initialize DAP structure at 0x0600
    mov di, DAP_ADDR
    mov ax, 0x0010            ; AH=0 (reserved), AL=0x10 (size)
    stosw
    mov al, 1                 ; AH still 0, AX=1 (sector count)
    stosw
    xor ax, ax
    stosw
    stosw
    stosd
    stosd

    ; Scan partition table for EFI partition (type 0xEF)
    mov si, partition_table
    mov cx, 4

.scan_partitions:
    cmp byte [si + 4], 0xEF
    je .found_efi
    add si, 16
    loop .scan_partitions
    mov al, '1'              ; No EFI partition
    jmp die
.no_dap:
    mov al, '4'              ; No DAP support
    jmp die

.found_efi:
    ; Read FAT32 boot sector (si+8 = partition LBA)
    mov eax, [si + 8]
    mov bx, 0x7E00
    call read_sector

    ; Validate FAT32 boot sector signature
    cmp word [0x7E00 + 0x1FE], 0xAA55
    jne .no_fat32            ; E2 = No FAT32 filesystem

    ; Parse FAT32 BPB
    xor eax, eax
    mov ax, [0x7E00 + 0x0E]
    add eax, [si + 8]
    mov [fat_start], eax

    movzx ecx, byte [0x7E00 + 0x10]
    movzx ebx, word [0x7E00 + 0x24]
    imul ebx, ecx
    add eax, ebx
    mov [data_start], eax

    mov al, [0x7E00 + 0x0D]
    mov [sectors_per_cluster], al

    ; Read root directory
    mov eax, [0x7E00 + 0x2C]
    call cluster_to_lba
    mov bx, 0x7E00
    call read_sector

    ; Search for BLDR file
    mov di, 0x7E00
    mov cl, 16

.search_file:
    mov al, [di]
    cmp al, 0
    je .file_not_found
    cmp al, 0xE5
    je .next_entry

    push di
    push cx
    mov si, filename
    mov cl, 11
    repe cmpsb
    pop cx
    pop di
    je .found_file

.next_entry:
    add di, 32
    loop .search_file
.file_not_found:
    mov al, '3'              ; E3 = No BLDR file
    jmp die
.no_fat32:
    mov al, '2'              ; E2 = No FAT32 filesystem
    jmp die

.found_file:
    ; Get starting cluster
    mov ax, [di + 0x14]
    shl eax, 16
    mov ax, [di + 0x1A]
    mov [file_cluster], eax

    ; Setup load address ES:BX = LOAD_SEG:0000
    mov ax, LOAD_SEG
    mov es, ax
    xor bx, bx

.load_cluster:
    ; Convert current cluster to LBA
    mov eax, [file_cluster]
    call cluster_to_lba

    ; Read all sectors in this cluster
    movzx ecx, byte [sectors_per_cluster]
.read_sector_loop:
    push ecx
    push eax
    call read_sector
    pop eax
    pop ecx

    ; Advance LBA and buffer pointer
    inc eax
    add bx, 512
    jnc .no_wrap
    mov dx, es
    add dh, 0x10
    mov es, dx
    xor bx, bx
.no_wrap:
    loop .read_sector_loop

    ; Get next cluster from FAT
    call get_next_cluster
    mov [file_cluster], eax

    ; Check for end of chain
    cmp eax, 0x0FFFFFF8
    jb .load_cluster

    ; Jump to loaded code
    jmp LOAD_SEG:0x0000

cluster_to_lba:
    sub eax, 2
    movzx edx, byte [sectors_per_cluster]
    mul edx
    add eax, [data_start]
    ret

get_next_cluster:
    push es
    mov eax, [file_cluster]
    shl eax, 2
    push ax
    shr eax, 9
    add eax, [fat_start]
    push ds
    pop es
    mov bx, 0x7E00
    call read_sector
    pop bx
    and bh, 1
    mov eax, [0x7E00 + bx]
    and eax, 0x0FFFFFFF
    pop es
    ret

read_sector:
    pusha
    mov [DAP_ADDR + 8], eax
    mov [DAP_ADDR + 4], bx
    mov [DAP_ADDR + 6], es
    mov si, DAP_ADDR
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc .disk_error
    popa
    ret
.disk_error:
    mov al, '5'              ; E5 = Read error (DAP failed)

die:
    mov ah, 0x0E
    push ax
    mov al, 'E'
    int 0x10
    pop ax
    int 0x10

halt:
    cli
    hlt
    jmp halt

; Data
filename: db "BLDR       "

boot_drive: db 0
fat_start: dd 0
data_start: dd 0
file_cluster: dd 0
sectors_per_cluster: db 0

times 446-($-$$) db 0

partition_table:
    times 64 db 0

dw 0xAA55
