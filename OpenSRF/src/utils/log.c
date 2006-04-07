#include "log.h"

int __osrfLogType					= -1;
int __osrfLogFacility			= LOG_LOCAL0;
int __osrfLogActFacility		= LOG_LOCAL1;
char* __osrfLogFile				= NULL;
char* __osrfLogAppname			= NULL;
int __osrfLogLevel				= OSRF_LOG_INFO;
int __osrfLogActivityEnabled	= 1;


void osrfLogCleanup() {
	free(__osrfLogAppname);
	free(__osrfLogFile);
}


void osrfLogInit( int type, const char* appname, int maxlevel ) {
	osrfLogSetType(type);
	if(appname) osrfLogSetAppname(appname);
	osrfLogSetLevel(maxlevel);
	if( type == OSRF_LOG_TYPE_SYSLOG ) 
		openlog(__osrfLogAppname, 0, __osrfLogFacility );
}

void osrfLogSetType( int logtype ) { 
	if( logtype != OSRF_LOG_TYPE_FILE &&
			logtype != OSRF_LOG_TYPE_SYSLOG ) {
		fprintf(stderr, "Unrecognized log type.  Logging to stderr\n");
		return;
	}
	__osrfLogType = logtype; 
}

void osrfLogSetFile( const char* logfile ) {
	if(!logfile) return;
	if(__osrfLogFile) free(__osrfLogFile);
	__osrfLogFile = strdup(logfile);
}

void osrfLogSetActivityEnabled( int enabled ) {
	__osrfLogActivityEnabled = enabled;
}

void osrfLogSetAppname( const char* appname ) {
	if(!appname) return;
	if(__osrfLogAppname) free(__osrfLogAppname);
	__osrfLogAppname = strdup(appname);

	/* if syslogging, re-open the log with the appname */
	if( __osrfLogType == OSRF_LOG_TYPE_SYSLOG) {
		closelog();
		openlog(__osrfLogAppname, 0, __osrfLogFacility);
	}
}

void osrfLogSetSyslogFacility( int facility ) {
	__osrfLogFacility = facility;
}
void osrfLogSetSyslogActFacility( int facility ) {
	__osrfLogActFacility = facility;
}

void osrfLogSetLevel( int loglevel ) {
	__osrfLogLevel = loglevel;
}

void osrfLogError( const char* file, int line, const char* msg, ... ) 
	{ OSRF_LOG_GO(file, line, msg, OSRF_LOG_ERROR); }
void osrfLogWarning( const char* file, int line, const char* msg, ... ) 
	{ OSRF_LOG_GO(file, line, msg, OSRF_LOG_WARNING); }
void osrfLogInfo( const char* file, int line, const char* msg, ... ) 
	{ OSRF_LOG_GO(file, line, msg, OSRF_LOG_INFO); }
void osrfLogDebug( const char* file, int line, const char* msg, ... ) 
	{ OSRF_LOG_GO(file, line, msg, OSRF_LOG_DEBUG); }
void osrfLogInternal( const char* file, int line, const char* msg, ... ) 
	{ OSRF_LOG_GO(file, line, msg, OSRF_LOG_INTERNAL); }
void osrfLogActivity( const char* file, int line, const char* msg, ... ) { 
	OSRF_LOG_GO(file, line, msg, OSRF_LOG_ACTIVITY); 
	_osrfLogDetail( OSRF_LOG_INFO, file, line, VA_BUF ); /* also log at info level */
}

void _osrfLogDetail( int level, const char* filename, int line, char* msg ) {

	if( level == OSRF_LOG_ACTIVITY && ! __osrfLogActivityEnabled ) return;
	if( level > __osrfLogLevel ) return;
	if(!msg) return;
	if(!filename) filename = "";

	char* l = "INFO";		/* level name */
	int lvl = LOG_INFO;	/* syslog level */
	int fac = __osrfLogFacility;

	switch( level ) {
		case OSRF_LOG_ERROR:		
			l = "ERR "; 
			lvl = LOG_ERR;
			break;

		case OSRF_LOG_WARNING:	
			l = "WARN"; 
			lvl = LOG_WARNING;
			break;

		case OSRF_LOG_INFO:		
			l = "INFO"; 
			lvl = LOG_INFO;
			break;

		case OSRF_LOG_DEBUG:	
			l = "DEBG"; 
			lvl = LOG_DEBUG;
			break;

		case OSRF_LOG_INTERNAL: 
			l = "INT "; 
			lvl = LOG_DEBUG;
			break;

		case OSRF_LOG_ACTIVITY: 
			l = "ACT"; 
			lvl = LOG_INFO;
			fac = __osrfLogActFacility;
			break;
	}

	if(__osrfLogType == OSRF_LOG_TYPE_SYSLOG )
		syslog( fac | lvl, "[%s:%d:%s:%d] %s", l, getpid(), filename, line, msg );

	else if( __osrfLogType == OSRF_LOG_TYPE_FILE )
		_osrfLogToFile("[%s:%d:%s:%d] %s", l, getpid(), filename, line, msg );

}


void _osrfLogToFile( char* msg, ... ) {

	if(!msg) return;
	if(!__osrfLogFile) return;
	VA_LIST_TO_STRING(msg);

	if(!__osrfLogAppname) __osrfLogAppname = strdup("osrf");
	int l = strlen(VA_BUF) + strlen(__osrfLogAppname) + 36;
	char buf[l];
	bzero(buf,l);

	char datebuf[36];
	bzero(datebuf,36);
	time_t t = time(NULL);
	struct tm* tms = localtime(&t);
	strftime(datebuf, 36, "%Y-%m-%d %H:%M:%S", tms);

	FILE* file = fopen(__osrfLogFile, "a");
	if(!file) {
		fprintf(stderr, "Unable to fopen file %s for writing", __osrfLogFile);
		return;
	}

	fprintf(file, "%s %s %s\n", __osrfLogAppname, datebuf, VA_BUF );
	if( fclose(file) != 0 ) 
		osrfLogWarning(OSRF_LOG_MARK, "Error closing log file: %s", strerror(errno));
	
}


int osrfLogFacilityToInt( char* facility ) {
	if(!facility) return LOG_LOCAL0;
	if(strlen(facility) < 6) return LOG_LOCAL0;
	switch( facility[5] ) {
		case '0': return LOG_LOCAL0;
		case '1': return LOG_LOCAL1;
		case '2': return LOG_LOCAL2;
		case '3': return LOG_LOCAL3;
		case '4': return LOG_LOCAL4;
		case '5': return LOG_LOCAL5;
		case '6': return LOG_LOCAL6;
		case '7': return LOG_LOCAL7;
	}
	return LOG_LOCAL0;
}


