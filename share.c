#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dpmi.h>
#include <go32.h>
#include <sys/movedata.h>

//
// share - file sharing between a compatibility-mode open and a
// deny-write / deny-none open (UPDATE 83), deterministic in one task.
// Opens go straight to real-mode DOS (0300h). Each line: the result
// and what is expected after UPDATE 83.
//

static int BAD;

//
// Open NAME with AL = MODE in real mode; handle, or -(error)
//

static int dopen(const char *NAME, int MODE)
{
	__dpmi_regs R;

	dosmemput(NAME, strlen(NAME) + 1, __tb);
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x3d00 | MODE;
	R.x.ds = __tb >> 4;
	R.x.dx = __tb & 15;
	__dpmi_int(0x21, &R);
	if (R.x.flags & 1)
		return -R.x.ax;
	return R.x.ax;
}

//
// Close a handle in real mode
//

static void dclose(int H)
{
	__dpmi_regs R;

	if (H <= 0)
		return;
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x3e00;
	R.x.bx = H;
	__dpmi_int(0x21, &R);
}

//
// Hold FILE with HOLD, then open it with TRY; report against WANT
//

static void pair(const char *WHAT, int HOLD, int TRY, int WANT)
{
	int H1;
	int H2;
	int OK;

	H1 = dopen("SHTEST.DAT", HOLD);
	H2 = dopen("SHTEST.DAT", TRY);
	OK = (H2 > 0) == WANT;
	printf("%s %-46s hold %02Xh: %d, open %02Xh: %d (want %s)\n", OK ? "OK " : "BAD",
	       WHAT, HOLD, H1, TRY, H2, WANT ? "ok" : "refused");
	if (!OK)
		BAD++;
	dclose(H2);
	dclose(H1);
}

//
// Real-mode int 24h handler that answers "fail" (mov al,3 / iret),
// so a sharing conflict returns an error instead of a prompt; a
// child started by system() inherits it through its PSP
//

static void int24_fail(void)
{
	static unsigned char STUB[] = { 0xb0, 0x03, 0xcf };
	__dpmi_regs R;
	int SEL;
	int SEG;

	SEG = __dpmi_allocate_dos_memory(1, &SEL);
	dosmemput(STUB, sizeof(STUB), SEG * 16);
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x2524;
	R.x.ds = SEG;
	R.x.dx = 0;
	__dpmi_int(0x21, &R);
}

int main(void)
{
	FILE *F;
	int H;
	int RC;

	int24_fail();

	F = fopen("SHTEST.DAT", "wb");
	fputs("share test\r\n", F);
	fclose(F);

	// the case that failed: deny-write holder, compat read-only opener
	pair("deny-write holder, compat read", 0x20, 0x00, 1);
	pair("deny-none holder, compat read", 0x40, 0x00, 1);
	pair("compat read holder, deny-write read", 0x00, 0x20, 1);
	pair("compat read holder, deny-none read", 0x00, 0x40, 1);

	// still refused
	pair("deny-write holder, compat WRITE", 0x20, 0x01, 0);
	pair("deny-write holder, compat read/write", 0x20, 0x02, 0);
	pair("deny-read/write holder, compat read", 0x10, 0x00, 0);
	pair("deny-read holder, compat read", 0x30, 0x00, 0);
	pair("compat WRITE holder, deny-write read", 0x01, 0x20, 0);
	pair("compat read holder, deny-read/write", 0x00, 0x10, 0);

	// the real thing: hold the program deny-write, then start it
	H = dopen("DJHELLO.EXE", 0x20);
	printf("    DJHELLO.EXE held deny-write: %d; starting it ...\n", H);
	RC = system("DJHELLO");
	printf("%s start a program held deny-write: rc %d (want 0)\n", RC == 0 ? "OK " : "BAD", RC);
	if (RC != 0)
		BAD++;
	dclose(H);

	remove("SHTEST.DAT");
	printf("SHARE: %d bad\n", BAD);
	return BAD;
}
