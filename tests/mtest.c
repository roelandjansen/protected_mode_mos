#include <stdio.h>
#include <stdlib.h>

#define MB (1024ul * 1024ul)
#define MAXB 64

int main(void)
{
	unsigned char *P[MAXB];
	unsigned char *BIG;
	int N;
	int I;
	int BAD = 0;

	for (N = 0; N < MAXB; N++) {
		P[N] = malloc(MB);
		if (P[N] == NULL)
			break;
		P[N][0] = (unsigned char)N;
		P[N][MB - 1] = (unsigned char)~N;
	}
	for (I = 0; I < N; I++)
		if (P[I][0] != (unsigned char)I || P[I][MB - 1] != (unsigned char)~I)
			BAD++;
	for (I = 0; I < N; I++)
		free(P[I]);
	BIG = N > 1 ? malloc((unsigned long)(N - 1) * MB) : NULL;
	if (BIG != NULL) {
		BIG[0] = 1;
		BIG[(unsigned long)(N - 1) * MB - 1] = 2;
	}
	printf("MTEST: %d MB in 1 MB blocks, %d bad, one %d MB block %s\n",
	       N, BAD, N - 1, BIG ? "ok" : "FAIL");
	free(BIG);
	return BAD != 0 || BIG == NULL;
}
