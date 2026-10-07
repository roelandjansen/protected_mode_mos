# UPDATE 75 -- client id computed once per int 31h call (2026-10-06)

Files: `_386.ASM` only. `$386.SYS` 36,736 bytes (was 36,720), md5
`bd8017cd2893` (built in the rig, MASM 5.10, 0 severe errors).

## Why

`MEASURE-0300.md`: a 0300h call cost 479 monitor instructions, and the
calling client's id was computed three times on the way in --
`addrnca` in `einative`, then `e31tid` (= `addrnca` + `cidl`) in the
hook check `einvh1`, then again through `c32edx` in `e0300s`.

## Change

| where | what |
| --- | --- |
| `einative` | after `addrnca` (esi -> tcb): `call cidl`, store dl in `entcid` |
| data, after `pendsw` | `entcid db 0` -- client id of the task that last entered `einative` |
| `einvh1` | `call e31tid` -> `mov dl,ss:[entcid]` |
| new `c32edc` | second entry to `c32edx`: same pushes, dl from `entcid`, `jmp short c32edj` past `call e31tid` |
| `e0300s` | `call c32edx` -> `call c32edc` (0300h, 0301h, 0302h) |

**Why the cache cannot be stale.** `einvhook` is reached only from
`einative`; `eindisp` only from `einvhook` and its exception path
(`einxcpt` -> `einvh1`). Between `einative` and both readers the monitor
runs at ring 0 with no v-86 execution, so no task switch and no other
`einative` can intervene. The other `c32edx` callers are left alone:
several run after `dovmint` or on the `einback`/exception-return side,
where a v-86 round trip (and a task switch) may have happened.

Side effect: on `einvh1`'s not-hooked path with `hookok = 0`, esi no
longer holds the tcb when `eindisp` is reached. With `hookok = 1` it
was already the bitmap index (UPDATE 74), so nothing can depend on it.

## Encodings checked in the linked binary

| offset | bytes | meaning |
| --- | --- | --- |
| 3918 | `66 E8 C4 11` | call cidl (4AE0) |
| 391C | `67 36 88 16 DA 46` | mov ss:[entcid],dl (46DA) |
| 574A | `67 36 8A 16 DA 46` | einvh1: mov dl,ss:[entcid] |
| 4B72 | `50 56 53 67 36 8A 16 DA 46 EB 07` | c32edc -> 4B84 (past `call e31tid`) |
| 585F | `66 E8 0F F3` | e0300s: call c32edc (4B72) |

RES16 now ends at 06558h (was 06540h).

## Measurement (rig, gdb-gated hook, `hookprof.sh`)

| | UPDATE 74 | UPDATE 75 |
| --- | --- | --- |
| 0300h call, monitor instructions | 479 | **440** |
| hook check (`EINVHOOK`..`EINVH1`) | 70 | 47 |
| 0300h setup | 111 | ~95 |
| `einative` | 75 | 86 (+`cidl`) |

Net -39 per 0300h call (-8 %), about -12 per other int 31h call.
Reflected interrupts that pass `einvh1` also gain ~12.

## Tests (rig, `--testconfig`, normal core)

| test | result |
| --- | --- |
| DPMI32 (s32) | pass: `#GP count:0000 bytes 1/2/3:A1A200A3` |
| Q300 | `ax=0005` |
| DJFTEST | `262144 bytes, one-shot ok, chunked ok, sum 1BE00000` |
| DJMTEST | `11 MB in 1 MB blocks, 0 bad, one 10 MB block ok` |
| DJXTEST DJXTEST DJHELLO | three deep, all rc 0 |
| GD.BAT, 4 tasks (DJGPP only) | tasks 1-3: XTEST rc 0; task 0: `A:\DJXTEST.EXE: can't open` |

The task-0 failure is **identical on the unchanged UPDATE 74 driver**
(same floppy, same batch): a property of this setup (one floppy, four
tasks loading DJGPP images, testconfig without `FILES=`), not of this
change.

## Not run here

- DOS/4GW and DOS/32A clients (no Open Watcom in this container),
  the original `GO.BAT` (needs W4XTEST/WAXTEST/DOS32A).
- The 19 DPMI32 kit images (not uploaded).
- DJSTEST in the four-task run did not finish within ~10 minutes, on UPDATE 74 and UPDATE 75 alike (normal core, four tasks).

## Files

- `_386.ASM` -- UPDATE 74 + this change, CRLF.
- `GD.BAT`, `T1.BAT`..`T3.BAT` -- `GO.BAT` with DJGPP clients only.
