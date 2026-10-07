#include <stdio.h>
#include <dpmi.h>

//
// q900 - virtual interrupt state functions 0900h-0902h, plus
// 0300h and 0501h/0502h around them so the fast path order matters
//

int main(void)
{
	int A;
	int B;
	int C;
	int D;
	int E;
	__dpmi_meminfo M;
	__dpmi_regs R = {0};

	A = __dpmi_get_virtual_interrupt_state();
	B = __dpmi_get_and_disable_virtual_interrupt_state();
	C = __dpmi_get_virtual_interrupt_state();
	D = __dpmi_get_and_enable_virtual_interrupt_state();
	E = __dpmi_get_virtual_interrupt_state();
	printf("Q900 0902:%d 0900:%d 0902:%d 0901:%d 0902:%d\n", A, B, C, D, E);
	R.h.ah = 0x30;
	__dpmi_simulate_real_mode_interrupt(0x21, &R);
	M.size = 4096;
	A = __dpmi_allocate_memory(&M);
	B = A == 0 ? __dpmi_free_memory(M.handle) : -2;
	printf("Q900 0300 ax=%04X 0501:%d 0502:%d %s\n", R.x.ax, A, B,
		(D == 0 && C == 0 && B == 0 && A == 0) ? "ok" : "check");
	return 0;
}
