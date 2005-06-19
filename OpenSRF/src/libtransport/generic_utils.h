#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>

#include "logging.h"
#include "utils.h"

/* libxml stuff for the config reader */
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/tree.h>

#include "utils.h"

#ifndef GENERIC_UTILS_H
#define GENERIC_UTILS_H

#define equals(a,b) !strcmp(a,b) 

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
