#ifndef OSRF_LIST_H
#define OSRF_LIST_H

#include "opensrf/utils.h"

#define OSRF_LIST_DEFAULT_SIZE 48 /* most opensrf lists are small... */
#define OSRF_LIST_INC_SIZE 256
#define OSRF_LIST_MAX_SIZE 10240


#define OSRF_LIST_GET_INDEX(l, i) (!l || i >= l->size) ? NULL: l->arrlist[i]

/**
  Items are stored as void*'s so it's up to the user to
  manage the data wisely.  Also, if the 'freeItem' callback is defined for the list,
  then, it will be used on any item that needs to be freed, so don't mix data
  types in the list if you want magic freeing */

struct __osrfListStruct {
	unsigned int size;			/* how many items in the list including NULL items between non-NULL items */	
	void (*freeItem) (void* item);	/* callback for freeing stored items */
	void** arrlist;
	int arrsize; /* how big is the currently allocated array */
};
typedef struct __osrfListStruct osrfList;


struct __osrfListIteratorStruct {
	osrfList* list;
	unsigned int current;
};
typedef struct __osrfListIteratorStruct osrfListIterator;

osrfList* osrfNewListSize( unsigned int size );


/**
  Creates a new list iterator with the given list
  */
osrfListIterator* osrfNewListIterator( osrfList* list );

/**
  Returns the next non-NULL item in the list, return NULL when
  the end of the list has been reached
  */
void* osrfListIteratorNext( osrfListIterator* itr );

/**
  Deallocates the given list
  */
void osrfListIteratorFree( osrfListIterator* itr );

void osrfListIteratorReset( osrfListIterator* itr );


/**
  Allocates a new list
  @param compress If true, the list will compress empty slots on delete.  If item positionality
  is not important, then using this feature is reccomended to keep the list from growing indefinitely.
  if item positionality is not important.
  @return The allocated list
  */
osrfList* osrfNewList();

/**
  Pushes an item onto the end of the list.  This always finds the highest index
  in the list and pushes the new item into the list after it.
  @param list The list
  @param item The item to push
  @return 0 on success, -1 on failure
  */
int osrfListPush( osrfList* list, void* item );


/**
 * Removes the last item in the list
 * See osrfListRemove for details on how the removed item is handled
 * @return The item, unless 'freeItem' exists, then returns NULL
 */
void* osrfListPop( osrfList* list );

/**
  Puts the given item into the list at the specified position.  If there
  is already an item at the given position and the list has it's 
  "freeItem" function defined, then it will be used to free said item.
  If no 'freeItem' callback is defined, then the displaced item will
  be returned;
  @param list The list
  @param item The item to put into the list
  @param position The position to place the item in
  @return NULL in successfully inserting the new item and freeing
  any displaced items.  Returns the displaced item if no "freeItem"
  callback is defined.
	*/
void* osrfListSet( osrfList* list, void* item, unsigned int position );

/**
  Returns the item at the given position
  @param list The list
  @param postiont the position
  */
void* osrfListGetIndex( osrfList* list, unsigned int  position );

/**
  Frees the list and all list items (if the list has a "freeItem" function defined )
  @param list The list
  */
void osrfListFree( osrfList* list );

/**
  Removes the list item at the given index
  @param list The list
  @param position The position of the item to remove
  @return A pointer to the item removed if "freeItem" is not defined
  for this list, returns NULL if it is.
  */
void* osrfListRemove( osrfList* list, int position );

/**
  Finds the list item whose void* is the same as the one passed in
  @param list The list
  @param addr The pointer connected to the list item we're to find
  @return the index of the item, or -1 if the item was not found
  */
int osrfListFind( osrfList* list, void* addr );


void __osrfListSetSize( osrfList* list );


/**
  @return The number of non-null items in the list
  */
unsigned int osrfListGetCount( osrfList* list );

/**
 * May be used as a default memory freeing call
 * Just calls free() on list items
 */
void osrfListVanillaFree( void* item );

/**
 * Tells the list to just call 'free()' on each item when
 * an item or the whole list is destroyed
 */
void osrfListSetDefaultFree( osrfList* list );

/**
 * Inserts the new item at the first free (null) slot
 * in the array.  Item is shoved onto the end of the
 * list if there are no null slots */
int osrfListPushFirst( osrfList* list, void* item );


#endif
