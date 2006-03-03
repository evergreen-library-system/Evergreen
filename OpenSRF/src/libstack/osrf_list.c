#include "osrf_list.h"

osrfList* osrfNewList() {
	osrfList* list = safe_malloc(sizeof(osrfList));
	list->size		= 0;
	list->freeItem = NULL;
	list->arrsize	= OSRF_LIST_DEFAULT_SIZE;
	list->arrlist	= safe_malloc( list->arrsize * sizeof(void*) );
	return list;
}

osrfList* osrfNewListSize( unsigned int size ) {
	osrfList* list = safe_malloc(sizeof(osrfList));
	list->size		= 0;
	list->freeItem = NULL;
	list->arrsize	= size;
	list->arrlist	= safe_malloc( list->arrsize * sizeof(void*) );
	return list;
}


int osrfListPush( osrfList* list, void* item ) {
	if(!(list)) return -1;
	osrfListSet( list, item, list->size );
	return 0;
}

int osrfListPushFirst( osrfList* list, void* item ) {
	if(!(list && item)) return -1;
	int i;
	for( i = 0; i < list->size; i++ ) 
		if(!list->arrlist[i]) break;
	osrfListSet( list, item, i );
	return list->size;
}

void* osrfListSet( osrfList* list, void* item, unsigned int position ) {
	if(!list || position < 0) return NULL;

	int i;
	int newsize = list->arrsize;
	void** newarr;

	while( position >= newsize ) 
		newsize += OSRF_LIST_INC_SIZE;

	if( newsize > list->arrsize ) { /* expand the list if necessary */
		newarr = safe_malloc( newsize * sizeof(void*) );
		for( i = 0; i < list->arrsize; i++ ) 
			newarr[i] = list->arrlist[i];
		free(list->arrlist);
		list->arrlist = newarr;
		list->arrsize = newsize;
	}

	void* olditem = osrfListRemove( list, position );
	list->arrlist[position] = item;
	if( list->size == 0 || list->size <= position )
		list->size = position + 1;
	return olditem;
}


void* osrfListGetIndex( osrfList* list, unsigned int position ) {
	if(!list || position >= list->size) return NULL;
	return list->arrlist[position];
}

void osrfListFree( osrfList* list ) {
	if(!list) return;

	if( list->freeItem ) {
		int i; void* val;
		for( i = 0; i < list->size; i++ ) {
			if( (val = list->arrlist[i]) ) 
				list->freeItem(val);
		}
	}

	free(list->arrlist);
	free(list);
}

void* osrfListRemove( osrfList* list, int position ) {
	if(!list || position >= list->size) return NULL;

	void* olditem = list->arrlist[position];
	list->arrlist[position] = NULL;
	if( list->freeItem ) {
		list->freeItem(olditem);
		olditem = NULL;
	}

	if( position == list->size - 1 ) list->size--;
	return olditem;
}


int osrfListFind( osrfList* list, void* addr ) {
	if(!(list && addr)) return -1;
	int index;
	for( index = 0; index < list->size; index++ ) {
		if( list->arrlist[index] == addr ) 
			return index;
	}
	return -1;
}


unsigned int osrfListGetCount( osrfList* list ) {
	if(!list) return -1;
	return list->size;
}


void* osrfListPop( osrfList* list ) {
	if(!list) return NULL;
	return osrfListRemove( list, list->size - 1 );
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
	if(itr->current >= itr->list->size) return NULL;
	return itr->list->arrlist[itr->current++];
}

void osrfListIteratorFree( osrfListIterator* itr ) {
	if(!itr) return;
	free(itr);
}


void osrfListIteratorReset( osrfListIterator* itr ) {
	if(!itr) return;
	itr->current = 0;
}


void osrfListVanillaFree( void* item ) {
	free(item);
}

void osrfListSetDefaultFree( osrfList* list ) {
	if(!list) return;
	list->freeItem = osrfListVanillaFree;
}
