#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>

/* libxml stuff for the config reader */
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/tree.h>

#include "utils.h"

#ifndef GENERIC_UTILS_H
#define GENERIC_UTILS_H

#define LOG_ERROR 1
#define LOG_WARNING 2
#define LOG_INFO 3
#define LOG_DEBUG 4


#define equals(a,b) !strcmp(a,b) 


/*
inline void* safe_malloc( int size );

#define BUFFER_MAX_SIZE 10485760 

struct growing_buffer_struct {
	char *buf;
	int n_used;
	int size;
};
typedef struct growing_buffer_struct growing_buffer;

growing_buffer* buffer_init( int initial_num_bytes);
int buffer_addchar(growing_buffer* gb, char c);
int buffer_add(growing_buffer* gb, char* c);
int buffer_reset( growing_buffer* gb);
char* buffer_data( growing_buffer* gb);
int buffer_free( growing_buffer* gb );
int buffer_fadd(growing_buffer* gb, const char* format, ... );
*/


void log_free(); 

// Utility method
void get_timestamp( char buf_36chars[]);
double get_timestamp_millis();

// ---------------------------------------------------------------------------------
// Error handling interface.
// ---------------------------------------------------------------------------------

void fatal_handler( char* message, ...);
void warning_handler( char* message, ... );
void info_handler( char* message, ... );
void debug_handler( char* message, ... );

/** If we return 0 either the log level is less than LOG_ERROR  
  * or we could not open the log file
  */
int log_init( int log_level, char* log_file );

// ---------------------------------------------------------------------------------
// Config file module
// ---------------------------------------------------------------------------------
struct config_reader_struct {
	xmlDocPtr config_doc;
	xmlXPathContextPtr xpathCx;
	char* name;
	struct config_reader_struct* next;
};
typedef struct config_reader_struct config_reader;
config_reader* conf_reader;

//void config_reader_init( char* config_file );
void config_reader_init( char* name, char* config_file );

void config_reader_free();

// allocastes a char*. FREE me.
char* config_value( const char* config_name, const char* xp_query, ... );

#endif
