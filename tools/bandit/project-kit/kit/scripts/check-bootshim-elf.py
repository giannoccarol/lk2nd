#!/usr/bin/env python3
"""Ripete i controlli di BootShim elf-loader-pre3 (src/EFIApp.c) su un emmc_appsboot.mbn.

BootShim accetta solo: ELF32, ARM, ET_EXEC, almeno un program header, e usa il
primo PT_LOAD con p_paddr == p_vaddr == e_entry. Copia p_filesz byte a p_paddr
(AllocatePages a indirizzo fisso) e salta a e_entry.
"""
import struct, sys

def check(path):
    data = open(path, "rb").read()
    ok = True
    def fail(msg):
        nonlocal ok
        ok = False
        print("  ERRORE:", msg)
    if data[:4] != b"\x7fELF":
        fail("magic ELF assente (file MBN piatto?)"); return False
    if data[4] != 1: fail("non ELF32")
    e_type, e_machine = struct.unpack_from("<HH", data, 16)
    e_entry, e_phoff = struct.unpack_from("<II", data, 24)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 42)
    if e_machine != 40: fail(f"e_machine {e_machine} != EM_ARM")
    if e_type != 2: fail(f"e_type {e_type} != ET_EXEC")
    if e_entry == 0: fail("entry point 0")
    if e_phnum < 1: fail("nessun program header")
    print(f"  entry 0x{e_entry:08x}, {e_phnum} program header")
    found = None
    for i in range(e_phnum):
        p_type, p_off, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
            struct.unpack_from("<8I", data, e_phoff + i * e_phentsize)
        print(f"  PH{i}: type {p_type} off 0x{p_off:x} vaddr 0x{p_vaddr:08x} paddr 0x{p_paddr:08x} filesz 0x{p_filesz:x} memsz 0x{p_memsz:x}")
        if p_type == 1 and p_paddr == p_vaddr and p_paddr == e_entry and found is None:
            found = (p_off, p_paddr, p_filesz, p_memsz)
    if not found:
        fail("nessun PT_LOAD con paddr == vaddr == entry")
    else:
        off, paddr, filesz, memsz = found
        if off + filesz > len(data): fail("segmento oltre la fine del file")
        if memsz > filesz:
            print(f"  NOTA: BootShim copia solo filesz; 0x{memsz - filesz:x} byte di .bss non azzerati da BootShim (LK li azzera da sé)")
        print(f"  carico a 0x{paddr:08x}-0x{paddr + memsz:08x}")
    return ok

if __name__ == "__main__":
    rc = 0
    for p in sys.argv[1:]:
        print(p)
        if check(p): print("  OK per BootShim")
        else: rc = 1
    sys.exit(rc)
