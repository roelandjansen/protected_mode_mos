#include <stdio.h>
#include <string.h>
#include <dpmi.h>
#include <go32.h>
#include <sys/movedata.h>
#include <sys/segments.h>

//
// xmst - $XMS.SYS from a DPMI client: int 2Fh 4300h/4310h, then the
// XMS entry through 0301h (call real-mode far procedure). Step 1:
// version, HMA/A20/UMB answers, query free, allocate/info/free,
// 32-bit 88h/89h/8Eh, handle exhaustion
//

static int BAD;
static int NOK;
static __dpmi_regs R;
static unsigned short ESEG;
static unsigned short EOFS;

//
// Report one check
//

static void check(const char *WHAT, int OK)
{
	if (!OK)
		printf("BAD %s\n", WHAT);
	NOK += OK;
	if (!OK)
		BAD++;
}

//
// Call the XMS entry with AX, BX, DX (32-bit EDX for the 3.0 calls)
//

static void xms(unsigned int AX, unsigned int BX, unsigned long EDX)
{
	memset(&R, 0, sizeof(R));
	R.x.ax = AX;
	R.x.bx = BX;
	R.d.edx = EDX;
	R.x.cs = ESEG;
	R.x.ip = EOFS;
	__dpmi_simulate_real_mode_procedure_retf(&R);
}

//
// 0Bh: move LEN bytes; handle 0 = real-mode SEG:OFF in OFS
//

static int move(unsigned long LEN, unsigned int SH, unsigned long SO,
		unsigned int DH, unsigned long DO)
{
	unsigned char S[16];

	*(unsigned long *)(S + 0) = LEN;
	*(unsigned short *)(S + 4) = SH;
	*(unsigned long *)(S + 6) = SO;
	*(unsigned short *)(S + 10) = DH;
	*(unsigned long *)(S + 12) = DO;
	dosmemput(S, 16, __tb);
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x0b00;
	R.x.ds = __tb >> 4;
	R.x.si = __tb & 15;
	R.x.cs = ESEG;
	R.x.ip = EOFS;
	__dpmi_simulate_real_mode_procedure_retf(&R);
	return R.x.ax == 1 ? 0 : R.h.bl;
}

//
// Step 3: moves (all directions, page crossings, overlap), lock with
// a 0800h cross-check, reallocate, error codes
//

static void step3(void)
{
	static unsigned char A[32768];
	static unsigned char B[32768];
	unsigned int SEGA;
	unsigned int SEGB;
	unsigned int H1;
	unsigned int H2;
	unsigned long PHYS;
	__dpmi_meminfo MI;
	int SEL;
	int I;
	int OK;

	// two 32 KB conventional buffers
	SEGA = __dpmi_allocate_dos_memory(2048, &SEL);
	SEGB = __dpmi_allocate_dos_memory(2048, &SEL);
	for (I = 0; I < 32768; I++)
		A[I] = (unsigned char)(I * 7 + (I >> 8));
	dosmemput(A, 32768, SEGA * 16);
	xms(0x0900, 0, 64);
	H1 = R.x.dx;
	xms(0x0900, 0, 64);
	H2 = R.x.dx;
	check("09h two 64 KB blocks", H1 && H2);

	// conventional A -> H1 at an odd offset across pages -> H2 -> B
	check("0Bh conv -> EMB (offset 4093, 30000 bytes)",
	      move(30000, 0, (unsigned long)SEGA << 16, H1, 4093) == 0);
	check("0Bh EMB -> EMB (4093 -> 8191)", move(30000, H1, 4093, H2, 8191) == 0);
	memset(B, 0, sizeof(B));
	dosmemput(B, 32768, SEGB * 16);
	check("0Bh EMB -> conv", move(30000, H2, 8191, 0, (unsigned long)SEGB << 16) == 0);
	dosmemget(SEGB * 16, 32768, B);
	check("0Bh round trip: same 30000 bytes", memcmp(A, B, 30000) == 0 && B[30000] == 0);

	// conventional -> conventional
	check("0Bh conv -> conv", move(1000, 0, (unsigned long)SEGA << 16, 0,
				       ((unsigned long)SEGB << 16) | 20000) == 0);
	dosmemget(SEGB * 16 + 20000, 1000, B);
	check("0Bh conv -> conv data", memcmp(A, B, 1000) == 0);

	// overlap inside H1: up by 6000 (must run downwards), then back down
	move(20000, 0, (unsigned long)SEGA << 16, H1, 0);
	check("0Bh overlap up (0 -> 6000, 20000 bytes)", move(20000, H1, 0, H1, 6000) == 0);
	move(20000, H1, 6000, 0, (unsigned long)SEGB << 16);
	dosmemget(SEGB * 16, 20000, B);
	check("0Bh overlap up: data intact", memcmp(A, B, 20000) == 0);
	check("0Bh overlap down (6000 -> 2)", move(20000, H1, 6000, H1, 2) == 0);
	move(20000, H1, 2, 0, (unsigned long)SEGB << 16);
	dosmemget(SEGB * 16, 20000, B);
	check("0Bh overlap down: data intact", memcmp(A, B, 20000) == 0);

	// errors
	check("0Bh odd length: A7h", move(3, 0, (unsigned long)SEGA << 16, H1, 0) == 0xa7);
	check("0Bh bad source handle: A3h", move(2, 999, 0, H1, 0) == 0xa3);
	check("0Bh bad destination handle: A5h", move(2, H1, 0, 999, 0) == 0xa5);
	check("0Bh past the end: A7h", move(4096, H1, 64 * 1024 - 2048, H2, 0) == 0xa7);
	check("0Bh source offset beyond: A4h", move(2, H1, 70000, H2, 0) == 0xa4);

	// lock: physical address, then look at it through 0800h
	move(4096, 0, (unsigned long)SEGA << 16, H2, 0);
	xms(0x0c00, 0, H2);
	PHYS = ((unsigned long)R.x.dx << 16) | R.x.bx;
	printf("    0Ch physical %08lX\n", PHYS);
	check("0Ch lock", R.x.ax == 1 && PHYS >= 0x100000);
	// 0800h maps only physical addresses outside RAM (UPDATE 81), so
	// the rig checks this one from outside: PHYS must hold A[0..7]
	printf("    0Ch expect %02X %02X %02X %02X %02X %02X %02X %02X at %08lX\n",
	       A[0], A[1], A[2], A[3], A[4], A[5], A[6], A[7], PHYS);
	(void)MI;
	(void)OK;
	xms(0x0a00, 0, H2);
	check("0Ah locked block: ABh", R.x.ax == 0 && R.h.bl == 0xab);
	xms(0x0e00, 0, H2);
	check("0Eh lock count 1", R.h.bh == 1);
	xms(0x0d00, 0, H2);
	check("0Dh unlock", R.x.ax == 1);
	xms(0x0d00, 0, H2);
	check("0Dh again: AAh", R.x.ax == 0 && R.h.bl == 0xaa);

	// reallocate: grow keeps the data, shrink too
	move(30000, 0, (unsigned long)SEGA << 16, H1, 0);
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x0f00;
	R.x.bx = 512;
	R.x.dx = H1;
	R.x.cs = ESEG;
	R.x.ip = EOFS;
	__dpmi_simulate_real_mode_procedure_retf(&R);
	check("0Fh grow 64 -> 512 KB", R.x.ax == 1);
	xms(0x0e00, 0, H1);
	check("0Eh: 512 KB", R.x.dx == 512);
	move(30000, H1, 0, 0, (unsigned long)SEGB << 16);
	dosmemget(SEGB * 16, 30000, B);
	check("0Fh grow: data kept", memcmp(A, B, 30000) == 0);
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x0f00;
	R.x.bx = 32;
	R.x.dx = H1;
	R.x.cs = ESEG;
	R.x.ip = EOFS;
	__dpmi_simulate_real_mode_procedure_retf(&R);
	check("0Fh shrink 512 -> 32 KB", R.x.ax == 1);
	move(30000, H1, 0, 0, (unsigned long)SEGB << 16);
	dosmemget(SEGB * 16, 30000, B);
	check("0Fh shrink: data kept", memcmp(A, B, 30000) == 0);

	xms(0x0a00, 0, H1);
	xms(0x0a00, 0, H2);
	check("0Ah free both", R.x.ax == 1);
}

int main(void)
{
	unsigned int H[40];
	unsigned long LARGEST;
	unsigned long AFTER;
	int I;
	int N;

	memset(&R, 0, sizeof(R));
	R.x.ax = 0x4300;
	__dpmi_int(0x2f, &R);
	check("2Fh 4300h: AL = 80h", R.h.al == 0x80);
	if (R.h.al != 0x80) {
		printf("XMST: no XMS driver\n");
		return 1;
	}
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x4310;
	__dpmi_int(0x2f, &R);
	ESEG = R.x.es;
	EOFS = R.x.bx;
	printf("    entry %04X:%04X\n", ESEG, EOFS);

	xms(0x0000, 0, 0);
	printf("    00h version %04X revision %04X hma %u\n", R.x.ax, R.x.bx, R.x.dx);
	check("00h version 3.00", R.x.ax == 0x0300);
	xms(0x0100, 0, 0xffff);
	check("01h HMA: 90h does not exist", R.x.ax == 0 && R.h.bl == 0x90);
	xms(0x0700, 0, 0);
	check("07h A20 on", R.x.ax == 1);
	xms(0x1000, 0, 0xffff);
	check("10h UMB: B1h none", R.x.ax == 0 && R.h.bl == 0xb1);

	xms(0x0800, 0, 0);
	LARGEST = R.x.ax;
	printf("    08h largest %lu KB total %u KB\n", LARGEST, R.x.dx);
	check("08h query free", R.h.bl == 0 && LARGEST > 1024);
	xms(0x8800, 0, 0);
	printf("    88h largest %lu KB\n", R.d.eax);
	check("88h query free (32-bit)", R.h.bl == 0 && R.d.eax >= LARGEST);

	xms(0x0900, 0, 1024);
	H[0] = R.x.dx;
	check("09h allocate 1024 KB", R.x.ax == 1 && H[0] != 0);
	xms(0x0e00, 0, H[0]);
	printf("    0Eh size %u KB lock %u free handles %u\n", R.x.dx, R.h.bh, R.h.bl);
	check("0Eh info: 1024 KB, unlocked", R.x.ax == 1 && R.x.dx == 1024 && R.h.bh == 0);
	xms(0x0800, 0, 0);
	AFTER = R.x.ax;
	check("08h: 1024 KB less free", AFTER + 1024 <= LARGEST);
	xms(0x8900, 0, 3000);
	H[1] = R.x.dx;
	check("89h allocate 3000 KB (32-bit)", R.x.ax == 1 && H[1] != 0);
	xms(0x8e00, 0, H[1]);
	check("8Eh info: 3000 KB rounded to 3000", R.x.ax == 1 && R.d.edx == 3000);
	xms(0x0a00, 0, H[0]);
	check("0Ah free", R.x.ax == 1);
	xms(0x0a00, 0, H[0]);
	check("0Ah free again: A2h", R.x.ax == 0 && R.h.bl == 0xa2);
	xms(0x0a00, 0, H[1]);
	check("0Ah free the 32-bit block", R.x.ax == 1);
	xms(0x0800, 0, 0);
	check("08h: all back", R.x.ax == LARGEST);

	// handles: zero-length blocks until refused
	for (N = 0; N < 40; N++) {
		xms(0x0900, 0, 0);
		if (R.x.ax != 1)
			break;
		H[N] = R.x.dx;
	}
	printf("    %d zero-length handles, then bl=%02X\n", N, R.h.bl);
	check("09h: handles run out with A1h", N >= 8 && R.h.bl == 0xa1);
	for (I = 0; I < N; I++)
		xms(0x0a00, 0, H[I]);
	xms(0x0900, 0, 0x7fff);
	check("09h 32 MB: A0h out of memory or ok", R.x.ax == 1 || R.h.bl == 0xa0);
	if (R.x.ax == 1)
		xms(0x0a00, 0, R.x.dx);

	step3();
	printf("XMST: %d ok, %d bad\n", NOK, BAD);
	return BAD;
}
