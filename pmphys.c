#include <stdio.h>
#include <string.h>
#include <dpmi.h>
#include <go32.h>
#include <sys/farptr.h>
#include <sys/movedata.h>

//
// pmphys - int 31h 0800h: map the VESA linear frame buffer and check
// that it reaches video memory (text mode: VRAM byte 0/1 = the first
// character/attribute at B800:0000), plus the refusals and reuse
//

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
// Physical address of the frame buffer from VBE 4F01h (mode 101h)
//

static unsigned long lfb_address(void)
{
	__dpmi_regs R;
	unsigned char INFO[256];

	memset(&R, 0, sizeof(R));
	R.x.ax = 0x4f01;
	R.x.cx = 0x101;
	R.x.es = __tb >> 4;
	R.x.di = __tb & 15;
	__dpmi_int(0x10, &R);
	if (R.x.ax != 0x004f)
		return 0;
	dosmemget(__tb, sizeof(INFO), INFO);
	return *(unsigned long *)(INFO + 0x28);
}

//
// Map ADDR/SIZE with 0800h; 0 if refused
//

static unsigned long map(unsigned long ADDR, unsigned long SIZE)
{
	__dpmi_meminfo M;

	M.handle = 0;
	M.address = ADDR;
	M.size = SIZE;
	if (__dpmi_physical_address_mapping(&M) != 0)
		return 0;
	return M.address;
}

int main(void)
{
	unsigned long PHYS;
	unsigned long LIN;
	unsigned long LIN2;
	int SEL;
	unsigned char VRAM[4];
	unsigned char SCREEN[2];

	PHYS = lfb_address();
	printf("VBE frame buffer at %08lX\n", PHYS);
	check("VBE 4F01h gives a frame buffer", PHYS != 0);
	if (PHYS == 0)
		return 1;

	LIN = map(PHYS, 0x400000);
	printf("0800h %08lX, 4 MB -> linear %08lX\n", PHYS, LIN);
	check("0800h maps 4 MB", LIN != 0);
	if (LIN == 0)
		return 1;

	SEL = __dpmi_allocate_ldt_descriptors(1);
	__dpmi_set_segment_base_address(SEL, LIN);
	__dpmi_set_segment_limit(SEL, 0x3fffff);
	VRAM[0] = _farpeekb(SEL, 0);
	VRAM[1] = _farpeekb(SEL, 1);
	dosmemget(0xb8000, 2, SCREEN);
	printf("VRAM via 0800h: %02X %02X   B800:0000: %02X %02X\n",
	       VRAM[0], VRAM[1], SCREEN[0], SCREEN[1]);
	check("mapped memory is video memory", VRAM[0] == SCREEN[0] && VRAM[1] == SCREEN[1]);
	_farpokeb(SEL, 0, 0x5a);			// 'Z' through the mapping ...
	dosmemget(0xb8000, 2, SCREEN);		// ... seen at B800:0000
	check("write via 0800h appears at B800:0000", SCREEN[0] == 0x5a);
	_farpokeb(SEL, 0, VRAM[0]);

	_farpokel(SEL, 0x3f0000, 0x5aa55aa5);	// off screen
	_farpokel(SEL, 0x3f0004, 0x12345678);
	check("write / read back at +3F0000h",
	      _farpeekl(SEL, 0x3f0000) == 0x5aa55aa5 && _farpeekl(SEL, 0x3f0004) == 0x12345678);

	LIN2 = map(PHYS, 0x400000);
	check("same range again: same linear", LIN2 == LIN);
	LIN2 = map(PHYS + 0x100000, 0x10000);
	check("inside the same 4 MB: linear = physical", LIN2 == PHYS + 0x100000);

	check("below 1 MB refused", map(0xa0000, 0x10000) == 0);
	check("size 0 refused", map(PHYS, 0) == 0);
	check("wrap past 4 GB refused", map(0xfffff000, 0x2000) == 0);
	check("RAM's linear space refused", map(0x200000, 0x1000) == 0);

	__dpmi_free_ldt_descriptor(SEL);
	printf("PMPHYS: %d bad\n", BAD);
	return BAD;
}
