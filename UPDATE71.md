## UPDATE 71 (2026-10-03) — default stubs out of conventional memory: +4 KB per task

The 4.2 KB of default stubs (`dpmistub`) no longer sit in res16, which
every task pays for in conventional memory. They are generated at run
time into two pages of extended memory. Maximum task size 580 -> 584
KB (task sizes come in 4 KB steps). `_386.ASM` only; full regression
clean.

### Change

- **`dpmistub` removed** (the `rept` data). `$386.SYS` 52,656 -> 48,640.
- **`e31stubs`**, on first use: two pages from **`stbget`** (new, res32:
  `adrpage`, `nalloc` with ecx = 2 -- as int 6Fh 7705h does, at PL0;
  a partial block goes back through `nrelease`). Banks are mapped at
  linear `(bank + 110h) << 12`, the same in every task; the pages are
  owned by no client and never freed. Linear in **`stublin`**. The
  stubs are generated there through the flat selector (`gdtzero`),
  layout unchanged:

| offset | content |
| --- | --- |
| `+000h` | 256 x `int E6h / N / iret` |
| `+400h` | `retf` (0305h pm routine); `+401h` `int E7h / nop` |
| `+404h` | 32 x `int E8h / N / nop` (default exception stubs) |
| `+484h`, `+488h` | `int E9h / nop / nop`, `int EAh / nop / nop` |
| `+48Ch`, `+A8Ch` | 256 x `int E6h / N / retf 2`, then `retf 4` |

- The two stub selectors get their base from `stublin` (32 bits);
  `einvst` reads N at `stublin` + IP. 0305h/0306h hand out those same
  selectors (in the kit's boots the 16-bit one happens to be `0073`).
- res16 reaches `stbget` through **`stbptr`** (`dw 0,0`), filled by
  `e6f8e` before every session start with `offset mmgrp:stbget`.
- **`einvst` clears eax** before loading N (see Found, 4).

### Found on the way (all fixed; all for the lessons)

1. A 16-bit immediate in res16 (`mov ax,gdtzero-gdt`): in the 32-bit
   segment `mov eax,imm32`, it swallowed the following `mov es,ax`;
   the generator wrote through the wrong es. Use `EAXI 0b8h,...`.
2. `MEMDEV` inside `e31stubs`: dovmint resets the monitor stack, and
   `e31stubs` is a nested call (six callers) -- its return address was
   gone; DOS/4GW hung before its banner. Hence `stbget` (PL0, no v-86).
3. `stbptr dd offset mmgrp:stbget` in res16: MASM A2057 -- a use16
   segment cannot hold a dword offset to a use32 label. Filled at run
   time instead. And `offset stbget` in res32 code is SEGMENT-relative
   (`1227h`); res16 calls through the group, where res32 starts at
   res16's length (now `9510h`): `offset mmgrp:stbget` (`A737h`). The
   wrong one jumped into res16 code: DOSBox "IRET: CS selector beyond
   limits". (`nca_ptr` works only because its target is in res16.)
4. **Latent: `e31desc` loads the function with `NLDW ncavax` (low 16
   bits) and tests all of eax (`or ax,ax` in the 32-bit segment).**
   `einvst` left `ncanip + stub base` in eax: below 10000h while the
   stubs were in res16, `001FABB4h` now -- DOS/4GW's 40th 0000h,
   chained through the default retf-4 stub, arrived as function
   `001F0000h` and failed (cf=1, ax=0); DOS/4GW exited silently.
   Found by differential trace (`W4HELLO`: identical to UPDATE 70 up
   to call 1549) and a monitor trace of exactly that call (new
   `PMTRACE_GATE_N`): `einvst -> einint31 -> e31desc -> e31dbad`.

### Measured

| | UPDATE 70 | UPDATE 71 |
| --- | --- | --- |
| `$386.SYS` | 52,656 | 48,640 |
| max task (`MAXTASK`) | 580 KB | **584 KB** |

`W4HELLO`'s 2,620 int 31h calls: the same sequence as UPDATE 70 (EIPs
from call 1961 on + 2000h: DOS/4GW loads above the two stub pages).

### Regression

- DPMI32 kit 19/19. Layout values moved DOWN by the 4 KB: sC/sD
  segments `20FC` -> `1FFC`, sB bx `7E03` -> `7F03`, sS rm->pm `7A00`.
- Four-task run (`GO.BAT`): every return rc 0; three STESTs 0 bad.
- FTEST `1BE00000`, TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
  (11/11/12 MB) on DJGPP, DOS/4GW, DOS/32A.
- `W4XTEST W4HELLO` (nested DOS/4GW): rc 0, rc 0.

### Build

| file | md5 |
| --- | --- |
| `_386.ASM` | `981e70c1d9c1568ab3f9044f0849e11d` |
| `$386.SYS` (48640) | `ba824a63de0f1bcfaa059d4e6eb76b47` |
| `rig/pmtrace-update71.patch` | on top of UPDATE 66's (`PMTRACE_GATE_AX`, `PMTRACE_GATE_N`) |

### Tracer: one call of many

`PMTRACE_GATE_AX=hex PMTRACE_GATE_N=n`: hook and step logging start at
the n-th int 31h with that ax. With `PMTRACE_HOOK_LO=0x100
PMTRACE_HOOK_HI=0xD000` (interpreter core: plain `boot.sh`, not
`CORE=dynamic`) it records the monitor's path through exactly that
call. Map addresses to routines from the listing: res16 offsets
directly, res32 + res16's length rounded to a paragraph (`9510h` now).

### Lessons

- No 16-bit immediates in res16 code (twice now -- `EAXI` for eax).
- `MEMDEV` only at a handler's top level, never in a called routine.
- use16 data cannot hold a use32 label's offset; a res32 label's
  group offset is `offset mmgrp:label`.
- Moving data to high linear addresses exposes code that tests eax
  after a 16-bit load: an assumption the old low address hid.

### To-do

1. The hook table (12 KB) out of conventional memory: ~41 accesses in
   18 routines change from `ss:[si+phooktab+N]` to a dedicated
   selector. Larger and riskier than the stubs; +12 KB per task.
2. Audit `NLDW` followed by 32-bit tests (the pattern of Found 4).
3. 0500h (free memory info) still probes with "valloc everything".
4. Per-client hook bitmap (fits with 1).
5. Fresh handover header summarising UPDATE 62-71.
