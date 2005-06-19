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


char* uescape( const char* string, int size, int full_escape );
double get_timestamp_millis();

/* utility methods */
int set_fl( int fd, int flags );
int clr_fl( int fd, int flags );



// Utility method
double get_timestamp_millis();




#endif
