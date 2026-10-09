#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

//
// djill - exception 6 (#UD, "ud2") in a DJGPP program with a SIGILL
// handler that reports and exits 4. (DOSBox does not check segment
// limits or null selectors, so a #GP cannot be provoked here.)
//

static void on_ill(int SIG)
{
	printf("DJILL: OK  SIGILL (%d) caught\n", SIG);
	exit(4);
}

int main(void)
{
	signal(SIGILL, on_ill);
	printf("DJILL: ud2\n");
	__asm__ __volatile__("ud2");
	printf("DJILL: BAD no exception\n");
	return 1;
}
