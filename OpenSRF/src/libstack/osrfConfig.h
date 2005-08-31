/*
Copyright (C) 2005  Georgia Public Library Service 
Bill Erickson <highfalutin@gmail.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#ifndef _OSRF_CONFIG_H
#define _OSRF_CONFIG_H

#include "xml_utils.h"
#include "utils.h"
#include "string_array.h"
#include "objson/object.h"

typedef struct {
	jsonObject* config;
	char* configContext;
} osrfConfig;


/**
	Parses a new config file.  Caller is responsible for freeing the returned
		config object when finished.  
	@param configFile The XML config file to parse.
	@param configContext Optional root of the subtree in the config file where 
	we will look for values. If it's not provided,  searches will be 
	performed from the root of the config file
	@return The config object if the file parses successfully.  Otherwise
		it returns NULL;
*/
osrfConfig* osrfConfigInit(char* configFile, char* configContext);

/**
	@return True if we have a default config defined
*/
int osrfConfigHasDefaultConfig();

/**
	Replaces the config object's objson object.  This is useful
	if you have an ojbson object already and not an XML config
	file to parse.
	@param cfg The config object to alter
	@param obj The objson objet to use when searching values
*/
void osrfConfigReplaceConfig(osrfConfig* cfg, const jsonObject* obj);

/** Deallocates a config object 
	@param cfg The config object to free
*/
void osrfConfigFree(osrfConfig* cfg);


/* Assigns the default config file.  This file will be used whenever
	NULL is passed to config retrieval functions 
	@param cfg The config object to use as the default config
*/
void osrfConfigSetDefaultConfig(osrfConfig* cfg);

/* frees the default config if one exists */
void osrfConfigCleanup();


/** 
	Returns the value in the config found at 'path'.
	If the value found at 'path' is a long or a double,
	the value is stringified and then returned.
	The caller must free the returned char* 

	if there is a configContext, then it will be appended to 
	the front of the path like so: //<configContext>/<path>
	if no configContext was provided to osfConfigSetFile, then 
	the path is interpreted literally.
	@param cfg The config file to search or NULL if the default
		config should be used
	@param path The search path
*/
char* osrfConfigGetValue(osrfConfig* cfg, char* path, ...);

/** 
	Puts the list of values found at 'path' into the pre-allocated 
	string array.  
	Note that the config node found at 'path' must be an array.
	@param cfg The config file to search or NULL if the default
		config should be used
	@param arr An allocated string_array where the values will
		be stored
	@param path The search path
	@return the number of values added to the string array;
*/

int osrfConfigGetValueList(osrfConfig* cfg, osrfStringArray* arr, char* path, ...);


#endif
