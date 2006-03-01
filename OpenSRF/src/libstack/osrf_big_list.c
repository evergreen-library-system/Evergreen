#include "osrf_big_list.h"


osrfBigList* osrfNewBigList() {
	osrfBigList* list = safe_malloc(sizeof(osrfBigList));
	list->list = (Pvoid_t) NULL;
	list->size = 0;
	list->freeItem = NULL;
	return list;
}


int osrfBigListPush( osrfBigList* list, void* item ) {
	if(!(list && item)) return -1;
	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );
	osrfBigListSet( list, item, index+1 );
	return 0;
}


void* osrfBigListSet( osrfBigList* list, void* item, unsigned long position ) {
	if(!list || position < 0) return NULL;

	Word_t* value;
	void* olditem = osrfBigListRemove( list, position );

	JLI( value, list->list, position ); 
	*value = (Word_t) item;
	__osrfBigListSetSize( list );

	return olditem;
}


void* osrfBigListGetIndex( osrfBigList* list, unsigned long position ) {
	if(!list) return NULL;

	Word_t* value;
	JLG( value, list->list, position );
	if(value) return (void*) *value;
	return NULL;
}

void osrfBigListFree( osrfBigList* list ) {
	if(!list) return;

	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );
	int retcode;

	while (value != NULL) {
		if(list->freeItem) 
			list->freeItem( (void*) *value );
		JLD(retcode, list->list, index);
		JLP(value, list->list, index);
	}               

	free(list);
}

void* osrfBigListRemove( osrfBigList* list, int position ) {
	if(!list) return NULL;

	int retcode;
	Word_t* value;
	JLG( value, list->list, position );
	void* olditem = NULL;

	if( value ) {

		olditem = (void*) *value;
		if( olditem ) {
			JLD(retcode, list->list, position );
			if(retcode == 1) {
				if(list->freeItem) {
					list->freeItem( olditem );
					olditem = NULL;
				}
				__osrfBigListSetSize( list );
			}
		}
	}

	return olditem;
}


int osrfBigListFind( osrfBigList* list, void* addr ) {
	if(!(list && addr)) return -1;

	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );

	while (value != NULL) {
		if( (void*) *value == addr )
			return index;
		JLP(value, list->list, index);
	}

	return -1;
}



void __osrfBigListSetSize( osrfBigList* list ) {
	if(!list) return;

	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );
	list->size = index + 1;
}


unsigned long osrfBigListGetCount( osrfBigList* list ) {
	if(!list) return -1;
	unsigned long retcode = -1;
	JLC( retcode, list->list, 0, -1 );
	return retcode;
}


void* osrfBigListPop( osrfBigList* list ) {
	if(!list) return NULL;
	return osrfBigListRemove( list, list->size - 1 );
}


osrfBigBigListIterator* osrfNewBigListIterator( osrfBigList* list ) {
	if(!list) return NULL;
	osrfBigBigListIterator* itr = safe_malloc(sizeof(osrfBigBigListIterator));
	itr->list = list;
	itr->current = 0;
	return itr;
}

void* osrfBigBigListIteratorNext( osrfBigBigListIterator* itr ) {
	if(!(itr && itr->list)) return NULL;

	Word_t* value;
	if(itr->current >= itr->list->size) return NULL;
	JLF( value, itr->list->list, itr->current );
	if(value) {
		itr->current++;
		return (void*) *value;
	}
	return NULL;
}

void osrfBigBigListIteratorFree( osrfBigBigListIterator* itr ) {
	if(!itr) return;
	free(itr);
}



void osrfBigBigListIteratorReset( osrfBigBigListIterator* itr ) {
	if(!itr) return;
	itr->current = 0;
}


void osrfBigListVanillaFree( void* item ) {
	free(item);
}

void osrfBigListSetDefaultFree( osrfBigList* list ) {
	if(!list) return;
	list->freeItem = osrfBigListVanillaFree;
}
