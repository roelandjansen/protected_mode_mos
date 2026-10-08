#include <stdio.h>
#include <dpmi.h>

//
// pmwatch - int 31h 0B00h-0B03h (debug watchpoints): the host has none,
// so every call must fail cleanly (cf set) and the client carry on
//

int main(void)
{
	__dpmi_meminfo M;
	int H;
	int S;
	int R0;
	int R1;
	int R2;
	static int X;

	M.address = (unsigned long)&X;		// a linear-ish address
	M.size = 4;
	H = __dpmi_set_debug_watchpoint(&M, 1);	// 0B00h, write
	R0 = __dpmi_get_state_of_debug_watchpoint(0, &S);	// 0B02h
	R1 = __dpmi_reset_debug_watchpoint(0);		// 0B03h
	R2 = __dpmi_clear_debug_watchpoint(0);		// 0B01h
	printf("PMWATCH 0B00h=%d 0B02h=%d 0B03h=%d 0B01h=%d %s\n", H, R0, R1, R2,
	       (H == -1 && R0 == -1 && R1 == -1 && R2 == -1) ? "all refused: ok" : "CHECK");
	return 0;
}
