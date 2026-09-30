#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZE (256u * 1024u)
#define CHUNK (32u * 1024u)

static unsigned long checksum(const unsigned char *P, unsigned long N)
{
	unsigned long S = 0;
	unsigned long I;

	for (I = 0; I < N; I++)
		S = S * 31u + P[I];
	return S;
}

static int roundtrip(const char *NAME, const unsigned char *A, unsigned char *B, int CHUNKED)
{
	FILE *F;
	unsigned long I;

	F = fopen(NAME, "wb");
	if (F == NULL)
		return 1;
	if (CHUNKED) {
		for (I = 0; I < SIZE; I += CHUNK)
			if (fwrite(A + I, 1, CHUNK, F) != CHUNK)
				return 2;
	} else if (fwrite(A, 1, SIZE, F) != SIZE) {
		return 2;
	}
	if (fclose(F) != 0)
		return 3;
	memset(B, 0, SIZE);
	F = fopen(NAME, "rb");
	if (F == NULL)
		return 4;
	if (fread(B, 1, SIZE, F) != SIZE)
		return 5;
	fclose(F);
	if (memcmp(A, B, SIZE) != 0)
		return 6;
	if (remove(NAME) != 0)
		return 7;
	return 0;
}

int main(void)
{
	unsigned char *A;
	unsigned char *B;
	unsigned long I;
	int R1;
	int R2;

	A = malloc(SIZE);
	B = malloc(SIZE);
	if (A == NULL || B == NULL) {
		printf("FTEST: malloc failed\n");
		return 1;
	}
	for (I = 0; I < SIZE; I++)
		A[I] = (unsigned char)(I * 13u + (I >> 9));
	R1 = roundtrip("FT1.DAT", A, B, 0);
	R2 = roundtrip("FT2.DAT", A, B, 1);
	printf("FTEST: %u bytes, one-shot %s, chunked %s, sum %08lX\n", SIZE,
	       R1 ? "FAIL" : "ok", R2 ? "FAIL" : "ok", checksum(B, SIZE));
	if (R1 || R2)
		printf("FTEST: codes %d %d\n", R1, R2);
	return R1 || R2;
}
