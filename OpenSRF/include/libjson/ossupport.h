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

#ifndef _ossupport_h_
#define _ossupport_h_

#ifdef __APPLE_CC__
char * strndup(const char *s, size_t len);
#endif /* __APPLE_CC__ */

#endif
