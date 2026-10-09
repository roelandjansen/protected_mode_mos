#include <stdio.h>
#include <dpmi.h>
#include <sys/segments.h>

//
// djexc0 - host delivery of #DE to a DJGPP (flat 32-bit) client's own
// 0203h handler, bypassing DJGPP's runtime handler. The handler counts
// and skips the 2-byte "divl %ecx" (frame eip at esp+12)
//

volatile int HIT;
extern void exc_handler(void);
extern int exc_ds;

__asm__(
	".globl _exc_handler\n"
	"_exc_handler:\n\t"
	"pushl %ds\n\t"
	"movw %cs:_exc_ds,%ds\n\t"
	"incl _HIT\n\t"
	"popl %ds\n\t"
	"addl $2,12(%esp)\n\t"
	"lret\n"
	".data\n"
	".globl _exc_ds\n"
	"_exc_ds: .long 0\n"
	".text\n");

int main(void)
{
	__dpmi_paddr OLD;
	__dpmi_paddr NEW;
	unsigned int Q;

	exc_ds = _my_ds();
	__dpmi_get_processor_exception_handler_vector(0, &OLD);
	NEW.selector = _my_cs();
	NEW.offset32 = (unsigned long)exc_handler;
	if (__dpmi_set_processor_exception_handler_vector(0, &NEW) != 0) {
		printf("DJEXC0: BAD 0203h refused\n");
		return 1;
	}
	__asm__ __volatile__("xorl %%ecx,%%ecx\n\tmovl $100,%%eax\n\txorl %%edx,%%edx\n\tdivl %%ecx"
			     : "=a"(Q) : : "ecx", "edx");
	__dpmi_set_processor_exception_handler_vector(0, &OLD);
	printf("DJEXC0: %s handler hits %d\n", HIT == 1 ? "OK " : "BAD", HIT);
	return HIT != 1;
}
