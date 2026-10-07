# int 31h 0300h: monitor instruction count per call (UPDATE 74 tree)

Measured 2026-10-06 on `$386.SYS` 36,720 bytes, md5 `6383f1809dc3`,
`CONFIG.SYS` = `--testconfig` (`MEMDEV=$386.SYS`, `DEVICE=$DPMI.SYS`).
No source changed.

## Method

1. **Label map.** Scratch copy of the tree; `include _386.pub` (the
   `public` tool's output) added after `include xifmacs.inc`, then
   `masm _386;` and `link _386,_386,_386/map;`. No listing (MASM writing
   `_386.LST` in the emulator ran at ~3 KB/min). The map's segments end
   at `08F6Fh` = 36,720 bytes, the shipped size: PUBLIC moves no code.
2. **Client.** `q300.c` (DJGPP 12.2): 0400h, 4 x 0300h (int 21h
   ah=30h), 0400h, print `ax`. Output `Q300 ax=0005`.
3. **Gate without a gate variable.** Boot with `PMTRACE=/tmp/q.log`
   and no `PMTRACE_HOOK_*`: the first `pmt_hook()` call reads the empty
   variables and leaves the hook off (`pmt_hook_lo = 0`). At the idle
   prompt, `q300` typed without Return, then via gdb:

       set var pmt_hook_lo=0x2800
       set var pmt_hook_hi=0x7B5F
       set var pmt_hook_left=3000000

   then Return. Range = resident RES16+RES32 code. Disarm afterwards
   with `set var pmt_hook_left=0`. Normal core (the hook needs it).
4. **Profile.** `hookprof.sh MAP LOG FROM TO` folds the `H` lines into
   label runs. The 0300h calls are found by their `E310300` (`5804h`)
   entry, bracketed by `E310400` (`3BF0h`); one call = one `EININT31`
   (`3AECh`) to the next.

The hook skips v-86 (`FLAG_VM`) and client code: the counts are monitor
instructions only. The DOS work of int 21h ah=30h in v-86 is **not**
in these numbers.

## Result

Three bracketed 0300h calls: 478 / 479 / 477 monitor instructions. One
call (479), by phase:

| phase | labels | instr |
| --- | --- | --- |
| function dispatch | `EININT31`, `E31N00`..`E31N25` (compare chain) | 24 |
| 0300h setup | `E310300`, `E0300A/S/B/T/V`, `C32EDX`, `E31TID`, `ADDRNCA`, `CIDL` | 111 |
| into v-86 | `DOVMINT`, `NIRQ1`, `DOVMRBAK`, `DOVMOKTF` | 69 |
| v-86 int 21h | (not traced) | - |
| back via int 6Fh | `I6F_TBL`, `EICOMMON`, `E6F02`, `DOVMCONT` | 53 |
| copy registers back | `E0300R` | 35 |
| return to client | `EINBACK` | 35 |
| next entry | `ETB`, `EICALLED`, `ENTIRQ(NT)`, `JEINAT`, `EINATIVE` + `ADDRNCA` | 75 |
| int 31h hook check | `EINVHOOK`..`EINVH1`, `EINXCPT`/`EINX1`/`EINXNO`, `E31TID`+`ADDRNCA`+`CIDL`, `E31HFIND`/`E31HFG1` | 70 |
| dispatch to int 31h | `EINDISP` | 7 |

For comparison, one 0400h call: **235** (dispatch chain 42, `E310400`
6, `EINBACK` 34, entry 75, hook check 70, `EINDISP` 7). So every int 31h
call pays ~180 monitor instructions of shared entry/exit before any
function work; 0300h adds ~268 of its own plus the v-86 run.

## Observations

- **Client id computed twice per call.** `E31TID` -> `ADDRNCA` (13) ->
  `CIDL` (9) runs once in the hook check and again in 0300h setup
  (with `C32EDX`, 13). About 25-40 instructions each time, same answer.
- **Hook check costs 70 for an unhooked vector.** The UPDATE 74
  bitmap test itself is short (`E31HFG1`, 17), but it is reached only
  after the exception check (`EINXCPT`/`EINX1`) and the client-id
  computation. Testing the bitmap first, with the id already at hand,
  would cut most of it.
- **`ADDRNCA` runs three times** per 0300h call (entry, hook check,
  setup): 39 instructions.
- **Dispatch chain** is a linear compare list: 24 for 0300h, 42 for
  0400h. A jump table would make it constant (~6).
- The v-86 round trip itself (`DOVMINT`..`DOVMCONT`, 122 monitor
  instructions) is the largest 0300h-specific block, but in an
  emulator every instruction costs about the same; on real hardware the
  ring transitions (IRETD into v-86, int 6Fh back) dominate, and their
  count is fixed (one each way). Cutting instructions here mainly helps
  the shared path.

## Candidates, by expected gain per call

| change | saves (approx.) | applies to |
| --- | --- | --- |
| cache the client id for the whole int 31h call (compute once at entry) | 50-80 | every int 31h |
| hook check: bitmap test first, exception check only on a hit | ~40 | every int 31h / reflected int |
| jump table instead of the compare chain | 18-36 | every int 31h |
| shorter `E0300R` / `E0300B`/`T` copy (rep movsd of the 50-byte struct) | ~30 | 0300h-0302h |

Not measured: v-86 instructions spent in int 21h ah=30h and in the
reflection stubs. That needs a step-count of VM mode (the current
`PMTRACE_STEPS` only arms on int 6Fh ax=7705h).

## Rig notes for this container

- Missing runtime libraries fetched with `apt-get download` into a
  user-local list dir and unpacked with `dpkg -x` to `~/deps/root`;
  `libiir.so.1` built from berndporr/iir1 **tag 1.9.3** (1.9.4+ lacks
  the out-of-line `Cascade::Cascade()`). `~/rig/env.sh` sets
  `LD_LIBRARY_PATH`/`PATH`. `xstart.sh` needs `xdpyinfo` (x11-utils).
- Rig scripts must run under bash (`bash -c '. ./env.sh; ...'`).
- `pkill -f` matched the tool's own shell again: stop by PID only.
- xdotool `type` lost the shifted `Q`; type lowercase via `rig.sh key`.
