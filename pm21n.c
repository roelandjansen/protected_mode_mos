#include <stdio.h>
#include <string.h>

//
// pm21n - the host's int 21h translation by its own (TSL native-mode)
// conventions: 4Eh/4Fh take the DTA in es:ebx, 42h returns eax
//

static unsigned int A, B, C, D, F;

//
// int 21h from protected mode, es = ds, ebx/ecx/edx as given
//

static void i21(unsigned int AX, unsigned int BX, unsigned int CX, unsigned int DX)
{
	__asm__ __volatile__(
		"pushl %%ebp\n\t"
		"pushl %%ds\n\t"
		"popl %%es\n\t"
		"int $0x21\n\t"
		"sbbl %%ebp,%%ebp\n\t"
		"movl %%ebp,%4\n\t"
		"popl %%ebp"
		: "=a"(A), "=b"(B), "=c"(C), "=d"(D), "=m"(F)
		: "a"(AX), "b"(BX), "c"(CX), "d"(DX)
		: "esi", "edi", "memory", "cc");
	F &= 1;
}

int main(void)
{
	static char N1[] = "PMNA.TMP";
	static char N2[] = "PMNB.TMP";
	static char SPEC[] = "PMN*.TMP";
	static char DTA[64];
	static char BUF[70000];
	unsigned int H;
	int K;

	i21(0x3c00, 0, 0, (unsigned int)N1);
	H = A & 0xffff;
	i21(0x4000, H, sizeof(BUF), (unsigned int)BUF);
	i21(0x4202, H, 0, 0);
	printf("42h end: cf=%u eax=%08X edx=%08X (70000=%08X)\n", F, A, D, 70000);
	i21(0x3e00, H, 0, 0);
	i21(0x3c00, 0, 0, (unsigned int)N2);
	i21(0x3e00, A & 0xffff, 0, 0);

	memset(DTA, 0, sizeof(DTA));
	i21(0x4e00, (unsigned int)DTA, 0, (unsigned int)SPEC);
	printf("4Eh: cf=%u ax=%04X name '%s'\n", F, A & 0xffff, DTA + 0x1e);
	for (K = 0; K < 3; K++) {
		i21(0x4f00, (unsigned int)DTA, 0, 0);
		printf("4Fh: cf=%u ax=%04X name '%s'\n", F, A & 0xffff, F ? "" : DTA + 0x1e);
	}
	i21(0x4100, 0, 0, (unsigned int)N1);
	i21(0x4100, 0, 0, (unsigned int)N2);
	return 0;
}
