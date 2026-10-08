#include <stdio.h>
#include <string.h>
#include <dpmi.h>
#include <go32.h>
#include <sys/farptr.h>

//
// pm38 - UPDATE 82: int 21h 5Ch (lock/unlock) by DOS conventions, and
// int 38h 02h (SCB) / 04h (TCB) from protected mode, each compared
// with the same call straight to real mode (0300h)
//

static int BAD;
static unsigned int A, B, C, F;

//
// Report one check
//

static void check(const char *WHAT, int OK)
{
	printf("%s %s\n", OK ? "OK " : "BAD", WHAT);
	if (!OK)
		BAD++;
}

//
// int 21h from protected mode: ax, bx, cx, dx = pointer, si, di
//

static void i21(unsigned int AX, unsigned int BX, unsigned int CX,
		unsigned int DX, unsigned int SI, unsigned int DI)
{
	__asm__ __volatile__(
		"pushl %%ebp\n\t"
		"int $0x21\n\t"
		"sbbl %%ebp,%%ebp\n\t"
		"movl %%ebp,%2\n\t"
		"popl %%ebp"
		: "=a"(A), "+b"(BX), "=m"(F)
		: "a"(AX), "c"(CX), "d"(DX), "S"(SI), "D"(DI)
		: "memory", "cc");
	F &= 1;
}

//
// int 38h from protected mode: ah = function, bx in; es:ebx out
//

static void i38(unsigned int AX, unsigned int BX)
{
	__asm__ __volatile__(
		"pushl %%ebp\n\t"
		"pushl %%es\n\t"
		"int $0x38\n\t"
		"sbbl %%ebp,%%ebp\n\t"
		"movl %%ebp,%3\n\t"
		"movw %%es,%%cx\n\t"
		"popl %%es\n\t"
		"popl %%ebp"
		: "=a"(A), "=b"(B), "=c"(C), "=m"(F)
		: "a"(AX), "b"(BX)
		: "edx", "esi", "edi", "memory", "cc");
	F &= 1;
	C &= 0xffff;
}

int main(void)
{
	static char NAME[] = "PM38.TMP";
	static char DATA[100];
	unsigned int H;
	unsigned long PMV;
	unsigned long RMV;
	__dpmi_regs R;
	int K;

	// 5Ch: offset in CX:DX, length in SI:DI, as DOS
	i21(0x3c00, 0, 0, (unsigned int)NAME, 0, 0);
	H = A & 0xffff;
	i21(0x4000, H, sizeof(DATA), (unsigned int)DATA, 0, 0);
	i21(0x5c00, H, 0, 10, 0, 20);		// lock 20 bytes at 10
	check("5Ch lock 20 at 10", !F);
	i21(0x5c01, H, 0, 10, 0, 20);		// unlock the same
	check("5Ch unlock it", !F);
	i21(0x5c01, H, 0, 10, 0, 20);		// not locked any more
	printf("    unlock again: cf=%u ax=%04X\n", F, A & 0xffff);
	check("5Ch unlock again fails", F);
	i21(0x5c00, H, 0, 50, 0, 5);
	i21(0x5c01, H, 0, 50, 0, 6);		// length differs: no such lock
	check("5Ch unlock with another length fails", F);
	i21(0x5c01, H, 0, 50, 0, 5);
	check("5Ch unlock with the right length", !F);
	i21(0x3e00, H, 0, 0, 0, 0);
	i21(0x4100, 0, 0, (unsigned int)NAME, 0, 0);

	// int 38h 02h: SCB address
	i38(0x0200, 0);
	check("38h 02h cf=0", !F);
	PMV = _farpeekl(C, B);
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x0200;
	__dpmi_int(0x38, &R);
	RMV = _farpeekl(_dos_ds, R.x.es * 16 + R.x.bx);
	printf("    02h pm es:ebx=%04X:%08X -> %08lX  rm %04X:%04X -> %08lX\n",
	       C, B, PMV, R.x.es, R.x.bx, RMV);
	check("38h 02h: same SCB as real mode", PMV == RMV && C == 0x43);

	// int 38h 04h: TCB of task 0 (bx = task id in, es = TCB out)
	for (K = 0; K < 1; K++) {
		i38(0x0400, 0);
		check("38h 04h cf=0", !F);
		PMV = _farpeekl(C, B);
		memset(&R, 0, sizeof(R));
		R.x.ax = 0x0400;
		R.x.bx = 0;
		__dpmi_int(0x38, &R);
		RMV = _farpeekl(_dos_ds, R.x.es * 16);
		printf("    04h pm es:ebx=%04X:%08X -> %08lX  rm %04X:0 -> %08lX\n",
		       C, B, PMV, R.x.es, RMV);
		check("38h 04h: same TCB as real mode", PMV == RMV);
	}

	printf("PM38: %d bad\n", BAD);
	return BAD;
}
