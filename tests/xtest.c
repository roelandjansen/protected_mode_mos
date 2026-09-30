#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int ARGC, char **ARGV)
{
	char CMD[128] = "";
	int I;
	int R1;
	int R2;

	if (ARGC < 2) {
		printf("XTEST: usage XTEST program [args]\n");
		return 1;
	}
	for (I = 1; I < ARGC; I++) {
		if (I > 1)
			strcat(CMD, " ");
		strncat(CMD, ARGV[I], sizeof(CMD) - strlen(CMD) - 2);
	}
	printf("XTEST: parent starting %s\n", CMD);
	fflush(stdout);
	R1 = system(CMD);
	printf("XTEST: back from %s, rc %d; again\n", CMD, R1);
	fflush(stdout);
	R2 = system(CMD);
	printf("XTEST: back from %s, rc %d; parent done\n", CMD, R2);
	return 0;
}
