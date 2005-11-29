#include "osrf_log.h"
#include <time.h>

char* __osrfLogAppName = NULL;
char* __osrfLogDir = NULL;
int __osrfLogLevel = 1;

int osrfLogInit(char* appname) {

	if( !appname ) return -1;
	osrfLogInfo("Initing application log for app %s", appname );

	char* dir = osrf_settings_host_value("/dirs/log");
	if(!dir) return osrfLogWarning("No '/dirs/log' setting in host config");

	char* level = osrfConfigGetValue(NULL, "/loglevel");
	if(level) { __osrfLogLevel = atoi(level); free(level); }

	__osrfLogAppName = strdup(appname);
	__osrfLogDir = strdup(dir);
	return 0;
}


void osrfLog( enum OSRF_LOG_LEVEL level, char* msg, ... ) {

	if( !(__osrfLogDir && __osrfLogAppName) ) return;
	if( level > __osrfLogLevel ) return;

	time_t t = time(NULL);
	struct tm* tms = localtime(&t);

	char datebuf[24];
	bzero(datebuf, 24);
	strftime( datebuf, 23, "%d%m%Y", tms );

	char timebuf[24];
	bzero(timebuf, 24);
	strftime( timebuf, 23, "%Y:%m:%d %H:%M:%S", tms );

	char millis[12];
	bzero(millis, 12);
	double d = get_timestamp_millis();
	d = d - (int) d;
	sprintf(millis, "%.6f", d);


	char* filename = va_list_to_string( 
			"%s/%s.%s.log", __osrfLogDir, __osrfLogAppName, datebuf);

	FILE* file = fopen(filename, "a");
	free(filename);

	if(!file) {
		osrfLogWarning("Unable to open application log file %s\n", filename);
		return;
	}

	VA_LIST_TO_STRING(msg);
	fprintf(file, "[%s.%s %d %d] %s\n", timebuf, millis + 2, getpid(), level, VA_BUF );
	fclose(file);

	if( level == OSRF_ERROR )
		fprintf(stderr, "[%s.%s %d %d] %s\n", timebuf, millis + 2, getpid(), level, VA_BUF );
}


