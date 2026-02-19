#include "openils/oils_event.h"
#include <libxml/parser.h>
#include <libxml/tree.h>
#include "opensrf/osrf_settings.h"

const char default_lang[] = "en-US";

static void _oilsEventParseEvents();
static const char* lookup_desc( const char* lang, const char* code );

// The following two osrfHashes are created when we
// create the first osrfEvent, and are never freed.

/**
	@brief Lookup store mapping event names to event numbers.

	- Key: textcode from the events config file.
	- Data: numeric code (as a string) from the events config file.
*/
static osrfHash* _oilsEventEvents = NULL;

/**
	@brief Lookup store mapping event numbers to descriptive text.

	- Key: numeric code (as a string) of the event.
	- Data: another layer of lookup, as follows:
		- Key: numeric code (as a string) of the event.
		- Data: text message describing the event.
*/
static osrfHash* _oilsEventDescriptions = NULL;

/**
	@brief Allocate and initialize a new oilsEvent.
	@param file The name of the source file where oilsNewEvent is called.
	@param line The line number in the source code where oilsNewEvent is called.
	@param event A name or label for the event.
	@return Pointer to the newly allocated oilsEvent.

	The first two parameters are normally passed as the OSRF_LOG_MARK macro.

	The calling code is responsible for freeing the oilsEvent by calling oilsEventFree().
*/
oilsEvent* oilsNewEvent( const char* file, int line, const char* event ) {
	if(!event) return NULL;

	osrfLogInfo(OSRF_LOG_MARK, "Creating new event: %s", event);

	if(!_oilsEventEvents)
		_oilsEventParseEvents();

	oilsEvent* evt = safe_malloc( sizeof(oilsEvent) );
	evt->event = strdup(event);
	evt->perm = NULL;
	evt->permloc = -1;
	evt->payload = NULL;
	evt->json = NULL;

	if(file)
		evt->file = strdup(file);
	else
		evt->file = strdup( "" );

	evt->line = line;
	return evt;
}

/**
	@brief Allocate and initialize a new oilsEvent with a payload.
	@param file The name of the source file where oilsNewEvent is called.
	@param line The line number in the source code where oilsNewEvent is called.
	@param event A name or label for the event.
	@param payload The payload, of which a copy will be incorporated into the oilsEvent.
	@return Pointer to the newly allocated oilsEvent.

	The first two parameters are normally passed as the OSRF_LOG_MARK macro.

	The calling code is responsible for freeing the oilsEvent by calling oilsEventFree().
*/
oilsEvent* oilsNewEvent2( const char* file, int line, const char* event,
		const jsonObject* payload ) {
	oilsEvent* evt = oilsNewEvent(file, line, event);

	if(payload)
		evt->payload = jsonObjectClone(payload);

	return evt;
}

/**
	@brief Create a new oilsEvent with a permission and a permission location.
	@param file The name of the source file where oilsNewEvent is called.
	@param line The line number in the source code where oilsNewEvent is called.
	@param event A name or label for the event.
	@param perm The permission name.
	@param permloc The permission location.
	@return Pointer to the newly allocated oilsEvent.

	The first two parameters are normally passed as the OSRF_LOG_MARK macro.

	The calling code is responsible for freeing the oilsEvent by calling oilsEventFree().
*/
oilsEvent* oilsNewEvent3( const char* file, int line, const char* event,
		const char* perm, int permloc ) {
	oilsEvent* evt = oilsNewEvent(file, line, event);
	if(perm) {
		evt->perm = strdup(perm);
		evt->permloc = permloc;
	}
	return evt;
}

/**
	@brief Create a new oilsEvent with a permission and a permission location.
	@param file The name of the source file where oilsNewEvent is called.
	@param line The line number in the source code where oilsNewEvent is called.
	@param event A name or label for the event.
	@param perm The permission name.
	@param permloc The permission location.
	@param payload Pointer to the payload.
	@return Pointer to the newly allocated oilsEvent.

	The first two parameters are normally passed as the OSRF_LOG_MARK macro.

	The calling code is responsible for freeing the oilsEvent by calling oilsEventFree().
*/
oilsEvent* oilsNewEvent4( const char* file, int line, const char* event,
		const char* perm, int permloc, const jsonObject* payload ) {
	oilsEvent* evt = oilsNewEvent3( file, line, event, perm, permloc );

	if(payload)
		evt->payload = jsonObjectClone(payload);

	return evt;
}

/**
	@brief Set the permission and permission location of an oilsEvent.
	@param event Pointer the oilsEvent whose permission and permission location are to be set.
	@param perm The permission name.
	@param permloc The permission location.
*/
void oilsEventSetPermission( oilsEvent* event, const char* perm, int permloc ) {
	if(!(event && perm)) return;

	if(event->perm)
		free(event->perm);

	event->perm = strdup(perm);
	event->permloc = permloc;
}

/**
	@brief Install a payload in an oilsEvent.
	@param event The oilsEvent in which the payload is to be installed.
	@param payload The payload, a copy of which will be installed in the oilsEvent.

	If @a payload is NULL, install a JSON_NULL as the payload.
*/
void oilsEventSetPayload( oilsEvent* event, const jsonObject* payload ) {
	if(!(event && payload)) return;

	if(event->payload)
		jsonObjectFree(event->payload);

	event->payload = jsonObjectClone(payload);
}

/**
	@brief Free an OilsEvent.
	@param event Pointer to the oilsEvent to be freed.
*/
void oilsEventFree( oilsEvent* event ) {
	if(!event) return;
	free(event->event);
	free(event->perm);
	free(event->file);

	// If present, the jsonObject to which event->json will include a pointer to
	// event->payload.  Hence we must avoid trying to free the payload twice.
	if(event->json)
		jsonObjectFree(event->json);
	else
		jsonObjectFree(event->payload);

	free(event);
}

/**
	@brief Package the contents of an oilsEvent into a jsonObject.
	@param event Pointer to the oilsEvent whose contents are to be packaged.
	@return Pointer to the newly created jsonObject if successful, or NULL if not.

	The jsonObject will include a textual description of the event, as loaded from the
	events file.  Although the events file may include text in multiple languages,
	oilsEventToJSON() uses only those marked as "en-US".

	A pointer to the resulting jsonObject will be stored in the oilsEvent.  Hence the calling
	code should @em not free the returned jsonObject directly.  It will be freed by
	oilsEventFree().
*/
jsonObject* oilsEventToJSON( oilsEvent* event ) {
	if(!event) return NULL;

	char* code = osrfHashGet( _oilsEventEvents, event->event );
	if(!code) {
		osrfLogError(OSRF_LOG_MARK, "No such event name: %s", event->event );
		return NULL;
	}

	// Look up the text message corresponding the code, preferably in the right language.
	const char* lang = osrf_message_get_last_locale();
	const char* desc = lookup_desc( lang, code );
	if( !desc && strcmp( lang, default_lang ) )    // No luck?
		desc = lookup_desc( default_lang, code );  // Try the default language

	if( !desc )
		desc = "";  // Not found?  Default to an empty string.

	jsonObject* json = jsonNewObject(NULL);
	jsonObjectSetKey( json, "ilsevent", jsonNewNumberObject(atoi(code)) );
	jsonObjectSetKey( json, "textcode", jsonNewObject(event->event) );
	jsonObjectSetKey( json, "desc", jsonNewObject(desc) );
	jsonObjectSetKey( json, "pid", jsonNewNumberObject(getpid()) );

	char buf[256] = "";
	snprintf(buf, sizeof(buf), "%s:%d", event->file, event->line);
	jsonObjectSetKey( json, "stacktrace", jsonNewObject(buf) );

	if(event->perm)
		jsonObjectSetKey( json, "ilsperm", jsonNewObject(event->perm) );

	if(event->permloc != -1)
		jsonObjectSetKey( json, "ilspermloc", jsonNewNumberObject(event->permloc) );

	if(event->payload)
		jsonObjectSetKey( json, "payload", event->payload );

	if(event->json)
		jsonObjectFree(event->json);

	event->json = json;
	return json;
}

/**
	@brief Lookup up the descriptive text, in a given language, for a given event code.
	@param lang The language (a.k.a. locale) of the desired message.
	@param code The numeric code for the event, as a string.
	return The corresponding descriptive text if found, or NULL if not.

	The lookup has two stages.  First we look up the language, and then within that
	language we look up the code.
*/
static const char* lookup_desc( const char* lang, const char* code ) {
	// Search for the right language
	const char* desc = NULL;
	osrfHash* lang_hash = osrfHashGet( _oilsEventDescriptions, lang );
	if( lang_hash ) {
		// Within that language, search for the right message
		osrfLogDebug( OSRF_LOG_MARK, "Loaded event lang hash for %s", lang );
		desc = osrfHashGet( lang_hash, code );
	}

	if( desc )
		osrfLogDebug( OSRF_LOG_MARK, "Found event description %s", desc );
	else
		osrfLogDebug( OSRF_LOG_MARK, "Event description not found for code %s", code );

	return desc;
}

/**
	@brief Parse and load the events file.

	Get the name of the events file from previously loaded settings.  Open it and load
	it into an xmlDoc.  Based on the contents of the xmlDoc, build two osrfHashes: one to
	map event names to event numbers, and another to map event numbers to descriptive
	text messages (actually one such hash for each supported language).
*/
static void _oilsEventParseEvents() {

	char* xml = osrf_settings_host_value("/ils_events");

	if(!xml) {
		osrfLogError(OSRF_LOG_MARK, "Unable to find ILS Events file: %s", xml);
		return;
	}

	xmlDocPtr doc = xmlParseFile(xml);
	int success = 0;
	_oilsEventEvents = osrfNewHash();
	_oilsEventDescriptions = osrfNewHash();

	if( doc ) {
		xmlNodePtr root = xmlDocGetRootElement(doc);
		if( root ) {
			xmlNodePtr child = root->children;
			while( child ) {
				if( !strcmp((char*) child->name, "event") ) {
					xmlChar* code = xmlGetProp( child, BAD_CAST "code");
					xmlChar* textcode = xmlGetProp( child, BAD_CAST "textcode");
					if( code && textcode ) {
						osrfHashSet( _oilsEventEvents, code, (char*) textcode );
						success = 1;
					}

					/* here we collect all of the <desc> nodes on the event
					 * element and store them based on the xml:lang attribute
					 */
					xmlNodePtr desc = child->children;
					while(desc) {
						if( !strcmp((char*) desc->name, "desc") ) {
							xmlChar* lang = xmlGetProp( desc, BAD_CAST "lang");
							if(lang) {
								osrfLogInternal( OSRF_LOG_MARK,
									"Loaded event lang: %s", (char*) lang );
								osrfHash* langHash = osrfHashGet(
									_oilsEventDescriptions, (char*) lang);
								if(!langHash) {
									langHash = osrfNewHash();
									osrfHashSet(_oilsEventDescriptions, langHash, (char*) lang);
								}
								char* content;
								if( desc->children
									&& (content = (char*) desc->children->content) ) {
									osrfLogInternal( OSRF_LOG_MARK,
										"Loaded event desc: %s", content);
									osrfHashSet( langHash, content, (char*) code );
								}
							}
						}
						desc = desc->next;
					}
				}
				child = child->next;
			}
		}
	}

	if(!success)
		osrfLogError(OSRF_LOG_MARK, " ! Unable to parse events file: %s", xml );
	free(xml);
}
