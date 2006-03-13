#include "osrf_hash.h"

osrfHash* osrfNewHash() {
	osrfHash* hash = safe_malloc(sizeof(osrfHash));
	hash->hash		= osrfNewList();
	hash->freeItem = NULL;
	hash->size		= 0;
	return hash;
}


/* algorithm proposed by Donald E. Knuth 
 * in The Art Of Computer Programming Volume 3 (more or less..)*/
static unsigned int osrfHashMakeKey(char* str) {
	if(!str) return 0;
	unsigned int len = strlen(str);
	unsigned int h = len;
	unsigned int i    = 0;
	for(i = 0; i < len; str++, i++)
		h = ((h << 5) ^ (h >> 27)) ^ (*str);
	return (h & 0x7FF);
}


/* returns the index of the item and points l to the sublist the item
 * lives in if the item and points n to the hashnode the item 
 * lives in if the item is found.  Otherwise -1 is returned */
static unsigned int osrfHashFindItem( osrfHash* hash, char* key, osrfList** l, osrfHashNode** n ) {
	if(!(hash && key)) return -1;

	int i = osrfHashMakeKey(key);
	osrfList* list = osrfListGetIndex( hash->hash, i );
	if( !list ) { return -1; }


	int k;
	osrfHashNode* node = NULL;
	for( k = 0; k < list->size; k++ ) {
		node = osrfListGetIndex(list, k);
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
	osrfHashNode* n = safe_malloc(sizeof(osrfHashNode));
	n->key = strdup(key);
	n->item = item;
	return n;
}

void osrfHashNodeFree(osrfHashNode* node) {
	if(!node) return;
	free(node->key);
	free(node);
}

void* osrfHashSet( osrfHash* hash, void* item, const char* key, ... ) {
	if(!(hash && item && key )) return NULL;

	VA_LIST_TO_STRING(key);
	void* olditem = osrfHashRemove( hash, VA_BUF );
	int bucketkey = osrfHashMakeKey(VA_BUF);

	osrfList* bucket;
	if( !(bucket = osrfListGetIndex(hash->hash, bucketkey)) ) {
		bucket = osrfNewList();
		osrfListSet( hash->hash, bucket, bucketkey );
	}

	osrfHashNode* node = osrfNewHashNode(VA_BUF, item);
	osrfListPushFirst( bucket, node );

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

	void* item = NULL;
	if(hash->freeItem) 
		hash->freeItem((char*) VA_BUF, node->item);
	 else item = node->item;

	osrfHashNodeFree(node);
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


osrfStringArray* osrfHashKeys( osrfHash* hash ) {
	if(!hash) return NULL;

	int i, k;
	osrfList* list;
	osrfHashNode* node;
	osrfStringArray* strings = osrfNewStringArray(8);

	for( i = 0; i != hash->hash->size; i++ ) {
		list = osrfListGetIndex( hash->hash, i );
		if(list) {
			for( k = 0; k != list->size; k++ ) {
				node = osrfListGetIndex( list, k );	
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
		if( ( list = osrfListGetIndex( hash->hash, i )) ) {
			for( j = 0; j != list->size; j++ ) {
				if( (node = osrfListGetIndex( list, j )) ) {
					if( hash->freeItem )
						hash->freeItem( node->key, node->item );
					osrfHashNodeFree(node);
				}
			}
			osrfListFree(list);
		}
	}

	osrfListFree(hash->hash);
	free(hash);
}



osrfHashIterator* osrfNewHashIterator( osrfHash* hash ) {
	if(!hash) return NULL;
	osrfHashIterator* itr = safe_malloc(sizeof(osrfHashIterator));
	itr->hash = hash;
	itr->current = NULL;
	itr->keys = osrfHashKeys(hash);
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
	osrfStringArrayFree(itr->keys);
	free(itr);
}

void osrfHashIteratorReset( osrfHashIterator* itr ) {
	if(!itr) return;
	free(itr->current);
	osrfStringArrayFree(itr->keys);
	itr->keys = osrfHashKeys(itr->hash);
	itr->currentIdx = 0;
	itr->current = NULL;
}



