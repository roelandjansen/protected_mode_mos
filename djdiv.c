#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

//
// djdiv - a real 32-bit client exception: integer divide by zero in a
// DJGPP program with a SIGFPE handler (DJGPP hooks the exception with
// int 31h 0203h); the handler reports and exits 3
//

static volatile int ZERO;

//
// SIGFPE handler: report and leave
//

static void on_fpe(int SIG)
{
	printf("DJDIV: SIGFPE (%d) caught\n", SIG);
	exit(3);
}

int main(void)
{
	volatile int R;

	signal(SIGFPE, on_fpe);
	printf("DJDIV: dividing by zero\n");
	R = 100 / ZERO;
	printf("DJDIV: BAD, no exception (%d)\n", R);
	return 1;
}
