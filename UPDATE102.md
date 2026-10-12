# UPDATE 102 -- build HDSETUP in build.sh, install floppy, hard disk install tested (20261012)

Files (top of the tree, LF):

- `build.sh`
- `ci_prereq.sh`
- `makefloppy.sh` (new)
- `pcmos386-howto-boot.md`

Rig: `rig/pmrig-toolkit.tar.gz`, with `rig.sh` and `RIG.md` updated.

No kernel or utility source change.

## build.sh

**New last step `build_hdsetup`:**

- Runs `SOURCES/src/cutils/HDBUILD.SH` (Open Watcom).
- Copies `HDSETUP.EXE`, `HDSETUP.MSG` and `HDSETUP.HLP` into
  `SOURCES/src/latest`, next to the other utilities. From there
  `run.sh`, `makefloppy.sh` and the rig pick them up.
- Uses `WATCOM` if set, else `toolchain/open-watcom` when
  `ci_prereq.sh` installed it there.
- Otherwise it prints "HDSETUP skipped: set WATCOM ..." and the build
  is otherwise unaffected.

**Clean:** `--clean` also removes `latest/HDSETUP.MSG` and `.HLP`.
`HDSETUP.EXE` already went with `latest/*.EXE`.

**Check:** run with `WATCOM` set, it gives `HDSETUP.EXE` md5
`6c77cff3ef1c`, the same binary as UPDATE 100. Without `WATCOM`, it
prints the skip note.

## ci_prereq.sh

The generated `toolchain/env.sh` now also exports `WATCOM`, so the
Watcom compilers and `HDBUILD.SH` find their headers after
`source toolchain/env.sh`.

## makefloppy.sh (new)

```
./makefloppy.sh [--all] [OUT.img]        # default mosboot.img
```

The script is your version with these changes:

- **Tree:** `TREE` defaults to the directory the script is in (still
  overridable).
- **Shell:** `$$SHELL.SYS`, or `__SHELL.SYS` renamed (the MAKEMOS rename
  gap).
- **Missing files:** reported, and the exit status is 1.
- **`CONFIG.SYS`:** `smpsize=64`, `cache=16`, **`memdev=$386.sys`**.
  - **Fix to my earlier advice:** `device=$386.sys` boots with "Not
    Enough SMP for DEVICE = $386.SYS". `$386.SYS` is a memory manager
    and loads with `MEMDEV=`, as in `testconfig/CONFIG.SYS`.
  - `smpsize=16` was also too small.
- **`AUTOEXEC.BAT`:** prints one line naming the install steps. With an
  `AUTOEXEC.BAT` present there is no date/time prompt.
- **`--all`:** adds the remaining `.COM`/`.SYS`/`.EXE` after the
  install set. All 81 files fit, with 760 KB free.

## Hard disk install: tested end to end

The rig can now boot a given floppy image and boot from the hard disk
(see the rig section). The whole procedure from
`pcmos386-howto-boot.md` section 4 was run on a blank 2 GB disk:

| step | result |
| --- | --- |
| boot `mosboot.img`, `HDSETUP`, F3 (C: 86 MB), Esc, Y | MBR with boot code (`EB 03 'TSL' ...`), C: type 06h, active |
| reboot from the floppy, `FORMAT C:` | "Format complete", 90,337,280 bytes |
| `MSYS C:` | silent, no error |
| `COPY *.* C:` | kernel, shell, `CONFIG.SYS`, `AUTOEXEC.BAT`, utilities on C: |
| boot from the hard disk (`boot -l c`) | banner, `$386.SYS` loads, `[C:\]` prompt |

**MBR boot code, MSYS boot sector on a hard disk partition, and the
kernel booting from C:** all work. This path had not been tested before
in this project.

**Notes for the VM:**

- **COPY needs time:** wait for the prompt after `COPY *.* C:`. In the
  test the emulator was stopped early and only 46 of 81 files arrived.
  The boot files were among them, so it still booted.
- **Keys:** use the keypad arrows in HDSETUP. FORMAT needs an extra
  Enter after `Y`.

## Rig (`rig.sh`, `RIG.md`)

- `BOOTIMG=img`: boot that floppy image instead of building one.
- `HDBOOT=1`: with `HDIMG=`, boot from the hard disk (`boot -l c`).

Example:

```
BOOTIMG=mosboot.img HDIMG=vm.img rig.sh start            # install
HDBOOT=1 BOOTIMG=mosboot.img HDIMG=vm.img rig.sh start   # boot C:
```
