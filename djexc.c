#include <stdio.h>
#include <dpmi.h>
#include <sys/segments.h>

//
// djexc - what a DJGPP program has hooked: 0202h for exceptions 0-0Eh,
// against the program's own cs
//

int main(void)
{
	__dpmi_paddr P;
	int E;

	printf("DJEXC: cs %04X\n", _my_cs());
	for (E = 0; E < 0x0f; E++) {
		if (__dpmi_get_processor_exception_handler_vector(E, &P) != 0) {
			printf("  %02X: refused\n", E);
			continue;
		}
		printf("  %02X: %04X:%08lX%s\n", E, P.selector, P.offset32,
		       P.selector == _my_cs() ? " (own)" : "");
	}
	return 0;
}
