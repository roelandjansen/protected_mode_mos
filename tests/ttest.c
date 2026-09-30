#include <stdio.h>
#include <time.h>

int main(void)
{
	clock_t T0;
	clock_t T;
	unsigned long LOOPS = 0;

	T0 = clock();
	do {
		LOOPS++;
		T = clock();
	} while ((T - T0) < 3 * CLOCKS_PER_SEC);
	printf("TTEST: %ld ticks of %ld/s, %lu loops\n", (long)(T - T0), (long)CLOCKS_PER_SEC, LOOPS);
	return 0;
}
