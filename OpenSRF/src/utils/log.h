#include <syslog.h>
#include <stdio.h>
#include "utils.h"
#include <time.h>
#include <errno.h>

#ifndef OSRF_LOG_INCLUDED
#define OSRF_LOG_INCLUDED

/* log levels */
#define OSRF_LOG_ERROR 1
#define OSRF_LOG_WARNING 2
#define OSRF_LOG_INFO 3
#define OSRF_LOG_DEBUG 4
#define OSRF_LOG_INTERNAL 5
#define OSRF_LOG_ACTIVITY -1

#define OSRF_LOG_TYPE_FILE 1
#define OSRF_LOG_TYPE_SYSLOG 2


#define OSRF_LOG_GO(m,l)		\
	if(!m) return;					\
	VA_LIST_TO_STRING(m);		\
	_osrfLogDetail( l, NULL, -1, NULL, VA_BUF );
	


/* Initializes the logger. */
void osrfLogInit( int type, const char* appname, int maxlevel );
/** Sets the type of logging to perform.  See log types */
void osrfLogSetType( int logtype );
/** Sets the systlog facility for the regular logs */
void osrfLogSetSyslogFacility( int facility );
/** Sets the systlog facility for the activity logs */
void osrfLogSetSyslogActFacility( int facility );
/** Sets the log file to use if we're logging to a file */
void osrfLogSetFile( const char* logfile );
/* once we know which application we're running, call this method to
 * set the appname so log lines can include the app name */
void osrfLogSetAppname( const char* appname );
/** Sets the global log level.  Any log statements with a higher level
 * than "level" will not be logged */
void osrfLogSetLevel( int loglevel );
/* Log an error message */
void osrfLogError( const char* msg, ... );
/* Log a warning message */
void osrfLogWarning( const char* msg, ... );
/* log an info message */
void osrfLogInfo( const char* msg, ... );
/* Log a debug message */
void osrfLogDebug( const char* msg, ... );
/* Log an internal debug message */
void osrfLogInternal( const char* msg, ... );
/* Log an activity message */
void osrfLogActivity( const char* msg, ... );

void osrfLogSetActivityEnabled( int enabled );

/* Use this for logging detailed message containing the filename, line number
 * and function name in addition to the usual level and message */
void osrfLogDetail( int level, char* filename, int line, char* func, char* msg, ... );

/** Actually does the logging */
void _osrfLogDetail( int level, char* filename, int line, char* func, char* msg );

void _osrfLogToFile( char* msg, ... );

/* returns the int representation of the log facility based on the facility name
 * if the facility name is invalid, LOG_LOCAL0 is returned 
 */
int osrfLogFacilityToInt( char* facility );

#endif
