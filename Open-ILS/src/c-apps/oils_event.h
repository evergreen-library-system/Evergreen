#ifndef OILS_EVENT_HEADER
#define OILS_EVENT_HEADER
#include "objson/object.h"
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_hash.h"


/* OILS Event structure */
struct _oilsEventStruct {
	char* event;			/* the event name */
	char* perm;				/* the permission error name */
	int permloc;			/* the permission location id */
	jsonObject* payload;	/* the payload */
	jsonObject* json;		/* the event as a jsonObject */
};
typedef struct _oilsEventStruct oilsEvent;


/** Creates a new event.  User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent( char* event );

/** Creates a new event with payload.  
 * User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent2( char* event, jsonObject* payload );

/** Creates a new event with permission and permission location.  
 * User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent3( char* event, char* perm, int permloc );

/** Creates a new event with permission, permission location, and payload.  
 * User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent4( char* event, char* perm, int permloc, jsonObject* payload );

/** Sets the permission info for the event */
void oilsEventSetPermission( oilsEvent* event, char* perm, int permloc );

/* Sets the payload for the event 
 * This clones the payload, so the user is responsible
 * for handling the payload object's memory
 * */
void oilsEventSetPayload( oilsEvent* event, jsonObject* payload );

/** Creates the JSON associated with an event.  The JSON should NOT be
 * freed by the user.  It will be freed by oilsEventFree */
jsonObject* oilsEventToJSON( oilsEvent* event );

/* Parses the events file */
void _oilsEventParseEvents();

/* Frees an event object */
void oilsEventFree( oilsEvent* event );



#endif
