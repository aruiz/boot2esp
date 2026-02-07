# Makefile for main boot sector

AS = as
LD = ld
OBJCOPY = objcopy

ASFLAGS = --32 -gstabs
LDFLAGS = -m elf_i386 -nostdlib -Ttext=0x7C00

all: main.bin

# Assemble to object file
#main.o: main.S
#	$(AS) $(ASFLAGS) -o $@ $<

# Link to ELF, then convert to flat binary
main.elf: main.S
	nasm -f elf -g -o $@ $<

main.bin: main.S
	nasm -f bin -g -o $@ $<

# BLDR payload and full disk image (in tests/)
tests/BLDR: tests/hello.S
	@mkdir -p tests
	nasm -f bin -o $@ $<

tests/disk.img: main.bin disk.template tests/BLDR
	@mkdir -p tests
	rm -f $@
	fallocate -l 100M $@
	dd if=main.bin of=$@ conv=notrunc bs=512
	sfdisk $@ < disk.template
	fallocate -l 103809024 tests/part.img
	mkfs.vfat -F 32 tests/part.img
	mcopy -i tests/part.img tests/BLDR ::BLDR
	dd if=tests/part.img of=$@ seek=2048 bs=512 conv=notrunc
	rm -f tests/part.img

# Test disk images (use main.bin; tests use expect + curses to capture VGA output)
PART_SIZE := 103809024
PART_SECTORS := 202752

tests/no-ef-partition.img: main.bin tests/disk-no-ef.template
	@mkdir -p tests
	rm -f $@
	fallocate -l 100M $@
	dd if=main.bin of=$@ conv=notrunc bs=512
	sfdisk $@ < tests/disk-no-ef.template

tests/no-fat32.img: main.bin disk.template
	@mkdir -p tests
	rm -f $@
	fallocate -l 100M $@
	dd if=main.bin of=$@ conv=notrunc bs=512
	sfdisk $@ < disk.template
	dd if=/dev/zero of=$@ seek=2048 bs=512 count=$(PART_SECTORS) conv=notrunc

tests/no-bldr.img: main.bin disk.template
	@mkdir -p tests
	rm -f $@
	fallocate -l 100M $@
	dd if=main.bin of=$@ conv=notrunc bs=512
	sfdisk $@ < disk.template
	fallocate -l $(PART_SIZE) tests/part.img
	mkfs.vfat -F 32 tests/part.img
	dd if=tests/part.img of=$@ seek=2048 bs=512 conv=notrunc
	rm -f tests/part.img

TEST_DISKS := tests/no-ef-partition.img tests/no-fat32.img tests/no-bldr.img tests/disk.img
TEST_EXPECT := tests/no-ef-partition.img:E1 tests/no-fat32.img:E2 tests/no-bldr.img:E3

test: $(TEST_DISKS)
	@failed=0; \
	for spec in $(TEST_EXPECT); do \
	  disk="$${spec%%:*}"; exp="$${spec##*:}"; \
	  echo "  TEST $$disk (expect $$exp)"; \
	  if expect tests/run_test.exp "$$disk" "$$exp"; then \
	    echo "  PASS $$exp"; \
	  else \
	    failed=$$((failed+1)); \
	  fi; \
	done; \
	echo "  TEST tests/disk.img (expect Hello, World!)"; \
	if expect tests/run_hello_test.exp tests/disk.img; then \
	  echo "  PASS Hello, World!"; \
	else \
	  failed=$$((failed+1)); \
	fi; \
	[ $$failed -eq 0 ] && echo "All tests passed." || { echo "$$failed test(s) failed."; exit 1; }

# Run tests inside a PTY (e.g. from host terminal or: script -q -c "make test")
# Use this when "make test" fails with "no more ptys" (e.g. inside containers)
test-tty: $(TEST_DISKS)
	@script -q -c "$(MAKE) test" /dev/null

clean:
	rm -f *.o *.elf *.bin
	rm -f tests/BLDR tests/part.img
	rm -f tests/no-ef-partition.img tests/no-fat32.img tests/no-bldr.img tests/disk.img

run: main.bin tests/disk.img
	qemu-kvm -M q35 -drive file=tests/disk.img,format=raw
