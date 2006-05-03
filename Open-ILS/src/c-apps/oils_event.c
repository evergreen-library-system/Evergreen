#include "oils_event.h"
#include <libxml/parser.h>
#include <libxml/tree.h>
#include "opensrf/osrf_settings.h"

osrfHash* __oilsEventEvents = NULL;
osrfHash* __oilsEventDescriptions = NULL;

oilsEvent* oilsNewEvent( char* event ) {
	if(!event) return NULL;
	osrfLogInfo(OSRF_LOG_MARK, "Creating new event: %s", event);
	if(!__oilsEventEvents) _oilsEventParseEvents();
	oilsEvent* evt =  (oilsEvent*) safe_malloc(sizeof(oilsEvent));
	evt->event = strdup(event);
	evt->permloc = -1;
	return evt;
}

oilsEvent* oilsNewEvent2( char* event, jsonObject* payload ) {
	oilsEvent* evt = oilsNewEvent(event);
	oilsEventSetPayload(evt, payload);
	return evt;
}

oilsEvent* oilsNewEvent3( char* event, char* perm, int permloc ) {
	oilsEvent* evt = oilsNewEvent(event);
	oilsEventSetPermission( evt, perm, permloc );
	return evt;
}

oilsEvent* oilsNewEvent4( char* event, char* perm, int permloc, jsonObject* payload ) {
	oilsEvent* evt = oilsNewEvent3( event, perm, permloc );
	if(evt) oilsEventSetPayload( evt, payload );
	return evt;
}

void oilsEventSetPermission( oilsEvent* event, char* perm, int permloc ) {
	if(!(event && perm)) return;
	event->perm = strdup(perm);
	event->permloc = permloc;
}

void oilsEventSetPayload( oilsEvent* event, jsonObject* payload ) {
	if(!(event && payload)) return;
	event->payload = jsonObjectClone(payload);
}


void oilsEventFree( oilsEvent* event ) {
	if(!event) return;
	free(event->perm);
	if(event->json) jsonObjectFree(event->json);
	else jsonObjectFree(event->payload);
	free(event);
}


jsonObject* oilsEventToJSON( oilsEvent* event ) {
	if(!event) return NULL;
	char* code = osrfHashGet( __oilsEventEvents, event->event );

	if(!code) {
		osrfLogError(OSRF_LOG_MARK,  "No such event name: %s", event->event );
		return NULL;
	}


	char* lang = "en-US"; /* assume this for now */
	char* desc = NULL;
	osrfHash* h = osrfHashGet(__oilsEventDescriptions, lang);
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

	if(event->perm) jsonObjectSetKey( json, "ilsperm", jsonNewObject(event->perm) );
	if(event->permloc != -1) jsonObjectSetKey( json, "ilspermloc", jsonNewNumberObject(event->permloc) );
	if(event->payload) jsonObjectSetKey( json, "payload", event->payload );
	event->json = json;
	return json;
}


void _oilsEventParseEvents() {
	
	char* xml = osrf_settings_host_value("/ils_events");

	if(!xml) {
		osrfLogError(OSRF_LOG_MARK, "Unable to find ILS Events file: %s", xml);
		return;
	}

	xmlDocPtr doc = xmlParseFile(xml);
	free(xml);
	int success = 0;
	__oilsEventEvents = osrfNewHash();
	__oilsEventDescriptions = osrfNewHash();

	if( doc ) {
		xmlNodePtr root = xmlDocGetRootElement(doc);
		if( root ) {
			xmlNodePtr child = root->children;
			while( child ) {
				if( !strcmp((char*) child->name, "event") ) {
					xmlChar* code = xmlGetProp( child, BAD_CAST "code");
					xmlChar* textcode = xmlGetProp( child, BAD_CAST "textcode");
					if( code && textcode ) {
						osrfHashSet( __oilsEventEvents, code, textcode );
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
								osrfLogDebug(OSRF_LOG_MARK, "Loaded event lang: %s", (char*) lang);
								osrfHash* langHash = osrfHashGet(
									__oilsEventDescriptions, lang);
								if(!langHash) {
									langHash = osrfNewHash();
									osrfHashSet(__oilsEventDescriptions, langHash, lang);
								}
								char* content;
								if( desc->children && (content = desc->children->content) ) {
									osrfLogDebug(OSRF_LOG_MARK, "Loaded event desc: %s", (char*) content);
									osrfHashSet( langHash, content, code );
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


