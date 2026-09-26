## UPDATE 62 (2026-09-26) — 32-bit clients: 16-bit CS at entry, frames by client type

`_386.ASM`: `$386.SYS` 32496 -> 32720, 0 warnings, 0 severe; binary
verified against the listing (`c32edx` at `431Ch`, all 16 calls `66 E8`).
New test client `DPMI32.ASM` (1030 bytes as `.COM`), new rig helper
`combuild.sh` (one `.COM` with the MASM error gate).

### Found

The first 32-bit client ever run (entry with `ax=1`) got a 32-bit CS:
`e6f8e` left makegdte's `g=1,d=1` when `cl` was nonzero. DPMI 0.9 5.2
(and 1.0, explicitly): every client resumes on a 16-bit CS with a 64K
limit; only interrupt and exception frames follow the client type. Every
real extender's 16-bit stub would have been decoded as 32-bit code.

Second, the host chose frame size, stub selector and `dx`/`edx` from the
D bit of the INTERRUPTED CS, at 15 places. With a conforming CS that is
wrong for a 32-bit client still in its initial code.

### Change

- `e6f8e`: client CS always `g=0,d=0`; records the client type per task
  in `c32tab` (128 bytes by task id: 0 no session, 1 16-bit, 2 32-bit)
- `c32edx` / `c32eax` (res16): bit 22 = 32-bit client, from `c32tab`;
  entry 0 falls back to the old D-bit rule, so non-DPMI native-mode code
  is unchanged. They replace every `lar e?x,[ebx+ncancs]` before a
  `test e?x,00400000h`: the three DOS translations, 0202h/0203h,
  0204h/0205h, 0300h, 0303h (x2), 0305h, 0306h, and the frame choice in
  `einvdl` / `einxdl`
- `e6f91`: callback frame size from the owning task's type (`dcbtab+1`),
  not the procedure's CS
- `dpmiclr`: clears the task's entry (unregister and session start)

Line endings: the 168 LF-only lines of `_386.ASM` are untouched; new
lines are CRLF. The diff is 183 lines.

### Measured (DPMI32, twice in one boot)

	1687h flags: 0001
	32: cs is 16-bit after entry
	cs/ss/ds ar-high: 0000 00C0 00C0
	0400 fl/ax/bx: 3292005A0001
	32i int60 eip:00000210 exp:0210 cs:007B/007B
	32x #DE   eip:0000022A exp:022A cs:007B/007B hostcs:0093

Both handlers are hand-encoded 32-bit code on a D=1 alias (000Ah +
0009h `cx=40FAh`) and return with `iretd` / 32-bit `retf`: a 12-byte
interrupt frame and a 32-byte exception frame with 32-bit EIP, taken
while the client ran in its 16-bit CS. No "Divide" on screen. Second
run: cs `006B`, same results.

Regression, all eighteen clients: identical to UPDATE 61 except sS's
rm->pm offset (`3D34` -> `3DB4`, the larger `$386.SYS`) and sL's loop
counter (timing, not checked).

### Test kit

`s32.img`: `$386.SYS` (UPDATE 62), `$DPMI.SYS`, `DPMI32.COM` as
`DPMITST.COM`. Checks: pattern `32i` -> eip equals exp, cs pair equal;
pattern `32x` -> the same plus a host cs; `Div=0 Int=0`.

Reference checksums:

| file | md5 |
| --- | --- |
| `$386.SYS` (32720) | `e434c145684b4f7ca518660b4fdb40be` |
| `$DPMI.SYS` (5117) | `2d8473ed064c1070cfd37cc111675e80` |
| `_386.ASM` | `42fd20a6c2c244457f32861698a3ff7c` |
| `DPMI32.ASM` | `40d44b45333df7409121ab61d8cbac18` |
| `s32.img` | `c067a77f0f0edc1dad176914c8fb0992` |

### Limits / open

- SS and DS come back `00C0` (G and B set) for 16- AND 32-bit clients:
  pre-existing; DPMI 0.9 says 64K selectors. Nothing has broken on it.
- `c32tab` assumes task ids below 80h (as the `80h|taskid` tags do).
- MASM 5.1 in `.386`: size forward memory references explicitly
  (`dword ptr`) and write far forward `jc` as `jnc $+5 / jmp near ptr`,
  or pass 2 reports a phase error.

Next: a real extender (DJGPP `hello.exe`, then DOS/4GW, DOS/32A).
