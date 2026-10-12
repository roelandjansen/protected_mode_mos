/* mkmbr: write an MBR with up to 4 primary partitions into IMG.
   args: IMG [type start size]...   CHS fields from 255/63 geometry,
   or 1023/254/63 when beyond the CHS limit */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//
// CHS triple for an LBA (255 heads, 63 sectors)
//

static void chs(unsigned char *P, unsigned long L)
{
	unsigned long C = L / (255 * 63);
	unsigned H = (L / 63) % 255;
	unsigned S = L % 63 + 1;

	if (C > 1023) {
		C = 1023;
		H = 254;
		S = 63;
	}
	P[0] = H;
	P[1] = S | ((C >> 2) & 0xc0);
	P[2] = C & 0xff;
}

int main(int AC, char **AV)
{
	unsigned char M[512];
	FILE *F = fopen(AV[1], "r+b");
	int I;

	memset(M, 0, sizeof(M));
	for (I = 0; 2 + I * 3 + 2 < AC && I < 4; I++) {
		unsigned char *E = M + 446 + I * 16;
		unsigned long T = strtoul(AV[2 + I * 3], 0, 16);
		unsigned long S = strtoul(AV[3 + I * 3], 0, 10);
		unsigned long N = strtoul(AV[4 + I * 3], 0, 10);
		E[0] = I == 0 ? 0x80 : 0;
		chs(E + 1, S);
		E[4] = T;
		chs(E + 5, S + N - 1);
		memcpy(E + 8, &S, 4);
		memcpy(E + 12, &N, 4);
	}
	M[510] = 0x55;
	M[511] = 0xaa;
	fwrite(M, 1, 512, F);
	fclose(F);
	return 0;
}
