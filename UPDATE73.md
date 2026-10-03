## UPDATE 73 (2026-10-03) — hook table out of conventional memory: 596 KB tasks

The pm hook table (`phooktab`, 1,024 x 12 = 12 KB, mostly empty) left
res16, which every task pays for in conventional memory. With UPDATE
71's stubs, `$386.SYS` went from 52,656 (UPDATE 70) to **36,544** bytes
and the maximum task size from 580 to **596 KB** (UPDATE 61's driver,
before protected-mode support: 600 KB). `_386.ASM` only; full
regression clean.

### Change

- **GDT entry `gdthook`** (after `gdtpage`, before `gdtspace`): data,
  DPL 0, limit `DPHKN*12-1`, base set at run time. User selectors
  shift up by one entry (8).
- **`phooktab equ 0`**: the table is offset 0 in `gdthook`; all 37
  accesses keep their offsets, `ss:` became GS. Defined before the GDT
  (before any use).
- **`hookinit`** (res32, from `e6f8e` before every session start, once):
  three pages from `nalloc` (as `stbget`), zeroed through `gdtzero` (a
  free entry is 0; `nalloc` does not clear), base into `gdthook`, flag
  **`hookok`**. Allocation fails: `hookok` stays 0.
- **GS = `gdthook` inside the monitor**: loaded in `einative` right
  after it saved the client's es/ds/fs/gs to the nca (`einback` reloads
  them; GS is free in between). `dpmiclr`'s hook loop (res32, entered
  through int 6Fh, not `einative`) saves GS, loads it, restores it --
  and is skipped while `hookok` is 0, so a task that never ran a client
  cannot touch linear 0 through a base-0 GS.

**GS inside the monitor now belongs to the hook table.** New code that
loads GS for something else must restore it before any hook lookup.

### Pitfalls (MASM 5.1, res16)

1. **No `gs:` override in res16** (assembled for the 286, A2068): each
   access is `db 65h` plus the instruction without an override; with
   `phooktab` a constant MASM emits no segment prefix of its own.
2. **Phase error**: `EAXI` is defined after `einative` -- pass 1 did not
   know the macro there. Raw bytes (`db 0b8h / dw gdthook-gdt,0`).
   Also: an `equ` used before its definition changes encodings
   between passes; define it first.

### Measured

| | UPDATE 70 | UPDATE 71 | UPDATE 73 |
| --- | --- | --- | --- |
| `$386.SYS` | 52,656 | 48,640 | **36,544** |
| max task (`MAXTASK`) | 580 KB | 584 KB | **596 KB** |

### Regression

- DPMI32 kit 19/19. Layout: DOS memory 12 KB lower (sC/sD segments
  `1FFC` -> `1CFC`, sS rm->pm `7A04` -> `4A0C`); selectors +8 (sK, sN,
  sS: `0073` -> `007B`); 0501h blocks three pages higher (s2 linear
  `0020A000` -> `0020D000`, s3, s5, sB): the table's pages come first.
- Four-task run (`GO.BAT`): every return rc 0; three STESTs 0 bad.
- FTEST `1BE00000`, TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
  (11/11/12 MB) on DJGPP, DOS/4GW, DOS/32A.
- `W4XTEST W4HELLO` (2 x 288 hooks, nested): rc 0, rc 0.

### Build

| file | md5 |
| --- | --- |
| `_386.ASM` | `9e3315afa3d497c909f0e78b4dfe78dd` |
| `$386.SYS` (36544) | `88f9f0c2dc73fb2b592fcbedce91911d` |

### To-do

1. Per-client hook bitmap: ~30% less monitor work per int 31h (the
   remaining hook lookup).
2. Fresh handover header summarising UPDATE 62-73.
