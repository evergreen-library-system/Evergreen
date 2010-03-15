#ifndef OILS_EVENT_HEADER
#define OILS_EVENT_HEADER
#include "opensrf/osrf_json.h"
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_hash.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
	@brief Represents an event; typically some kind of error condition.
*/
struct _oilsEventStruct {
	char* event;            /**< Event name. */
	char* perm;             /**< Permission error name. */
	int permloc;            /**< Permission location id. */
	jsonObject* payload;    /**< Payload. */
	jsonObject* json;       /**< The event as a jsonObject. */
	char* file;             /**< Name of source file where event was created. */
	int line;               /**< Line number in source file where event was created. */
};
typedef struct _oilsEventStruct oilsEvent;

oilsEvent* oilsNewEvent( const char* file, int line, const char* event );

oilsEvent* oilsNewEvent2( const char* file, int line, const char* event,
		const jsonObject* payload );

oilsEvent* oilsNewEvent3( const char* file, int line, const char* event,
		const char* perm, int permloc );

oilsEvent* oilsNewEvent4( const char* file, int line, const char* event,
		const char* perm, int permloc, const jsonObject* payload );

void oilsEventSetPermission( oilsEvent* event, const char* perm, int permloc );

void oilsEventSetPayload( oilsEvent* event, const jsonObject* payload );

jsonObject* oilsEventToJSON( oilsEvent* event );

void oilsEventFree( oilsEvent* event );

#ifdef __cplusplus
}
#endif

#endif
