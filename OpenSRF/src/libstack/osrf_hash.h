#ifndef OSRF_HASH_H
#define OSRF_HASH_H

#include "opensrf/utils.h"
#include "opensrf/string_array.h"
#include "osrf_list.h"

/* 0x100 is a good size for small hashes */
#define OSRF_HASH_LIST_SIZE 0x100  /* size of the main hash list */

/* used internally */
#define OSRF_HASH_NODE_FREE(h, n) \
	if(h && n) { \
		if(h->freeItem) h->freeItem(n->key, n->item);\
		free(n->key); free(n); \
	}


struct __osrfHashStruct {
	osrfList* hash; /* this hash */
	void (*freeItem) (char* key, void* item);	/* callback for freeing stored items */
	unsigned int size;
	osrfStringArray* keys;
};
typedef struct __osrfHashStruct osrfHash;

struct _osrfHashNodeStruct {
	char* key;
	void* item;
};
typedef struct _osrfHashNodeStruct osrfHashNode;


struct __osrfHashIteratorStruct {
	char* current;
	int currentIdx;
	osrfHash* hash;
	osrfStringArray* keys;
};
typedef struct __osrfHashIteratorStruct osrfHashIterator;

osrfHashNode* osrfNewHashNode(char* key, void* item);
void* osrfHashNodeFree(osrfHash*, osrfHashNode*);

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

osrfStringArray* osrfHashKeysInc( osrfHash* hash );

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
