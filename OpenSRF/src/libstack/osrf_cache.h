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


#include "objson/object.h"
#include "objson/json_parser.h"
#include "memcache.h"

/**
  osrfCache is a globally shared cache	API
  */


/**
  Initialize the cache.
  @param serverStrings An array of "ip:port" strings to use as cache servers
  @param size The size of the serverStrings array
  @param maxCacheSeconds The maximum amount of time an object / string may
	be cached.  Negative number means there is no limit
  */
int osrfCacheInit( char* serverStrings[], int size, time_t maxCacheSeconds );


/**
  Puts an object into the cache
  @param key The cache key
  @param obj The object to cache
  @param seconds The amount of time to cache the data, negative number means
	to cache up to 'maxCacheSeconds' as set by osrfCacheInit()
  @return 0 on success, -1 on error
  */
int osrfCachePutObject( char* key, const jsonObject* obj, time_t seconds );

/**
  Puts a string into the cache
  @param key The cache key
  @param value The string to cache
  @param seconds The amount of time to cache the data, negative number means
	to cache up to 'maxCacheSeconds' as set by osrfCacheInit()
  @return 0 on success, -1 on error
  */
int osrfCachePutString( char* key, const char* value, time_t seconds);

/**
  Grabs an object from the cache.
  @param key The cache key
  @return The object (which must be freed) if it exists, otherwise returns NULL
  */
jsonObject* osrfCacheGetObject( char* key );

/**
  Grabs a string from the cache.
  @param key The cache key
  @return The string (which must be freed) if it exists, otherwise returns NULL
  */
char* osrfCacheGetString( char* key );

/**
  Removes the item with the given key from the cache.
  @return 0 on success, -1 on error.
  */
int osrfCacheRemove( char* key );



