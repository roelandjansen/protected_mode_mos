#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <dpmi.h>
#include <sys/segments.h>

//
// djdiv2 - DJGPP's own exception path for #DE: show exception 0's
// handler right before the fault, then "divl %ecx" with ecx = 0 and a
// SIGFPE handler that reports and exits 3
//

static void on_fpe(int SIG)
{
	printf("DJDIV2: OK  SIGFPE (%d) caught\n", SIG);
	exit(3);
}

int main(void)
{
	__dpmi_paddr P;
	unsigned int Q;

	signal(SIGFPE, on_fpe);
	__dpmi_get_processor_exception_handler_vector(0, &P);
	printf("DJDIV2: cs %04X ds %04X ss %04X, exc 0 -> %04X:%08lX\n",
	       _my_cs(), _my_ds(), _my_ss(), P.selector, P.offset32);
	__asm__ __volatile__("xorl %%ecx,%%ecx\n\tmovl $100,%%eax\n\txorl %%edx,%%edx\n\tdivl %%ecx"
			     : "=a"(Q) : : "ecx", "edx");
	printf("DJDIV2: BAD no exception (%u)\n", Q);
	return 1;
}
