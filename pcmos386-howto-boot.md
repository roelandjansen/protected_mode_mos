# PC-MOS/386: Build and Boot — Quick Reference

The whole workflow is three scripts, run in order, plus a fourth to install
on a hard disk.

## 1. One-time setup

```
./ci_prereq.sh
```

(as root, or inside a root CI container — see the tooling policy). Installs
`dosbox`, `mtools`, and the build-tool packages via `zypper`, and builds
UASM from source. Also fetches the Open Watcom archive, but that one step
stays manual/interactive on purpose (see the script's own comments) —
**not required** for the build/boot workflow below, only for the future
native-toolchain migration. Safe to skip that part if all you want is to
build and boot.

## 2. Build

```
./build.sh
```

Runs the real DOS-era toolchain (`MASM`/`LINK`/`PUBLIC`/`TS`/`EXE2BIN`)
under DOSBox against the actual source tree. Produces the kernel
(`SOURCES/src/latest/$$MOS.SYS`), the shell, and every utility/driver —
confirms success by checking `$$MOS.SYS` actually exists afterward, since
DOSBox itself always exits 0 regardless of whether the DOS-side build
succeeded.

**HDSETUP** is Borland C, which this tree cannot build. `build.sh` builds
it with Open Watcom (`SOURCES/src/cutils/HDBUILD.SH`) when `WATCOM` is set
or `ci_prereq.sh` has installed Open Watcom under `toolchain/`. Otherwise
it prints "HDSETUP skipped" and the rest of the build is unaffected.

## 3. Boot

```
./run.sh
```

Assembles a fresh boot floppy each time from `IMAGES/template/
empty-bootable.img` plus whatever's currently in `SOURCES/src/latest/`
(kernel, shell, every utility, `HELP.SRC`), then boots it. Re-running
`build.sh` and then `run.sh` is how you test any change — `run.sh` always
picks up the latest build output.

## 4. Install on a hard disk (VM or real machine)

```
./makefloppy.sh --all mosboot.img
```

Builds a persistent 1.44 MB boot floppy image from the latest build:

- kernel and shell;
- `$386.SYS` with `MEMDEV=$386.SYS` in `CONFIG.SYS` (not `DEVICE=`: that
  gives "Not Enough SMP");
- an `AUTOEXEC.BAT`, so there is no date/time prompt;
- HDSETUP (`.EXE`, `.MSG`, `.HLP`), FORMAT and MSYS;
- with `--all`, every other utility as well. Everything fits, with about
  750 KB to spare.

Attach the image as the VM's floppy, together with an empty virtual hard
disk, and boot from floppy:

1. **Partition:** `HDSETUP`.
   - F3 adds the primary partition (C:, FAT16, at most 2 GB).
   - F4 adds logical drives.
   - The keypad arrows move between lines; the grey arrows may not.
   - Esc, then Y writes the partition table and the MBR boot code. C:
     is marked active.
   - At "Prepare system for reboot", reboot from the floppy again.
2. **Format:** `FORMAT C:`, answer `Y`, press Enter once more.
3. **Make C: bootable:** `MSYS C:` writes the PC-MOS boot sector. It is
   silent when it works.
4. **Copy the system:** `COPY *.* C:` copies the kernel, shell,
   `CONFIG.SYS`, `AUTOEXEC.BAT` and the utilities. Wait for the prompt;
   it takes a while.
5. **Boot from C:** remove the floppy and reboot. The prompt is
   `[C:\]`.

Keep C: and the virtual disk modest for a first install (8 GB or less).
Beyond 8.4 GB PC-MOS needs a BIOS with int 13h extensions (SeaBIOS in
QEMU has them).

**FREEMEM on a real PC or VM:** C0000-C7FFF holds the video BIOS and
E0000-FFFFF the system BIOS. A range such as `FREEMEM=C0000,F0000` (fine
in DOSBox) used to hang the machine at the next screen output. Since
UPDATE 106 PC-MOS leaves ROM out of a FREEMEM range and says so (`FREEMEM
holds ROM; using ...`). On VMware, `FREEMEM=D0000,E0000` is a safe choice.
The build leaves the XMS driver as `_XMS.SYS`; `makefloppy.sh` puts it on
the floppy as `$XMS.SYS`.

Tested end to end in DOSBox Staging with int 13h extensions: blank 2 GB
disk, steps 1-5, boot from C:.

## While it's running

**Window size** — handled automatically, nothing to configure. `run.sh`
detects whether you have classic DOSBox or DOSBox Staging installed
(`zypper install dosbox` on openSUSE gives you Staging) and sets an
appropriately large window for each — PC-MOS's own text mode is a fixed
80×25 grid either way, this just renders it bigger.

**Exiting** — press **Ctrl+F9**. There's no in-guest `EXIT` command that
works here — you've booted a real OS image, not just mounted a directory,
so DOS-level exit commands have nothing to hand control back to. Ctrl+F9
is DOSBox's own documented shutdown hotkey and works regardless of what's
running inside. Don't use `kill`/`kill -HUP` on the process — it skips
`run.sh`'s own cleanup of its temporary floppy image file.

**Other useful hotkeys** (DOSBox Staging defaults; classic DOSBox mostly
matches):
- `Ctrl+Alt+Home` — restart DOSBox without fully quitting
- `Alt+Enter` — toggle fullscreen
- `Ctrl+F11` / `Ctrl+F12` — decrease/increase emulated CPU speed

**First-boot prompts** — PC-MOS asks for the date and time on every boot
since nothing pre-seeds them. Press Enter twice to accept the current
values and continue straight to the `[A:\]` prompt.

## Known rough edges

- `MAKEMOS.BAT`'s own rename step (`__SHELL.SYS` → `$$SHELL.SYS`) doesn't
  reliably take effect under the DOSBox build path — `run.sh` checks for
  both names and handles either, so this doesn't block anything, but it's
  still an open, unexplained gap in `build.sh`/`MAKEMOS.BAT` itself.
- `ci_prereq.sh` installs `dosbox`/`mtools` for `build.sh`/`run.sh`, but
  doesn't yet install anything for a from-scratch native-toolchain build
  (that path still runs the DOS-era toolchain under DOSBox, not
  live) — see the Linux-native-build note for where that stands.
