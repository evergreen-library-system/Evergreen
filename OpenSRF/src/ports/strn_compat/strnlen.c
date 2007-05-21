/*
 * Copyright (c) 2007 The Akuma Project
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 * $Id$
 */

/*
 * sys/types.h is a Single Unix Specification header and defines size_t.
 */

#include <sys/types.h>

/*
 * As per the Linux manual page:
 *
 * The strnlen() function returns the number of characters in the string
 * pointed to by s, not including the terminating '\0' character, but at most
 * maxlen. In doing this, strnlen() looks only at the first maxlen characters
 * at s and never beyond s+maxlen.
 *
 * The strnlen() function returns strlen(s), if that is less than maxlen, or
 * maxlen if there is no '\0' character among the first maxlen characters
 * pointed to by s.
 */

size_t
strnlen(const char *string, size_t maxlen)
{
	int len = 0;

	if (maxlen == 0)
		return (0);

	while (*string++ && ++len < maxlen)
		;

	return (len);
}
