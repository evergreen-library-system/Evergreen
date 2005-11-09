#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
#include "apr_compat.h"
#include "apr_strings.h"
#include "apr_reslist.h"


#include "string_array.h"
#include "utils.h"
#include "opensrf/utils.h"

#ifndef APACHE_TOOLS_H
#define APACHE_TOOLS_H


/* parses apache URL params (GET and POST).  
	Returns a string_array of the form [ key, val, key, val, ...]
	Returns NULL if there are no params */
string_array* apacheParseParms(request_rec* r);

/* provide the params string array, and this will generate a 
	string of array of param keys 
	the returned string_array most be freed by the caller
	*/
string_array* apacheGetParamKeys(string_array* params);

/* provide the params string array and a key name, and 
	this will provide the value found for that key 
	the returned string_array most be freed by the caller
	*/
string_array* apacheGetParamValues(string_array* params, char* key);

/* returns the first value found for the given param.  
	char* must be freed by the caller */
char* apacheGetFirstParamValue(string_array* params, char* key);

/* Writes msg to stderr, flushes stderr, and returns 0 */
int apacheDebug( char* msg, ... );

/* Writes to stderr, flushe stderr, and returns HTTP_INTERNAL_SERVER_ERROR; 
 */
int apacheError( char* msg, ... );


#endif
