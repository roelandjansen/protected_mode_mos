#include <stdio.h>
#include <string.h>
#include <time.h>
#include <dpmi.h>
#include <stdlib.h>

static int N = 2000;

static double secs(clock_t A, clock_t B)
{
	return (double)(B - A) / CLOCKS_PER_SEC;
}

int main(int ARGC, char **ARGV)
{
	clock_t T0, T1;
	if (ARGC > 1) N = atoi(ARGV[1]);
	int I;
	volatile unsigned long X = 0;
	__dpmi_version_ret V;
	__dpmi_regs R;
	__dpmi_meminfo M;

	T0 = clock();
	for (I = 0; I < N * 5000; I++)
		X += I;
	T1 = clock();
	printf("BENCH cpu loop      : %6.2f s\n", secs(T0, T1));

	T0 = clock();
	for (I = 0; I < N; I++)
		__dpmi_get_version(&V);
	T1 = clock();
	printf("BENCH %d x 0400h  : %6.2f s\n", N, secs(T0, T1));

	T0 = clock();
	for (I = 0; I < N; I++) {
		memset(&R, 0, sizeof(R));
		R.h.ah = 0x30;
		__dpmi_simulate_real_mode_interrupt(0x21, &R);
	}
	T1 = clock();
	printf("BENCH %d x 0300h  : %6.2f s\n", N, secs(T0, T1));

	T0 = clock();
	for (I = 0; I < N; I++) {
		M.size = 65536;
		if (__dpmi_allocate_memory(&M) == 0)
			__dpmi_free_memory(M.handle);
	}
	T1 = clock();
	printf("BENCH %d x 0501+2 : %6.2f s\n", N, secs(T0, T1));
	return 0;
}
