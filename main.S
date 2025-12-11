; Partition Type Debug Bootloader + FAT32 File Reader
; Finds 0xEF partition, reads BLDR file from FAT32 root directory
; Assemble with: nasm -f bin -o debug_boot.bin debug_boot.asm

[BITS 16]
[ORG 0x7C00]

DAP_ADDR equ 0x0600

start:
    ; Setup segments
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    
    ; Save boot drive
    mov [boot_drive], dl
    
    ; Initialize DAP structure at 0x0600
    mov di, DAP_ADDR
    mov al, 0x10
    stosb
    xor al, al
    stosb
    mov ax, 1
    stosw
    xor ax, ax
    stosw
    stosw
    stosd
    stosd
    
    ; Scan partition table
    mov si, partition_table
    mov cx, 4
    
.scan_partitions:
    cmp byte [si + 4], 0xEF
    je .found_efi
    add si, 16
    loop .scan_partitions
    jmp halt
    
.found_efi:
    mov eax, [si + 8]
    mov [partition_lba], eax
    
    ; Read boot sector
    mov eax, [partition_lba]
    mov bx, 0x7E00
    call read_sector
    
    ; Parse FAT32
    mov ax, [0x7E00 + 0x0E]
    movzx eax, ax
    add eax, [partition_lba]
    mov [fat_start], eax
    
    movzx ecx, byte [0x7E00 + 0x10]
    movzx ebx, word [0x7E00 + 0x24]
    imul ebx, ecx
    add eax, ebx
    mov [data_start], eax
    
    mov eax, [0x7E00 + 0x2C]
    mov [root_cluster], eax
    movzx eax, byte [0x7E00 + 0x0D]
    mov [sectors_per_cluster], al
    
    ; Read root directory
    mov eax, [root_cluster]
    call cluster_to_lba
    mov bx, 0x7E00
    call read_sector
    
    ; Search for BLDR
    mov di, 0x7E00
    mov cx, 16
    
.search_file:
    mov al, [di]
    cmp al, 0
    je halt
    cmp al, 0xE5
    je .next_entry
    
    push di
    push cx
    mov si, filename
    mov cx, 11
    repe cmpsb
    pop cx
    pop di
    je .found_file
    
.next_entry:
    add di, 32
    loop .search_file
    jmp halt
    
.found_file:
    ; Get cluster
    mov ax, [di + 0x14]
    shl eax, 16
    mov ax, [di + 0x1A]
    mov [file_cluster], eax
    
    ; Get size
    mov eax, [di + 0x1C]
    mov [file_size], eax
    
    ; Load and print file contents
    mov eax, [file_cluster]
    call cluster_to_lba
    mov bx, 0x7E00
    call read_sector
    
    ; Print first 256 bytes as ASCII
    mov si, 0x7E00
    mov cx, 256
    cmp [file_size], ecx
    jae .print_loop
    mov cx, [file_size]
    
.print_loop:
    lodsb
    cmp al, 32                 ; Printable?
    jb .print_dot
    cmp al, 126
    ja .print_dot
    jmp .do_print
.print_dot:
    mov al, '.'
.do_print:
    mov ah, 0x0E
    int 0x10
    loop .print_loop
    
    call print_nl
    jmp halt

cluster_to_lba:
    sub eax, 2
    movzx ebx, byte [sectors_per_cluster]
    imul eax, ebx
    add eax, [data_start]
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
    jc halt
    popa
    ret

print_string:
    push ax
.loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp .loop
.done:
    pop ax
    ret

print_hex_dword:
    push eax
    shr eax, 16
    call print_hex_word
    pop eax
    call print_hex_word
    ret

print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    ; Fall through to print_hex_byte

print_hex_byte:
    push ax
    shr al, 4
    call print_hex_nibble
    pop ax
    push ax
    and al, 0x0F
    call print_hex_nibble
    pop ax
    ret

print_hex_nibble:
    cmp al, 9
    jle .digit
    add al, 'A' - 10
    jmp .print
.digit:
    add al, '0'
.print:
    push ax
    mov ah, 0x0E
    int 0x10
    pop ax
    ret

print_nl:
    push ax
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    pop ax
    ret

halt:
    cli
    hlt
    jmp halt

; Data
filename: db "BLDR       "

boot_drive: db 0
partition_lba: dd 0
fat_start: dd 0
data_start: dd 0
root_cluster: dd 0
file_cluster: dd 0
file_size: dd 0
sectors_per_cluster: db 0

times 446-($-$$) db 0

partition_table:
    times 64 db 0

dw 0xAA55