#ifndef OSRF_HASH_H
#define OSRF_HASH_H

#include <Judy.h>
#include "opensrf/utils.h"
#include "opensrf/string_array.h"

#define OSRF_HASH_MAXKEY 256

struct __osrfBigHashStruct {
	Pvoid_t hash;							/* the hash */
	void (*freeItem) (char* key, void* item);	/* callback for freeing stored items */
};
typedef struct __osrfBigHashStruct osrfBigHash;


struct __osrfBigHashIteratorStruct {
	char* current;
	osrfBigHash* hash;
};
typedef struct __osrfBigHashIteratorStruct osrfBigHashIterator;

/**
  Allocates a new hash object
  */
osrfBigHash* osrfNewBigHash();

/**
  Sets the given key with the given item
  if "freeItem" is defined and an item already exists at the given location, 
  then old item is freed and the new item is put into place.
  if "freeItem" is not defined and an item already exists, the old item
  is returned.
  @return The old item if exists and there is no 'freeItem', returns NULL
  otherwise
  */
void* osrfBigHashSet( osrfBigHash* hash, void* item, const char* key, ... );

/**
  Removes an item from the hash.
  if 'freeItem' is defined it is used and NULL is returned,
  else the freed item is returned
  */
void* osrfBigHashRemove( osrfBigHash* hash, const char* key, ... );

void* osrfBigHashGet( osrfBigHash* hash, const char* key, ... );


/**
  @return A list of strings representing the keys of the hash. 
  caller is responsible for freeing the returned string array 
  with osrfStringArrayFree();
  */
osrfStringArray* osrfBigHashKeys( osrfBigHash* hash );

/**
  Frees a hash
  */
void osrfBigHashFree( osrfBigHash* hash );

/**
  @return The number of items in the hash
  */
unsigned long osrfBigHashGetCount( osrfBigHash* hash );




/**
  Creates a new list iterator with the given list
  */
osrfBigHashIterator* osrfNewBigHashIterator( osrfBigHash* hash );

/**
  Returns the next non-NULL item in the list, return NULL when
  the end of the list has been reached
  */
void* osrfBigHashIteratorNext( osrfBigHashIterator* itr );

/**
  Deallocates the given list
  */
void osrfBigHashIteratorFree( osrfBigHashIterator* itr );

void osrfBigHashIteratorReset( osrfBigHashIterator* itr );

#endif
