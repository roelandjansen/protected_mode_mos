# UPDATE 81 -- int 31h 0800h: physical address mapping (2026-10-08)

Files: `_386.ASM` only, on top of UPDATE 80. `u81/_386.ASM` is 77-81,
CRLF. `$386.SYS` 37,664 bytes (was 37,056), md5 `881cfa9196de`. MASM
5.10, 0 warnings, 0 severe errors. RES16 ends at 066BAh, RES32 at
07F08h (resident part still below 8000h). **MAXTASK: 596 KB**
(measured).

## Why

0800h is the one DPMI 0.9 function the host lacked: it fell through to
`e31bad` (CF set, nothing mapped). Programs use it to reach memory-
mapped hardware above 1 MB -- typically the VESA linear frame buffer
(DJGPP `__dpmi_physical_address_mapping`, graphics libraries, games).

## Design

- **Identity mapping**: linear = physical. Allowed only where the
  range's page-directory entries are all at or above `pt_pages`, i.e.
  outside the linear space the memory manager uses for RAM. A frame
  buffer (here C0000000h) is far above it.
- **Page tables** from `nalloc` (one bank each), zeroed, entered in the
  page directory. The page directory is the physical page below the page
  table, reached at `gdtpage` base - 1000h (the parspace maps extended
  memory contiguously); it is a single global directory (one CR3).
- `phytab`/`phylin` (16 slots) remember the PDE indices made here and
  their page tables' linear addresses: a later mapping in the same 4 MB,
  by any client, reuses the page table. A present PDE not in `phytab` is
  uninitialised directory memory and is overwritten.
- **PTEs**: present, writable, user, PCD + PWT (uncached), as for
  memory-mapped I/O. TLB flushed after the PDEs and after the PTEs.
- **Refused** (CF set): below 1 MB, size 0, a range that wraps past
  4 GB, overlap with RAM's linear space, `phytab` full, no memory for a
  page table.
- Mappings stay until reboot (DPMI 0.9 has no 0801h).

## Change

| where | what |
| --- | --- |
| `e31n99` | `0800h` -> `e310800` before the 0400h test |
| `e310800` (res16, after `e31bad`) | BX:CX, SI:DI -> eax, ecx; `call dword ss:[phyptr]`; BX:CX = linear, `e31dok`; refused -> `e31bad` |
| `phyptr` (res16 data, after `nlgptr`) | filled by `e6f8e` with `offset mmgrp:e31phys` |
| `e31phys`, `ephown`, `ephn0` (res32, before `stbget`) | the mapping; data `phypd`, `phyhwm`, `phytab`, `phylin` |

`ephn0: jmp ephno` sits before `e31phys`: MASM 5.1 encodes a `jcc` only
short, also in use32 code, and the entry checks are >127 bytes from
the exit. (First build: A2053, out of range by 202 bytes.)

Encodings checked in the linked binary: dispatch at 3CECh, `e310800`
at 3D3Dh (`mov ax,[ebx+ncavbx]` / `shl eax,16` / ... / `call
ss:[418Ch]`). MASM picked short `jmp`s behind the `66h` prefixes; with
the operand-size prefix a short jump only truncates EIP to 16 bits,
harmless below 10000h.

## Tests (rig, `--testconfig`, dynamic core)

`pmphys.c` (DJGPP): VBE 4F01h (mode 101h) for the frame buffer's
physical address, then 0800h.

| check | result |
| --- | --- |
| VBE frame buffer | C0000000h |
| 0800h, 4 MB | linear C0000000h |
| mapped bytes 0/1 = B800:0000 char/attr | `20 07` = `20 07` |
| 'Z' written through the mapping appears at B800:0000 | yes |
| write / read back at +3F0000h | yes |
| same range again | same linear |
| a range inside the same 4 MB | linear = physical (page table reused) |
| below 1 MB / size 0 / wrap / RAM's linear space | refused |
| PMPHYS again, as a new client | 0 bad (page table reused across clients) |

Regression: `pm21` 0 bad, DPMI32 (`#GP count:0000 bytes 1/2/3:A1A200A3`),
Q300, original `GO.BAT` (all rc 0, STEST 0 bad x3, all DONE), W4TIME,
nested DOS/4GW, nested DOS/32A.

## Files

- `_386.ASM` -- UPDATE 80 + this change, CRLF.
- `pmphys.c` -- 0800h probe.
