# UPDATE 80 -- host int 21h translation: DOS conventions for DTA and seek (2026-10-08)

Files: `_386.ASM` only, on top of UPDATE 79. `u80/_386.ASM` is 77-80,
CRLF. `$386.SYS` 37,056 bytes (was 36,816), md5 `f186e2e8d52c`. MASM
5.10, 0 warnings, 0 severe errors. RES16 ends at 06678h (was 065A0h),
RES32 at 07CA2h (was 07BBEh).

## Why

The host's own int 21h translation (`einfun39` .. `einfun5C`, used by a
client that issues int 21h straight from protected mode) followed TSL's
pre-DPMI native-mode API, not what translating DPMI hosts (Windows,
HDPMI) do (`INT21-CONVENTIONS.md`, UPDATE 79 folder):

| function | before (TSL) | now (DOS / Windows / HDPMI) |
| --- | --- | --- |
| 1Ah set DTA | not translated | the client's ds:(e)dx is kept as its DTA |
| 2Fh get DTA | not translated | es:ebx = that DTA (reflected if none was set) |
| 4Eh / 4Fh | DTA in **es:ebx** at every call | the DTA from 1Ah, else DOS's default PSP:80h |
| 42h seek | offset in **ecx**, result in **eax** | CX:DX in, DX:AX out (plain reflection) |

There are no native-mode programs left to keep the old API for.

## Change

- **Per-client DTA** in the hook segment (gs): a 5th page,
  `gs:[4000h + id*8]` = dd offset, dw selector, db set. `hookinit` takes
  5 pages (was 4) and zeroes them; `gdthook`'s limit is
  `DPHKN*12 + 2000h - 1`. `cidstart` clears the 8 bytes when it hands an
  id out (next to the bitmap clear), so a reused id starts with DOS's
  default DTA.
- **`einfun1a`**: stores ds:edx (edx zero-extended for a 16-bit client,
  `c32edc`); no reflection.
- **`einfun2f`**: es:ebx from the entry if set, else reflected.
- **`e4dst`** (near subroutine, before any `dovmint`, reads `entcid`):
  the DTA copy's destination into `ncauregs+00/+04` -- the client's DTA,
  or flat `cidpsp[id]*16 + 80h` -- and the client's edx into `+08`.
- **`einfun4e`**: name from ds:edx to `ncabufer+44`; real-mode DTA =
  `ncabufer` (1Ah); 4Eh; 44 bytes back to the destination; edx restored.
- **`einfun4f`**: 44 bytes (the search state) from the destination to
  `ncabufer`; 1Ah; 4Fh; back as 4Eh.
- **42h**: `eintable` entry -> `einstand`. The old `einfun42` is now
  unreferenced (left in place).
- **Dispatch**: `einlt39b` tests 1Ah and 2Fh before 1Ch.

Encodings checked in the linked binary (`einfun1a` 3400h, `einfun2f`
343Ah, `e4dst` 346Bh: 16-bit `gs:[si+4000h]` addressing via `67h 65h`,
`add eax,80h` as `05 80 00 00 00`; dispatch at 3A7Ah).

**Extended memory**: one more page before the first client. Linear
addresses in the kit values (s2, s3, s5, sB) move by 1000h, as in
UPDATE 74.

**Task size**: the resident part grows by 228 bytes (RES16 + RES32 end
07BBEh -> 07CA2h), still below the same 4 KB page boundary (8000h); the
maximum task size should stay 596 KB. **MAXTASK not run here.**

## Tests (rig, `--testconfig`, dynamic core)

| test | result |
| --- | --- |
| `pm21` (DOS conventions, 1Ah DTA) | 0 bad: 3Ch, 40h/3Fh 100,000 bytes, 42h seek end = 100,000 in DX:AX, 3Eh, 43h, 56h, 4Eh name in DTA, 4Fh none CF=1 AX=12h, 41h, 39h/3Bh/47h/3Ah, 5Ah |
| `pmfn` | one match: 4Fh CF=1 AX=12h; two matches: `FNB.TMP`, then CF=1 AX=12h |
| `pmdef` (no 1Ah) | result at PSP:80h |
| id reuse: `pmfn` (sets a DTA), then `pmdef` | `pmdef`'s result at its own PSP:80h |
| DPMI32 | `#GP count:0000 bytes 1/2/3:A1A200A3`, `32: done` |
| Q300 | `ax=0005` |
| original `GO.BAT` | all rc 0, STEST 0 bad x3, all DONE |
| W4TIME | 2Ch live and correct |
| nested DOS/4GW, nested DOS/32A | rc 0, rc 0 each |

Kernel check: find next straight to real-mode DOS (`fnext`, 0300h)
returns CF=1 AX=12h, as the host now does.

## Probe errors found on the way (not host bugs)

- `pm21` read its carry through a stack local addressed esp-relative
  *after* the asm pushed ebp -- 4 bytes off. Every carry it reported on
  UPDATE 79 was unreliable (the register findings stand). Fixed: the
  carry is static now.
- A 100,000-byte write that stopped at 63,376 bytes with CF=0: the test
  floppy was full (62,464 bytes free). Run probes that write on a
  floppy with room.

## Files

- `_386.ASM` -- UPDATE 79 + this change, CRLF.
- `pm21.c` -- the int 21h translation by DOS conventions (fixed carry).
- `pmfn.c` -- 1Ah/4Eh/4Fh, one and two matches.
- `pmdef.c` -- 4Eh without 1Ah: default DTA PSP:80h.
