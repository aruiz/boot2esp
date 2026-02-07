# Bootloader test plan

Sources and artifacts:

- **`hello.S`** – BLDR payload (prints "Hello, World!"); built as `BLDR` and placed on the FAT32 image.
- **`disk.img`** – Full disk: MBR + EFI partition + FAT32 + BLDR; used for `make run` and the success test.

Error-case test images and expected output:

| Image | Scenario | Expected |
|-------|----------|----------|
| `no-ef-partition.img` | No partition with type 0xEF (uses type 0x83 Linux) | E1 |
| `no-fat32.img` | 0xEF partition present but partition data is zeros (no FAT32 boot signature) | E2 |
| `no-bldr.img` | Valid FAT32 on 0xEF partition but no BLDR file in root | E3 |
| `disk.img` | Normal boot: EFI + FAT32 + BLDR | Hello, World! |

Run all tests from the project root:

```sh
make test
```

Tests use **expect** and QEMU **-display curses**: the harness spawns QEMU with a curses window (VGA text), waits up to 2 seconds for the bootloader to print the error code (INT 10h), and matches it against the expected E1/E2/E3. No serial output is required in the bootloader.

**PTY requirement:** Tests use expect + QEMU curses, so a PTY must be available. If `make test` fails with "The system has no more ptys" (e.g. inside a container or IDE):

- **From the host:** Run `make test` (or `make test-tty`) in a terminal on the host, not inside the container.
- **Force a PTY:** Run `make test-tty`, which runs the test under `script` so a PTY is allocated:  
  `make test-tty`
- **One-liner from host:**  
  `script -q -c "make test" /dev/null`
