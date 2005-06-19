/*
 * $Id$
 *
 * Copyright Marc Butler 2005.
 * Marc Butler <marcbutler@acm.org>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public (LGPL)
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details: http://www.gnu.org/
 *
 */

#include <string.h>
#include <stdlib.h>
#include "ossupport.h"

#ifdef __APPLE_CC__
/**
 * Synthesize strndup for MacOS X.
 */
char * strndup(const char *s, size_t len)
{
  char *copy = malloc(sizeof (char) * (len + 1));
  strncpy(copy, s, len);
  return copy;
}
#endif /* __APPLE_CC__ */
