/* --- The MD5 routines --- */

/* MD5 routines, after Ron Rivest */
/* Written by David Madore <david.madore@ens.fr>, with code taken in
 * part from Colin Plumb. */
/* Public domain (1999/11/24) */

/* Note: these routines do not depend on endianness. */

/* === The header === */

/* Put this in md5.h if you don't like having everything in one big
 * file. */

#ifndef _DMADORE_MD5_H
#define _DMADORE_MD5_H

struct md5_ctx {
  /* The four chaining variables */
  unsigned long buf[4];
  /* Count number of message bits */
  unsigned long bits[2];
  /* Data being fed in */
  unsigned long in[16];
  /* Our position within the 512 bits (always between 0 and 63) */
  int b;
};

void MD5_transform (unsigned long buf[4], const unsigned long in[16]);
void MD5_start (struct md5_ctx *context);
void MD5_feed (struct md5_ctx *context, unsigned char inb);
void MD5_stop (struct md5_ctx *context, unsigned char digest[16]);

#endif /* not defined _DMADORE_MD5_H */

