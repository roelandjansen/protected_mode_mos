#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# Print guest CPU state (registers, segments, mode, control registers)
#

dump_regs() {
	gdb_batch \
		-ex 'set print pretty off' \
		-ex 'printf "EAX=%08x EBX=%08x ECX=%08x EDX=%08x\n", cpu_regs.regs[0].dword[0], cpu_regs.regs[3].dword[0], cpu_regs.regs[1].dword[0], cpu_regs.regs[2].dword[0]' \
		-ex 'printf "ESI=%08x EDI=%08x EBP=%08x ESP=%08x\n", cpu_regs.regs[6].dword[0], cpu_regs.regs[7].dword[0], cpu_regs.regs[5].dword[0], cpu_regs.regs[4].dword[0]' \
		-ex 'printf "EIP=%08x FLAGS=%08x\n", cpu_regs.ip.dword[0], cpu_regs.flags' \
		-ex 'printf "ES=%04x CS=%04x SS=%04x DS=%04x FS=%04x GS=%04x\n", Segs.val[0], Segs.val[1], Segs.val[2], Segs.val[3], Segs.val[4], Segs.val[5]' \
		-ex 'printf "CSbase=%08x SSbase=%08x DSbase=%08x\n", Segs.phys[1], Segs.phys[2], Segs.phys[3]' \
		-ex 'printf "pmode=%d cr0=%08x cpl=%d\n", cpu.pmode, cpu.cr0, cpu.cpl' \
		-ex 'printf "CR3=%08x\n", paging.cr3'
}

dump_regs
