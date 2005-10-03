#include "osrf_list.h"


osrfList* osrfNewList() {
	osrfList* list = safe_malloc(sizeof(osrfList));
	list->list = (Pvoid_t) NULL;
	list->size = 0;
	list->freeItem = NULL;
	return list;
}


int osrfListPush( osrfList* list, void* item ) {
	if(!(list && item)) return -1;
	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );
	osrfListSet( list, item, index+1 );
	return 0;
}


void* osrfListSet( osrfList* list, void* item, unsigned long position ) {
	if(!list || position < 0) return NULL;

	Word_t* value;
	void* olditem = osrfListRemove( list, position );

	JLI( value, list->list, position ); 
	*value = (Word_t) item;
	__osrfListSetSize( list );

	return olditem;
}


void* osrfListGetIndex( osrfList* list, unsigned long position ) {
	if(!list) return NULL;

	Word_t* value;
	JLG( value, list->list, position );
	if(value) return (void*) *value;
	return NULL;
}

void osrfListFree( osrfList* list ) {
	if(!list) return;

	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );
	int retcode;

	while (value != NULL) {
		JLD(retcode, list->list, index);

		if(list->freeItem) {
			list->freeItem( (void*) *value );
			*value = (Word_t) NULL;
		}

		JLP(value, list->list, index);
	}               

	free(list);
}

void* osrfListRemove( osrfList* list, int position ) {
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
				__osrfListSetSize( list );
			}
		}
	}

	return olditem;
}


int osrfListFind( osrfList* list, void* addr ) {
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



void __osrfListSetSize( osrfList* list ) {
	if(!list) return;

	Word_t* value;
	unsigned long index = -1;
	JLL(value, list->list, index );
	list->size = index + 1;
}


unsigned long osrfListGetCount( osrfList* list ) {
	if(!list) return -1;
	unsigned long retcode = -1;
	JLC( retcode, list->list, 0, -1 );
	return retcode;
}


osrfListIterator* osrfNewListIterator( osrfList* list ) {
	if(!list) return NULL;
	osrfListIterator* itr = safe_malloc(sizeof(osrfListIterator));
	itr->list = list;
	itr->current = 0;
	return itr;
}

void* osrfListIteratorNext( osrfListIterator* itr ) {
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

void osrfListIteratorFree( osrfListIterator* itr ) {
	if(!itr) return;
	free(itr);
}



void osrfListIteratorReset( osrfListIterator* itr ) {
	if(!itr) return;
	itr->current = 0;
}


