/* mkpt: write a partition table sector (MBR or EBR) at sector SEC of IMG.
   args: IMG SEC [type start size]...  start is as stored (relative for EBRs);
   CHS fields are computed from ABS = BASE + start, BASE given by -b N first. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//
// CHS triple for an LBA (255 heads, 63 sectors), 1023/254/63 when too big
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
	unsigned long SEC = strtoul(AV[2], 0, 10);
	unsigned long BASE = strtoul(AV[3], 0, 10);
	FILE *F = fopen(AV[1], "r+b");
	int I;

	memset(M, 0, sizeof(M));
	for (I = 0; 4 + I * 3 + 2 < AC && I < 4; I++) {
		unsigned char *E = M + 446 + I * 16;
		unsigned long T = strtoul(AV[4 + I * 3], 0, 16);
		unsigned long S = strtoul(AV[5 + I * 3], 0, 10);
		unsigned long N = strtoul(AV[6 + I * 3], 0, 10);
		E[0] = (SEC == 0 && I == 0) ? 0x80 : 0;
		chs(E + 1, BASE + S);
		E[4] = T;
		chs(E + 5, BASE + S + N - 1);
		memcpy(E + 8, &S, 4);
		memcpy(E + 12, &N, 4);
	}
	M[510] = 0x55;
	M[511] = 0xaa;
	fseek(F, (long)(SEC * 512), SEEK_SET);
	fwrite(M, 1, 512, F);
	fclose(F);
	return 0;
}
