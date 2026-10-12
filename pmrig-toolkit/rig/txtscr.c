/*
 * txtscr - render a raw VGA text-mode dump (char,attr pairs) as rows.
 *
 * usage: txtscr <dumpfile> [cols] [rows] [--attr]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	FILE *f;
	int cols = 80;
	int rows = 25;
	int show_attr = 0;
	int r, c;
	unsigned char cell[2];

	if (argc < 2) {
		fprintf(stderr, "usage: %s <dump> [cols] [rows] [--attr]\n", argv[0]);
		return 1;
	}
	if (argc > 2 && strcmp(argv[2], "--attr") != 0)
		cols = atoi(argv[2]);
	if (argc > 3 && strcmp(argv[3], "--attr") != 0)
		rows = atoi(argv[3]);
	for (r = 2; r < argc; r++)
		if (strcmp(argv[r], "--attr") == 0)
			show_attr = 1;

	f = fopen(argv[1], "rb");
	if (!f) {
		perror(argv[1]);
		return 1;
	}

	for (r = 0; r < rows; r++) {
		printf("%02d|", r);
		for (c = 0; c < cols; c++) {
			if (fread(cell, 1, 2, f) != 2) {
				putchar('\n');
				fclose(f);
				return 0;
			}
			if (show_attr)
				printf("%02x", cell[1]);
			else
				putchar(cell[0] >= 0x20 && cell[0] < 0x7f ? cell[0] : '.');
		}
		printf("|\n");
	}

	fclose(f);
	return 0;
}
