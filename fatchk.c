/* fatchk: FAT16 lost-cluster checker for a partition at an offset */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
static FILE *f; static long off; static uint8_t bs[512];
static uint16_t *fat; static uint8_t *used; static unsigned ncl, spc, bps, rsv, nf, rootn, spf; static long datas;
static void rd(long sec, void *b, long n){ fseek(f, off+sec*512, SEEK_SET); fread(b,1,n,f); }
static void walk(unsigned c, int isdir, const char *nm);
static void dirents(uint8_t *d, long n){
 for(long i=0;i<n;i+=32){ uint8_t *e=d+i; if(!e[0])return; if(e[0]==0xe5||e[11]==0x0f||(e[11]&8))continue;
  if(e[0]=='.')continue; printf("%.11s start %u size %u\n",(char*)e,e[26]|e[27]<<8,*(unsigned*)(e+28)); unsigned c=e[26]|e[27]<<8; char nm[13]; memcpy(nm,e,11); nm[11]=0;
  walk(c, e[11]&0x10, nm);} }
static void walk(unsigned c,int isdir,const char *nm){ long cb=(long)spc*512; uint8_t *b=isdir?malloc(cb):0;
 while(c>=2&&c<ncl+2){ if(used[c]){printf("crosslink %s %u\n",nm,c);break;} used[c]=1;
  if(isdir){ rd(datas+(long)(c-2)*spc,b,cb); dirents(b,cb);} c=fat[c]; }
 free(b);}
int main(int a,char**v){ f=fopen(v[1],"rb"); off=atol(v[2]); rd(0,bs,512);
 bps=bs[11]|bs[12]<<8; spc=bs[13]; rsv=bs[14]|bs[15]<<8; nf=bs[16]; rootn=bs[17]|bs[18]<<8; spf=bs[22]|bs[23]<<8;
 uint32_t tot=bs[19]|bs[20]<<8; if(!tot) tot=*(uint32_t*)(bs+32);
 long roots=(rootn*32+511)/512; datas=rsv+nf*spf+roots; ncl=(tot-datas)/spc;
 fat=malloc(spf*512); rd(rsv,fat,spf*512L); used=calloc(ncl+2,1);
 uint8_t *r=malloc(roots*512); rd(rsv+nf*spf,r,roots*512); dirents(r,roots*512);
 unsigned lost=0, fr=0; for(unsigned c=2;c<ncl+2;c++){ if(!fat[c])fr++; else if(!used[c]){lost++; printf("lost %u fat=%04x\n",c,fat[c]);} }
 printf("clusters %u (fat entries %u) free %u lost %u spc %u\n",ncl,spf*256,fr,lost,spc); return 0;}
