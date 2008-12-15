#include "openils/oils_idl.h"
/*
 * vim:noet:ts=4:
 */

#include <stdlib.h>
#include <string.h>
#include <libxml/globals.h>
#include <libxml/xmlerror.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/debugXML.h>
#include <libxml/xmlmemory.h>

#define PERSIST_NS "http://open-ils.org/spec/opensrf/IDL/persistence/v1"
#define OBJECT_NS "http://open-ils.org/spec/opensrf/IDL/objects/v1"
#define BASE_NS "http://opensrf.org/spec/IDL/base/v1"
#define REPORTER_NS "http://open-ils.org/spec/opensrf/IDL/reporter/v1"
#define PERM_NS "http://open-ils.org/spec/opensrf/IDL/permacrud/v1"

static xmlDocPtr idlDoc = NULL; // parse and store the IDL here

/* parse and store the IDL here */
static osrfHash* idlHash;

osrfHash* oilsIDL(void) { return idlHash; }
osrfHash* oilsIDLInit( const char* idl_filename ) {

	if (idlHash) return idlHash;

	char* string_tmp = NULL;

	idlHash = osrfNewHash();
	osrfHash* usrData = NULL;

	osrfLogInfo(OSRF_LOG_MARK, "Parsing the IDL XML...");
	idlDoc = xmlReadFile( idl_filename, NULL, XML_PARSE_XINCLUDE );
	
	if (!idlDoc) {
		osrfLogError(OSRF_LOG_MARK, "Could not load or parse the IDL XML file!");
		return NULL;
	}

	osrfLogDebug(OSRF_LOG_MARK, "Initializing the Fieldmapper IDL...");

	xmlNodePtr docRoot = xmlDocGetRootElement(idlDoc);
	xmlNodePtr kid = docRoot->children;
	while (kid) {
		if (!strcmp( (char*)kid->name, "class" )) {

			usrData = osrfNewHash();
			osrfHashSet( usrData, xmlGetProp(kid, BAD_CAST "id"), "classname");
			osrfHashSet( usrData, xmlGetNsProp(kid, BAD_CAST "fieldmapper", BAD_CAST OBJECT_NS), "fieldmapper");
			osrfHashSet( usrData, xmlGetNsProp(kid, BAD_CAST "readonly", BAD_CAST PERSIST_NS), "readonly");

			osrfHashSet( idlHash, usrData, (char*)osrfHashGet(usrData, "classname") );

			string_tmp = NULL;
			if ((string_tmp = (char*)xmlGetNsProp(kid, BAD_CAST "tablename", BAD_CAST PERSIST_NS))) {
				osrfLogDebug(OSRF_LOG_MARK, "Using table '%s' for class %s", string_tmp, osrfHashGet(usrData, "classname") );
				osrfHashSet(
					usrData,
					strdup( string_tmp ),
					"tablename"
				);
			}

			string_tmp = NULL;
			if ((string_tmp = (char*)xmlGetNsProp(kid, BAD_CAST "virtual", BAD_CAST PERSIST_NS))) {
				osrfHashSet(
					usrData,
					strdup( string_tmp ),
					"virtual"
				);
			}

			osrfStringArray* controller = osrfNewStringArray(0);
			string_tmp = NULL;
			if( (string_tmp = (char*)xmlGetProp(kid, BAD_CAST "controller") )) {
				char* controller_list = strdup( string_tmp );
				osrfLogDebug(OSRF_LOG_MARK, "Controller list is %s", string_tmp );

				if (strlen( controller_list ) > 0) {
					char* st_tmp = NULL;
					char* _controller_class = strtok_r(controller_list, " ", &st_tmp);
					osrfStringArrayAdd(controller, strdup(_controller_class));

					while ((_controller_class = strtok_r(NULL, " ", &st_tmp))) {
						osrfStringArrayAdd(controller, strdup(_controller_class));
					}
				}
				free(controller_list);
			}
			osrfHashSet( usrData, controller, "controller");


			osrfHash* _tmp;
			osrfHash* links = osrfNewHash();
			osrfHash* fields = osrfNewHash();
			osrfHash* pcrud = osrfNewHash();

			osrfHashSet( usrData, fields, "fields" );
			osrfHashSet( usrData, links, "links" );

			xmlNodePtr _cur = kid->children;

			while (_cur) {

				if (!strcmp( (char*)_cur->name, "fields" )) {

					string_tmp = NULL;
					if( (string_tmp = (char*)xmlGetNsProp(_cur, BAD_CAST "primary", BAD_CAST PERSIST_NS)) ) {
						osrfHashSet(
							usrData,
							strdup( string_tmp ),
							"primarykey"
						);
					}

					string_tmp = NULL;
					if( (string_tmp = (char*)xmlGetNsProp(_cur, BAD_CAST "sequence", BAD_CAST PERSIST_NS)) ) {
						osrfHashSet(
							usrData,
							strdup( string_tmp ),
							"sequence"
						);
					}

					xmlNodePtr _f = _cur->children;

					while(_f) {
						if (strcmp( (char*)_f->name, "field" )) {
							_f = _f->next;
							continue;
						}

						_tmp = osrfNewHash();

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetNsProp(_f, BAD_CAST "array_position", BAD_CAST OBJECT_NS)) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"array_position"
							);
						}

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetNsProp(_f, BAD_CAST "i18n", BAD_CAST PERSIST_NS)) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"i18n"
							);
						}

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetNsProp(_f, BAD_CAST "virtual", BAD_CAST PERSIST_NS)) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"virtual"
							);
						}

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetNsProp(_f, BAD_CAST "primitive", BAD_CAST PERSIST_NS)) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"primitive"
							);
						}

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetProp(_f, BAD_CAST "name")) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"name"
							);
						}

						osrfLogDebug(OSRF_LOG_MARK, "Found field %s for class %s", string_tmp, osrfHashGet(usrData, "classname") );

						osrfHashSet(
							fields,
							_tmp,
							strdup( string_tmp )
						);
						_f = _f->next;
					}
				}

				if (!strcmp( (char*)_cur->name, "links" )) {
					xmlNodePtr _l = _cur->children;

					while(_l) {
						if (strcmp( (char*)_l->name, "link" )) {
							_l = _l->next;
							continue;
						}

						_tmp = osrfNewHash();

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetProp(_l, BAD_CAST "reltype")) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"reltype"
							);
						}
						osrfLogDebug(OSRF_LOG_MARK, "Adding link with reltype %s", string_tmp );

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetProp(_l, BAD_CAST "key")) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"key"
							);
						}
						osrfLogDebug(OSRF_LOG_MARK, "Link fkey is %s", string_tmp );

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetProp(_l, BAD_CAST "class")) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"class"
							);
						}
						osrfLogDebug(OSRF_LOG_MARK, "Link fclass is %s", string_tmp );

						osrfStringArray* map = osrfNewStringArray(0);

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetProp(_l, BAD_CAST "map") )) {
							char* map_list = strdup( string_tmp );
							osrfLogDebug(OSRF_LOG_MARK, "Link mapping list is %s", string_tmp );

							if (strlen( map_list ) > 0) {
								char* st_tmp = NULL;
								char* _map_class = strtok_r(map_list, " ", &st_tmp);
								osrfStringArrayAdd(map, strdup(_map_class));
						
								while ((_map_class = strtok_r(NULL, " ", &st_tmp))) {
									osrfStringArrayAdd(map, strdup(_map_class));
								}
							}
							free(map_list);
						}
						osrfHashSet( _tmp, map, "map");

						string_tmp = NULL;
						if( (string_tmp = (char*)xmlGetProp(_l, BAD_CAST "field")) ) {
							osrfHashSet(
								_tmp,
								strdup( string_tmp ),
								"field"
							);
						}

						osrfHashSet(
							links,
							_tmp,
							strdup( string_tmp )
						);

						osrfLogDebug(OSRF_LOG_MARK, "Found link %s for class %s", string_tmp, osrfHashGet(usrData, "classname") );

						_l = _l->next;
					}
				}
/**** Structure of permacrud in memory ****

{ create :
    { permission : [ x, y, z ],
      global_required : "true", -- anything else, or missing, is false
      local_context : [ f1, f2 ],
      foreign_context : { class1 : { fkey : local_class_key, field : class1_field, context : [ a, b, c ] }, ...}
    },
  retrieve : null, -- no perm check, or structure similar to the others
  update : -- like create
    ...
  delete : -- like create
    ...
}   

**** Structure of permacrud in memory ****/

				if (!strcmp( (char*)_cur->name, "permacrud" )) {
					osrfHashSet( usrData, pcrud, "permacrud" );
					xmlNodePtr _l = _cur->children;

					while(_l) {
						if (strcmp( (char*)_l->name, "actions" )) {
							_l = _l->next;
							continue;
						}

						xmlNodePtr _a = _l->children;

						while(_a) {
							if (
								strcmp( (char*)_a->name, "create" ) &&
								strcmp( (char*)_a->name, "retrieve" ) &&
								strcmp( (char*)_a->name, "update" ) &&
								strcmp( (char*)_a->name, "delete" )
							) {
								_a = _a->next;
								continue;
							}

							string_tmp = strdup( (char*)_a->name );
							osrfLogDebug(OSRF_LOG_MARK, "Found Permacrud action %s for class %s", string_tmp, osrfHashGet(usrData, "classname") );

							_tmp = osrfNewHash();
							osrfHashSet( pcrud, _tmp, string_tmp );

							osrfStringArray* map = osrfNewStringArray(0);
							string_tmp = NULL;
							if( (string_tmp = (char*)xmlGetProp(_a, BAD_CAST "permission") )) {
								char* map_list = strdup( string_tmp );
								osrfLogDebug(OSRF_LOG_MARK, "Permacrud permission list is %s", string_tmp );
	
								if (strlen( map_list ) > 0) {
									char* st_tmp = NULL;
									char* _map_class = strtok_r(map_list, "|", &st_tmp);
									osrfStringArrayAdd(map, strdup(_map_class));
							
									while ((_map_class = strtok_r(NULL, "|", &st_tmp))) {
										osrfStringArrayAdd(map, strdup(_map_class));
									}
								}
								free(map_list);
							}
							osrfHashSet( _tmp, map, "permission");

					    	osrfHashSet( _tmp, (char*)xmlGetProp(_a, BAD_CAST "global_required"), "global_required");

							map = osrfNewStringArray(0);
							string_tmp = NULL;
							if( (string_tmp = (char*)xmlGetProp(_a, BAD_CAST "context_field") )) {
								char* map_list = strdup( string_tmp );
								osrfLogDebug(OSRF_LOG_MARK, "Permacrud context_field list is %s", string_tmp );
	
								if (strlen( map_list ) > 0) {
									char* st_tmp = NULL;
									char* _map_class = strtok_r(map_list, "|", &st_tmp);
									osrfStringArrayAdd(map, strdup(_map_class));
							
									while ((_map_class = strtok_r(NULL, "|", &st_tmp))) {
										osrfStringArrayAdd(map, strdup(_map_class));
									}
								}
								free(map_list);
							}
							osrfHashSet( _tmp, map, "local_context");

							osrfHash* foreign_context = osrfNewHash();
							osrfHashSet( _tmp, foreign_context, "foreign_context");

							xmlNodePtr _f = _a->children;

							while(_f) {
								if ( strcmp( (char*)_f->name, "context" ) ) {
									_f = _f->next;
									continue;
								}

								string_tmp = NULL;
								if( (string_tmp = (char*)xmlGetProp(_f, BAD_CAST "link")) ) {
									osrfLogDebug(OSRF_LOG_MARK, "Permacrud context link definition is %s", string_tmp );

									osrfHash* _flink = oilsIDLFindPath("/%s/links/%s", osrfHashGet(usrData, "classname"), string_tmp);

									osrfHashSet( foreign_context, osrfNewHash(), osrfHashGet(_flink, "class") );
									osrfHash* _tmp_fcontext = osrfHashGet( foreign_context, osrfHashGet(_flink, "class") );

									osrfHashSet( _tmp_fcontext, osrfHashGet(_flink, "field"), "fkey" );
									osrfHashSet( _tmp_fcontext, osrfHashGet(_flink, "key"), "field" );

									map = osrfNewStringArray(0);
									string_tmp = NULL;
									if( (string_tmp = (char*)xmlGetProp(_f, BAD_CAST "field") )) {
										char* map_list = strdup( string_tmp );
										osrfLogDebug(OSRF_LOG_MARK, "Permacrud foreign context field list is %s", string_tmp );
			
										if (strlen( map_list ) > 0) {
											char* st_tmp = NULL;
											char* _map_class = strtok_r(map_list, "|", &st_tmp);
											osrfStringArrayAdd(map, strdup(_map_class));
									
											while ((_map_class = strtok_r(NULL, "|", &st_tmp))) {
												osrfStringArrayAdd(map, strdup(_map_class));
											}
										}
										free(map_list);
									}
									osrfHashSet( _tmp_fcontext, map, "context");

								} else {

									if( (string_tmp = (char*)xmlGetProp(_f, BAD_CAST "field") )) {
										char* map_list = strdup( string_tmp );
										osrfLogDebug(OSRF_LOG_MARK, "Permacrud foreign context field list is %s", string_tmp );
			
										if (strlen( map_list ) > 0) {
											char* st_tmp = NULL;
											char* _map_class = strtok_r(map_list, "|", &st_tmp);
											osrfStringArrayAdd(osrfHashGet( _tmp, "local_context"), strdup(_map_class));
									
											while ((_map_class = strtok_r(NULL, "|", &st_tmp))) {
												osrfStringArrayAdd(osrfHashGet( _tmp, "local_context"), strdup(_map_class));
											}
										}
										free(map_list);
									}

								}
								_f = _f->next;
							}
							_a = _a->next;
						}
						_l = _l->next;
					}
				}

				if (!strcmp( (char*)_cur->name, "source_definition" )) {
					string_tmp = NULL;
					if( (string_tmp = (char*)xmlNodeGetContent(_cur)) ) {
						osrfLogDebug(OSRF_LOG_MARK, "Using source definition '%s' for class %s", string_tmp, osrfHashGet(usrData, "classname") );
						osrfHashSet(
							usrData,
							strdup( string_tmp ),
							"source_definition"
						);
					}

				}

				_cur = _cur->next;
			} // end while
		}

		kid = kid->next;
	} // end while

	osrfLogInfo(OSRF_LOG_MARK, "...IDL XML parsed");

	return idlHash;
}

osrfHash* oilsIDLFindPath( const char* path, ... ) {
	if(!path || strlen(path) < 1) return NULL;

	osrfHash* obj = idlHash;

	VA_LIST_TO_STRING(path);
	char* buf = VA_BUF;

	char* token = NULL;
	char* t = buf;
	char* tt;

	token = strtok_r(t, "/", &tt);
	if(!token) return NULL;

	do {
		obj = osrfHashGet(obj, token);
	} while( (token = strtok_r(NULL, "/", &tt)) && obj);

	return obj;
}

int oilsIDL_classIsFieldmapper ( const char* classname ) {
	if (!classname) return 0;
	if(oilsIDLFindPath( "/%s", classname )) return 1;
	return 0;
}

int oilsIDL_ntop (const char* classname, const char* fieldname) {
	osrfHash* _pos = NULL;

	if (!oilsIDL_classIsFieldmapper(classname)) return -1;
	_pos = oilsIDLFindPath( "/%s/fields/%s", classname, fieldname );
	if (_pos) return atoi( osrfHashGet(_pos, "array_position") );
	return -1;
}

char * oilsIDL_pton (const char* classname, int pos) {
	char* ret = NULL;
	osrfHash* f = NULL;
	osrfHash* fields = NULL;
	osrfHashIterator* itr = NULL;

	if (!oilsIDL_classIsFieldmapper(classname)) return NULL;

	fields = oilsIDLFindPath( "/%s/fields", classname );
	itr = osrfNewHashIterator( fields );

	while ( (f = osrfHashIteratorNext( itr )) ) {
		if ( atoi(osrfHashGet(f, "array_position")) == pos ) {
			ret = strdup(osrfHashIteratorKey(itr));
			break;
		}
	}

	osrfHashIteratorFree( itr );

	return ret;
}

