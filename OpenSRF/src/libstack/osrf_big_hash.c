#include "osrf_big_hash.h"

osrfBigHash* osrfNewBigHash() {
	osrfBigHash* hash = safe_malloc(sizeof(osrfBigHash));
	hash->hash = (Pvoid_t) NULL;
	hash->freeItem = NULL;
	return hash;
}

void* osrfBigHashSet( osrfBigHash* hash, void* item, const char* key, ... ) {
	if(!(hash && item && key )) return NULL;

	Word_t* value;
	VA_LIST_TO_STRING(key);
	uint8_t idx[strlen(VA_BUF) + 1];
	strcpy( idx, VA_BUF );

	void* olditem = osrfBigHashRemove( hash, VA_BUF );

	JSLI(value, hash->hash, idx);
	if(value) *value = (Word_t) item;
	return olditem;
	
}

void* osrfBigHashRemove( osrfBigHash* hash, const char* key, ... ) {
	if(!(hash && key )) return NULL;

	VA_LIST_TO_STRING(key);

	Word_t* value;
	uint8_t idx[strlen(VA_BUF) + 1];
	strcpy( idx, VA_BUF );
	void* item = NULL;
	int retcode;

	JSLG( value, hash->hash,  idx);

	if( value ) {
		item = (void*) *value;
		if(item) {
			if( hash->freeItem ) {
				hash->freeItem( (char*) idx, item ); 
				item = NULL;
			}
		}
	}


	JSLD( retcode, hash->hash, idx );

	return item;
}


void* osrfBigHashGet( osrfBigHash* hash, const char* key, ... ) {
	if(!(hash && key )) return NULL;

	VA_LIST_TO_STRING(key);

	Word_t* value;
	uint8_t idx[strlen(VA_BUF) + 1];
	strcpy( idx, VA_BUF );

	JSLG( value, hash->hash, idx );
	if(value) return (void*) *value;
	return NULL;
}


osrfStringArray* osrfBigHashKeys( osrfBigHash* hash ) {
	if(!hash) return NULL;

	Word_t* value;
	uint8_t idx[OSRF_HASH_MAXKEY];
	strcpy(idx, "");
	char* key;
	osrfStringArray* strings = osrfNewStringArray(8);

	JSLF( value, hash->hash, idx );

	while( value ) {
		key = (char*) idx;
		osrfStringArrayAdd( strings, key );
		JSLN( value, hash->hash, idx );
	}

	return strings;
}


unsigned long osrfBigHashGetCount( osrfBigHash* hash ) {
	if(!hash) return -1;

	Word_t* value;
	unsigned long count = 0;
	uint8_t idx[OSRF_HASH_MAXKEY];

	strcpy( (char*) idx, "");
	JSLF(value, hash->hash, idx);

	while(value) {
		count++;
		JSLN( value, hash->hash, idx );
	}

	return count;
}

void osrfBigHashFree( osrfBigHash* hash ) {
	if(!hash) return;

	int i;
	osrfStringArray* keys = osrfBigHashKeys( hash );

	for( i = 0; i != keys->size; i++ )  {
		char* key = (char*) osrfStringArrayGetString( keys, i );
		osrfBigHashRemove( hash, key );
	}

	osrfStringArrayFree(keys);
	free(hash);
}



osrfBigHashIterator* osrfNewBigHashIterator( osrfBigHash* hash ) {
	if(!hash) return NULL;
	osrfBigHashIterator* itr = safe_malloc(sizeof(osrfBigHashIterator));
	itr->hash = hash;
	itr->current = NULL;
	return itr;
}

void* osrfBigHashIteratorNext( osrfBigHashIterator* itr ) {
	if(!(itr && itr->hash)) return NULL;

	Word_t* value;
	uint8_t idx[OSRF_HASH_MAXKEY];

	if( itr->current == NULL ) { /* get the first item in the list */
		strcpy(idx, "");
		JSLF( value, itr->hash->hash, idx );

	} else {
		strcpy(idx, itr->current);
		JSLN( value, itr->hash->hash, idx );
	}

	if(value) {
		free(itr->current);
		itr->current = strdup((char*) idx);
		return (void*) *value;
	}

	return NULL;

}

void osrfBigHashIteratorFree( osrfBigHashIterator* itr ) {
	if(!itr) return;
	free(itr->current);
	free(itr);
}

void osrfBigHashIteratorReset( osrfBigHashIterator* itr ) {
	if(!itr) return;
	free(itr->current);
	itr->current = NULL;
}



