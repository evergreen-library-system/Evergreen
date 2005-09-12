#include "opensrf/utils.h"
#include "osrf_settings.h"
#include "osrfConfig.h"

enum OSRF_LOG_LEVEL { OSRF_ERROR = 1, OSRF_WARN = 2, OSRF_INFO = 3, OSRF_DEBUG = 4 };

int osrfLogInit(char* appname);
void osrfLog( enum OSRF_LOG_LEVEL, char* msg, ... );

