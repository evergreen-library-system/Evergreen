#include "openils/oils_event.h"
#include <libxml/parser.h>
#include <libxml/tree.h>
#include "opensrf/osrf_settings.h"

static void _oilsEventParseEvents();

// The following two osrfHashes are created when we
// create the first osrfEvent, and are never freed.

static osrfHash* _oilsEventEvents = NULL;
static osrfHash* _oilsEventDescriptions = NULL;

oilsEvent* oilsNewEvent( const char* file, int line, const char* event ) {
	if(!event) return NULL;
	osrfLogInfo(OSRF_LOG_MARK, "Creating new event: %s", event);
	if(!_oilsEventEvents) _oilsEventParseEvents();
	oilsEvent* evt = safe_malloc(sizeof(oilsEvent));
	evt->event = strdup(event);
	evt->perm = NULL;
	evt->permloc = -1;
	evt->payload = NULL;
	evt->json = NULL;
	if(file) evt->file = strdup(file);
	else evt->file = NULL;
	evt->line = line;
	return evt;
}

oilsEvent* oilsNewEvent2( const char* file, int line, const char* event,
		const jsonObject* payload ) {
	oilsEvent* evt = oilsNewEvent(file, line, event);
	if(payload) evt->payload = jsonObjectClone(payload);
	return evt;
}

oilsEvent* oilsNewEvent3( const char* file, int line, const char* event,
		const char* perm, int permloc ) {
	oilsEvent* evt = oilsNewEvent(file, line, event);
	if(perm) {
		evt->perm = strdup(perm);
		evt->permloc = permloc;
	}
	return evt;
}

oilsEvent* oilsNewEvent4( const char* file, int line, const char* event,
		const char* perm, int permloc, const jsonObject* payload ) {
	oilsEvent* evt = oilsNewEvent3( file, line, event, perm, permloc );
	if(payload) evt->payload = jsonObjectClone(payload);
	return evt;
}

void oilsEventSetPermission( oilsEvent* event, const char* perm, int permloc ) {
	if(!(event && perm)) return;
	if(event->perm) free(event->perm);
	event->perm = strdup(perm);
	event->permloc = permloc;
}

void oilsEventSetPayload( oilsEvent* event, const jsonObject* payload ) {
	if(!(event && payload)) return;
	if(event->payload) jsonObjectFree(event->payload);
	event->payload = jsonObjectClone(payload);
}


void oilsEventFree( oilsEvent* event ) {
	if(!event) return;
	free(event->event);
	free(event->perm);
	free(event->file);
	if(event->json) jsonObjectFree(event->json);
    /* event->json will contain a pointer to event->payload */
    else jsonObjectFree(event->payload); 
	free(event);
}


jsonObject* oilsEventToJSON( oilsEvent* event ) {
	if(!event) return NULL;
	char* code = osrfHashGet( _oilsEventEvents, event->event );

	if(!code) {
		osrfLogError(OSRF_LOG_MARK,  "No such event name: %s", event->event );
		return NULL;
	}


	char* lang = "en-US"; /* assume this for now */
	char* desc = NULL;
	osrfHash* h = osrfHashGet(_oilsEventDescriptions, lang);
	if(h) {
		osrfLogDebug(OSRF_LOG_MARK, "Loaded event lang hash for %s",lang);
		desc = osrfHashGet(h, code);
		osrfLogDebug(OSRF_LOG_MARK, "Found event description %s", desc);
	}
	if(!desc) desc = "";

	jsonObject* json = jsonNewObject(NULL);
	jsonObjectSetKey( json, "ilsevent", jsonNewNumberObject(atoi(code)) );
	jsonObjectSetKey( json, "textcode", jsonNewObject(event->event) );
	jsonObjectSetKey( json, "desc", jsonNewObject(desc) );
	jsonObjectSetKey( json, "pid", jsonNewNumberObject(getpid()) );

	char buf[256];
	memset(buf, '\0', sizeof(buf));
	snprintf(buf, sizeof(buf), "%s:%d", event->file, event->line);
	jsonObjectSetKey( json, "stacktrace", jsonNewObject(buf) );

	if(event->perm) jsonObjectSetKey( json, "ilsperm", jsonNewObject(event->perm) );
	if(event->permloc != -1) jsonObjectSetKey( json, "ilspermloc", jsonNewNumberObject(event->permloc) );
	if(event->payload) jsonObjectSetKey( json, "payload", event->payload );
	
	if(event->json) jsonObjectFree(event->json);
	event->json = json;
	return json;
}

/* Parses the events file */
static void _oilsEventParseEvents() {
	
	char* xml = osrf_settings_host_value("/ils_events");

	if(!xml) {
		osrfLogError(OSRF_LOG_MARK, "Unable to find ILS Events file: %s", xml);
		return;
	}

	xmlDocPtr doc = xmlParseFile(xml);
	free(xml);
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
								osrfLogInternal(OSRF_LOG_MARK, "Loaded event lang: %s", (char*) lang);
								osrfHash* langHash = osrfHashGet(
									_oilsEventDescriptions, (char*) lang);
								if(!langHash) {
									langHash = osrfNewHash();
									osrfHashSet(_oilsEventDescriptions, langHash, (char*) lang);
								}
								char* content;
								if( desc->children && (content = (char*) desc->children->content) ) {
									osrfLogInternal(OSRF_LOG_MARK, "Loaded event desc: %s", content);
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

	if(!success) osrfLogError(OSRF_LOG_MARK,  " ! Unable to parse events file: %s", xml );
}


