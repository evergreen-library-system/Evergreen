/* --- The data --- */

const char data[] =
"/* --- The MD5 routines --- */\n\n/* MD5 routines, after Ron R"
"ivest */\n/* Written by David Madore <david.madore@ens.fr>, w"
"ith code taken in\n * part from Colin Plumb. */\n/* Public dom"
"ain (1999/11/24) */\n\n/* Note: these routines do not depend o"
"n endianness. */\n\n/* === The header === */\n\n/* Put this in m"
"d5.h if you don't like having everything in one big\n * file."
" */\n\n#ifndef _DMADORE_MD5_H\n#define _DMADORE_MD5_H\n\nstruct m"
"d5_ctx {\n  /* The four chaining variables */\n  unsigned long"
" buf[4];\n  /* Count number of message bits */\n  unsigned lon"
"g bits[2];\n  /* Data being fed in */\n  unsigned long in[16];"
"\n  /* Our position within the 512 bits (always between 0 and"
" 63) */\n  int b;\n};\n\nvoid MD5_transform (unsigned long buf[4"
"], const unsigned long in[16]);\nvoid MD5_start (struct md5_c"
"tx *context);\nvoid MD5_feed (struct md5_ctx *context, unsign"
"ed char inb);\nvoid MD5_stop (struct md5_ctx *context, unsign"
"ed char digest[16]);\n\n#endif /* not defined _DMADORE_MD5_H *"
"/\n\n/* === The implementation === */\n\n#define F1(x, y, z) (z "
"^ (x & (y ^ z)))\n#define F2(x, y, z) F1(z, x, y)\n#define F3("
"x, y, z) (x ^ y ^ z)\n#define F4(x, y, z) (y ^ (x | ~z))\n\n#de"
"fine MD5STEP(f, w, x, y, z, data, s) \\\n\t{ w += f (x, y, z) +"
" data;  w = w<<s | (w&0xffffffffUL)>>(32-s); \\\n\t  w += x; }\n"
"\nvoid\nMD5_transform (unsigned long buf[4], const unsigned lo"
"ng in[16])\n{\n  register unsigned long a, b, c, d;\n\n  a = buf"
"[0];  b = buf[1];  c = buf[2];  d = buf[3];\n  MD5STEP(F1, a,"
" b, c, d, in[0] + 0xd76aa478UL, 7);\n  MD5STEP(F1, d, a, b, c"
", in[1] + 0xe8c7b756UL, 12);\n  MD5STEP(F1, c, d, a, b, in[2]"
" + 0x242070dbUL, 17);\n  MD5STEP(F1, b, c, d, a, in[3] + 0xc1"
"bdceeeUL, 22);\n  MD5STEP(F1, a, b, c, d, in[4] + 0xf57c0fafU"
"L, 7);\n  MD5STEP(F1, d, a, b, c, in[5] + 0x4787c62aUL, 12);\n"
"  MD5STEP(F1, c, d, a, b, in[6] + 0xa8304613UL, 17);\n  MD5ST"
"EP(F1, b, c, d, a, in[7] + 0xfd469501UL, 22);\n  MD5STEP(F1, "
"a, b, c, d, in[8] + 0x698098d8UL, 7);\n  MD5STEP(F1, d, a, b,"
" c, in[9] + 0x8b44f7afUL, 12);\n  MD5STEP(F1, c, d, a, b, in["
"10] + 0xffff5bb1UL, 17);\n  MD5STEP(F1, b, c, d, a, in[11] + "
"0x895cd7beUL, 22);\n  MD5STEP(F1, a, b, c, d, in[12] + 0x6b90"
"1122UL, 7);\n  MD5STEP(F1, d, a, b, c, in[13] + 0xfd987193UL,"
" 12);\n  MD5STEP(F1, c, d, a, b, in[14] + 0xa679438eUL, 17);\n"
"  MD5STEP(F1, b, c, d, a, in[15] + 0x49b40821UL, 22);\n  MD5S"
"TEP(F2, a, b, c, d, in[1] + 0xf61e2562UL, 5);\n  MD5STEP(F2, "
"d, a, b, c, in[6] + 0xc040b340UL, 9);\n  MD5STEP(F2, c, d, a,"
" b, in[11] + 0x265e5a51UL, 14);\n  MD5STEP(F2, b, c, d, a, in"
"[0] + 0xe9b6c7aaUL, 20);\n  MD5STEP(F2, a, b, c, d, in[5] + 0"
"xd62f105dUL, 5);\n  MD5STEP(F2, d, a, b, c, in[10] + 0x024414"
"53UL, 9);\n  MD5STEP(F2, c, d, a, b, in[15] + 0xd8a1e681UL, 1"
"4);\n  MD5STEP(F2, b, c, d, a, in[4] + 0xe7d3fbc8UL, 20);\n  M"
"D5STEP(F2, a, b, c, d, in[9] + 0x21e1cde6UL, 5);\n  MD5STEP(F"
"2, d, a, b, c, in[14] + 0xc33707d6UL, 9);\n  MD5STEP(F2, c, d"
", a, b, in[3] + 0xf4d50d87UL, 14);\n  MD5STEP(F2, b, c, d, a,"
" in[8] + 0x455a14edUL, 20);\n  MD5STEP(F2, a, b, c, d, in[13]"
" + 0xa9e3e905UL, 5);\n  MD5STEP(F2, d, a, b, c, in[2] + 0xfce"
"fa3f8UL, 9);\n  MD5STEP(F2, c, d, a, b, in[7] + 0x676f02d9UL,"
" 14);\n  MD5STEP(F2, b, c, d, a, in[12] + 0x8d2a4c8aUL, 20);\n"
"  MD5STEP(F3, a, b, c, d, in[5] + 0xfffa3942UL, 4);\n  MD5STE"
"P(F3, d, a, b, c, in[8] + 0x8771f681UL, 11);\n  MD5STEP(F3, c"
", d, a, b, in[11] + 0x6d9d6122UL, 16);\n  MD5STEP(F3, b, c, d"
", a, in[14] + 0xfde5380cUL, 23);\n  MD5STEP(F3, a, b, c, d, i"
"n[1] + 0xa4beea44UL, 4);\n  MD5STEP(F3, d, a, b, c, in[4] + 0"
"x4bdecfa9UL, 11);\n  MD5STEP(F3, c, d, a, b, in[7] + 0xf6bb4b"
"60UL, 16);\n  MD5STEP(F3, b, c, d, a, in[10] + 0xbebfbc70UL, "
"23);\n  MD5STEP(F3, a, b, c, d, in[13] + 0x289b7ec6UL, 4);\n  "
"MD5STEP(F3, d, a, b, c, in[0] + 0xeaa127faUL, 11);\n  MD5STEP"
"(F3, c, d, a, b, in[3] + 0xd4ef3085UL, 16);\n  MD5STEP(F3, b,"
" c, d, a, in[6] + 0x04881d05UL, 23);\n  MD5STEP(F3, a, b, c, "
"d, in[9] + 0xd9d4d039UL, 4);\n  MD5STEP(F3, d, a, b, c, in[12"
"] + 0xe6db99e5UL, 11);\n  MD5STEP(F3, c, d, a, b, in[15] + 0x"
"1fa27cf8UL, 16);\n  MD5STEP(F3, b, c, d, a, in[2] + 0xc4ac566"
"5UL, 23);\n  MD5STEP(F4, a, b, c, d, in[0] + 0xf4292244UL, 6)"
";\n  MD5STEP(F4, d, a, b, c, in[7] + 0x432aff97UL, 10);\n  MD5"
"STEP(F4, c, d, a, b, in[14] + 0xab9423a7UL, 15);\n  MD5STEP(F"
"4, b, c, d, a, in[5] + 0xfc93a039UL, 21);\n  MD5STEP(F4, a, b"
", c, d, in[12] + 0x655b59c3UL, 6);\n  MD5STEP(F4, d, a, b, c,"
" in[3] + 0x8f0ccc92UL, 10);\n  MD5STEP(F4, c, d, a, b, in[10]"
" + 0xffeff47dUL, 15);\n  MD5STEP(F4, b, c, d, a, in[1] + 0x85"
"845dd1UL, 21);\n  MD5STEP(F4, a, b, c, d, in[8] + 0x6fa87e4fU"
"L, 6);\n  MD5STEP(F4, d, a, b, c, in[15] + 0xfe2ce6e0UL, 10);"
"\n  MD5STEP(F4, c, d, a, b, in[6] + 0xa3014314UL, 15);\n  MD5S"
"TEP(F4, b, c, d, a, in[13] + 0x4e0811a1UL, 21);\n  MD5STEP(F4"
", a, b, c, d, in[4] + 0xf7537e82UL, 6);\n  MD5STEP(F4, d, a, "
"b, c, in[11] + 0xbd3af235UL, 10);\n  MD5STEP(F4, c, d, a, b, "
"in[2] + 0x2ad7d2bbUL, 15);\n  MD5STEP(F4, b, c, d, a, in[9] +"
" 0xeb86d391UL, 21);\n  buf[0] += a;  buf[1] += b;  buf[2] += "
"c;  buf[3] += d;\n}\n\n#undef F1\n#undef F2\n#undef F3\n#undef F4\n"
"#undef MD5STEP\n\nvoid\nMD5_start (struct md5_ctx *ctx)\n{\n  int"
" i;\n\n  ctx->buf[0] = 0x67452301UL;\n  ctx->buf[1] = 0xefcdab8"
"9UL;\n  ctx->buf[2] = 0x98badcfeUL;\n  ctx->buf[3] = 0x1032547"
"6UL;\n  ctx->bits[0] = 0;\n  ctx->bits[1] = 0;\n  for ( i=0 ; i"
"<16 ; i++ )\n    ctx->in[i] = 0;\n  ctx->b = 0;\n}\n\nvoid\nMD5_fe"
"ed (struct md5_ctx *ctx, unsigned char inb)\n{\n  int i;\n  uns"
"igned long temp;\n\n  ctx->in[ctx->b/4] |= ((unsigned long)inb"
") << ((ctx->b%4)*8);\n  if ( ++ctx->b >= 64 )\n    {\n      MD5"
"_transform (ctx->buf, ctx->in);\n      ctx->b = 0;\n      for "
"( i=0 ; i<16 ; i++ )\n\tctx->in[i] = 0;\n    }\n  temp = ctx->bi"
"ts[0];\n  ctx->bits[0] += 8;\n  if ( (temp&0xffffffffUL) > (ct"
"x->bits[0]&0xffffffffUL) )\n    ctx->bits[1]++;\n}\n\nvoid\nMD5_s"
"top (struct md5_ctx *ctx, unsigned char digest[16])\n{\n  int "
"i;\n  unsigned long bits[2];\n\n  for ( i=0 ; i<2 ; i++ )\n    b"
"its[i] = ctx->bits[i];\n  MD5_feed (ctx, 0x80);\n  for ( ; ctx"
"->b!=56 ; )\n    MD5_feed (ctx, 0);\n  for ( i=0 ; i<2 ; i++ )"
"\n    {\n      MD5_feed (ctx, bits[i]&0xff);\n      MD5_feed (c"
"tx, (bits[i]>>8)&0xff);\n      MD5_feed (ctx, (bits[i]>>16)&0"
"xff);\n      MD5_feed (ctx, (bits[i]>>24)&0xff);\n    }\n  for "
"( i=0 ; i<4 ; i++ )\n    {\n      digest[4*i] = ctx->buf[i]&0x"
"ff;\n      digest[4*i+1] = (ctx->buf[i]>>8)&0xff;\n      diges"
"t[4*i+2] = (ctx->buf[i]>>16)&0xff;\n      digest[4*i+3] = (ct"
"x->buf[i]>>24)&0xff;\n    }\n}\n\f\n/* --- The core of the progra"
"m --- */\n\n#include <stdio.h>\n#include <string.h>\n\n#define LA"
"RGE_ENOUGH 16384\n\nchar buffer[LARGE_ENOUGH];\n\nint\nmain (int "
"argc, char *argv[])\n{\n  unsigned int i;\n\n  buffer[0] = 0;\n  "
"strcat (buffer, \"/* --- The data --- */\\n\\n\");\n  strcat (buf"
"fer, \"const char data[] =\");\n  for ( i=0 ; data[i] ; i++ )\n "
"   {\n      if ( i%60 == 0 )\n\tstrcat (buffer, \"\\n\\\"\");\n      "
"switch ( data[i] )\n\t{\n\tcase '\\\\':\n\tcase '\"':\n\t  strcat (buff"
"er, \"\\\\\");\n\t  buffer[strlen(buffer)+1] = 0;\n\t  buffer[strlen"
"(buffer)] = data[i];\n\t  break;\n\tcase '\\n':\n\t  strcat (buffer"
", \"\\\\n\");\n\t  break;\n\tcase '\\t':\n\t  strcat (buffer, \"\\\\t\");\n\t"
"  break;\n\tcase '\\f':\n\t  strcat (buffer, \"\\\\f\");\n\t  break;\n\td"
"efault:\n\t  buffer[strlen(buffer)+1] = 0;\n\t  buffer[strlen(bu"
"ffer)] = data[i];\n\t}\n      if ( i%60 == 59 || !data[i+1] )\n\t"
"strcat (buffer, \"\\\"\");\n    }\n  strcat (buffer, \";\\n\\f\\n\");\n "
" strcat (buffer, data);\n  if ( argc >= 2 && strcmp (argv[1],"
" \"xyzzy\") == 0 )\n    printf (\"%s\", buffer);\n  else\n    {\n   "
"   struct md5_ctx ctx;\n      unsigned char digest[16];\n\n    "
"  MD5_start (&ctx);\n      for ( i=0 ; buffer[i] ; i++ )\n\tMD5"
"_feed (&ctx, buffer[i]);\n      MD5_stop (&ctx, digest);\n    "
"  for ( i=0 ; i<16 ; i++ )\n\tprintf (\"%02x\", digest[i]);\n    "
"  printf (\"\\n\");\n    }\n  return 0;\n}\n";


#include "md5.h"


/* --- The MD5 routines --- */

/* MD5 routines, after Ron Rivest */
/* Written by David Madore <david.madore@ens.fr>, with code taken in
 * part from Colin Plumb. */
/* Public domain (1999/11/24) */

/* Note: these routines do not depend on endianness. */

/* === The header === */

/* Put this in md5.h if you don't like having everything in one big
 * file. */


#define F1(x, y, z) (z ^ (x & (y ^ z)))
#define F2(x, y, z) F1(z, x, y)
#define F3(x, y, z) (x ^ y ^ z)
#define F4(x, y, z) (y ^ (x | ~z))

#define MD5STEP(f, w, x, y, z, data, s) \
	{ w += f (x, y, z) + data;  w = w<<s | (w&0xffffffffUL)>>(32-s); \
	  w += x; }

void
MD5_transform (unsigned long buf[4], const unsigned long in[16])
{
  register unsigned long a, b, c, d;

  a = buf[0];  b = buf[1];  c = buf[2];  d = buf[3];
  MD5STEP(F1, a, b, c, d, in[0] + 0xd76aa478UL, 7);
  MD5STEP(F1, d, a, b, c, in[1] + 0xe8c7b756UL, 12);
  MD5STEP(F1, c, d, a, b, in[2] + 0x242070dbUL, 17);
  MD5STEP(F1, b, c, d, a, in[3] + 0xc1bdceeeUL, 22);
  MD5STEP(F1, a, b, c, d, in[4] + 0xf57c0fafUL, 7);
  MD5STEP(F1, d, a, b, c, in[5] + 0x4787c62aUL, 12);
  MD5STEP(F1, c, d, a, b, in[6] + 0xa8304613UL, 17);
  MD5STEP(F1, b, c, d, a, in[7] + 0xfd469501UL, 22);
  MD5STEP(F1, a, b, c, d, in[8] + 0x698098d8UL, 7);
  MD5STEP(F1, d, a, b, c, in[9] + 0x8b44f7afUL, 12);
  MD5STEP(F1, c, d, a, b, in[10] + 0xffff5bb1UL, 17);
  MD5STEP(F1, b, c, d, a, in[11] + 0x895cd7beUL, 22);
  MD5STEP(F1, a, b, c, d, in[12] + 0x6b901122UL, 7);
  MD5STEP(F1, d, a, b, c, in[13] + 0xfd987193UL, 12);
  MD5STEP(F1, c, d, a, b, in[14] + 0xa679438eUL, 17);
  MD5STEP(F1, b, c, d, a, in[15] + 0x49b40821UL, 22);
  MD5STEP(F2, a, b, c, d, in[1] + 0xf61e2562UL, 5);
  MD5STEP(F2, d, a, b, c, in[6] + 0xc040b340UL, 9);
  MD5STEP(F2, c, d, a, b, in[11] + 0x265e5a51UL, 14);
  MD5STEP(F2, b, c, d, a, in[0] + 0xe9b6c7aaUL, 20);
  MD5STEP(F2, a, b, c, d, in[5] + 0xd62f105dUL, 5);
  MD5STEP(F2, d, a, b, c, in[10] + 0x02441453UL, 9);
  MD5STEP(F2, c, d, a, b, in[15] + 0xd8a1e681UL, 14);
  MD5STEP(F2, b, c, d, a, in[4] + 0xe7d3fbc8UL, 20);
  MD5STEP(F2, a, b, c, d, in[9] + 0x21e1cde6UL, 5);
  MD5STEP(F2, d, a, b, c, in[14] + 0xc33707d6UL, 9);
  MD5STEP(F2, c, d, a, b, in[3] + 0xf4d50d87UL, 14);
  MD5STEP(F2, b, c, d, a, in[8] + 0x455a14edUL, 20);
  MD5STEP(F2, a, b, c, d, in[13] + 0xa9e3e905UL, 5);
  MD5STEP(F2, d, a, b, c, in[2] + 0xfcefa3f8UL, 9);
  MD5STEP(F2, c, d, a, b, in[7] + 0x676f02d9UL, 14);
  MD5STEP(F2, b, c, d, a, in[12] + 0x8d2a4c8aUL, 20);
  MD5STEP(F3, a, b, c, d, in[5] + 0xfffa3942UL, 4);
  MD5STEP(F3, d, a, b, c, in[8] + 0x8771f681UL, 11);
  MD5STEP(F3, c, d, a, b, in[11] + 0x6d9d6122UL, 16);
  MD5STEP(F3, b, c, d, a, in[14] + 0xfde5380cUL, 23);
  MD5STEP(F3, a, b, c, d, in[1] + 0xa4beea44UL, 4);
  MD5STEP(F3, d, a, b, c, in[4] + 0x4bdecfa9UL, 11);
  MD5STEP(F3, c, d, a, b, in[7] + 0xf6bb4b60UL, 16);
  MD5STEP(F3, b, c, d, a, in[10] + 0xbebfbc70UL, 23);
  MD5STEP(F3, a, b, c, d, in[13] + 0x289b7ec6UL, 4);
  MD5STEP(F3, d, a, b, c, in[0] + 0xeaa127faUL, 11);
  MD5STEP(F3, c, d, a, b, in[3] + 0xd4ef3085UL, 16);
  MD5STEP(F3, b, c, d, a, in[6] + 0x04881d05UL, 23);
  MD5STEP(F3, a, b, c, d, in[9] + 0xd9d4d039UL, 4);
  MD5STEP(F3, d, a, b, c, in[12] + 0xe6db99e5UL, 11);
  MD5STEP(F3, c, d, a, b, in[15] + 0x1fa27cf8UL, 16);
  MD5STEP(F3, b, c, d, a, in[2] + 0xc4ac5665UL, 23);
  MD5STEP(F4, a, b, c, d, in[0] + 0xf4292244UL, 6);
  MD5STEP(F4, d, a, b, c, in[7] + 0x432aff97UL, 10);
  MD5STEP(F4, c, d, a, b, in[14] + 0xab9423a7UL, 15);
  MD5STEP(F4, b, c, d, a, in[5] + 0xfc93a039UL, 21);
  MD5STEP(F4, a, b, c, d, in[12] + 0x655b59c3UL, 6);
  MD5STEP(F4, d, a, b, c, in[3] + 0x8f0ccc92UL, 10);
  MD5STEP(F4, c, d, a, b, in[10] + 0xffeff47dUL, 15);
  MD5STEP(F4, b, c, d, a, in[1] + 0x85845dd1UL, 21);
  MD5STEP(F4, a, b, c, d, in[8] + 0x6fa87e4fUL, 6);
  MD5STEP(F4, d, a, b, c, in[15] + 0xfe2ce6e0UL, 10);
  MD5STEP(F4, c, d, a, b, in[6] + 0xa3014314UL, 15);
  MD5STEP(F4, b, c, d, a, in[13] + 0x4e0811a1UL, 21);
  MD5STEP(F4, a, b, c, d, in[4] + 0xf7537e82UL, 6);
  MD5STEP(F4, d, a, b, c, in[11] + 0xbd3af235UL, 10);
  MD5STEP(F4, c, d, a, b, in[2] + 0x2ad7d2bbUL, 15);
  MD5STEP(F4, b, c, d, a, in[9] + 0xeb86d391UL, 21);
  buf[0] += a;  buf[1] += b;  buf[2] += c;  buf[3] += d;
}

#undef F1
#undef F2
#undef F3
#undef F4
#undef MD5STEP

void
MD5_start (struct md5_ctx *ctx)
{
  int i;

  ctx->buf[0] = 0x67452301UL;
  ctx->buf[1] = 0xefcdab89UL;
  ctx->buf[2] = 0x98badcfeUL;
  ctx->buf[3] = 0x10325476UL;
  ctx->bits[0] = 0;
  ctx->bits[1] = 0;
  for ( i=0 ; i<16 ; i++ )
    ctx->in[i] = 0;
  ctx->b = 0;
}

void
MD5_feed (struct md5_ctx *ctx, unsigned char inb)
{
  int i;
  unsigned long temp;

  ctx->in[ctx->b/4] |= ((unsigned long)inb) << ((ctx->b%4)*8);
  if ( ++ctx->b >= 64 )
    {
      MD5_transform (ctx->buf, ctx->in);
      ctx->b = 0;
      for ( i=0 ; i<16 ; i++ )
	ctx->in[i] = 0;
    }
  temp = ctx->bits[0];
  ctx->bits[0] += 8;
  if ( (temp&0xffffffffUL) > (ctx->bits[0]&0xffffffffUL) )
    ctx->bits[1]++;
}

void
MD5_stop (struct md5_ctx *ctx, unsigned char digest[16])
{
  int i;
  unsigned long bits[2];

  for ( i=0 ; i<2 ; i++ )
    bits[i] = ctx->bits[i];
  MD5_feed (ctx, 0x80);
  for ( ; ctx->b!=56 ; )
    MD5_feed (ctx, 0);
  for ( i=0 ; i<2 ; i++ )
    {
      MD5_feed (ctx, bits[i]&0xff);
      MD5_feed (ctx, (bits[i]>>8)&0xff);
      MD5_feed (ctx, (bits[i]>>16)&0xff);
      MD5_feed (ctx, (bits[i]>>24)&0xff);
    }
  for ( i=0 ; i<4 ; i++ )
    {
      digest[4*i] = ctx->buf[i]&0xff;
      digest[4*i+1] = (ctx->buf[i]>>8)&0xff;
      digest[4*i+2] = (ctx->buf[i]>>16)&0xff;
      digest[4*i+3] = (ctx->buf[i]>>24)&0xff;
    }
}

/* --- The core of the program --- */

#include <stdio.h>
#include <string.h>

#define LARGE_ENOUGH 16384

char buffer[LARGE_ENOUGH];

/*
int
main (int argc, char *argv[])
{
  unsigned int i;

  buffer[0] = 0;
  strcat (buffer, \n\n");
  strcat (buffer, "const char data[] =");
  for ( i=0 ; data[i] ; i++ )
    {
      if ( i%60 == 0 )
	strcat (buffer, "\n\"");
      switch ( data[i] )
	{
	case '\\':
	case '"':
	  strcat (buffer, "\\");
	  buffer[strlen(buffer)+1] = 0;
	  buffer[strlen(buffer)] = data[i];
	  break;
	case '\n':
	  strcat (buffer, "\\n");
	  break;
	case '\t':
	  strcat (buffer, "\\t");
	  break;
	case '\f':
	  strcat (buffer, "\\f");
	  break;
	default:
	  buffer[strlen(buffer)+1] = 0;
	  buffer[strlen(buffer)] = data[i];
	}
      if ( i%60 == 59 || !data[i+1] )
	strcat (buffer, "\"");
    }
  strcat (buffer, ";\n\f\n");
  strcat (buffer, data);
  if ( argc >= 2 && strcmp (argv[1], "xyzzy") == 0 )
    printf ("%s", buffer);
  else
    {
      struct md5_ctx ctx;
      unsigned char digest[16];

      MD5_start (&ctx);
      for ( i=0 ; buffer[i] ; i++ )
	MD5_feed (&ctx, buffer[i]);
      MD5_stop (&ctx, digest);
      for ( i=0 ; i<16 ; i++ )
	printf ("%02x", digest[i]);
      printf ("\n");
    }
  return 0;
}
*/
