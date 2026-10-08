#include <stdio.h>
#include <time.h>
#include <i86.h>

//
// wtime - time() against raw int 21h 2Ah/2Ch, twice, 2 s apart
//

static void show(const char *TAG)
{
	union REGS R;
	time_t T;
	struct tm *TM;

	T = time(NULL);
	TM = localtime(&T);
	R.h.ah = 0x2c;
	int386(0x21, &R, &R);
	printf("%s time() %02d:%02d:%02d  2Ch %02d:%02d:%02d.%02d",
	       TAG, TM->tm_hour, TM->tm_min, TM->tm_sec,
	       R.h.ch, R.h.cl, R.h.dh, R.h.dl);
	R.h.ah = 0x2a;
	int386(0x21, &R, &R);
	printf("  2Ah %04d-%02d-%02d  tm %04d-%02d-%02d\n",
	       R.w.cx, R.h.dh, R.h.dl,
	       TM->tm_year + 1900, TM->tm_mon + 1, TM->tm_mday);
}

int main(void)
{
	clock_t C;

	show("A");
	C = clock();
	while (clock() - C < 2 * CLOCKS_PER_SEC)
		;
	show("B");
	return 0;
}
