#include <stdio.h>
#include <string.h>

int main(void)
{
	char LINE[80];

	printf("KTEST: type a line\n");
	fflush(stdout);
	if (fgets(LINE, sizeof(LINE), stdin) == NULL) {
		printf("KTEST: no input\n");
		return 1;
	}
	LINE[strcspn(LINE, "\r\n")] = 0;
	printf("KTEST: got [%s]\n", LINE);
	return 0;
}
