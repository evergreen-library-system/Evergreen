#ifndef OILS_EVENT_HEADER
#define OILS_EVENT_HEADER
#include "opensrf/osrf_json.h"
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_hash.h"

#ifdef __cplusplus
extern "C" {
#endif

/* OILS Event structure */
struct _oilsEventStruct {
	char* event;			/* the event name */
	char* perm;				/* the permission error name */
	int permloc;			/* the permission location id */
	jsonObject* payload;	/* the payload */
	jsonObject* json;		/* the event as a jsonObject */
	char* file;
	int line;
};
typedef struct _oilsEventStruct oilsEvent;


/** Creates a new event.  User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent( const char* file, int line, const char* event );

/** Creates a new event with payload.  
 * User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent2( const char* file, int line, const char* event,
		const jsonObject* payload );

/** Creates a new event with permission and permission location.  
 * User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent3( const char* file, int line, const char* event,
		const char* perm, int permloc );

/** Creates a new event with permission, permission location, and payload.  
 * User is responsible for freeing event with oilsEventFree */
oilsEvent* oilsNewEvent4( const char* file, int line, const char* event,
		const char* perm, int permloc, const jsonObject* payload );

/** Sets the permission info for the event */
void oilsEventSetPermission( oilsEvent* event, const char* perm, int permloc );

/* Sets the payload for the event 
 * This clones the payload, so the user is responsible
 * for handling the payload object's memory
 * */
void oilsEventSetPayload( oilsEvent* event, const jsonObject* payload );

/** Creates the JSON associated with an event.  The JSON should NOT be
 * freed by the user.  It will be freed by oilsEventFree */
jsonObject* oilsEventToJSON( oilsEvent* event );

/* Frees an event object */
void oilsEventFree( oilsEvent* event );

#ifdef __cplusplus
}
#endif

#endif
