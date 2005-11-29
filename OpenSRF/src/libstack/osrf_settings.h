#ifndef OSRF_SETTINGS_H
#define OSRF_SETTINGS_H

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>
#include <stdarg.h>

#include "opensrf/log.h"
#include "opensrf/utils.h"
#include "objson/object.h"
#include "objson/json_parser.h"
#include "osrf_app_session.h"


typedef struct { 
	char* hostname; 
	jsonObject* config; 
} osrf_host_config;


osrf_host_config* osrf_settings_new_host_config(char* hostname);
void osrf_settings_free_host_config(osrf_host_config*);
char* osrf_settings_host_value(char* path, ...);
jsonObject* osrf_settings_host_value_object(char* format, ...);
int osrf_settings_retrieve(char* hostname);

#endif

