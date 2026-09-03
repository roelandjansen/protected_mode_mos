#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//
// omfdump - minimal Intel OMF object-record walker.
//
// Prints record type, offset, and length for every record in a
// .OBJ file, so two objects (e.g. one built with real MASM under
// dosemu2/DOSBox, one built with UASM) can be compared structurally
// rather than byte-for-byte -- byte-identical output is not the bar,
// semantically-identical segment/data content is. Pass -d to also
// dump LEDATA record payloads (segment index, offset, raw bytes),
// which is what actually matters for confirming two builds agree.
//
// Usage: omfdump [-d] file.obj
//

static const char *record_name(unsigned char type) {

	switch (type) {
	case 0x80: return "THEADR";
	case 0x82: return "LHEADR";
	case 0x88: return "COMENT";
	case 0x8A: return "MODEND";
	case 0x8B: return "MODEND32";
	case 0x8C: return "EXTDEF";
	case 0x90: return "PUBDEF";
	case 0x91: return "PUBDEF32";
	case 0x94: return "LINNUM";
	case 0x95: return "LINNUM32";
	case 0x96: return "LNAMES";
	case 0x98: return "SEGDEF";
	case 0x99: return "SEGDEF32";
	case 0x9A: return "GRPDEF";
	case 0x9C: return "FIXUPP";
	case 0x9D: return "FIXUPP32";
	case 0xA0: return "LEDATA";
	case 0xA1: return "LEDATA32";
	case 0xA2: return "LIDATA";
	case 0xA3: return "LIDATA32";
	case 0xB0: return "COMDEF";
	case 0xB2: return "BAKPAT";
	case 0xB3: return "BAKPAT32";
	case 0xB4: return "LEXTDEF";
	case 0xB6: return "LPUBDEF";
	case 0xB7: return "LPUBDEF32";
	case 0xB8: return "LCOMDEF";
	case 0xBC: return "CEXTDEF";
	case 0xC2: return "COMDAT";
	case 0xC3: return "COMDAT32";
	case 0xC4: return "SYMBASE";
	case 0xC5: return "SYMBASE32";
	case 0xC6: return "SYMBOLS";
	case 0xC8: return "STATIC";
	case 0xCA: return "ALIAS";
	case 0xCC: return "LLNAMES";
	case 0xCE: return "VERNUM";
	case 0xCF: return "VENDEXT";
	default:   return "UNKNOWN";
	}
}

//
// Prints one LEDATA record's segment index, start offset, and raw
// data bytes. buf/len cover the record payload only (not the
// type/length header already consumed by the caller).
//

static void dump_ledata(const unsigned char *buf, unsigned short len) {

	unsigned short data_off;
	int            i;

	if (len < 3) {
		return;
	}

	data_off = (unsigned short)(buf[1] | (buf[2] << 8));

	printf("        seg=%u off=0x%04x data(%d bytes):", buf[0], data_off, len - 3 - 1);
	for (i = 3; i < len - 1; i++) {
		printf(" %02x", buf[i]);
	}
	printf("\n");
}

int main(int argc, char **argv) {

	FILE          *f;
	const char    *path;
	int            dump_data;
	unsigned char  type;
	unsigned char  lenbuf[2];
	unsigned short len;
	unsigned char  buf[4096];
	long           offset;

	dump_data = 0;
	path      = NULL;

	if (argc == 3 && strcmp(argv[1], "-d") == 0) {
		dump_data = 1;
		path      = argv[2];
	} else if (argc == 2) {
		path = argv[1];
	} else {
		fprintf(stderr, "usage: %s [-d] file.obj\n", argv[0]);
		return 1;
	}

	f = fopen(path, "rb");
	if (!f) {
		perror(path);
		return 1;
	}

	offset = 0;
	while (fread(&type, 1, 1, f) == 1) {
		if (fread(lenbuf, 1, 2, f) != 2) {
			fprintf(stderr, "truncated at offset %ld\n", offset);
			break;
		}
		len = (unsigned short)(lenbuf[0] | (lenbuf[1] << 8));

		printf("%04lx  %-10s type=0x%02x  len=%u\n", offset, record_name(type), type, len);

		if (len > sizeof(buf)) {
			if (fseek(f, len, SEEK_CUR) != 0) {
				fprintf(stderr, "seek failed at offset %ld\n", offset);
				break;
			}
		} else {
			if (fread(buf, 1, len, f) != len) {
				fprintf(stderr, "truncated payload at offset %ld\n", offset);
				break;
			}
			if (dump_data && type == 0xA0) {
				dump_ledata(buf, len);
			}
		}

		offset = ftell(f);
	}

	fclose(f);
	return 0;
}
