# Makefile for main boot sector

AS = as
LD = ld
OBJCOPY = objcopy

ASFLAGS = --32 -gstabs
LDFLAGS = -m elf_i386 -nostdlib -Ttext=0x7C00

all: main.bin BLDR

# Assemble to object file
#main.o: main.S
#	$(AS) $(ASFLAGS) -o $@ $<

# Link to ELF, then convert to flat binary
main.elf: main.S
	nasm -f elf -g -o $@ $<

main.bin: main.S
	nasm -f bin -g -o $@ $<

BLDR: hello.S
	nasm -f bin -o $@ $<

disk.img: main.bin disk.template BLDR
	rm -f disk.img
	fallocate -l 100M disk.img
	dd if=main.bin of=disk.img conv=notrunc
	sfdisk disk.img < disk.template
	fallocate -l 103809024 part.img
	mkfs.vfat -F 32 part.img
	mcopy -i part.img BLDR ::BLDR
	dd if=part.img of=disk.img seek=2048 bs=512 conv=notrunc
	rm part.img

clean:
	rm -f *.o *.elf *.bin BLDR

run: main.bin disk.img
	qemu-kvm -M q35 -drive file=disk.img,format=raw
