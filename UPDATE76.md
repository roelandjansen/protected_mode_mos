# UPDATE 76 -- int 31h fast path for the frequent functions (2026-10-07)

Files: `_386.ASM` only (on top of UPDATE 75). `$386.SYS` 36,800 bytes
(was 36,736), md5 `22d9b4882343`. MASM 5.10, 0 severe errors.

## Why

`einint31` dispatched through a linear compare chain: 24 instructions
to reach 0300h, 42 to reach 0400h, ~40 for 0900h-0902h. 0300h-0302h
(every DOS call an extender makes), 0501h-0503h (malloc/sbrk) and
0900h-0902h (virtual IF) are the calls made at run time; the rest of
the chain is mostly startup.

## Change

`einint31`: after the descriptor-range test (`ax < 0010h`), `jae` now
goes to a new block `e31nf0` placed just before `e31n00`:

| check | target |
| --- | --- |
| `ax = 0300h` | `e310300` |
| `ax = 0301h` or `0302h` | `e310301` |
| `0501h <= ax <= 0503h` | `e31save` |
| `0900h <= ax <= 0902h` | `e3190x` |
| anything else | falls into the unchanged chain at `e31n00` |

Targets and entry state (ax = function, ebx -> nca) are exactly what
the old chain used. A function outside the fast path pays ~10 extra
instructions (four compares); those are startup calls.

## Encodings checked in the linked binary

| offset | bytes | meaning |
| --- | --- | --- |
| 3AFE | `73 04` | jae e31nf0 (3B04) |
| 3B00 | `66 E9 32 14` | jmp e31desc (4F36) |
| 3B0A | `66 E9 48 1D` | jmp e310300 (5856) |
| 3B12 / 3B18 | `74 06` / `75 04` | 0301h -> 3B1A, else -> e31nf2 (3B1E) |
| 3B1A | `66 E9 20 1D` | jmp e310301 (583E) |
| 3B22 / 3B28 | `72 1A` / `77 04` | below 0501h -> e31n00 (3B3E); above 0503h -> e31nf3 (3B2E) |
| 3B2A | `66 E9 B4 0F` | jmp e31save (4AE2) |
| 3B32 / 3B38 | `72 0A` / `77 04` | outside 0900h-0902h -> e31n00 (3B3E) |
| 3B3A | `66 E9 51 20` | jmp e3190x (5B8F) |

RES16 now ends at 06592h.

## Measurement (gdb-gated hook, `hookprof.sh`, Q300)

| | UPDATE 74 | UPDATE 75 | UPDATE 76 |
| --- | --- | --- | --- |
| 0300h call, monitor instructions | 479 | 440 | **423** |
| dispatch (`EININT31`..chain) | 24 | 24 | 6 |

Two clean calls at 423; a third at 565 contains a timer IRQ.
Total since UPDATE 74: -56 per 0300h call (-12 %).

## Tests (rig, `--testconfig`, normal core)

| test | result |
| --- | --- |
| DPMI32 (s32) | pass: `#GP count:0000 bytes 1/2/3:A1A200A3`, all lines as UPDATE 74 |
| Q300 | `ax=0005` |
| Q900 (new) | `0902:1 0900:1 0902:0 0901:0 0902:1`, `0300 ax=0005 0501:0 0502:0 ok` |
| DJMTEST | `11 MB in 1 MB blocks, 0 bad, one 10 MB block ok` |
| DJFTEST | `262144 bytes, one-shot ok, chunked ok, sum 1BE00000` |
| DJXTEST DJXTEST DJHELLO | three deep, all rc 0 |

Q900 checks the 0900h-0902h semantics (previous state returned,
state changed) and runs 0300h, 0501h, 0502h in the same client.

## Not run here

- DOS/4GW, DOS/32A, the original `GO.BAT`, the 19 kit images (no Open
  Watcom, kit images not uploaded).
- Four-task GD.BAT: not rerun for 76. On 74 and 75 task 0 fails with
  `A:\DJXTEST.EXE: can't open` (setup, identical on both drivers).

## Rig note

xdotool `type` drops characters under load (`djmtet`, `clsdi32`). The
test driver now types one key at a time, compares the echoed command
line with what it typed, and only then presses Return.

## Files

- `_386.ASM` -- UPDATE 75 + this change, CRLF.
- `q900.c` -- 0900h-0902h test client (DJGPP).
