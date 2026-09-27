## UPDATE 63 (2026-09-27) — first real extender: DJGPP runs

DJGPP (GCC 12.2 cross, `hello` and a 4 MB malloc test) runs on the
host: five runs in one boot, `DJMEM` checksum `1FE00000` (reference
computed on Linux), environment intact afterwards.

### Found (measured)

1. **ES after the switch was not a PSP selector** (DPMI 0.9 5.2): the
   stub came back with ES = DS = SS = `005B`; DJGPP's
   `stubinfo->psp_selector` then pointed at the stub's data.
2. **PSP:2Ch was not converted** to a selector. DJGPP's
   `setup_environment()` loads it as one: `#GP` on `mov ds,[ebp+8]` in
   `movedata()` (`008B:76A9`), chained by DJGPP to our default handler,
   which prints a misleading "Divide by zero error".
3. **`0201h` did `cli / mov [esi],eax / sti`**: the `sti` enabled
   interrupts inside the monitor at cpl 0 (int 31h enters with IF=0).
   IRQ 0 then hit host code (`0018:4C71`) and the emulator aborted with
   "IRET: CS selector beyond limits". Timing-dependent: with pmtrace on,
   the run got further and showed (2) instead. This was the very first
   DJHELLO failure.

### Change

- `_386.ASM`
  - int 6Fh 7793h `CLIENT_PSP` (`e6f93`, res32): PSP selector (limit
    FFh) and environment selector (limit from its MCB, `M`/`Z` size at
    +3; FFFFh otherwise), both data r/w dpl 3, byte-granular, 16-bit,
    tagged `80h|taskid`; environment selector written to PSP:2Ch;
    original kept in `envtab` (128 dwords, `env<<16 | PSP` by task id).
    Table full: cf set, PSP:2Ch unchanged. Helper `e93sel`.
  - `envr16` (res16), called in `einfun4c` after `freeclsel`: puts the
    segment back before the 4Ch is reflected -- DOS frees the
    environment through PSP:2Ch.
  - `envrest` (res32), called first in `dpmiclr`: the same for
    unregister and a dead predecessor.
  - `e310201`: `pushf / cli / mov / popf` instead of `cli / ... / sti`.
- `_DPMI.ASM` `GoProtect`: 7793h before the switch, PSP selector pushed
  and popped into ES after it (`db 66h / pop ax / mov es,ax`); refused
  switch: drop it and call `FREE_CLIENT_SEL` (restores PSP:2Ch);
  7793h failure: `gp_nopsp` puts the real-mode cs back.
- `_DPMI.INC`: `CLIENT_PSP equ 7793h`.
- `DPMI32.ASM`: `32e` / `32v` lines (below).

`$386.SYS` 32720 -> 33664, 0 warnings. `$DPMI.SYS` 5117 -> 5133, 4
warnings -- pre-existing (`scbmmsub` / `memman`, A4057), the unchanged
baseline gives the same 4. Binary checked against the listing at
`envr16` (`4556h`) and `4C6Dh` (`9C FA 89 06`).

### Measured

DPMI32, twice in one boot, then `set`:

	32e es base:0000BAA0 psp:0BAA0 lim:00FF
	32v env sel:0093 base:0000BA60 was:0BA60 fl:3296
	(second run: env sel 007B, same bases)
	COMSPEC=A:\COMMAND.COM

GDT read from the emulator (second run): `70h` PSP base `0BAA0` limit
`00FF`; `78h` environment base `0BA60` limit `002F`; both `F2`, g=0 d=0.

Regression, all eighteen: identical to UPDATE 62, except sS's rm->pm
offset (`3DB4` -> `3FB4`, larger `$386.SYS`) and sL's loop counter.

### Reference checksums

| file | size | md5 |
| --- | --- | --- |
| `$386.SYS` | 33664 | `b944ee2d112d4fd24bbf6c7fe0574db7` |
| `$DPMI.SYS` | 5133 | `070993942be14dbca2c059d6f4cafa5c` |
| `DPMI32.COM` | 1240 | `ffdd18363aa265eaa2bc12c8e94d0cee` |
| `_386.ASM` | | `c997e3001812ede6543efbe1546cb51e` |
| `_DPMI.ASM` | | `c52cd710cd4ecdbafba6ff72ec10e5b0` |
| `_DPMI.INC` | | `257e4cb379a82ff203fbcec87bfbe63b` |
| `DPMI32.ASM` | | `0c48eab30c4524a3e0290a755104b32b` |

### Lessons

- In a test client, `puthex` prints through `int 21h ah=02h` (dl):
  printing CX destroys DX. The first 32e/32v run showed wrong bases
  that were the test's, not the host's. Read the GDT from the emulator
  before believing a host bug.
- An abort that moves when pmtrace is on is a timing bug: look for
  interrupts enabled where they should not be.
- The container shell is dash: no `<(...)`, no `$'\t'`. Run edit
  scripts as `bash script.sh`.

### Limits / open

- A client that dies without 4Ch (int 20h, abort from an exception)
  leaves a selector in PSP:2Ch until `dpmiclr` at unregister or the next
  session; DOS may already have freed through it.
- `makegdte` reuses a descriptor with the same tag, access and base: a
  client selector for the PSP or environment segment would be shared and
  get the new limit.
- One DPMI session per task (`envtab`, `c32tab`), as before.

Next: DOS/4GW (Open Watcom), then DOS/32A.
