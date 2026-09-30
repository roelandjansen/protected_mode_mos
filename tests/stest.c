#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dos.h>

#define SLOTS 2000
#define ROUNDS 60000
#define NSORT 100000

static unsigned long SEED = 12345;

static unsigned long rnd(void)
{
	SEED = SEED * 1103515245ul + 12345ul;
	return (SEED >> 8) & 0xffffff;
}

static int cmp(const void *A, const void *B)
{
	unsigned long X = *(const unsigned long *)A;
	unsigned long Y = *(const unsigned long *)B;
	return (X > Y) - (X < Y);
}

int main(void)
{
	static unsigned char *P[SLOTS];
	static unsigned short SZ[SLOTS];
	unsigned long *A;
	unsigned long R, I;
	unsigned long BAD = 0, SORTBAD = 0, NFILES = 0;
	time_t T0;
	struct tm *TM;
	struct find_t F;

	T0 = time(NULL);
	for (R = 0; R < ROUNDS; R++) {
		unsigned int S = (unsigned int)(rnd() % SLOTS);
		if (P[S] != NULL) {
			unsigned char K = (unsigned char)(S * 7);
			for (I = 0; I < SZ[S]; I++)
				if (P[S][I] != K) {
					BAD++;
					break;
				}
			free(P[S]);
			P[S] = NULL;
		} else {
			SZ[S] = (unsigned short)(1 + rnd() % 4000);
			P[S] = malloc(SZ[S]);
			if (P[S] != NULL)
				memset(P[S], (unsigned char)(S * 7), SZ[S]);
		}
	}
	for (I = 0; I < SLOTS; I++)
		free(P[I]);
	A = malloc(NSORT * sizeof(unsigned long));
	if (A == NULL) {
		printf("STEST: sort malloc failed\n");
		return 1;
	}
	for (I = 0; I < NSORT; I++)
		A[I] = rnd();
	qsort(A, NSORT, sizeof(unsigned long), cmp);
	for (I = 1; I < NSORT; I++)
		if (A[I - 1] > A[I])
			SORTBAD++;
	free(A);
	if (_dos_findfirst("*.*", _A_NORMAL, &F) == 0) {
		do
			NFILES++;
		while (_dos_findnext(&F) == 0);
	}
	TM = localtime(&T0);
	printf("STEST: churn bad %lu, sort bad %lu, %lu files, started %02d:%02d:%02d, %ld s\n",
	       BAD, SORTBAD, NFILES, TM->tm_hour, TM->tm_min, TM->tm_sec, (long)(time(NULL) - T0));
	return BAD != 0 || SORTBAD != 0;
}
