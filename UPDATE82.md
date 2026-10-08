# UPDATE 82 -- 16-bit clients' int 21h, 5Ch by DOS conventions, int 38h 02h/04h, tidy-up (2026-10-08)

Files: `_386.ASM` only, on top of UPDATE 81. `u82/_386.ASM` is 77-82,
CRLF. `$386.SYS` 37,584 bytes (was 37,664: dead code removed), md5
`22081d7ac5ca`. MASM 5.10, 0 warnings, 0 severe errors. RES16 ends at
0666Ah, RES32 at 07EB0h. **MAXTASK: 596 KB** (measured).

## 1. A 16-bit client's int 21h (crash fix)

The int 21h translators take pointers and counts from the 32-bit
register slots: 3Fh/40h (ECX bytes at DS:EDX), 39h-3Dh, 41h, 43h, 4Eh,
56h, 5Ah (DS:EDX, ES:EDI), 47h (DS:ESI). Only 09h, 0Ah and 1Ah
zero-extended for a 16-bit client. A 16-bit client with junk in a high
word -- normal for 16-bit code that uses 386 instructions -- made the
host copy from far beyond the client's segment.

**Measured on UPDATE 81** with `HI16.COM` (a 16-bit client, EDX/ECX =
0BADxxxxh): DOSBox aborts, `IRET: CS selector beyond limits` -- on
hardware the monitor takes a fault on its own return path: the whole
machine, not just the client.

**Fix**, once at the int 21h dispatch (`e31skip`, after `cmp dl,21h`):
for a 16-bit client (`c32edc`, `entcid` still valid) clear the high
words of the CX, DX, SI, DI slots before any translator runs. A
reflected call already returned these slots with the v-86 side's high
words, so nothing a 16-bit client could rely on is lost.

## 2. 5Ch lock/unlock by DOS conventions

Like 42h before UPDATE 80, `einfun5c` used TSL's native API: offset in
ECX, length in EDX, converted to CX:DX / SI:DI. DOS (and Windows/HDPMI)
take CX:DX = offset, SI:DI = length. Now a plain reflection
(`eintable` -> `einstand`); `einfun5c` removed.

## 3. Int 38h/D4h 02h (SCB) and 04h (TCB) from protected mode

`einfun82` (both functions) took the segment from `ncavds` -- the
caller's DS -- although the kernel returns ES (`mosext02`: ES:BX ->
SCB; `mosext04`: ES -> TCB, BX is its *input*, the task id), and
computed ES*16 + BX for both. Now: the function is saved before the
call; ES; offset BX for 02h, 0 for 04h; untouched on an error (CF).
Result still ES = 0043h, EBX = linear - 400h (UPDATE 79).

## 4. Tidy-up

- `e93sel` asks `makegdte` for access `F3h` directly (was `F2h`, patched
  to `F3h` afterwards, UPDATE 78). `makegdte` now reuses only an `F3h`
  entry of the same tag and base -- a previous PSP/environment
  descriptor -- so the UPDATE 78 corner case (reusing and re-limiting a
  plain `F2h` data descriptor) is gone.
- `einfun42` (unreferenced since UPDATE 80) and `einfun5c` removed.

## 5. 0B00h-0B03h (debug watchpoints): no change

They fall through to `e31bad` (CF set). For 0B00h that is DPMI 0.9's
"no watchpoint available"; the others then see an invalid handle. Real
watchpoints would need DR0-DR7 saved and restored at every PC-MOS task
switch, and DOSBox does not emulate hardware watchpoints (untestable
here). `pmwatch.c`: all four return failure, the client continues.

## Encodings checked in the linked binary

| offset | bytes | meaning |
| --- | --- | --- |
| 39D7 | `52` / `66 E8 ..` / `F7 C2 00 00 40 00` / `5A` / `75 18` | push edx, call c32edc, test, pop edx, jnz |
| 39E5 | `66 C7 43 1A 00 00` ... `0E`, `0A`, `06` | clear high words of cx, dx, si, di |
| 363E | `8A 43 11` / `89 43 4C` | einfun82: save the function |
| 364A | `F6 43 00 01` / `75 25` | CF set -> untouched |
| 3652 | `66 8B 53 1C` | ES (`ncaves`), was DS |
| 365B | `80 7B 4C 04` / `74 04` | 04h: offset 0 |

## Tests (rig, `--testconfig`, dynamic core)

| test | UPDATE 81 | UPDATE 82 |
| --- | --- | --- |
| `HI16.COM` (16-bit, junk high words): create, write 5, read back, delete | emulator aborts | OK |
| `pm38`: 5Ch lock/unlock/unlock again/other length/right length | 2 BAD | all OK (unlock again: CF=1, AX=21h) |
| `pm38`: int 38h 02h vs real mode | BAD (0043:00000970) | same SCB |
| `pm38`: int 38h 04h vs real mode | BAD | same TCB |
| `pmwatch`: 0B00h-0B03h | | all refused, client continues |

Regression on 82: `pm21` 0 bad, `pmdef`, `pmphys` 0 bad, DPMI32
(`#GP count:0000 bytes 1/2/3:A1A200A3`), Q300, MAXTASK 596 KB, original
`GO.BAT` (all rc 0, STEST 0 bad x3, all DONE), W4TIME, nested DOS/4GW,
nested DOS/32A.

## Files

- `_386.ASM` -- UPDATE 81 + this change, CRLF.
- `HI16.ASM` -- 16-bit DPMI client test (`combuild.sh HI16`).
- `pm38.c` -- 5Ch and int 38h 02h/04h against real mode.
- `pmwatch.c` -- 0B00h-0B03h refusal.
