# SHRINK phase 0 -- the "mos is full" limit (20261010, in progress)

UPDATE 91 found that 24 bytes added to `mos` (in `MOSTEMP.ASM`) made
`swa >outa.txt` hang. This note records what that limit turned out to
be. No source change; the tree is back on the UPDATE 91 kernel (md5
`5dbab76c6434`).

## How mos is loaded

- `mos` runs at `FFF8:xxxx` (HMA), from offset 1080h. The first 1080h
  bytes of the segment are not loaded (`sub 108h` in `initp5`).
- What stays resident is 1080h up to `CLOBBER` (0F75Ah). Everything
  after `CLOBBER` is init code that is overwritten after boot. That is
  the 2 KB between 0F75Ah and `MOSEND` 0FFC6h.
- `MOS INFO`, segment #2: 101000h-10F700h (linear). Physical memory
  starts at 100000h ($386 maps linear 101000h to physical 100000h).
- Room up to the end of the HMA (10FFF0h): about **2.3 KB**. The
  64 KB segment limit is not the real constraint.

## Experiments (24 bytes of padding, redirect test `swa >outa.txt`)

| padding at | resident end | result |
| --- | --- | --- |
| after `CLOBBER` (init part) | unchanged | ok |
| just before `CLOBBER` | +24 | **ok** |
| in `MOSTEMP` (mosint2f), 8 / 16 bytes | +8 / +16 | ok |
| in `MOSTEMP`, 18 / 20 / 24 bytes | +18..24 | hang |
| end of `MOSINT10` | +24 | hang |
| end of `MOSINT16`, `MOSDDTMC`, `MOSFUTL2` | +24 | ok |
| `MOSINT16` before line 3070 (before `shfttbl`) | +24 | hang |
| `MOSINT16` before line 3210 (between `shfttbl` and `ctrltbl`) | +24 | ok |
| `swa >nul` with a failing layout | | ok |

## Conclusion so far

- **It is not a size limit.** `mos` can grow, at least by 24 bytes,
  as long as the keyboard **shift translation table** (`shfttbl`,
  `MOSINT16.ASM`) does not move by more than 16 bytes.
- Something depends on the **absolute address** of `shfttbl`, and only
  when a program writes redirected output to the floppy.
- What does not matter: moving `ctrltbl`/`alttbl` and all code after
  them (ok), and moving `basetbl`'s neighbourhood by 8 or 16 bytes.
- Memory dumps before and after the run show **no stray writes** into
  resident `mos`, on both the good and the failing layout.
- At the hang the CPU is in the kernel idle loop (TSL): the task waits
  for something. Keys do not release it.

## Next steps

1. Find who uses `shfttbl`'s address besides the two `mov si,offset
   shfttbl` and `[shfttbl+bx]` in `MOSINT16`. Candidates: a
   hard-coded offset in another module or utility (`KEYMAP`,
   `MOSKBFOR.INC`), or a computation that keeps only part of an
   address.
2. Alternatively, trace the floppy write path at the hang: request
   header, DMA address, retry counters.
3. Once found and fixed, `mos` has about 2.3 KB of usable room. Shrink
   phase 1 may not even be needed for the LBA work.

## Resolved (UPDATE 92)

The `shfttbl` dependency was a coincidence. The stale kernel image at
physical 18C6Eh lies in the test program's heap. Watcom's runtime reads
that uninitialised memory when it decides whether to commit after a
write. The real bug: `fgenioctl` marked the BPB dirty on a 440Dh get
device parameters. With uncommitted writes open, the next access then
failed with int 24h, general failure. Fixed in `MOSDDBLK.ASM`; see
UPDATE92.md.
