# PC-MOS/386: Tooling & Scripting Policy

Reference doc — what is used, what is not, no exceptions unless explicitly
revisited here. Confirmed against the current tree: no `.py`/`.pl`/`.pm`
files and no `python`/`perl` shebangs exist anywhere outside the vendored
`BORLANDC` third-party bundle, so this is a clean baseline, not a cleanup.

## 0. Target platforms

**openSUSE Leap 15.x, Leap 16.x, and Tumbleweed only.** Debian-based
systems (Debian, Ubuntu, and derivatives) are out of scope — no `apt`,
`apt-get`, `dpkg`, `.deb` packaging, or Debian/Ubuntu-specific paths or
assumptions anywhere in this project's scripts or docs. Package
installation, where a script needs it at all, is `zypper` (still without
`sudo` — see §3).

## 1. Languages

**Used:**
- **C** — for any host-side helper/build tooling (e.g. the EXE→raw-image
  replacement tool identified in the Linux-native-build note), and for the
  small number of `.C` files inside the OS tree itself (`COMPFILE.C`,
  `ED.C`, `ulib`/`cutils`).
- **x86 assembly, MASM dialect** — the OS/kernel itself. Assembled via UASM
  going forward (see the Linux-native-build note); MASM/dosemu2 remains the
  fallback/reference path until UASM output is validated.
- **bash** — all scripting and build orchestration.

**Forbidden, strictly, no exceptions:**
- **Perl** — not for build scripts, not for one-off helper scripts, not in
  CI, not as a "quick throwaway."
- **Python** — same, no exceptions.

If a task seems to call for Perl or Python (text munging, a quick parser,
CI glue), the answer is a small C tool or a bash script, not an exception
to this rule.

**Not part of this project's own code, not a precedent:** the vendored
`BORLANDC` directory bundles Borland's own C++ (CLASSLIB) tooling and
examples as third-party reference material — it predates and sits outside
this policy and isn't grounds for writing new C++ or pulling in other
languages elsewhere in the tree.

## 2. Build tooling

Two different targets need to stay distinct — this is not a contradiction
of the C-only/gcc rule, it's two audiences for it:

- **Host-side tooling** (anything that runs on the Linux build machine
  itself — helper utilities, format converters, validation scripts):
  **C, compiled with gcc.** Not Open Watcom's `wcc`, not any other host
  compiler — gcc is the one used for native Linux tools.
- **DOS-target cross-compilation** (the actual kernel and OS binaries):
  gcc cannot be used here — it does not target 16-bit real-mode DOS OMF
  output. This path uses **UASM** (assembler) and **Open Watcom's
  `wcc`/`wlink`/`wlib`** (C compiler/linker/librarian), as laid out in the
  Linux-native-build note. Open Watcom here is a cross-toolchain for the
  OS's own binaries, not a substitute for gcc on the host side.
- **Build orchestration**: **bash only.** No Makefiles or CI steps that
  shell out to Python/Perl helpers — if a build step needs logic beyond
  what `make`/bash comfortably expresses, it's a gcc-built C helper, not a
  scripting-language escape hatch.

## 3. Bash scripting conventions

Every script in this project follows the same house style:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- Tabs for indentation, never spaces.
- `printf`, never `echo`.
- Variable names in UPPERCASE.
- Functions separated by a comment block, immediately above the function:

```bash
#
# Brief description of what the function does
#

function_name() {
	...
}
```

- **No `sudo` inside project scripts.** `ci_prereq.sh` used to fail this on
  two counts — `sudo apt`/`add-apt-repository`, i.e. `sudo` plus Debian
  tooling on a SUSE-only project (§0). It's been rewritten: `zypper`,
  no `sudo`, and it now refuses to run and explains why if it isn't
  already root, rather than escalating itself. Package/repo availability
  for dosemu2 differs by target (Tumbleweed carries it directly at time of
  writing; Leap may need the OBS repo the script falls back to) — worth
  re-checking that fallback URL periodically rather than trusting it
  indefinitely.

## 4. Change size

Small, self-contained changes only. Every change — a build-tooling patch, a
kernel-module port to UASM, a new host helper — should be small enough to
review and test on its own, with a clear before/after check (e.g. the
byte-diff validation from the Linux-native-build note). No large, multi-part
commits that bundle several unrelated changes together: those are hard, and
sometimes impossible, to assess when something breaks, since there's no
way to isolate which part caused it. If a piece of work doesn't fit in one
reviewable, testable step, split it into a sequence of smaller ones instead
of landing it as one.

## 5. Documentation

All docs are `.md`. No `.doc`/`.rtf`/`.txt` for anything newly written
(the vendored DOS-era `DOC`/`DOCS` PDFs and `.DOC` files from the original
Software Link release are historical artifacts, not something to match
going forward).

## 6. Scope

This governs new work — build tooling, host helper utilities, CI, and
scripting conventions. It does not relitigate the CVE-triage doc
conventions (separate area, separate rules) or the C header-file style
rules (typedef/struct spacing, grouped-field comment blocks) — those stand
as already specified and apply on top of this doc wherever C is written.
