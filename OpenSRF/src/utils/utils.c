#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include <sys/timeb.h>
#include "utils.h"

inline void* safe_malloc( int size ) {
	void* ptr = (void*) malloc( size );
	if( ptr == NULL ) {
		perror("safe_malloc(): Out of Memory" );
		exit(99);
	}
	memset( ptr, 0, size );
	return ptr;
}

/* utility method for profiling */
double get_timestamp_millis() {
	struct timeb t;
	ftime(&t);
	double time	= ( 
		(int)t.time	+ ( ((double)t.millitm) / 1000 ) );
	return time;
}


/* setting/clearing file flags */
int set_fl( int fd, int flags ) {
	
	int val;

	if( (val = fcntl( fd, F_GETFL, 0) ) < 0 ) {
		fprintf(stderr, "fcntl F_GETFL error");
		return -1;
	}

	val |= flags;

	if( fcntl( fd, F_SETFL, val ) < 0 ) {
		fprintf(stderr, "fcntl F_SETFL error");
		return -1;
	}
	return 0;
}
	
int clr_fl( int fd, int flags ) {
	
	int val;

	if( (val = fcntl( fd, F_GETFL, 0) ) < 0 ) {
		fprintf(stderr, "fcntl F_GETFL error" );
		return -1;
	}

	val &= ~flags;

	if( fcntl( fd, F_SETFL, val ) < 0 ) {
		fprintf( stderr, "fcntl F_SETFL error" );
		return -1;
	}
	return 0;
}

// ---------------------------------------------------------------------------------
// Flesh out a ubiqitous growing string buffer
// ---------------------------------------------------------------------------------

growing_buffer* buffer_init(int num_initial_bytes) {

	if( num_initial_bytes > BUFFER_MAX_SIZE ) {
		return NULL;
	}


	size_t len = sizeof(growing_buffer);

	growing_buffer* gb = (growing_buffer*) safe_malloc(len);

	gb->n_used = 0;/* nothing stored so far */
	gb->size = num_initial_bytes;
	gb->buf = (char *) safe_malloc(gb->size + 1);

	return gb;
}

int buffer_fadd(growing_buffer* gb, const char* format, ... ) {

	if(!gb || !format) return 0; 

	va_list args;

	int len = strlen(format) + 1024;
	char buf[len];
	memset(buf, 0, len);

	va_start(args, format);
	vsnprintf(buf, len - 1, format, args);
	va_end(args);

	return buffer_add(gb, buf);

}


int buffer_add(growing_buffer* gb, char* data) {


	if( ! gb || ! data  ) { return 0; }
	int data_len = strlen( data );

	if( data_len == 0 ) { return 0; }
	int total_len = data_len + gb->n_used;

	while( total_len >= gb->size ) {
		gb->size *= 2;
	}

	if( gb->size > BUFFER_MAX_SIZE ) {
		fprintf(stderr, "Buffer reached MAX_SIZE of %d", BUFFER_MAX_SIZE );
		buffer_free( gb );
		return 0;
	}

	char* new_data = (char*) safe_malloc( gb->size );

	strcpy( new_data, gb->buf );
	free( gb->buf );
	gb->buf = new_data;

	strcat( gb->buf, data );
	gb->n_used = total_len;
	return total_len;
}


int buffer_reset( growing_buffer *gb){
	if( gb == NULL ) { return 0; }
	if( gb->buf == NULL ) { return 0; }
	memset( gb->buf, 0, gb->size );
	gb->n_used = 0;
	return 1;
}

int buffer_free( growing_buffer* gb ) {
	if( gb == NULL ) 
		return 0;
	free( gb->buf );
	free( gb );
	return 1;
}

char* buffer_data( growing_buffer *gb) {
	return strdup( gb->buf );
}


int buffer_add_char(growing_buffer* gb, char c) {
	char buf[2];
	buf[0] = c;
	buf[1] = '\0';
	buffer_add(gb, buf);
	return 1;
}



char* uescape( const char* string, int size, int full_escape ) {

	growing_buffer* buf = buffer_init(size + 64);
	int idx = 0;
	long unsigned int c = 0;

	while (string[idx]) {
	
		c ^= c;
		
		if ((string[idx] & 0xF0) == 0xF0) {
			c = string[idx]<<18;

			if( size - idx < 4 ) return NULL;
			
			idx++;
			c |= (string[idx] & 0x3F)<<12;
			
			idx++;
			c |= (string[idx] & 0x3F)<<6;
			
			idx++;
			c |= (string[idx] & 0x3F);
			
			c ^= 0xFF000000;
			
			buffer_fadd(buf, "\\u%0.4x", c);

		} else if ((string[idx] & 0xE0) == 0xE0) {
			c = string[idx]<<12;
			if( size - idx < 3 ) return NULL;
			
			idx++;
			c |= (string[idx] & 0x3F)<<6;
			
			idx++;
			c |= (string[idx] & 0x3F);
			
			c ^= 0xFFF80000;
			
			buffer_fadd(buf, "\\u%0.4x", c);

		} else if ((string[idx] & 0xC0) == 0xC0) {
			// Two byte char
			c = string[idx]<<6;
			if( size - idx < 2 ) return NULL;
			
			idx++;
			c |= (string[idx] & 0x3F);
			
			c ^= 0xFFFFF000;
			
			buffer_fadd(buf, "\\u%0.4x", c);

		} else {
			c = string[idx];

			/* escape the usual suspects */
			if(full_escape) {
				switch(c) {
					case '"':
						buffer_add_char(buf, '\\');
						buffer_add_char(buf, '"');
						break;
	
					case '\b':
						buffer_add_char(buf, '\\');
						buffer_add_char(buf, 'b');
						break;
	
					case '\f':
						buffer_add_char(buf, '\\');
						buffer_add_char(buf, 'f');
						break;
	
					case '\t':
						buffer_add_char(buf, '\\');
						buffer_add_char(buf, 't');
						break;
	
					case '\n':
						buffer_add_char(buf, '\\');
						buffer_add_char(buf, 'n');
						break;
	
					case '\r':
						buffer_add_char(buf, '\\');
						buffer_add_char(buf, 'r');
						break;

					default:
						buffer_add_char(buf, c);
				}

			} else {
				buffer_add_char(buf, c);
			}
		}

		idx++;
	}

	char* d = buffer_data(buf);
	buffer_free(buf);
	return d;
}
	
