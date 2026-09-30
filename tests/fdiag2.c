#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZE (256u * 1024u)
#define PAT(I) ((unsigned char)((I) * 13u + ((I) >> 9)))

unsigned short getds(void);
#pragma aux getds = "mov ax,ds" value [ax];
unsigned short getes(void);
#pragma aux getes = "mov ax,es" value [ax];
unsigned short getss(void);
#pragma aux getss = "mov ax,ss" value [ax];
unsigned short getfs(void);
#pragma aux getfs = "mov ax,fs" value [ax];
unsigned short getgs(void);
#pragma aux getgs = "mov ax,gs" value [ax];
unsigned long lslsel(unsigned short S);
#pragma aux lslsel = "movzx eax,ax" "lsl eax,eax" "jz ok" "xor eax,eax" "dec eax" "ok:" parm [ax] value [eax];

static unsigned short DS0, ES0, SS0;

static void check(const char *WHEN, const unsigned char *P)
{
	unsigned long I;
	unsigned long BAD = 0;
	unsigned char GOT;
	unsigned short DS1 = 0, ES1 = 0, SS1 = 0, FS1 = 0, GS1 = 0;
	unsigned long I1 = 0;
	unsigned char G1 = 0, R1 = 0;

	for (I = 0; I < SIZE; I++) {
		GOT = P[I];
		if (GOT != PAT(I)) {
			if (BAD == 0) {
				DS1 = getds(); ES1 = getes(); SS1 = getss();
				FS1 = getfs(); GS1 = getgs();
				I1 = I; G1 = GOT; R1 = P[I];
			}
			BAD++;
		}
	}
	printf("FD2 %s: %lu bad", WHEN, BAD);
	if (BAD)
		printf(" @%05lX got %02X reread %02X want %02X | ds %04X es %04X ss %04X fs %04X gs %04X (start %04X %04X %04X) lim ds %08lX",
		       I1, G1, R1, PAT(I1), DS1, ES1, SS1, FS1, GS1, DS0, ES0, SS0, lslsel(DS1));
	printf("\n");
}

int main(void)
{
	unsigned char *A;
	unsigned long I;
	int K;

	DS0 = getds(); ES0 = getes(); SS0 = getss();
	A = malloc(SIZE);
	if (A == NULL)
		return 1;
	for (I = 0; I < SIZE; I++)
		A[I] = PAT(I);
	for (K = 0; K < 6; K++)
		check("A", A);
	return 0;
}
