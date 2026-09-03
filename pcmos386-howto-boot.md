# PC-MOS/386: Build and Boot — Quick Reference

The whole workflow is three scripts, run in order.

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

## 3. Boot

```
./run.sh
```

Assembles a fresh boot floppy each time from `IMAGES/template/
empty-bootable.img` plus whatever's currently in `SOURCES/src/latest/`
(kernel, shell, every utility, `HELP.SRC`), then boots it. Re-running
`build.sh` and then `run.sh` is how you test any change — `run.sh` always
picks up the latest build output.

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
  (that path is still `dosemu2`/DOSBox-under-the-hood territory, not
  live) — see the Linux-native-build note for where that stands.
