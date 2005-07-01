/*
Copyright (C) 2005  Georgia Public Library Service 
Bill Erickson <highfalutin@gmail.com>
Mike Rylander <mrylander@gmail.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#ifndef UTILS_H
#define UTILS_H

#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <fcntl.h>

#define BUFFER_MAX_SIZE 10485760 

void* safe_malloc(int size);

// ---------------------------------------------------------------------------------
// Generic growing buffer. Add data all you want
// ---------------------------------------------------------------------------------
struct growing_buffer_struct {
	char *buf;
	int n_used;
	int size;
};
typedef struct growing_buffer_struct growing_buffer;

growing_buffer* buffer_init( int initial_num_bytes);
int buffer_addchar(growing_buffer* gb, char c);
int buffer_add(growing_buffer* gb, char* c);
int buffer_fadd(growing_buffer* gb, const char* format, ... );
int buffer_reset( growing_buffer* gb);
char* buffer_data( growing_buffer* gb);
int buffer_free( growing_buffer* gb );
int buffer_add_char(growing_buffer* gb, char c);


/* string escape utility method.  escapes unicode embeded characters.
	escapes the usual \n, \t, etc. 
	for example, if you provide a string like so:

	hello,
		you

	you would get back:
	hello,\n\tyou
 
 */
char* uescape( const char* string, int size, int full_escape );

/* utility methods */
int set_fl( int fd, int flags );
int clr_fl( int fd, int flags );



// Utility method
double get_timestamp_millis();




#endif
