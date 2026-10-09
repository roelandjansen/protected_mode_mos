#include <stdio.h>
#include <string.h>
#include <dpmi.h>
#include <go32.h>
#include <sys/farptr.h>
#include <sys/movedata.h>

//
// lfbdraw - a real graphics client of int 31h 0800h: VBE mode 101h
// (640x480x8) with the linear frame buffer, draw through the mapping,
// then read the same pixels back through the banked window at A000h
// (VBE 4F05h), which does not use the mapping at all
//

#define W 640
#define H 480

static int BAD;

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
// VBE 4F01h for mode 101h into INFO; 1 if supported
//

static int mode_info(unsigned char *INFO)
{
	__dpmi_regs R;

	memset(&R, 0, sizeof(R));
	R.x.ax = 0x4f01;
	R.x.cx = 0x101;
	R.x.es = __tb >> 4;
	R.x.di = __tb & 15;
	__dpmi_int(0x10, &R);
	if (R.x.ax != 0x004f)
		return 0;
	dosmemget(__tb, 256, INFO);
	return 1;
}

//
// Set a video mode through VBE 4F02h (or int 10h 00h for mode 3)
//

static int set_mode(unsigned int MODE)
{
	__dpmi_regs R;

	memset(&R, 0, sizeof(R));
	if (MODE == 3) {
		R.x.ax = 0x0003;
		__dpmi_int(0x10, &R);
		return 1;
	}
	R.x.ax = 0x4f02;
	R.x.bx = MODE;
	__dpmi_int(0x10, &R);
	return R.x.ax == 0x004f;
}

//
// Select bank N in window A (VBE 4F05h)
//

static void bank(unsigned int N)
{
	__dpmi_regs R;

	memset(&R, 0, sizeof(R));
	R.x.ax = 0x4f05;
	R.x.bx = 0;
	R.x.dx = N;
	__dpmi_int(0x10, &R);
}

//
// The test pattern: a function of the pixel position
//

static unsigned char pattern(unsigned long OFS)
{
	unsigned long X = OFS % W;
	unsigned long Y = OFS / W;

	return (unsigned char)((X / 8) ^ (Y / 4) ^ (Y << 3));
}

int main(void)
{
	unsigned char INFO[256];
	unsigned char ROW[W];
	unsigned long PHYS;
	unsigned long OFS;
	unsigned long GRAN;
	unsigned long SIZE;
	unsigned long DIFF;
	unsigned long BDIFF;
	unsigned int N;
	__dpmi_meminfo M;
	int SEL;

	if (!mode_info(INFO)) {
		printf("BAD no VBE mode 101h\n");
		return 1;
	}
	PHYS = *(unsigned long *)(INFO + 0x28);
	GRAN = (unsigned long)*(unsigned short *)(INFO + 4) * 1024;
	printf("    mode 101h attr %04X, LFB %08lX, granularity %lu\n",
	       *(unsigned short *)INFO, PHYS, GRAN);
	check("mode 101h has a linear frame buffer", (INFO[0] & 0x80) && PHYS);

	SIZE = W * H;
	M.handle = 0;
	M.address = PHYS;
	M.size = (SIZE + 4095) & ~4095UL;
	check("0800h maps the frame buffer", __dpmi_physical_address_mapping(&M) == 0);
	SEL = __dpmi_allocate_ldt_descriptors(1);
	__dpmi_set_segment_base_address(SEL, M.address);
	__dpmi_set_segment_limit(SEL, M.size - 1);

	check("set mode 4101h (LFB)", set_mode(0x4101));

	// draw a row at a time through the mapping, read it back the same way
	DIFF = 0;
	for (OFS = 0; OFS < SIZE; OFS += W) {
		for (N = 0; N < W; N++)
			ROW[N] = pattern(OFS + N);
		movedata(_my_ds(), (unsigned)ROW, SEL, OFS, W);
	}
	for (OFS = 0; OFS < SIZE; OFS++)
		if (_farpeekb(SEL, OFS) != pattern(OFS))
			DIFF++;

	// read it back through the banked window (no mapping involved)
	set_mode(0x0101 | 0x8000);	// same mode, banked, keep the contents
	BDIFF = 0;
	for (OFS = 0; OFS < SIZE; OFS++) {
		if (OFS % GRAN == 0)
			bank(OFS / GRAN);
		if (_farpeekb(_dos_ds, 0xa0000 + OFS % GRAN) != pattern(OFS))
			BDIFF++;
	}

	set_mode(3);
	printf("    %lu pixels: %lu differ via LFB, %lu via the A000h window\n", SIZE, DIFF, BDIFF);
	check("LFB read back", DIFF == 0);
	check("same pixels through the banked window", BDIFF == 0);
	printf("    0801h (DPMI 1.0, not in 0.9): %s\n", __dpmi_free_physical_address_mapping(&M) == 0 ? "freed" : "refused");
	printf("LFBDRAW: %d bad\n", BAD);
	return BAD;
}
