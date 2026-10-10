# SHRINK PLAN -- kernel resident size (parked, 20261010)

Status: **parked**. Feasibility checked against `$$MOS.MAP` of the
UPDATE 88 kernel (md5 `4be8fcbff98e`).

## Where the bytes are

| segment | range | size | lives in | limit |
| --- | --- | --- | --- | --- |
| GRP (GDATA, TCB, IRQ, POLL) | 00000h-0229Bh | 8.6 KB | low memory | - |
| MO2 (DDT, code2) | 02300h-0CC7Bh | 42.4 KB | low memory | 64 KB, but 8 KB steps (below) |
| MOS (MOSSEG, code1) | 0CD00h-1CCC5h | 65,478 of 65,536 | **full** | 64 KB segment |
| INIT | 1CCD0h-1FC60h | 12 KB | discarded after boot | - |

Two separate problems:

1. **MOS is full** (58 bytes left). Nothing more can go into `mos`;
   it does not cost per-task memory, it only blocks growth.
   **Worse than the link map says (UPDATE 91):** 24 bytes of padding
   (MOSSEG 0FFC6h -> 0FFDEh) already make a program with redirected
   output hang. The link succeeds, and segment #2 ends at 10F700h,
   inside the HMA. So something else limits `mos` below 0FFDEh; find
   it first (phase 0) before relying on any `mos` space.
2. **GRP+MO2 is the low area** ("IO system data", 74K in `MEM`) that
   sits below every task. It grows in 8 KB steps. Today MO2 ends
   about **130 bytes** before the next step.

## What a shrink buys

- Per-task memory (MAXTASK 564K) only improves when GRP+MO2 drops
  **a whole step: about 7.9 KB** (8 KB minus the 130 bytes margin).
  Smaller savings give headroom, not memory.
- Moving code from MO2 to MOS is impossible (MOS full); moving from
  MOS to MO2 costs low memory. So "room" must come from deleting,
  compacting or evicting code, not from shuffling.

Verdict: **feasible for headroom (1-3 KB), hard for a full 8 KB step.**
A full step needs one large eviction (phase 3).

## Candidates

| # | candidate | segment | est. gain | risk |
| --- | --- | --- | --- | --- |
| 1 | dead code after UPDATE 88: `tcbopen60` path (old TRUENAME "last opened file") in open/close | MO2/MOS | 50-150 B | low |
| 2 | duplicate case tables (`capstbl` vs the new 65h upper case path) | MO2 | 128-256 B | low |
| 3 | message strings: long resident error texts, duplicated in several modules | both | 0.5-1.5 KB | low, needs inventory |
| 4 | code that only runs at boot but sits in MO2/MOS (table builders, config parsing helpers called from INIT) | both | 0.5-2 KB | medium: each must be proven boot-only |
| 5 | rarely used int 21h functions (FCB family 0Fh-17h, 21h-28h: `MOSFUN0F.ASM` is 60 KB source) | MO2 | 2-5 KB if evicted | medium |
| 6 | evict a cold block to extended memory via memdev (load at boot, map in on call, like the `$XMS.SYS` window) | MO2 | 4-10 KB | high: needs a far call stub, reentrancy under task switch |
| 7 | MOSINT10 video BIOS emulation parts not used with modern VGA | MOS | 1-3 KB | medium, frees MOS only |

Debug conditionals: none of the large MO2 modules carry `if debug`
blocks (checked `MOSDDTSH`, `MOSFUN39`, `MOSFUTIL`), so no free gain there.

## Plan (when unparked)

1. **Measure** (no code change):
   - add a per-module size listing to `kbuild.sh` (link with `/MAP`
     per object or assemble with listings) so every candidate has a
     real byte count;
   - record GRP+MO2 end, MOS end and MAXTASK as the baseline.
2. **Phase 1, low risk (target 1-2 KB headroom):** candidates 1, 2, 3.
   One small update each, regression: sweep, `xmst`, four-task `GO.BAT`,
   STEST, MAXTASK.
3. **Phase 2, boot-only code to INIT (target +1-2 KB):** candidate 4.
   Each routine traced (DOSBox pmtrace) to prove it never runs after
   boot.
4. **Phase 3, only if an 8 KB step is wanted:** candidate 5 or 6.
   Design note first (`EVICT-DESIGN.md`), then a prototype on one
   function group (FCB calls), measured on MAXTASK.
5. MOS room (candidate 7, 3) is done whenever a new feature needs
   space in `mos`.

## Rules

- Each step: one small update, CRLF kept, MASM 0 warnings, the
  regression above, MAXTASK reported.
- Never trade a working DOS function for space without saying so in
  the update notes (as UPDATE 88 did with 6502h-6507h).
- Watch the 8 KB step on every MO2 change: `$$MOS.MAP`, DDT stop
  address must stay below 0CD00h.
