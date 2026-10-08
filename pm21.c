#include <stdio.h>
#include <string.h>
#include <stdlib.h>

//
// pm21 - the DPMI host's own int 21h translation: raw int 21h from
// protected mode with ds:(e)dx / es:(e)di pointing at client memory.
// DJGPP installs no pm int 21h handler, so these reach the host.
// One line per check: OK or BAD with the registers.
//

//
// Register set for one raw int 21h
//

typedef struct {
	unsigned int EAX;
	unsigned int EBX;
	unsigned int ECX;
	unsigned int EDX;
	unsigned int ESI;
	unsigned int EDI;
	unsigned int CF;
} R21;

static int BAD;

//
// Issue int 21h from protected mode; ds = es = the program's data
//

static void i21(R21 *R)
{
	unsigned int A, B, C, D, S, DI, F;

	__asm__ __volatile__(
		"pushl %%ebp\n\t"
		"pushl %%ds\n\t"
		"popl %%es\n\t"
		"int $0x21\n\t"
		"sbbl %%ebp,%%ebp\n\t"
		"movl %%ebp,%6\n\t"
		"popl %%ebp"
		: "=a"(A), "=b"(B), "=c"(C), "=d"(D), "=S"(S), "=D"(DI), "=m"(F)
		: "a"(R->EAX), "b"(R->EBX), "c"(R->ECX), "d"(R->EDX),
		  "S"(R->ESI), "D"(R->EDI)
		: "memory", "cc");
	R->EAX = A;
	R->EBX = B;
	R->ECX = C;
	R->EDX = D;
	R->ESI = S;
	R->EDI = DI;
	R->CF = F & 1;
}

//
// Report one check
//

static void check(const char *WHAT, int OK, const R21 *R)
{
	if (OK) {
		printf("OK  %s\n", WHAT);
		return;
	}
	BAD++;
	printf("BAD %s cf=%u eax=%08X ebx=%08X ecx=%08X edx=%08X\n",
	       WHAT, R->CF, R->EAX, R->EBX, R->ECX, R->EDX);
}

//
// Prepare a register set with ah and pointers
//

static void set(R21 *R, unsigned int AX, const void *DX)
{
	memset(R, 0, sizeof(*R));
	R->EAX = AX;
	R->EDX = (unsigned int)DX;
}

#define BIG 100000

int main(void)
{
	static char NAME[] = "PM21A.TMP";
	static char NAME2[] = "PM21B.TMP";
	static char DIR[] = "PM21D";
	static char SPEC[] = "PM21*.TMP";
	static char CWD[80];
	static char DTA[128];
	static char TMPDIR[] = ".\\\0\0\0\0\0\0\0\0\0\0\0\0\0\0";
	unsigned char *WBUF;
	unsigned char *RBUF;
	unsigned int H;
	unsigned int I;
	R21 R;

	WBUF = malloc(BIG);
	RBUF = malloc(BIG);
	for (I = 0; I < BIG; I++)
		WBUF[I] = (unsigned char)(I * 7 + (I >> 8));

	set(&R, 0x3c00, NAME);			// create
	R.ECX = 0;
	i21(&R);
	check("3Ch create", !R.CF, &R);
	H = R.EAX & 0xffff;

	set(&R, 0x4000, WBUF);			// write 100,000 bytes
	R.EBX = H;
	R.ECX = BIG;
	i21(&R);
	check("40h write 100000 (>64K)", !R.CF && R.EAX == BIG, &R);

	set(&R, 0x4200, 0);			// seek to 0
	R.EBX = H;
	i21(&R);
	check("42h seek 0", !R.CF && (R.EAX & 0xffff) == 0 && (R.EDX & 0xffff) == 0, &R);

	memset(RBUF, 0, BIG);
	set(&R, 0x3f00, RBUF);			// read it back
	R.EBX = H;
	R.ECX = BIG;
	i21(&R);
	check("3Fh read 100000 (>64K)", !R.CF && R.EAX == BIG, &R);
	check("3Fh data equal", memcmp(WBUF, RBUF, BIG) == 0, &R);

	set(&R, 0x4202, 0);			// seek to end: size
	R.EBX = H;
	i21(&R);
	check("42h seek end = 100000",
	      !R.CF && ((R.EDX & 0xffff) << 16 | (R.EAX & 0xffff)) == BIG, &R);

	set(&R, 0x3e00, 0);			// close
	R.EBX = H;
	i21(&R);
	check("3Eh close", !R.CF, &R);

	set(&R, 0x4300, NAME);			// get attributes
	i21(&R);
	check("43h get attr", !R.CF, &R);

	set(&R, 0x5600, NAME);			// rename ds:edx -> es:edi
	R.EDI = (unsigned int)NAME2;
	i21(&R);
	check("56h rename", !R.CF, &R);

	set(&R, 0x1a00, DTA);			// set DTA, then find first/next
	i21(&R);
	set(&R, 0x4e00, SPEC);
	R.ECX = 0;
	i21(&R);
	check("4Eh find first", !R.CF, &R);
	check("4Eh name in DTA", strcmp(DTA + 0x1e, NAME2) == 0, &R);
	if (!R.CF)
		printf("    DTA name '%.13s' size %u\n", DTA + 0x1e,
		       *(unsigned int *)(DTA + 0x1a));
	set(&R, 0x4f00, 0);
	i21(&R);
	check("4Fh find next: none (cf=1, ax=12h)", R.CF && (R.EAX & 0xffff) == 0x12, &R);

	set(&R, 0x4100, NAME2);			// delete
	i21(&R);
	check("41h delete", !R.CF, &R);

	set(&R, 0x3900, DIR);			// mkdir / chdir / getcwd / back / rmdir
	i21(&R);
	check("39h mkdir", !R.CF, &R);
	set(&R, 0x3b00, DIR);
	i21(&R);
	check("3Bh chdir", !R.CF, &R);
	set(&R, 0x4700, 0);
	R.ESI = (unsigned int)CWD;
	i21(&R);
	check("47h getcwd = PM21D", !R.CF && strcmp(CWD, "PM21D") == 0, &R);
	printf("    cwd '%s'\n", CWD);
	set(&R, 0x3b00, "\\");
	i21(&R);
	check("3Bh chdir \\", !R.CF, &R);
	set(&R, 0x3a00, DIR);
	i21(&R);
	check("3Ah rmdir", !R.CF, &R);

	set(&R, 0x5a00, TMPDIR);		// create temporary file
	R.ECX = 0;
	i21(&R);
	check("5Ah temp file", !R.CF, &R);
	printf("    temp '%s'\n", TMPDIR);
	if (!R.CF) {
		H = R.EAX & 0xffff;
		set(&R, 0x3e00, 0);
		R.EBX = H;
		i21(&R);
		set(&R, 0x4100, TMPDIR);
		i21(&R);
		check("41h delete temp", !R.CF, &R);
	}

	printf("PM21: %d bad\n", BAD);
	return BAD;
}
