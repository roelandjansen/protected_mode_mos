#include <stdio.h>
#include <string.h>
#include <dos.h>
#include <i86.h>

//
// sweep2 - DOS API sweep, part 2 (16-bit real mode, Open Watcom):
// int 2Fh multiplex, IOCTL (44h), disk information (1Bh/1Ch/1Fh/32h/36h,
// 440Dh), extended open (6Ch), serial (69h), commit (68h), file time
// (57h), locking (5Ch), temp/new files (5Ah/5Bh), redirection list
// (5F02h). Default drive only, relative names, so the same binary runs
// on a reference DOS and on PC-MOS and the outputs can be diffed.
//

static union REGS R;
static struct SREGS S;
static unsigned char BUF[512];

//
// int 21h with AX..DX, DS=ES=our data, SI=DI=0; returns carry
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
// int 2Fh with AX, BX=CX=DX=0; returns AX
//

static unsigned mux(unsigned AX)
{
	segread(&S);
	R.x.ax = AX;
	R.x.bx = 0;
	R.x.cx = 0;
	R.x.dx = 0;
	int86x(0x2f, &R, &R, &S);
	return R.x.ax;
}


//
// Hex dump of the first N bytes of BUF
//

static void hexbuf(const char *TAG, int N)
{
	int I;

	printf("%-10s", TAG);
	for (I = 0; I < N; I++)
		printf(" %02X", BUF[I]);
	printf("\n");
}
//
// Print "TAG cf ax bx cx dx"
//

static void show(const char *TAG, int CF)
{
	printf("%-10s cf=%d ax=%04X bx=%04X cx=%04X dx=%04X\n", TAG, CF, R.x.ax, R.x.bx, R.x.cx, R.x.dx);
}

//
// int 2Fh installation checks
//

static void multiplex(void)
{
	static const unsigned F[] = { 0x0100, 0x1000, 0x1100, 0x1400, 0x1600, 0x1a00, 0x4300,
				      0x4800, 0xad00, 0xb700, 0x4a10, 0x1689 };
	int I;

	for (I = 0; I < (int)(sizeof(F) / sizeof(F[0])); I++) {
		char T[12];
		sprintf(T, "2F%04Xh", F[I]);
		mux(F[I]);
		printf("%-10s al=%02X\n", T, R.h.al);
	}
}

//
// IOCTL on handles and on the default drive
//

static void ioctl(void)
{
	int CF;
	unsigned H;
	unsigned D;

	dos(0x1900, 0, 0, 0);
	D = R.h.al + 1;

	CF = dos(0x4400, 1, 0, 0);
	show("4400 out", CF);
	CF = dos(0x3c00, 0, 0, (unsigned)"SW2.TMP");
	H = R.x.ax;
	CF = dos(0x4400, H, 0, 0);
	printf("%-10s cf=%d dx&3F=%02X dx&C0=%02X\n", "4400 file", CF, R.x.dx & 0x3f, R.x.dx & 0xc0);
	CF = dos(0x4406, H, 0, 0);
	printf("%-10s cf=%d al=%02X\n", "4406 file", CF, R.h.al);
	CF = dos(0x4407, H, 0, 0);
	printf("%-10s cf=%d al=%02X\n", "4407 file", CF, R.h.al);
	CF = dos(0x440a, H, 0, 0);
	printf("%-10s cf=%d ax=%04X dx&8000=%04X\n", "440A file", CF, R.x.ax, R.x.dx & 0x8000);
	CF = dos(0x4401, H, 0, 0x0040);
	printf("%-10s cf=%d ax=%04X\n", "4401 file", CF, CF ? R.x.ax : 0);
	CF = dos(0x6800, H, 0, 0);
	printf("%-10s cf=%d\n", "6800h", CF);
	R.x.si = 0;
	R.x.di = 10;
	segread(&S);
	R.x.ax = 0x5c00;
	R.x.bx = H;
	R.x.cx = 0;
	R.x.dx = 0;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "5C00 lock", R.x.cflag ? 1 : 0, R.x.cflag ? R.x.ax : 0);
	R.x.ax = 0x5c01;
	R.x.bx = H;
	R.x.cx = 0;
	R.x.dx = 0;
	R.x.si = 0;
	R.x.di = 10;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "5C01 unlk", R.x.cflag ? 1 : 0, R.x.cflag ? R.x.ax : 0);
	R.x.ax = 0x5c01;
	R.x.bx = H;
	R.x.cx = 0;
	R.x.dx = 0;
	R.x.si = 0;
	R.x.di = 10;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "5C01 again", R.x.cflag ? 1 : 0, R.x.cflag ? R.x.ax : 0);
	CF = dos(0x5700, H, 0, 0);
	printf("%-10s cf=%d time-set=%s\n", "5700h", CF, (R.x.cx | R.x.dx) ? "yes" : "NO");
	CF = dos(0x5701, H, 0x6000, 0x5821);
	printf("%-10s cf=%d\n", "5701h", CF);
	CF = dos(0x5700, H, 0, 0);
	printf("%-10s cf=%d cx=%04X dx=%04X\n", "5700 back", CF, R.x.cx, R.x.dx);
	dos(0x3e00, H, 0, 0);
	dos(0x4100, 0, 0, (unsigned)"SW2.TMP");

	CF = dos(0x4408, 0, 0, 0);
	printf("%-10s cf=%d ax=%04X\n", "4408 dflt", CF, R.x.ax);
	CF = dos(0x4408, 26, 0, 0);
	printf("%-10s cf=%d ax=%04X\n", "4408 Z:", CF, R.x.ax);
	CF = dos(0x4409, 0, 0, 0);
	printf("%-10s cf=%d dx&9200=%04X\n", "4409 dflt", CF, R.x.dx & 0x9200);
	CF = dos(0x4409, 26, 0, 0);
	printf("%-10s cf=%d ax=%04X\n", "4409 Z:", CF, R.x.ax);
	CF = dos(0x440e, 0, 0, 0);
	printf("%-10s cf=%d al=%02X\n", "440E dflt", CF, R.h.al);
	CF = dos(0x4411, 0, 0x0860, 0);
	printf("%-10s cf=%d ax=%04X\n", "4411 0860", CF, R.x.ax);
	CF = dos(0x4411, 0, 0x0866, 0);
	printf("%-10s cf=%d ax=%04X\n", "4411 0866", CF, R.x.ax);

	memset(BUF, 0, sizeof(BUF));
	CF = dos(0x440d, 0, 0x0860, (unsigned)BUF);
	printf("%-10s cf=%d ax=%04X devtype=%u bps=%u spc=%u res=%u fats=%u root=%u media=%02X\n", "440D 0860",
	       CF, CF ? R.x.ax : 0, BUF[1], *(unsigned *)(BUF + 7), BUF[9], *(unsigned *)(BUF + 10), BUF[12],
	       *(unsigned *)(BUF + 13), BUF[17]);
	memset(BUF, 0, sizeof(BUF));
	CF = dos(0x440d, 0, 0x0866, (unsigned)BUF);
	printf("%-10s cf=%d ax=%04X fs=%.8s\n", "440D 0866", CF, CF ? R.x.ax : 0, CF ? "" : (char *)BUF + 17);
	hexbuf("0866 raw", 25);
	CF = dos(0x4400 | 0x0d, 0, 0x0867, (unsigned)BUF);
	printf("%-10s cf=%d ax=%04X\n", "440D 0867", CF, CF ? R.x.ax : 0);
	(void)D;
}

//
// Disk information calls, results relative to each other
//

static void disk(void)
{
	int CF;
	unsigned SPC;
	unsigned BPS;
	unsigned CL;
	unsigned char far *P;

	CF = dos(0x3600, 0, 0, 0);
	SPC = R.x.ax;
	BPS = R.x.cx;
	CL = R.x.dx;
	printf("%-10s cf=%d spc=%u bps=%u clusters=%u free>0=%s\n", "36h", CF, SPC, BPS, CL, R.x.bx ? "yes" : "NO");
	CF = dos(0x3600, 0, 0, 26);
	printf("%-10s ax=%04X\n", "36h Z:", R.x.ax);

	dos(0x1b00, 0, 0, 0);
	printf("%-10s spc=%u bps=%u clusters=%u same-as-36h=%s\n", "1Bh", R.h.al, R.x.cx, R.x.dx,
	       (R.h.al == SPC && R.x.cx == BPS && R.x.dx == CL) ? "yes" : "NO");
	dos(0x1c00, 0, 0, 0);
	printf("%-10s spc=%u bps=%u clusters=%u\n", "1Ch dflt", R.h.al, R.x.cx, R.x.dx);
	dos(0x1c00, 0, 0, 26);
	printf("%-10s al=%02X\n", "1Ch Z:", R.h.al);

	segread(&S);
	R.x.ax = 0x1f00;
	int86x(0x21, &R, &R, &S);
	if (R.h.al == 0) {
		P = MK_FP(S.ds, R.x.bx);
		printf("%-10s al=00 bps=%u spc=%u shift=%u res=%u fats=%u root=%u data=%u maxcl=%u same=%s\n",
		       "1Fh", *(unsigned far *)(P + 2), P[4] + 1, P[5], *(unsigned far *)(P + 6), P[8],
		       *(unsigned far *)(P + 9), *(unsigned far *)(P + 11), *(unsigned far *)(P + 13),
		       (*(unsigned far *)(P + 13) - 1 == CL) ? "yes" : "NO");
	} else {
		printf("%-10s al=%02X\n", "1Fh", R.h.al);
	}
	segread(&S);
	R.x.ax = 0x3200;
	R.x.dx = 0;
	int86x(0x21, &R, &R, &S);
	printf("%-10s al=%02X\n", "32h dflt", R.h.al);
	segread(&S);
	R.x.ax = 0x3200;
	R.x.dx = 26;
	int86x(0x21, &R, &R, &S);
	printf("%-10s al=%02X\n", "32h Z:", R.h.al);

	memset(BUF, 0, sizeof(BUF));
	segread(&S);
	R.x.ax = 0x6900;
	R.x.bx = 0;
	R.x.dx = (unsigned)BUF;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X fs=%.8s\n", "6900h", R.x.cflag ? 1 : 0, R.x.cflag ? R.x.ax : 0,
	       R.x.cflag ? "" : (char *)BUF + 17);
	hexbuf("6900 raw", 25);
	R.x.ax = 0x6902;
	R.x.bx = 0;
	R.x.dx = (unsigned)BUF;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "6902h", R.x.cflag ? 1 : 0, R.x.ax);
	R.x.ax = 0x6900;
	R.x.bx = 26;
	R.x.dx = (unsigned)BUF;
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "6900 Z:", R.x.cflag ? 1 : 0, R.x.ax);
}

//
// Extended open, temp and new files, redirection list
//

static void files(void)
{
	int CF;
	unsigned H;
	int N;
	char T[80];

	segread(&S);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0012;
	R.x.si = (unsigned)"SW2X.TMP";
	int86x(0x21, &R, &R, &S);
	CF = R.x.cflag ? 1 : 0;
	H = R.x.ax;
	printf("%-10s cf=%d action=%u\n", "6C create", CF, R.x.cx);
	if (!CF)
		dos(0x3e00, H, 0, 0);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0001;
	R.x.si = (unsigned)"SW2X.TMP";
	int86x(0x21, &R, &R, &S);
	CF = R.x.cflag ? 1 : 0;
	printf("%-10s cf=%d action=%u\n", "6C open", CF, R.x.cx);
	if (!CF)
		dos(0x3e00, R.x.ax, 0, 0);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0010;
	R.x.si = (unsigned)"SW2X.TMP";
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "6C excl", R.x.cflag ? 1 : 0, R.x.ax);
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0002;
	R.x.si = (unsigned)"SW2X.TMP";
	int86x(0x21, &R, &R, &S);
	CF = R.x.cflag ? 1 : 0;
	printf("%-10s cf=%d action=%u\n", "6C trunc", CF, R.x.cx);
	if (!CF)
		dos(0x3e00, R.x.ax, 0, 0);
	dos(0x4100, 0, 0, (unsigned)"SW2X.TMP");
	R.x.ax = 0x6c00;
	R.x.bx = 0x0002;
	R.x.cx = 0;
	R.x.dx = 0x0001;
	R.x.si = (unsigned)"SW2X.TMP";
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "6C nofile", R.x.cflag ? 1 : 0, R.x.ax);

	CF = dos(0x5b00, 0, 0, (unsigned)"SW2N.TMP");
	printf("%-10s cf=%d\n", "5Bh new", CF);
	if (!CF)
		dos(0x3e00, R.x.ax, 0, 0);
	CF = dos(0x5b00, 0, 0, (unsigned)"SW2N.TMP");
	printf("%-10s cf=%d ax=%04X\n", "5Bh again", CF, R.x.ax);
	dos(0x4100, 0, 0, (unsigned)"SW2N.TMP");

	strcpy(T, ".\\");
	CF = dos(0x5a00, 0, 0, (unsigned)T);
	N = (int)strlen(T);
	printf("%-10s cf=%d namelen=%d\n", "5Ah temp", CF, N);
	if (!CF) {
		dos(0x3e00, R.x.ax, 0, 0);
		dos(0x4100, 0, 0, (unsigned)T);
	}

	CF = dos(0x4300, 0, 0, (unsigned)"NOFILE.XYZ");
	printf("%-10s cf=%d ax=%04X\n", "4300 nf", CF, R.x.ax);

	segread(&S);
	R.x.ax = 0x5f02;
	R.x.bx = 0;
	R.x.si = (unsigned)BUF;
	R.x.di = (unsigned)(BUF + 128);
	int86x(0x21, &R, &R, &S);
	printf("%-10s cf=%d ax=%04X\n", "5F02h", R.x.cflag ? 1 : 0, R.x.ax);
}

int main(void)
{
	multiplex();
	ioctl();
	disk();
	files();
	printf("END\n");
	return 0;
}
