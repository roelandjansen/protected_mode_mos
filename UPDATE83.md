# UPDATE 83 -- kernel: compat read opens coexist with deny-write / deny-none (2026-10-08)

Files: `MOSFUTIL.ASM` only (kernel, `chkacc`). `$$MOS.SYS` 130,017
bytes (unchanged size: segment padding), md5 `2ec22df3de51`; built with
`kbuild.sh MOSFUTIL`. No driver change: boot it with the UPDATE 82
`$386.SYS`.

**Baseline check**: `kbuild.sh MOSFUTIL MOSFUTL4` on the unchanged tree
gives md5 `16fc9d34ac6c`, byte-identical to the `$$MOS.SYS` in the
handover header (UPDATE 66). Note: the `$$MOS.SYS` in the uploaded
tarball's `latest/` is an **older 129,249-byte build** (md5
`4c35ea6e383a`, without UPDATE 66); the UPDATE 75-82 tests in this
container booted that one. From UPDATE 83 on, tests use the documented
kernel.

## Problem

Two tasks starting the same DJGPP program at once: `can't open` or
rc 255 (UPDATE 75/76 notes). EXEC opens the program 3D20h (read,
**deny-write**); the DJGPP stub reopens its own EXE 3D00h (read,
**compatibility mode**). `chkacc` treats these as exclusive both ways:

- new compat open, existing deny-write/deny-none: retry `tcbntry` times
  (~1 s each), then a critical error (the user sees "File lock conflict
  while reading A: -- Enter A to abort or R to retry");
- new deny-write/deny-none open, existing compat open: sharing
  violation at once.

But deny-write means "others may read", and a compat open with read
access only reads. The kernel already allowed exactly this for files
with the read-only attribute (`di` flag, the "special case for
read-only files", mjs 1991); UPDATE 83 allows it whenever the opens only
read.

## Change (`chkacc`)

| place | rule added |
| --- | --- |
| `ch14` loop (new open compat) | if the new access is **read** (`bl == access_r`), an existing deny-write or deny-none open is no conflict -- as for read-only files |
| `ch7` loop (new open not compat) | if the existing compat open's access is **read** (`tfbacc == access_r`) **and** the new access is read, a new deny-write/deny-none open is no conflict |

Still refused: compat write or read/write against deny-write; anything
against deny-read or deny-read/write; a new deny-write/deny-none open
against a compat open that writes. The later `accok` pass is unchanged.

`ljnz chkacy` (was `jnz`): the insertion put TSL's own jump out of
short range (A2053 by 13 bytes); `ljnz` is MACROS.INC's long form,
used on the line above (`ljc`).

**UPDAT501.SYS** (TSL's 1992 runtime patch driver) replaces `chkacc` by
patching fixed offsets of the original 5.01 binary. Its rules are the
same as the kernel's before this update (the kernel already carries
its 1.04 rewrite: "mjs 09/17/92 ... parallel: updat501.sys version
1.04"). It must never be loaded with a rebuilt `$$MOS.SYS` -- already
true since UPDATE 66.

## Tests (rig, UPDATE 82 drivers, `--testconfig`)

`share.c` (DJGPP): opens straight to real-mode DOS (0300h), one task,
deterministic; a real-mode int 24h handler answers "fail" so a conflict
returns an error instead of a prompt.

| case | kernel 16fc9d34ac6c | UPDATE 83 |
| --- | --- | --- |
| deny-write holder, compat read | refused (5) | **ok** |
| deny-none holder, compat read | refused (5) | **ok** |
| compat read holder, deny-write read | refused (32) | **ok** |
| compat read holder, deny-none read | refused (32) | **ok** |
| deny-write holder, compat write | refused | refused |
| deny-write holder, compat read/write | refused | refused |
| deny-read/write holder, compat read | refused | refused |
| deny-read holder, compat read | refused | refused |
| compat write holder, deny-write read | refused | refused |
| compat read holder, deny-read/write | refused | refused |
| start `DJHELLO` while held deny-write | `DJHELLO.exe: can't open`, rc 102 | runs, rc 0 |
| **SHARE** | **5 bad** | **0 bad** |

Four tasks starting the same `DJXTEST`/`DJHELLO` (normal core): all rc 0
on both kernels this time -- the collision depends on timing; `share.c`
is the deterministic proof.

## Regression -- one open point

Original `GO.BAT` (dynamic core), repeated:

| kernel | runs | all rc 0, STEST 0 bad, all DONE |
| --- | --- | --- |
| 16fc9d34ac6c (unchanged) | 5 | 5 |
| UPDATE 83 | 6 | **5** |

In one UPDATE 83 run (the first), task 2 (DOS/4GW: `W4XTEST W4HELLO`,
then `W4STEST`) printed the DOS/4GW banner for W4STEST and then nothing
for more than 5 minutes (normally ~1 minute); tasks 0, 1, 3 finished
normally. It did not recur in five more runs. W4STEST opens no files
itself (only find first/next); the DOS/4GW loader and `DOS4GW.EXE` are
shared with task 0's `W4XTEST`. **Not attributed**: it may be rare and
pre-existing, or UPDATE 83 may allow an interleaving the old rules
blocked. Please run `GO.BAT` several times on your rig; if task 2 hangs
again, its screen (DOS/4GW message, critical-error box?) is the lead.

## Files

- `MOSFUTIL.ASM` -- the kernel module, CRLF.
- `share.c` -- deterministic sharing probe; `share-base.txt`,
  `share-83.txt` -- its output on both kernels.
