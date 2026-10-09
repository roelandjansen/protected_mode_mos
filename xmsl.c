#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dpmi.h>

//
// xmsl - XMS query free; "xmsl n" also allocates n KB and exits
// WITHOUT freeing it (to test the cleanup when the task is removed)
//

int main(int ARGC, char **ARGV)
{
	__dpmi_regs R;
	unsigned short SEG;
	unsigned short OFS;

	memset(&R, 0, sizeof(R));
	R.x.ax = 0x4310;
	__dpmi_int(0x2f, &R);
	SEG = R.x.es;
	OFS = R.x.bx;
	if (ARGC > 1) {
		memset(&R, 0, sizeof(R));
		R.x.ax = 0x0900;
		R.x.dx = atoi(ARGV[1]);
		R.x.cs = SEG;
		R.x.ip = OFS;
		__dpmi_simulate_real_mode_procedure_retf(&R);
		printf("XMSL: allocate %s KB: ax=%u handle %u (kept)\n", ARGV[1], R.x.ax, R.x.dx);
	}
	memset(&R, 0, sizeof(R));
	R.x.ax = 0x0800;
	R.x.cs = SEG;
	R.x.ip = OFS;
	__dpmi_simulate_real_mode_procedure_retf(&R);
	printf("XMSL: free largest %u KB total %u KB\n", R.x.ax, R.x.dx);
	return 0;
}
