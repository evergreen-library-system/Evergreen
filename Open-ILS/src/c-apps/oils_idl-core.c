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

static void add_std_fld( osrfHash* fields_hash, const char* field_name, unsigned pos );
osrfHash* oilsIDL(void) { return idlHash; }
osrfHash* oilsIDLInit( const char* idl_filename ) {

	if (idlHash) return idlHash;

	char* prop_str = NULL;

	idlHash = osrfNewHash();
	osrfHash* class_def_hash = NULL;

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

			class_def_hash = osrfNewHash();
			char* current_class_name = (char*) xmlGetProp(kid, BAD_CAST "id");
			
			osrfHashSet( class_def_hash, current_class_name, "classname" );
			osrfHashSet( class_def_hash, xmlGetNsProp(kid, BAD_CAST "fieldmapper", BAD_CAST OBJECT_NS), "fieldmapper" );
			osrfHashSet( class_def_hash, xmlGetNsProp(kid, BAD_CAST "readonly", BAD_CAST PERSIST_NS), "readonly" );

			osrfHashSet( idlHash, class_def_hash, current_class_name );

			if ((prop_str = (char*)xmlGetNsProp(kid, BAD_CAST "tablename", BAD_CAST PERSIST_NS))) {
				osrfLogDebug(OSRF_LOG_MARK, "Using table '%s' for class %s", prop_str, current_class_name );
				osrfHashSet(
					class_def_hash,
					prop_str,
					"tablename"
				);
			}

			if ((prop_str = (char*)xmlGetNsProp(kid, BAD_CAST "restrict_primary", BAD_CAST PERSIST_NS))) {
				osrfLogDebug(OSRF_LOG_MARK, "Delete restriction policy set at '%s' for pkey of class %s", prop_str, current_class_name );
				osrfHashSet(
					class_def_hash,
					prop_str,
					"restrict_primary"
				);
			}

			if ((prop_str = (char*)xmlGetNsProp(kid, BAD_CAST "virtual", BAD_CAST PERSIST_NS))) {
				osrfHashSet(
					class_def_hash,
					prop_str,
					"virtual"
				);
			}

			// Tokenize controller attribute into an osrfStringArray
			prop_str = (char*) xmlGetProp(kid, BAD_CAST "controller");
			if( prop_str )
				osrfLogDebug(OSRF_LOG_MARK, "Controller list is %s", prop_str );
			osrfStringArray* controller = osrfStringArrayTokenize( prop_str, ' ' );
			xmlFree( prop_str );
			osrfHashSet( class_def_hash, controller, "controller");

			osrfHash* current_links_hash = osrfNewHash();
			osrfHash* current_fields_hash = osrfNewHash();

			osrfHashSet( class_def_hash, current_fields_hash, "fields" );
			osrfHashSet( class_def_hash, current_links_hash, "links" );

			xmlNodePtr _cur = kid->children;

			while (_cur) {

				if (!strcmp( (char*)_cur->name, "fields" )) {

					if( (prop_str = (char*)xmlGetNsProp(_cur, BAD_CAST "primary", BAD_CAST PERSIST_NS)) ) {
						osrfHashSet(
							class_def_hash,
							prop_str,
							"primarykey"
						);
					}

					if( (prop_str = (char*)xmlGetNsProp(_cur, BAD_CAST "sequence", BAD_CAST PERSIST_NS)) ) {
						osrfHashSet(
							class_def_hash,
							prop_str,
							"sequence"
						);
					}

					unsigned int array_pos = 0;
					char array_pos_buf[ 7 ];  // For up to 1,000,000 fields per class

					xmlNodePtr _f = _cur->children;
					while(_f) {
						if (strcmp( (char*)_f->name, "field" )) {
							_f = _f->next;
							continue;
						}

						// Get the field name.  If it's one of the three standard
						// fields that we always generate, ignore it.
						char* field_name = (char*)xmlGetProp(_f, BAD_CAST "name");
						if( field_name ) {
							osrfLogDebug(OSRF_LOG_MARK, 
									"Found field %s for class %s", field_name, current_class_name );
							if(    !strcmp( field_name, "isnew" )
								|| !strcmp( field_name, "ischanged" )
								|| !strcmp( field_name, "isdeleted" ) ) {
								free( field_name );
								_f = _f->next;
								continue;
							}
						} else {
							osrfLogDebug(OSRF_LOG_MARK,
									"Found field with no name for class %s", current_class_name );
							_f = _f->next;
							continue;
						}
 
						osrfHash* field_def_hash = osrfNewHash();

						// Insert array_position
						snprintf( array_pos_buf, sizeof( array_pos_buf ), "%u", array_pos++ );
						osrfHashSet( field_def_hash, strdup( array_pos_buf ), "array_position" );

						// Tokenize suppress_controller attribute into an osrfStringArray
						if( (prop_str = (char*)xmlGetProp(_f, BAD_CAST "suppress_controller")) ) {
							osrfLogDebug(OSRF_LOG_MARK, "Controller suppression list is %s", prop_str );
							osrfStringArray* controller = osrfStringArrayTokenize( prop_str, ' ' );
							osrfHashSet( field_def_hash, controller, "suppress_controller");
						}

						if( (prop_str = (char*)xmlGetNsProp(_f, BAD_CAST "i18n", BAD_CAST PERSIST_NS)) ) {
							osrfHashSet(
								field_def_hash,
								prop_str,
								"i18n"
							);
						}

						if( (prop_str = (char*)xmlGetNsProp(_f, BAD_CAST "virtual", BAD_CAST PERSIST_NS)) ) {
							osrfHashSet(
								field_def_hash,
								prop_str,
								"virtual"
							);
						} else {   // default to virtual
							osrfHashSet(
								field_def_hash,
								"false",
								"virtual"
							);
						}

						if( (prop_str = (char*)xmlGetNsProp(_f, BAD_CAST "primitive", BAD_CAST PERSIST_NS)) ) {
							osrfHashSet(
								field_def_hash,
								prop_str,
								"primitive"
							);
						}

						osrfHashSet( field_def_hash, field_name, "name" );
						osrfHashSet(
							current_fields_hash,
							field_def_hash,
							field_name
						);
						_f = _f->next;
					}

					// Create three standard, stereotyped virtual fields for every class
					add_std_fld( current_fields_hash, "isnew",     array_pos++ );
					add_std_fld( current_fields_hash, "ischanged", array_pos++ );
					add_std_fld( current_fields_hash, "isdeleted", array_pos   );

				}

				if (!strcmp( (char*)_cur->name, "links" )) {
					xmlNodePtr _l = _cur->children;

					while(_l) {
						if (strcmp( (char*)_l->name, "link" )) {
							_l = _l->next;
							continue;
						}

						osrfHash* link_def_hash = osrfNewHash();

						if( (prop_str = (char*)xmlGetProp(_l, BAD_CAST "reltype")) ) {
							osrfHashSet(
								link_def_hash,
								prop_str,
								"reltype"
							);
							osrfLogDebug(OSRF_LOG_MARK, "Adding link with reltype %s", prop_str );
						} else
							osrfLogDebug(OSRF_LOG_MARK, "Adding link with no reltype" );

						if( (prop_str = (char*)xmlGetProp(_l, BAD_CAST "key")) ) {
							osrfHashSet(
								link_def_hash,
								prop_str,
								"key"
							);
							osrfLogDebug(OSRF_LOG_MARK, "Link fkey is %s", prop_str );
						} else
							osrfLogDebug(OSRF_LOG_MARK, "Link with no fkey" );

						if( (prop_str = (char*)xmlGetProp(_l, BAD_CAST "class")) ) {
							osrfHashSet(
								link_def_hash,
								prop_str,
								"class"
							);
							osrfLogDebug(OSRF_LOG_MARK, "Link fclass is %s", prop_str );
						} else
							osrfLogDebug(OSRF_LOG_MARK, "Link with no fclass" );

						// Tokenize map attribute into an osrfStringArray
						prop_str = (char*) xmlGetProp(_l, BAD_CAST "map");
						if( prop_str )
							osrfLogDebug(OSRF_LOG_MARK, "Link mapping list is %s", prop_str );
						osrfStringArray* map = osrfStringArrayTokenize( prop_str, ' ' );
						osrfHashSet( link_def_hash, map, "map");
						xmlFree( prop_str );

						if( (prop_str = (char*)xmlGetProp(_l, BAD_CAST "field")) ) {
							osrfHashSet(
								link_def_hash,
								prop_str,
								"field"
							);
							osrfLogDebug(OSRF_LOG_MARK, "Link fclass is %s", prop_str );
						} else
							osrfLogDebug(OSRF_LOG_MARK, "Link with no fclass" );

						osrfHashSet(
							current_links_hash,
							link_def_hash,
							prop_str
						);

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
					osrfHash* pcrud = osrfNewHash();
					osrfHashSet( class_def_hash, pcrud, "permacrud" );
					xmlNodePtr _l = _cur->children;

					while(_l) {
						if (strcmp( (char*)_l->name, "actions" )) {
							_l = _l->next;
							continue;
						}

						xmlNodePtr _a = _l->children;

						while(_a) {
							const char* action_name = (const char*) _a->name;
							if (
								strcmp( action_name, "create" ) &&
								strcmp( action_name, "retrieve" ) &&
								strcmp( action_name, "update" ) &&
								strcmp( action_name, "delete" )
							) {
								_a = _a->next;
								continue;
							}

							osrfLogDebug(OSRF_LOG_MARK, "Found Permacrud action %s for class %s",
								action_name, current_class_name );

							osrfHash* action_def_hash = osrfNewHash();
							osrfHashSet( pcrud, action_def_hash, action_name );

							// Tokenize permission attribute into an osrfStringArray
							prop_str = (char*) xmlGetProp(_a, BAD_CAST "permission");
							if( prop_str )
								osrfLogDebug(OSRF_LOG_MARK,
									"Permacrud permission list is %s", prop_str );
							osrfStringArray* map = osrfStringArrayTokenize( prop_str, ' ' );
							osrfHashSet( action_def_hash, map, "permission");
							xmlFree( prop_str );

					    	osrfHashSet( action_def_hash,
								(char*)xmlGetNoNsProp(_a, BAD_CAST "global_required"), "global_required");

							// Tokenize context_field attribute into an osrfStringArray
							prop_str = (char*) xmlGetProp(_a, BAD_CAST "context_field");
							if( prop_str )
								osrfLogDebug(OSRF_LOG_MARK,
									"Permacrud context_field list is %s", prop_str );
							map = osrfStringArrayTokenize( prop_str, ' ' );
							osrfHashSet( action_def_hash, map, "local_context");
							xmlFree( prop_str );

							osrfHash* foreign_context = osrfNewHash();
							osrfHashSet( action_def_hash, foreign_context, "foreign_context");

							xmlNodePtr _f = _a->children;

							while(_f) {
								if ( strcmp( (char*)_f->name, "context" ) ) {
									_f = _f->next;
									continue;
								}

								if( (prop_str = (char*)xmlGetNoNsProp(_f, BAD_CAST "link")) ) {
									osrfLogDebug(OSRF_LOG_MARK,
										"Permacrud context link definition is %s", prop_str );

									osrfHash* _tmp_fcontext = osrfNewHash();

									// Store pointers to elements already stored
									// from the <link> aggregate
									osrfHash* _flink = osrfHashGet( current_links_hash, prop_str );
									osrfHashSet( _tmp_fcontext, osrfHashGet(_flink, "field"), "fkey" );
									osrfHashSet( _tmp_fcontext, osrfHashGet(_flink, "key"), "field" );
									xmlFree( prop_str );

								    if( (prop_str = (char*)xmlGetNoNsProp(_f, BAD_CAST "jump")) )
									    osrfHashSet( _tmp_fcontext, osrfStringArrayTokenize( prop_str, '.' ), "jump" );
									xmlFree( prop_str );

									// Tokenize field attribute into an osrfStringArray
									char * field_list = (char*) xmlGetProp(_f, BAD_CAST "field");
									if( field_list )
										osrfLogDebug(OSRF_LOG_MARK,
											"Permacrud foreign context field list is %s", field_list );
									map = osrfStringArrayTokenize( field_list, ' ' );
									osrfHashSet( _tmp_fcontext, map, "context");
									xmlFree( field_list );

									// Insert the new hash into a hash attached to the parent node
									osrfHashSet( foreign_context, _tmp_fcontext, osrfHashGet( _flink, "class" ) );

								} else {

									if( (prop_str = (char*)xmlGetNoNsProp(_f, BAD_CAST "field") )) {
										char* map_list = prop_str;
										osrfLogDebug(OSRF_LOG_MARK,
											"Permacrud local context field list is %s", prop_str );
			
										if (strlen( map_list ) > 0) {
											char* st_tmp = NULL;
											char* _map_class = strtok_r(map_list, " ", &st_tmp);
											osrfStringArrayAdd(
												osrfHashGet( action_def_hash, "local_context"), _map_class);
									
											while ((_map_class = strtok_r(NULL, " ", &st_tmp))) {
												osrfStringArrayAdd(
													osrfHashGet( action_def_hash, "local_context"), _map_class);
											}
										}
										xmlFree(map_list);
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
					char* content_str;
					if( (content_str = (char*)xmlNodeGetContent(_cur)) ) {
						osrfLogDebug(OSRF_LOG_MARK, "Using source definition '%s' for class %s",
							content_str, current_class_name );
						osrfHashSet(
							class_def_hash,
							content_str,
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

// Adds a standard virtual field to a fields hash
static void add_std_fld( osrfHash* fields_hash, const char* field_name, unsigned pos ) {
	char array_pos_buf[ 7 ];
	osrfHash* std_fld_hash = osrfNewHash();

	snprintf( array_pos_buf, sizeof( array_pos_buf ), "%u", pos );
	osrfHashSet( std_fld_hash, strdup( array_pos_buf ), "array_position" );
	osrfHashSet( std_fld_hash, "true", "virtual" );
	osrfHashSet( std_fld_hash, strdup( field_name ), "name" );
	osrfHashSet( fields_hash, std_fld_hash, field_name );
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

static osrfHash* findClassDef( const char* classname ) {
	if( !classname || !idlHash )
		return NULL;
	else
		return osrfHashGet( idlHash, classname );
}

osrfHash* oilsIDL_links( const char* classname ) {
	osrfHash* classdef = findClassDef( classname );
	if( classdef )
		return osrfHashGet( classdef, "links" );
	else
		return NULL;
}

osrfHash* oilsIDL_fields( const char* classname ) {
	osrfHash* classdef = findClassDef( classname );
	if( classdef )
		return osrfHashGet( classdef, "fields" );
	else
		return NULL;
}

int oilsIDL_classIsFieldmapper ( const char* classname ) {
	if( findClassDef( classname ) )
		return 1;
	else
		return 0;
}

// For a given class: return the array_position associated with a 
// specified field. (or -1 if it doesn't exist)
int oilsIDL_ntop (const char* classname, const char* fieldname) {
	osrfHash* fields_hash = oilsIDL_fields( classname );
	if( !fields_hash )
		return -1;     // No such class, or no fields for it

	osrfHash* field_def_hash = osrfHashGet( fields_hash, fieldname );
	if( !field_def_hash )
		return -1;			// No such field

	const char* pos_attr = osrfHashGet( field_def_hash, "array_position" );
	if( !pos_attr )
		return -1;			// No array_position attribute

	return atoi( pos_attr );	// Return position as int
}

// For a given class: return a copy of the name of the field 
// at a specified array_position (or NULL if there is none)
char * oilsIDL_pton (const char* classname, int pos) {
	osrfHash* fields_hash = oilsIDL_fields( classname );
	if( !fields_hash )
		return NULL;     // No such class, or no fields for it

	char* ret = NULL;
	osrfHash* field_def_hash = NULL;
	osrfHashIterator* iter = osrfNewHashIterator( fields_hash );

	while ( ( field_def_hash = osrfHashIteratorNext( iter ) ) ) {
		if ( atoi( osrfHashGet( field_def_hash, "array_position" ) ) == pos ) {
			ret = strdup( osrfHashIteratorKey( iter ) );
			break;
		}
	}

	osrfHashIteratorFree( iter );

	return ret;
}

