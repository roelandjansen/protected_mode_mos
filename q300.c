#include <stdio.h>
#include <string.h>
#include <dpmi.h>

//
// q300 - bracketed 0300h calls for a gated monitor trace:
// 0400h marker, N x 0300h (int 21h ah=30h), 0400h marker
//

int main(void)
{
	__dpmi_version_ret V;
	__dpmi_regs R;
	int I;

	__dpmi_get_version(&V);
	for (I = 0; I < 4; I++) {
		memset(&R, 0, sizeof(R));
		R.h.ah = 0x30;
		__dpmi_simulate_real_mode_interrupt(0x21, &R);
	}
	__dpmi_get_version(&V);
	printf("Q300 ax=%04X\n", R.x.ax);
	return 0;
}
