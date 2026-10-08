# UPDATE 79 -- selector 0040h = BIOS data area: DOS/4GW's clock (2026-10-07)

Files: `_386.ASM` only, on top of UPDATE 78. `u79/_386.ASM` is 77 + 78 +
79, CRLF. `$386.SYS` 36,816 bytes, md5 `9dc2b362946b`. MASM 5.10, 0
warnings, 0 severe errors.

## Symptom

Under DOS/4GW, int 21h ah=2Ch (get time) returns the same garbage on
every call; `time()` stands still and `localtime()` lands days ahead
(`W4STEST ... started 20:33:15, 0 s`; `W4TIME`: `2Ch 236:33:15.99`,
date 10-16 on 10-07). 2Ah (get date) is right. DOS/32A and DJGPP are
right. **Present on UPDATE 74.**

## Cause (traced)

1. The INT/IRET log of one `int 21h ah=2Ch` from the client shows the
   host delivering it to DOS/4GW's hook (0173:0084), DOS/4GW's
   dispatcher (00DB:0C9E), and the IRET back -- **no real-mode int 21h,
   no raw switch, no trap**. CX/DX change inside DOS/4GW.
2. DOS/4GW's int 21h dispatcher jumps through a table at CS:066Ah
   indexed by (AH+1)*2. The 2Ch entry (CS:149Bh) computes the time
   itself:

   ```
   push 40h / pop es
   mov  bx,es:[6Eh]          ; BIOS tick count, high word
   ... es:[6Ch]              ; low word
   mul/div 0CFBh, 0EC54h, 3Ch, 025Dh  -> CH:CL:DH:DL
   ```

   It relies on the convention that selector **0040h** addresses the
   BIOS data area (base 400h), as Windows and HDPMI provide.
3. In this host, selector 0040h is `gdtzero3`, base **0**. DOS/4GW read
   linear 6Ch-6Fh (the IVT entry for int 1Bh) as the tick count: a
   constant, hence the frozen value, the same across boots.

The tick count itself is fine: linear 46Ch is live and equals int 1Ah
under both extenders (`wtick.c`).

## Change

| where | what |
| --- | --- |
| `gdtzero3` (selector 0040h, dpl 3) | base 0 -> **400h**; limit and attributes unchanged |
| `einfun82` (MOS int 21h 82h, get SCB address) | `sub eax,400h` after the linear address is built, before it goes into the client's ebx |

`einfun82` was the only user of `gdtzero3`: it returns `es:ebx` with
ES = 0043h and EBX = the linear address. With base 400h, EBX is now
linear - 400h, so `es:ebx` still points at the same byte. The SCB lies
far above 400h.

`sub eax,400h` is hand-encoded (`db 2Dh / dw 0400h,0`): in res16 a
16-bit `sub ax,imm16` would execute as a 32-bit op with a 2-byte
immediate, and `EAXI` is defined after this point (phase error).

## Encodings checked in the linked binary

| offset | bytes | meaning |
| --- | --- | --- |
| 18E0 | `FF FF 00 04 00 F2 4F 00` | descriptor 0040h: limit FFFFFh, base 400h, data r/w dpl 3 |
| 3617 | `03 C2` | add eax,edx (linear) |
| 3619 | `2D 00 04 00 00` | sub eax,400h |
| 361E | `89 43 14` | mov [ebx+ncavbx],eax |

## Tests (rig, `--testconfig`, dynamic core)

| test | result |
| --- | --- |
| W4TIME (DOS/4GW) | `2Ch 20:31:56.02` -> `20:31:58.05` 2 s later, date 2026-10-07 |
| WATIME (DOS/32A) | unchanged, correct |
| W4STEST | `churn bad 0, sort bad 0, 27 files, started 20:32:50, 23 s` |
| DPMI32 | `#GP count:0000 bytes 1/2/3:A1A200A3`, `32: done` |
| W4XTEST W4HELLO | rc 0, rc 0 |
| original `GO.BAT`, four tasks | all rc 0; STEST 0 bad x3 (task 2, DOS/4GW, now with a real start time); all DONE |

Not tested: a client calling MOS int 21h 82h from protected mode (no
such client in the test set).

## Side note

`einfun82` loads the segment from `ncavds` while its comment says ES.
Pre-existing; not changed here.

## Files

- `_386.ASM` -- UPDATE 78 + this change, CRLF.
- `wtime.c` -- time() vs raw 2Ch/2Ah, 2 s apart (Open Watcom; DOS/4GW
  and DOS/32A).
- `wtick.c` -- linear 46Ch vs int 1Ah, 2 s apart.
