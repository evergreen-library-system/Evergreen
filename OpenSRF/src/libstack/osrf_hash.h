#ifndef OSRF_HASH_H
#define OSRF_HASH_H

#include <Judy.h>
#include "opensrf/utils.h"
#include "opensrf/string_array.h"

#define OSRF_HASH_MAXKEY 256

struct __osrfHashStruct {
	Pvoid_t hash;							/* the hash */
	void (*freeItem) (char* key, void* item);	/* callback for freeing stored items */
};
typedef struct __osrfHashStruct osrfHash;


struct __osrfHashIteratorStruct {
	char* current;
	osrfHash* hash;
};
typedef struct __osrfHashIteratorStruct osrfHashIterator;

/**
  Allocates a new hash object
  */
osrfHash* osrfNewHash();

/**
  Sets the given key with the given item
  if "freeItem" is defined and an item already exists at the given location, 
  then old item is freed and the new item is put into place.
  if "freeItem" is not defined and an item already exists, the old item
  is returned.
  @return The old item if exists and there is no 'freeItem', returns NULL
  otherwise
  */
void* osrfHashSet( osrfHash* hash, void* item, const char* key, ... );

/**
  Removes an item from the hash.
  if 'freeItem' is defined it is used and NULL is returned,
  else the freed item is returned
  */
void* osrfHashRemove( osrfHash* hash, const char* key, ... );

void* osrfHashGet( osrfHash* hash, const char* key, ... );


/**
  @return A list of strings representing the keys of the hash. 
  caller is responsible for freeing the returned string array 
  with osrfStringArrayFree();
  */
osrfStringArray* osrfHashKeys( osrfHash* hash );

/**
  Frees a hash
  */
void osrfHashFree( osrfHash* hash );

/**
  @return The number of items in the hash
  */
unsigned long osrfHashGetCount( osrfHash* hash );




/**
  Creates a new list iterator with the given list
  */
osrfHashIterator* osrfNewHashIterator( osrfHash* hash );

/**
  Returns the next non-NULL item in the list, return NULL when
  the end of the list has been reached
  */
void* osrfHashIteratorNext( osrfHashIterator* itr );

/**
  Deallocates the given list
  */
void osrfHashIteratorFree( osrfHashIterator* itr );

void osrfHashIteratorReset( osrfHashIterator* itr );

#endif
