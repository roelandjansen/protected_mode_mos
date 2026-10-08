#include <stdio.h>
#include <time.h>
#include <i86.h>

//
// wtick - BIOS tick count at linear 46Ch, as a flat client sees it,
// against what real-mode int 1Ah ah=0 reports, twice, 2 s apart
//

static void show(const char *TAG)
{
	volatile unsigned long *P = (volatile unsigned long *)0x46c;
	volatile unsigned char *F = (volatile unsigned char *)0x470;
	union REGS R;

	R.h.ah = 0x00;
	int386(0x1a, &R, &R);
	printf("%s lin46C=%08lX lin470=%02X  int1Ah cx:dx=%04X%04X al=%02X\n",
	       TAG, *P, *F, R.w.cx, R.w.dx, R.h.al);
}

int main(void)
{
	clock_t C;

	show("A");
	C = clock();
	while (clock() - C < 2 * CLOCKS_PER_SEC)
		;
	show("B");
	return 0;
}
