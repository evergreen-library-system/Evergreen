#include "osrf_hash.h"

osrfHash* osrfNewHash() {
	osrfHash* hash;
	OSRF_MALLOC(hash, sizeof(osrfHash));
	hash->hash		= osrfNewList();
	hash->freeItem = NULL;
	hash->size		= 0;
	hash->keys		= osrfNewStringArray(64);
	return hash;
}


/* algorithm proposed by Donald E. Knuth 
 * in The Art Of Computer Programming Volume 3 (more or less..)*/
static unsigned int osrfHashMakeKey(char* str) {
	if(!str) return 0;
	unsigned int len = strlen(str);
	unsigned int h = len;
	unsigned int i = 0;
	for(i = 0; i < len; str++, i++)
		h = ((h << 5) ^ (h >> 27)) ^ (*str);
	return (h & (OSRF_HASH_LIST_SIZE-1));
}


/*
#define OSRF_HASH_MAKE_KEY(str,num)	\
	do {\
		unsigned int len = strlen(str); \
		unsigned int h = len;\
		unsigned int i = 0;\
		for(i = 0; i < len; str++, i++)\
			h = ((h << 5) ^ (h >> 27)) ^ (*str);\
		*num = (h & (OSRF_HASH_LIST_SIZE-1));\
	} while(0)
	*/

/*
#define OSRF_HASH_MAKE_KEY(str,num)	\
	unsigned int ___len = strlen(str);\
	unsigned int ___h = ___len;\
	unsigned int ___i = 0;\
	for(___i = 0; ___i < ___len; str++, ___i++)\
		___h = ((___h << 5) ^ (___h >> 27)) ^ (*str);\
	num = (___h & (OSRF_HASH_LIST_SIZE-1));\
	*/

/*
#define OSRF_HASH_MAKE_KEY(str,num,len)	\
	unsigned int __i;\
	num = len;\
	for(__i = 0; __i < len; __i++, str++)\
		num = ((num << 5) ^ (num >> 27)) ^ (*str);\
	num = (num & (OSRF_HASH_LIST_SIZE-1));\
	*/

/*
#define OSRF_HASH_MAKE_KEY(str,num, len)	\
	num = osrfHashMakeKey(str);\
	fprintf(stderr, "made num: %d\n", num);
	*/
	


/* returns the index of the item and points l to the sublist the item
 * lives in if the item and points n to the hashnode the item 
 * lives in if the item is found.  Otherwise -1 is returned */
static unsigned int osrfHashFindItem( osrfHash* hash, char* key, osrfList** l, osrfHashNode** n ) {
	if(!(hash && key)) return -1;


	int i = osrfHashMakeKey(key);

	/*
	unsigned int i;
	OSRF_HASH_MAKE_KEY(key, &i);
	*/

	osrfList* list = OSRF_LIST_GET_INDEX( hash->hash, i );
	if( !list ) { return -1; }

	int k;
	osrfHashNode* node = NULL;
	for( k = 0; k < list->size; k++ ) {
		node = OSRF_LIST_GET_INDEX(list, k);
		if( node && node->key && !strcmp(node->key, key) )
			break;
		node = NULL;
	}

	if(!node) return -1;

	if(l) *l = list;
	if(n) *n = node;
	return k;
}

osrfHashNode* osrfNewHashNode(char* key, void* item) {
	if(!(key && item)) return NULL;
	osrfHashNode* n;
	OSRF_MALLOC(n, sizeof(osrfHashNode));
	n->key = strdup(key);
	n->item = item;
	return n;
}

void* osrfHashNodeFree(osrfHash* hash, osrfHashNode* node) {
	if(!(node && hash)) return NULL;
	void* item = NULL;
	if( hash->freeItem )
		hash->freeItem( node->key, node->item );
	else item = node->item;
	free(node->key);
	free(node);
	return item;
}

void* osrfHashSet( osrfHash* hash, void* item, const char* key, ... ) {
	if(!(hash && item && key )) return NULL;

	VA_LIST_TO_STRING(key);
	void* olditem = osrfHashRemove( hash, VA_BUF );

	int bucketkey = osrfHashMakeKey(VA_BUF);

	/*
	unsigned int bucketkey;
	OSRF_HASH_MAKE_KEY(VA_BUF, &bucketkey);
	*/

	osrfList* bucket;
	if( !(bucket = OSRF_LIST_GET_INDEX(hash->hash, bucketkey)) ) {
		bucket = osrfNewList();
		osrfListSet( hash->hash, bucket, bucketkey );
	}

	osrfHashNode* node = osrfNewHashNode(VA_BUF, item);
	osrfListPushFirst( bucket, node );

	if(!osrfStringArrayContains(hash->keys, VA_BUF))
		osrfStringArrayAdd( hash->keys, VA_BUF );

	hash->size++;
	return olditem;
}

void* osrfHashRemove( osrfHash* hash, const char* key, ... ) {
	if(!(hash && key )) return NULL;

	VA_LIST_TO_STRING(key);

	osrfList* list = NULL;
	osrfHashNode* node;
	int index = osrfHashFindItem( hash, (char*) VA_BUF, &list, &node );
	if( index == -1 ) return NULL;

	osrfListRemove( list, index );
	hash->size--;

	void* item = osrfHashNodeFree(hash, node);
	osrfStringArrayRemove(hash->keys, VA_BUF);
	return item;
}


void* osrfHashGet( osrfHash* hash, const char* key, ... ) {
	if(!(hash && key )) return NULL;
	VA_LIST_TO_STRING(key);

	osrfHashNode* node = NULL;
	int index = osrfHashFindItem( hash, (char*) VA_BUF, NULL, &node );
	if( index == -1 ) return NULL;
	return node->item;
}


osrfStringArray* osrfHashKeysInc( osrfHash* hash ) {
	if(!hash) return NULL;
	return hash->keys;
}

osrfStringArray* osrfHashKeys( osrfHash* hash ) {
	if(!hash) return NULL;
	
	int i, k;
	osrfList* list;
	osrfHashNode* node;
	osrfStringArray* strings = osrfNewStringArray(8);

	for( i = 0; i != hash->hash->size; i++ ) {
		list = OSRF_LIST_GET_INDEX( hash->hash, i );
		if(list) {
			for( k = 0; k != list->size; k++ ) {
				node = OSRF_LIST_GET_INDEX( list, k );	
				if( node ) osrfStringArrayAdd( strings, node->key );
			}
		}
	}

	return strings;
}


unsigned long osrfHashGetCount( osrfHash* hash ) {
	if(!hash) return -1;
	return hash->size;
}

void osrfHashFree( osrfHash* hash ) {
	if(!hash) return;

	int i, j;
	osrfList* list;
	osrfHashNode* node;

	for( i = 0; i != hash->hash->size; i++ ) {
		if( ( list = OSRF_LIST_GET_INDEX( hash->hash, i )) ) {
			for( j = 0; j != list->size; j++ ) {
				if( (node = OSRF_LIST_GET_INDEX( list, j )) ) {
					OSRF_HASH_NODE_FREE(hash, node);
				}
			}
			osrfListFree(list);
		}
	}

	osrfListFree(hash->hash);
	osrfStringArrayFree(hash->keys);
	free(hash);
}



osrfHashIterator* osrfNewHashIterator( osrfHash* hash ) {
	if(!hash) return NULL;
	//osrfHashIterator* itr = safe_malloc(sizeof(osrfHashIterator));
	osrfHashIterator* itr;
	OSRF_MALLOC(itr, sizeof(osrfHashIterator));
	itr->hash = hash;
	itr->current = NULL;
	itr->keys = osrfHashKeysInc(hash);
	return itr;
}

void* osrfHashIteratorNext( osrfHashIterator* itr ) {
	if(!(itr && itr->hash)) return NULL;
	if( itr->currentIdx >= itr->keys->size ) return NULL;
	free(itr->current);
	itr->current = strdup(
			osrfStringArrayGetString(itr->keys, itr->currentIdx++));
	char* val = osrfHashGet( itr->hash, itr->current );
	return val;
}

void osrfHashIteratorFree( osrfHashIterator* itr ) {
	if(!itr) return;
	free(itr->current);
	//osrfStringArrayFree(itr->keys);
	free(itr);
}

void osrfHashIteratorReset( osrfHashIterator* itr ) {
	if(!itr) return;
	free(itr->current);
	//osrfStringArrayFree(itr->keys);
	itr->keys = osrfHashKeysInc(itr->hash);
	itr->currentIdx = 0;
	itr->current = NULL;
}



