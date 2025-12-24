; Hello World - loaded by bootloader at LOAD_SEG:0000
[BITS 16]
[ORG 0]

start:
    mov ax, cs
    mov ds, ax

    mov si, message
.print:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp .print

.done:
    cli
    hlt
    jmp .done

message: db "Hello, World!", 13, 10, 0
