#include <stdio.h>
#include <string.h>
#include <dos.h>
#include <i86.h>

//
// sweep - DOS API compatibility sweep (16-bit real mode, Open Watcom).
// Prints one line per call with the raw results, so the same binary
// can be run on a reference DOS and on PC-MOS and the outputs diffed.
// Uses only relative file names (no drive letters) for that reason.
//

static union REGS R;
static struct SREGS S;
static char BUF[256];

//
// int 21h with AX..DX, DS=ES=our data; returns carry
//

static int dos(unsigned AX, unsigned BX, unsigned CX, unsigned DX)
{
	segread(&S);
	R.x.ax = AX;
	R.x.bx = BX;
	R.x.cx = CX;
	R.x.dx = DX;
	R.x.si = 0;
	R.x.di = 0;
	int86x(0x21, &R, &R, &S);
	return R.x.cflag ? 1 : 0;
}

//
// Print "TAG cf ax bx cx dx" for the last call
//

static void show(const char *TAG, int CF)
{
	printf("%-10s cf=%d ax=%04X bx=%04X cx=%04X dx=%04X\n", TAG, CF, R.x.ax, R.x.bx, R.x.cx, R.x.dx);
}

//
// 59h extended error after a failing call: error, class, action, locus
//

static void exterr(const char *TAG)
{
	union REGS E;
	struct SREGS ES;

	segread(&ES);
	E.x.ax = 0x5900;
	E.x.bx = 0;
	int86x(0x21, &E, &E, &ES);
	printf("%-10s err=%04X class=%02X action=%02X locus=%02X\n", TAG, E.x.ax, E.h.bh, E.h.bl, E.h.ch);
}

//
// Version, system and process information
//

static void sysinfo(void)
{
	unsigned char far *P;
	unsigned SEG;
	int N;

	dos(0x3000, 0, 0, 0);
	printf("%-10s major=%u minor=%u oem=%02X\n", "30h", R.h.al, R.h.ah, R.h.bh);
	dos(0x3306, 0, 0, 0);
	printf("%-10s al=%02X true=%u.%u rev=%u flags=%02X\n", "3306h", R.h.al, R.h.bl, R.h.bh, R.h.dl, R.h.dh);
	dos(0x3305, 0, 0, 0);
	printf("%-10s al=%02X boot drive=%u\n", "3305h", R.h.al, R.h.dl);
	dos(0x3300, 0, 0, 0);
	printf("%-10s break=%u\n", "3300h", R.h.dl);
	dos(0x3700, 0, 0, 0);
	printf("%-10s al=%02X switchar=%c\n", "3700h", R.h.al, R.h.dl ? R.h.dl : '?');
	dos(0x5400, 0, 0, 0);
	printf("%-10s verify=%u\n", "54h", R.h.al);
	dos(0x1900, 0, 0, 0);
	printf("%-10s drive=%u\n", "19h", R.h.al);
	N = R.h.al;
	dos(0x0e00, 0, 0, N);
	printf("%-10s lastdrive count=%u\n", "0Eh", R.h.al);

	dos(0x5100, 0, 0, 0);
	SEG = R.x.bx;
	dos(0x6200, 0, 0, 0);
	printf("%-10s 51h==62h:%s psp int20=%s\n", "psp", SEG == R.x.bx ? "yes" : "NO",
	       *(unsigned far *)MK_FP(SEG, 0) == 0x20cd ? "yes" : "NO");
	dos(0x3400, 0, 0, 0);
	printf("%-10s indos ptr nonzero=%s\n", "34h", (S.es | R.x.bx) ? "yes" : "NO");

	// list of lists: first MCB, walk the chain, names
	dos(0x5200, 0, 0, 0);
	SEG = *(unsigned far *)MK_FP(S.es, R.x.bx - 2);
	printf("%-10s first mcb=%s\n", "52h", SEG ? "set" : "ZERO");
	for (N = 0; N < 40 && SEG; N++) {
		P = MK_FP(SEG, 0);
		if (P[0] != 'M' && P[0] != 'Z') {
			printf("%-10s chain broken at block %d (sig %02X)\n", "mcb", N, P[0]);
			break;
		}
		if (P[0] == 'Z') {
			printf("%-10s chain ok, %d blocks\n", "mcb", N + 1);
			break;
		}
		SEG += *(unsigned far *)(P + 3) + 1;
	}
}

//
// Country information
//

static void country(void)
{
	dos(0x3800, 0, 0, (unsigned)BUF);
	printf("%-10s cf=%d code=%u datefmt=%u cur=%.4s thou=%c dec=%c date=%c time=%c\n", "3800h",
	       R.x.cflag ? 1 : 0, R.x.bx, *(unsigned *)BUF, BUF + 2, BUF[7], BUF[9], BUF[11], BUF[13]);
	memset(BUF, 0, sizeof(BUF));
	segread(&S);
	R.x.ax = 0x6501;
	R.x.bx = 0xffff;
	R.x.dx = 0xffff;
	R.x.cx = 41;
	R.x.di = (unsigned)BUF;
	S.es = S.ds;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d id=%02X len=%u country=%u cp=%u\n", "6501h", R.x.cflag ? 1 : 0, BUF[0],
	       *(unsigned *)(BUF + 1), *(unsigned *)(BUF + 3), *(unsigned *)(BUF + 5));
	dos(0x6520, 0, 'a', 0);
	R.x.dx = 'a';
	R.x.ax = 0x6520;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d upcase('a')=%c\n", "6520h", R.x.cflag ? 1 : 0, R.h.dl);
	{
		unsigned char far *T;

		segread(&S);
		R.x.ax = 0x6502;
		R.x.bx = 0xffff;
		R.x.dx = 0xffff;
		R.x.cx = 5;
		R.x.di = (unsigned)BUF;
		S.es = S.ds;
		BUF[0] = 0;
		int86x(0x21, &R, &R, &S);
		T = *(unsigned char far * far *)(BUF + 1);
		printf("%-10s cf=%d id=%02X size=%u up(81h)=%02X\n", "6502h", R.x.cflag ? 1 : 0, BUF[0],
		       R.x.cflag ? 0 : *(unsigned far *)T, R.x.cflag ? 0 : T[2 + 1]);
		strcpy(BUF, "abc\x81xyz");
		segread(&S);
		R.x.ax = 0x6522;
		R.x.dx = (unsigned)BUF;
		int86x(0x21, &R, &R, &S);
		printf("%-10s cf=%d %s\n", "6522h", R.x.cflag ? 1 : 0, BUF);
		R.x.ax = 0x6523;
		R.x.dx = 'y';
		int86x(0x21, &R, &R, &S);
		printf("%-10s cf=%d y->%u\n", "6523h", R.x.cflag ? 1 : 0, R.x.ax);
	}
	dos(0x6601, 0, 0, 0);
	show("6601h", R.x.cflag);
}

//
// Files: create, write, seek, read, attributes, date/time, rename,
//
// 60h truename of NAME, printed without the drive letter
//

static void truename(const char *NAME)
{
	segread(&S);
	R.x.ax = 0x6000;
	R.x.si = (unsigned)NAME;
	R.x.di = (unsigned)BUF;
	S.es = S.ds;
	BUF[0] = 0;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X %s -> %s\n", "60h", R.x.cflag ? 1 : 0, R.x.cflag ? R.x.ax : 0, NAME,
	       R.x.cflag ? "-" : (BUF[1] == ':' ? BUF + 2 : BUF));
}

// dup, extended open, temp file, create-new, lock, commit, truename
//

static void files(void)
{
	unsigned H;
	unsigned H2;
	int CF;

	CF = dos(0x3c00, 0, 0, (unsigned)"SW1.TMP");
	H = R.x.ax;
	show("3Ch", CF);
	CF = dos(0x4000, H, 10, (unsigned)"0123456789");
	show("40h", CF);
	CF = dos(0x4202, H, 0xffff, 0xfffe);	// end - 2
	show("4202h -2", CF);
	CF = dos(0x4200, H, 0, 3);
	CF |= dos(0x3f00, H, 4, (unsigned)BUF);
	printf("%-10s cf=%d n=%u data=%.4s\n", "3Fh @3", CF, R.x.ax, BUF);
	CF = dos(0x4500, H, 0, 0);
	H2 = R.x.ax;
	show("45h dup", CF);
	CF = dos(0x4201, H2, 0, 0);
	show("4201h dup", CF);	// dup shares the file pointer: 7
	dos(0x3e00, H2, 0, 0);
	CF = dos(0x5700, H, 0, 0);
	printf("%-10s cf=%d time=%04X date=%04X\n", "5700h", CF, R.x.cx, R.x.dx);
	CF = dos(0x5701, H, 0x6000, 0x5949);	// 2024-10-09 12:00:00
	CF |= dos(0x5700, H, 0, 0);
	printf("%-10s cf=%d time=%04X date=%04X\n", "5701h", CF, R.x.cx, R.x.dx);
	CF = dos(0x6800, H, 0, 0);
	show("68h commit", CF);
	segread(&S);
	R.x.ax = 0x5c00;
	R.x.bx = H;
	R.x.cx = 0;
	R.x.dx = 0;
	R.x.si = 0;
	R.x.di = 4;
	int86x(0x21, &R, &R, &S);
	show("5Ch lock", R.x.cflag);
	R.x.ax = 0x5c01;
	R.x.bx = H;
	R.x.cx = 0;
	R.x.dx = 0;
	R.x.si = 0;
	R.x.di = 4;
	int86x(0x21, &R, &R, &S);
	show("5Ch unlock", R.x.cflag);
	dos(0x3e00, H, 0, 0);

	CF = dos(0x4300, 0, 0, (unsigned)"SW1.TMP");
	printf("%-10s cf=%d attr=%04X\n", "4300h", CF, R.x.cx);
	CF = dos(0x4301, 0, 0x01, (unsigned)"SW1.TMP");
	CF |= dos(0x4300, 0, 0, (unsigned)"SW1.TMP");
	printf("%-10s cf=%d attr=%04X\n", "4301h ro", CF, R.x.cx);
	CF = dos(0x3d01, 0, 0, (unsigned)"SW1.TMP");
	printf("%-10s cf=%d ax=%04X (want cf=1 ax=0005)\n", "3D01h ro", CF, R.x.ax);
	dos(0x4301, 0, 0x00, (unsigned)"SW1.TMP");

	segread(&S);
	R.x.ax = 0x5600;
	R.x.dx = (unsigned)"SW1.TMP";
	R.x.di = (unsigned)"SW2.TMP";
	S.es = S.ds;
	int86x(0x21, &R, &R, &S);
	show("56h ren", R.x.cflag);

	CF = dos(0x3d00, 0, 0, (unsigned)"NOFILE.XYZ");
	show("3Dh nofile", CF);
	exterr("59h");
	CF = dos(0x4100, 0, 0, (unsigned)"NOFILE.XYZ");
	show("41h nofile", CF);

	CF = dos(0x5b00, 0, 0, (unsigned)"SW2.TMP");
	show("5Bh exists", CF);	// want cf=1 ax=0050

	// 6Ch: open existing; create new; exists + fail
	segread(&S);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0001;		// open if exists, fail if not
	R.x.si = (unsigned)"SW2.TMP";
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X action=%u (want 1 opened)\n", "6Ch open", R.x.cflag ? 1 : 0, R.x.ax, R.x.cx);
	if (!R.x.cflag)
		dos(0x3e00, R.x.ax, 0, 0);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0010;		// create if not exists, fail if exists
	R.x.si = (unsigned)"SW3.TMP";
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X action=%u (want 2 created)\n", "6Ch create", R.x.cflag ? 1 : 0, R.x.ax, R.x.cx);
	if (!R.x.cflag)
		dos(0x3e00, R.x.ax, 0, 0);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0010;
	R.x.si = (unsigned)"SW3.TMP";
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X (want cf=1 ax=0050)\n", "6Ch exists", R.x.cflag ? 1 : 0, R.x.ax);

	// 5Ah temp file in the current directory
	strcpy(BUF, "");
	CF = dos(0x5a00, 0, 0, (unsigned)BUF);
	printf("%-10s cf=%d name=%s\n", "5Ah", CF, CF ? "-" : (BUF[0] ? "set" : "EMPTY"));
	if (!CF) {
		dos(0x3e00, R.x.ax, 0, 0);
		dos(0x4100, 0, 0, (unsigned)BUF);
	}

	// 60h truename
	segread(&S);
	R.x.ax = 0x6000;
	R.x.si = (unsigned)"sw2.tmp";
	R.x.di = (unsigned)BUF;
	S.es = S.ds;
	BUF[0] = 0;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d name=%s\n", "60h", R.x.cflag ? 1 : 0, strchr(BUF, '\\') ? strchr(BUF, '\\') : BUF);

	truename("\\A\\.\\B\\..\\C.TXT");
	truename("sub\\..\\x.y");
	truename("\\");
	truename("Q:FOO");
	dos(0x4100, 0, 0, (unsigned)"SW2.TMP");
	dos(0x4100, 0, 0, (unsigned)"SW3.TMP");
}

//
// Directories and search
//

static void dirs(void)
{
	int CF;
	int N;

	CF = dos(0x3900, 0, 0, (unsigned)"SWDIR");
	show("39h md", CF);
	CF = dos(0x3b00, 0, 0, (unsigned)"SWDIR");
	show("3Bh cd", CF);
	BUF[0] = 0;
	segread(&S);
	R.x.ax = 0x4700;
	R.x.dx = 0;
	R.x.si = (unsigned)BUF;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d cwd=%s\n", "47h", R.x.cflag ? 1 : 0, BUF);
	dos(0x3b00, 0, 0, (unsigned)"..");
	CF = dos(0x3a00, 0, 0, (unsigned)"SWDIR");
	show("3Ah rd", CF);
	CF = dos(0x3a00, 0, 0, (unsigned)"SWDIR");
	show("3Ah again", CF);	// want cf=1 ax=0003

	dos(0x1a00, 0, 0, (unsigned)BUF);
	CF = dos(0x4e00, 0, 0x08, (unsigned)"*.*");	// volume label
	printf("%-10s cf=%d attr=%02X\n", "4Eh label", CF, (unsigned char)BUF[21]);
	CF = dos(0x4e00, 0, 0x10, (unsigned)"*.*");
	for (N = 0; !CF && N < 500; N++)
		CF = dos(0x4f00, 0, 0, 0);
	printf("%-10s entries>0=%s end ax=%04X (want 0012)\n", "4E/4Fh", N > 0 ? "yes" : "NO", R.x.ax);
	CF = dos(0x4e00, 0, 0, (unsigned)"NOSUCH.*");
	show("4Eh none", CF);	// want cf=1 ax=0012 (or 0002)
}

//
// Memory, strategy, handles, IOCTL, date/time, misc
//

static void misc(void)
{
	unsigned SEG;
	int CF;

	CF = dos(0x4800, 0xffff, 0, 0);
	printf("%-10s cf=%d ax=%04X largest=%s\n", "48h max", CF, R.x.ax, R.x.bx ? "set" : "ZERO");
	CF = dos(0x4800, 0x10, 0, 0);
	SEG = R.x.ax;
	show("48h 16p", CF);
	segread(&S);
	S.es = SEG;
	R.x.ax = 0x4a00;
	R.x.bx = 0x20;
	int86x(0x21, &R, &R, &S);
	show("4Ah grow", R.x.cflag);
	R.x.ax = 0x4900;
	int86x(0x21, &R, &R, &S);
	show("49h", R.x.cflag);
	R.x.ax = 0x4900;
	int86x(0x21, &R, &R, &S);
	show("49h again", R.x.cflag);	// want cf=1 ax=0009

	dos(0x5800, 0, 0, 0);
	printf("%-10s strategy=%u\n", "5800h", R.x.ax);
	CF = dos(0x5801, 2, 0, 0);
	CF |= dos(0x5800, 0, 0, 0);
	printf("%-10s cf=%d strategy=%u\n", "5801h", CF, R.x.ax);
	dos(0x5801, 0, 0, 0);
	CF = dos(0x5802, 0, 0, 0);
	show("5802h umb", CF);

	CF = dos(0x6700, 40, 0, 0);
	show("67h 40", CF);

	CF = dos(0x4400, 0, 0, 0);
	show("4400h stdin", CF);
	CF = dos(0x4400, 1, 0, 0);
	show("4400h stdout", CF);
	CF = dos(0x4408, 0, 0, 0);
	show("4408h def", CF);
	CF = dos(0x4409, 0, 0, 0);
	show("4409h def", CF);
	CF = dos(0x440e, 0, 0, 0);
	show("440Eh def", CF);

	dos(0x2a00, 0, 0, 0);
	printf("%-10s year>=2024=%s dow<7=%s\n", "2Ah", R.x.cx >= 2024 ? "yes" : "NO", R.h.al < 7 ? "yes" : "NO");
	CF = dos(0x2b00, 0, 2026, 0x0d20);	// month 13: invalid
	printf("%-10s al=%02X (want FF)\n", "2Bh bad", R.h.al);
	dos(0x2c00, 0, 0, 0);
	printf("%-10s h<24=%s\n", "2Ch", R.h.ch < 24 ? "yes" : "NO");
	CF = dos(0x2d00, 0, 0x1900, 0);	// hour 25 (hex 19h): invalid
	printf("%-10s al=%02X (want FF)\n", "2Dh bad", R.h.al);

	dos(0x3600, 0, 0, 0);
	printf("%-10s spc=%u avail>0=%s bps=%u\n", "36h", R.x.ax, R.x.bx ? "yes" : "NO", R.x.cx);
	CF = dos(0x3600, 0, 0, 26);
	printf("%-10s ax=%04X (want FFFF)\n", "36h bad", R.x.ax);

	R.x.ax = 0x4300;
	int86(0x2f, &R, &R);
	printf("%-10s xms=%02X\n", "2F 4300h", R.h.al);
	R.x.ax = 0x1600;
	int86(0x2f, &R, &R);
	printf("%-10s windows=%02X\n", "2F 1600h", R.h.al);
	R.x.ax = 0x1687;
	int86(0x2f, &R, &R);
	printf("%-10s dpmi ax=%04X\n", "2F 1687h", R.x.ax);
	R.x.ax = 0x7147;
	R.x.dx = 0;
	R.x.si = (unsigned)BUF;
	R.x.cflag = 0;
	segread(&S);
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X (LFN: 7100h = not supported)\n", "7147h", R.x.cflag ? 1 : 0, R.x.ax);
}

int main(void)
{
	sysinfo();
	country();
	files();
	dirs();
	misc();
	printf("SWEEP DONE\n");
	return 0;
}
