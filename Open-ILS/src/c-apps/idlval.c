/**
	@file idlval.c
	@brief Validator for IDL files.
*/

/*
Copyright (C) 2009  Georgia Public Library Service
Scott McKellar <scott@esilibrary.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <libxml/globals.h>
#include <libxml/xmlerror.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/debugXML.h>
#include <libxml/xmlmemory.h>

#include <opensrf/utils.h>
#include <opensrf/osrf_hash.h>

/* Represents the command line */
struct Opts {
	int new_argc;
	char ** new_argv;

	char * idl_file_name;
	int idl_file_name_found;
	int warning;
};
typedef struct Opts Opts;

/* datatype attribute of <field> element */
typedef enum {
	DT_NONE,
	DT_BOOL,
	DT_FLOAT,
	DT_ID,
	DT_INT,
	DT_INTERVAL,
	DT_LINK,
	DT_MONEY,
	DT_NUMBER,
	DT_ORG_UNIT,
	DT_TEXT,
	DT_TIMESTAMP,
	DT_INVALID
} Datatype;

/* Represents a <Field> aggregate */
struct Field_struct {
	struct Field_struct* next;
	xmlChar* name;
	int is_virtual;     // boolean
	xmlChar* label;
	Datatype datatype;
};
typedef struct Field_struct Field;

/* reltype attribute of <link> element */
typedef enum {
	RT_NONE,
	RT_HAS_A,
	RT_MIGHT_HAVE,
	RT_HAS_MANY,
	RT_INVALID
} Reltype;

/* Represents a <link> element */
struct Link_struct {
	struct Link_struct* next;
	xmlChar* field;
	Reltype reltype;
	xmlChar* key;
	xmlChar* classref;
};
typedef struct Link_struct Link;

/* Represents a <class> aggregate */
typedef struct {
	xmlNodePtr node;
	int loaded;        // boolean
	int is_virtual;    // boolean
	xmlChar* primary;  // name of primary key column
	Field* fields;     // linked list
	Link* links;       // linked list
} Class;

static int get_Opts( int argc, char * argv[], Opts * pOpts );;
static int val_idl( void );
static int cross_validate_classes( Class* class, const char* id );
static int cross_validate_linkage( Class* class, const char*id, Link* link );
static int val_class( Class* class, const char* id );
static int val_class_attributes( Class* class, const char* id );
static int check_labels( const Class* class, const char* id );
static int val_fields_attributes( Class* class, const char* id, xmlNodePtr fields );
static int val_links_to_fields( const Class* class, const char* id );
static int compareFieldAndLink( const Class* class, const char* id,
		const Field* field, const Link* link );
static int val_fields_to_links( const Class* class, const char* id );
static const Field* searchFieldByName( const Class* class, const xmlChar* field_name );
static int val_fields( Class* class, const char* id, xmlNodePtr fields );
static int val_one_field( Class* class, const char* id, xmlNodePtr field );
static Datatype translate_datatype( const xmlChar* value );
static int val_links( Class* class, const char* id, xmlNodePtr links );
static int val_one_link( Class* class, const char* id, xmlNodePtr link );
static Reltype translate_reltype( const xmlChar* value );
static int scan_idl( xmlDocPtr doc );
static int register_class( xmlNodePtr child );
static int addField( Class* class, const char* id, Field* new_field );
static int addLink( Class* class, const char* id, Link* new_link );
static Class* newClass( xmlNodePtr node );
static void freeClass( char* key, void* p );
static Field* newField( xmlChar* name );
static void freeField( Field* field );
static Link* newLink( xmlChar* field );
static void freeLink( Link* link );

/* Stores an in-memory representation of the IDL */
static osrfHash* classes = NULL;

static int warn = 0;       // boolean; true if -w present on command line

int main( int argc, char* argv[] ) {

	// Examine command line
	Opts opts;
	if( get_Opts( argc, argv, &opts ) )
		return 1;

	const char* IDL_filename = NULL;
	if( opts.idl_file_name_found )
		IDL_filename = opts.idl_file_name;
	else {
		IDL_filename = getenv( "OILS_IDL_FILENAME" );
		if( ! IDL_filename )
			IDL_filename = "/openils/conf/fm_IDL.xml";
	}

	if( opts.warning )
		warn = 1;

	int rc = 0;

	xmlLineNumbersDefault(1);
	xmlDocPtr doc = xmlReadFile( IDL_filename, NULL, XML_PARSE_XINCLUDE );
	if ( ! doc ) {
		fprintf( stderr, "Could not load or parse the IDL XML file %s\n", IDL_filename );
		rc = 1;
	} else {
		printf( "Validating: %s\n", IDL_filename );
		classes = osrfNewHash();
		osrfHashSetCallback( classes, freeClass );

		// Load the IDL
		if( scan_idl( doc ) )
			rc = 1;

		if( opts.new_argc < 2 ) {

			// No classes specified: validate all classes
			if( val_idl() )
				rc = 1;
		} else {

			// Validate one or more specified classes
			int i = 1;
			while( i < opts.new_argc ) {
				const char* classname = opts.new_argv[ i ];
				Class* class = osrfHashGet( classes, classname );
				if( ! class ) {
					printf( "Class \"%s\" does not exist\n", classname );
					rc = 1;
				} else {
					// Validate the class in isolation
					if( val_class( class, classname ) )
						rc = 1;
					// Cross-validate with linked classes
					if( cross_validate_classes( class, classname ) )
						rc = 1;
				}
				++i;
			}
		}
		osrfHashFree( classes );
		xmlFreeDoc( doc );
	}

	return rc;
}

/**
	@brief Examine the command line
	@param argc Number of entries in argv[]
	@param argv Array of pointers to command line strings
	@param pOpts Pointer to structure to be populated
	@return 0 upon success, or 1 if the command line is invalid
*/
static int get_Opts( int argc, char * argv[], Opts * pOpts ) {
	int rc = 0; /* return code */
	int opt;

	/* Define valid option characters */

	const char optstring[] = ":f:w";

	/* Initialize members of struct */

	pOpts->new_argc = 0;
	pOpts->new_argv = NULL;

	pOpts->idl_file_name_found = 0;
	pOpts->idl_file_name = NULL;
	pOpts->warning = 0;

	/* Suppress error messages from getopt() */

	opterr = 0;

	/* Examine command line options */

	while( ( opt = getopt( argc, argv, optstring ) ) != -1 ) {
		switch( opt ) {
			case 'f' :   /* Get idl_file_name */
				if( pOpts->idl_file_name_found ) {
					fprintf( stderr, "Only one occurrence of -f option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->idl_file_name_found = 1;

				pOpts->idl_file_name = optarg;
				break;
				case 'w' :   /* Get warning */
					pOpts->warning = 1;
					break;
					case ':' : /* Missing argument */
						fprintf( stderr, "Required argument missing on -%c option\n",
								 (char) optopt );
						rc = 1;
						break;
						case '?' : /* Invalid option */
							fprintf( stderr, "Invalid option '-%c' on command line\n",
									 (char) optopt );
							rc = 1;
							break;
							default :  /* Programmer error */
								fprintf( stderr, "Internal error: unexpected value '-%c'"
										"for optopt", (char) optopt );
								rc = 1;
								break;
		} /* end switch */
	} /* end while */

	if( optind > argc ) {
		/* This should never happen! */

		fprintf( stderr, "Program error: found more arguments than expected\n" );
		rc = 1;
	} else {
		/* Calculate new_argcv and new_argc to reflect */
		/* the number of arguments consumed */

		pOpts->new_argc = argc - optind + 1;
		pOpts->new_argv = argv + optind - 1;
	}

	return rc;
}

/**
	@brief Validate all classes.
	@return 1 if errors found, or 0 if not.

	Traverse the class list and validate each class in turn.
*/
static int val_idl( void ) {
	int rc = 0;
	osrfHashIterator* itr = osrfNewHashIterator( classes );
	Class* class = NULL;

	// For each class
	while( (class = osrfHashIteratorNext( itr )) ) {
		const char* id = osrfHashIteratorKey( itr );
		if( val_class( class, id ) )               // validate class separately
			rc = 1;
		if( cross_validate_classes( class, id ) )  // cross-validate with linked classes
			rc = 1;
	}

	osrfHashIteratorFree( itr );
	return rc;
}

/**
	@brief Make sure that every linkage appropriately matches the linked class.
	@param class Pointer to the current Class.
	@param id Class id.
	@return 1 if errors found, or 0 if not.
*/
static int cross_validate_classes( Class* class, const char* id ) {
	int rc = 0;
	Link* link = class->links;
	while( link ) {
		if( cross_validate_linkage( class, id, link ) )
			rc = 1;
		link = link->next;
	}

	return rc;
}

/**
	@brief Make sure that a linkage appropriately matches the linked class.
	@param class Pointer to the current class.
	@param id Class id.
	@param link Pointer to the link being validated.
	@return 1 if errors found, or 0 if not.

	Rules:
	- The linked class must exist.
	- The field to which the linkage points must exist.
	- If the linked class has a corresponding link back to the current class, then exactly
	one end of the linkage must have a reltype of "has_many".

	It is not an error if the linkage is not reciprocated.
*/
static int cross_validate_linkage( Class* class, const char*id, Link* link ) {
	int rc = 0;
	Class* other_class = osrfHashGet( classes, (char*) link->classref );
	if( ! other_class ) {
		printf( "In class \"%s\": class \"%s\", referenced by \"%s\" field, does not exist\n",
				id, (char*) link->classref, (char*) link->field );
		rc = 1;
	} else {
		// Make sure the other class is loaded before we look at it further
		if( val_class( other_class, (char*) link->classref ) )
			rc = 1;

		// Now see if the other class links back to this one
		Link* other_link = other_class->links;
		while( other_link ) {
			if( !strcmp( id, (char*) other_link->classref )                    // class to class
				&& !strcmp( (char*) link->key,   (char*) other_link->field )   // key to field
				&& !strcmp( (char*) link->field, (char*) other_link->key ) ) { // field to key
				break;
			}
			other_link = other_link->next;
		}

		if( ! other_link ) {
			// Link is not reciprocated?  That's okay, as long as
			// the referenced field exists in the referenced class.
			if( !searchFieldByName( other_class, link->key ) ) {
				printf( "In class \"%s\": field \"%s\" links to field \"%s\" of class \"%s\", "
					"but that field doesn't exist\n", id, (char*) link->field,
					(char*) link->key, (char*) link->classref );
				rc = 1;
			}
		} else {
			// The link is reciprocated.  Make sure that exactly one of the links
			// has a reltype of "has_many"
			int many_count = 0;
			if( RT_HAS_MANY == link->reltype )
				++many_count;
			if( RT_HAS_MANY == other_link->reltype )
				++many_count;

			if( 0 == many_count ) {
				printf( "Classes \"%s\" and \"%s\" link to each other, but neither has a reltype "
						"of \"has_many\"\n", id, (char*) link->classref );
				rc = 1;
			} else if( 2 == many_count ) {
				printf( "Classes \"%s\" and \"%s\" link to each other, but both have a reltype "
						"of \"has_many\"\n", id, (char*) link->classref );
				rc = 1;
			}
		}
	}

	return rc;
}

/**
	@brief Validate a single class.
	@param id Class id.
	@param class Pointer to the XML node for the class element.
	@return 1 if errors found, or 0 if not.

	We have already validated the id.

	Rules:
	- Allowed elements are "fields", "links", "permacrud", and "source_definition".
	- None of these elements may occur more than once in the same class.
	- The "fields" element is required.
	- No text allowed, other than white space.
	- Comments are allowed (and ignored).
*/
static int val_class( Class* class, const char* id ) {
	if( !class )
		return 1;
	else if( class->loaded )
		return 0;         // We've already validated this one locally

	int rc = 0;

	if( val_class_attributes( class, id ) )
		rc = 1;

	xmlNodePtr fields = NULL;
	xmlNodePtr links = NULL;
	xmlNodePtr permacrud = NULL;
	xmlNodePtr src_def = NULL;

	// Examine every child element of the <class> element.
	xmlNodePtr child = class->node->children;
	while( child ) {
		const char* child_name = (char*) child->name;
		if( xmlNodeIsText( child ) ) {
			if( ! xmlIsBlankNode( child ) ) {
				// Found unexpected text.  After removing leading and
				// trailing white space, complain about it.
				xmlChar* content = xmlNodeGetContent( child );

				xmlChar* begin = content;
				while( *begin && isspace( *begin ) )
					++begin;
				if( *begin ) {
					xmlChar* end = begin + strlen( (char*) begin ) - 1;
					while( (isspace( *end ) ) )
						--end;
					end[ 1 ] = '\0';
				}

				printf( "Unexpected text in class \"%s\": \"%s\"\n", id,
					(char*) begin );
				xmlFree( content );
			}
		} else if( !strcmp( child_name, "fields" ) ) {
			if( fields ) {
				printf( "Multiple <fields> elements in class \"%s\"\n", id );
				rc = 1;
			} else {
				fields = child;
				// Identify the primary key, if any
				class->primary = xmlGetProp( fields, (xmlChar*) "primary" );
				if( val_fields( class, id, fields ) )
					rc = 1;
			}
		} else if( !strcmp( child_name, "links" ) ) {
			if( links ) {
				printf( "Multiple <links> elements in class \"%s\"\n", id );
				rc = 1;
			} else {
				links = child;
				if( val_links( class, id, links ) )
					rc = 1;
			}
		} else if( !strcmp( child_name, "permacrud" ) ) {
			if( permacrud ) {
				printf( "Multiple <permacrud> elements in class \"%s\"\n", id );
				rc = 1;
			} else {
				permacrud = child;
			}
		} else if( !strcmp( child_name, "source_definition" ) ) {
			if( src_def ) {
				printf( "Multiple <source_definition> elements in class \"%s\"\n", id );
				rc = 1;
			} else {
				// To do: verify that there is nothing in <source_definition> except text and
				// comments, and that the text is non-empty.
				src_def = child;
			}
		} else if( !strcmp( child_name, "comment" ) )
			;  // ignore comment
		else {
			printf( "Line %ld: Unexpected <%s> element in class \"%s\"\n",
				xmlGetLineNo( child ), child_name, id );
			rc = 1;
		}
		child = child->next;
	}

	if( fields ) {
		if( check_labels( class, id ) )
			rc = 1;
		if( val_fields_attributes( class, id, fields ) )
			rc = 1;
	} else {
		printf( "No <fields> element in class \"%s\"\n", id );
		rc = 1;
	}

	if( val_links_to_fields( class, id ) )
		rc = 1;

	if( val_fields_to_links( class, id ) )
		rc = 1;

	class->loaded = 1;
	return rc;
}

/**
	@brief Validate the class attributes.
	@param class Pointer to the current Class.
	@param id Class id.
	@return if errors found, or 0 if not.

	Rules:
	- Only the following attributes are valid: controller, core, field_safe, field_mapper,
	id, label, readonly, restrict_primary, tablename, and virtual.
	- The controller and fieldmapper attributes are required (as is the id attribute, but
	that's checked elsewhere).
	- Every attribute value must be non-empty.
	- The values of attributes core, field_safe, reaadonly, and virtual must be either
	"true" or "false".
	- A virtual class must not have a tablename attribute.
*/
static int val_class_attributes( Class* class, const char* id ) {
	int rc = 0;

	int controller_found = 0;     // boolean
	int fieldmapper_found = 0;    // boolean
	int tablename_found = 0;      // boolean

	xmlAttrPtr attr = class->node->properties;
	while( attr ) {
		const char* attr_name = (char*) attr->name;
		if( !strcmp( (char*) attr_name, "id" ) ) {
			;  // ignore; we already grabbed this one
		} else if( !strcmp( (char*) attr_name, "controller" ) ) {
			controller_found = 1;
			xmlChar* value = xmlGetProp( class->node, (xmlChar*) "controller" );
			if( '\0' == *value ) {
				printf( "Line %ld: Value of controller attribute is empty in class \"%s\"\n",
					xmlGetLineNo( class->node ), id );
				rc = 1;
			}
			xmlFree( value );
		} else if( !strcmp( (char*) attr_name, "fieldmapper" ) ) {
			fieldmapper_found = 1;
			xmlChar* value = xmlGetProp( class->node, (xmlChar*) "fieldmapper" );
			if( '\0' == *value ) {
				printf( "Line %ld: Value of fieldmapper attribute is empty in class \"%s\"\n",
						xmlGetLineNo( class->node ), id );
				rc = 1;
			}
			xmlFree( value );
		} else if( !strcmp( (char*) attr_name, "label" ) ) {
			xmlChar* value = xmlGetProp( class->node, (xmlChar*) "label" );
			if( '\0' == *value ) {
				printf( "Line %ld: Value of label attribute is empty in class \"%s\"\n",
						xmlGetLineNo( class->node ), id );
				rc = 1;
			}
			xmlFree( value );
		} else if( !strcmp( (char*) attr_name, "tablename" ) ) {
			tablename_found = 1;
			xmlChar* value = xmlGetProp( class->node, (xmlChar*) "tablename" );
			if( '\0' == *value ) {
				printf( "Line %ld: Value of tablename attribute is empty in class \"%s\"\n",
						xmlGetLineNo( class->node ), id );
				rc = 1;
			}
			xmlFree( value );
		} else if( !strcmp( (char*) attr_name, "virtual" ) ) {
			xmlChar* virtual_str = xmlGetProp( class->node, (xmlChar*) "virtual" );
			if( virtual_str ) {
				if( !strcmp( (char*) virtual_str, "true" ) ) {
					class->is_virtual = 1;
				} else if( strcmp( (char*) virtual_str, "false" ) ) {
					printf(
						"Line %ld: Invalid value \"%s\" for virtual attribute of class\"%s\"\n",
						xmlGetLineNo( class->node ), (char*) virtual_str, id );
					rc = 1;
				}
				xmlFree( virtual_str );
			}
		} else if( !strcmp( (char*) attr_name, "readonly" ) ) {
			xmlChar* readonly = xmlGetProp( class->node, (xmlChar*) "readonly" );
			if( readonly ) {
				if(    strcmp( (char*) readonly, "true" )
					&& strcmp( (char*) readonly, "false" ) ) {
					printf(
						"Line %ld: Invalid value \"%s\" for readonly attribute of class\"%s\"\n",
						xmlGetLineNo( class->node ), (char*) readonly, id );
					rc = 1;
				}
				xmlFree( readonly );
			}
		} else if( !strcmp( (char*) attr_name, "restrict_primary" ) ) {
			xmlChar* value = xmlGetProp( class->node, (xmlChar*) "restrict_primary" );
			if( '\0' == *value ) {
				printf( "Line %ld: Value of restrict_primary attribute is empty in class \"%s\"\n",
						xmlGetLineNo( class->node ), id );
				rc = 1;
			}
			xmlFree( value );
		} else if( !strcmp( (char*) attr_name, "core" ) ) {
			xmlChar* core = xmlGetProp( class->node, (xmlChar*) "core" );
			if( core ) {
				if(    strcmp( (char*) core, "true" )
					&& strcmp( (char*) core, "false" ) ) {
					printf(
					   "Line %ld: Invalid value \"%s\" for core attribute of class\"%s\"\n",
						xmlGetLineNo( class->node ), (char*) core, id );
					rc = 1;
				}
				xmlFree( core );
			}
		} else if( !strcmp( (char*) attr_name, "field_safe" ) ) {
			xmlChar* field_safe = xmlGetProp( class->node, (xmlChar*) "field_safe" );
			if( field_safe ) {
				if(    strcmp( (char*) field_safe, "true" )
					&& strcmp( (char*) field_safe, "false" ) ) {
					printf(
						"Line %ld: Invalid value \"%s\" for field_safe attribute of class\"%s\"\n",
						xmlGetLineNo( class->node ), (char*) field_safe, id );
					rc = 1;
				}
				xmlFree( field_safe );
			}
		} else {
			printf( "Line %ld: Unrecognized class attribute \"%s\" in class \"%s\"\n",
				xmlGetLineNo( class->node ), attr_name, id );
			rc = 1;
		}
		attr = attr->next;
	} // end while

	if( ! controller_found ) {
		printf( "Line %ld: No controller attribute for class \"%s\"\n",
			xmlGetLineNo( class->node ), id );
		rc = 1;
	}

	if( ! fieldmapper_found ) {
		printf( "Line %ld: No fieldmapper attribute for class \"\%s\"\n",
			xmlGetLineNo( class->node ), id );
		rc = 1;
	}

	if( class->is_virtual && tablename_found ) {
		printf( "Line %ld: Virtual class \"%s\" shouldn't have a tablename",
			xmlGetLineNo( class->node ), id );
		rc = 1;
	}

	return rc;
}

/**
	@brief Determine whether fields are either all labeled or all unlabeled.
	@param class Pointer to the current Class.
	@param id Class id.
	@return 1 if errors found, or 0 if not.

	Rule:
	- The fields for a given class must either all be labeled or all unlabeled.

	For purposes of this validation, a field is considered labeled even if the label is an
	empty string.  Empty labels are reported elsewhere.
*/
static int check_labels( const Class* class, const char* id ) {
	int rc = 0;

	int label_found = 0;    // boolean
	int unlabel_found = 0;  // boolean

	Field* field = class->fields;
	while( field ) {
		if( field->label )
			label_found = 1;
		else
			unlabel_found = 1;
		field = field->next;
	}

	if( label_found && unlabel_found ) {
		printf( "Class \"%s\" has a mixture of labeled and unlabeled fields\n", id );
		rc = 1;
	}

	return rc;
}

/**
	@brief Validate the fields attributes.
	@param class Pointer to the current Class.
	@param id Class id.
	@param fields Pointer to the XML node for the fields element.
	@return if errors found, or 0 if not.

	Rules:
	- The only valid attributes for the fields element are "primary" and "sequence".
	- Neither attribute may have an empty string for a value.
	- If there is a sequence attribute, there must also be a primary attribute.
	- If there is a primary attribute, the field identified must exist.
	- If the primary key field has the datatype "id", there must be a sequence attribute.
	- If the datatype of the primary key is not "id" or "int", there must @em not be a
	sequence attribute.
*/
static int val_fields_attributes( Class* class, const char* id, xmlNodePtr fields ) {
	int rc = 0;

	xmlChar* sequence = NULL;
	xmlChar* primary  = NULL;

	// Traverse the attributes
	xmlAttrPtr attr = fields->properties;
	while( attr ) {
		const char* attr_name = (char*) attr->name;
		if( !strcmp( attr_name, "primary" ) ) {
			primary = xmlGetProp( fields, (xmlChar*) "primary" );
			if( '\0' == primary[0] ) {
				printf(
					"Line %ld: value of primary attribute is an empty string for class \"%s\"\n",
					xmlGetLineNo( fields ), id );
				rc = 1;
			}
		} else if( !strcmp( attr_name, "sequence" )) {
			sequence = xmlGetProp( fields, (xmlChar*) "sequence" );
			if( '\0' == sequence[0] ) {
				printf(
					"Line %ld: value of sequence attribute is an empty string for class \"%s\"\n",
					xmlGetLineNo( fields ), id );
				rc = 1;
			} else if( !strchr( (const char*) sequence, '.' )) {
				printf(
					"Line %ld: name of sequence for class \"%s\" is not qualified by schema\n",
					xmlGetLineNo( fields ), id );
				rc = 1;
			}
		} else {
			printf( "Line %ld: Unexpected fields attribute \"%s\" in class \"%s\"\n",
				xmlGetLineNo( fields ), attr_name, id );
			rc = 1;
		}

		attr = attr->next;
	}

	if( sequence && ! primary ) {
		printf( "Line %ld: class \"%s\" has a sequence identified but no primary key\n",
			xmlGetLineNo( fields ), id );
		rc = 1;
	}

	if( primary ) {
		// look for the primary key
		Field* field = class->fields;
		while( field ) {
			if( !strcmp( (char*) field->name, (char*) primary ) )
				break;
			field = field->next;
		}
		if( !field ) {
			printf( "Primary key field \"%s\" does not exist for class \"%s\"\n",
				(char*) primary, id );
			rc = 1;
		} else if( DT_ID == field->datatype && ! sequence && ! class->is_virtual ) {
			printf(
				"Line %ld: Primary key is an id; class \"%s\" may need a sequence attribute\n",
				xmlGetLineNo( fields ), id );
			rc = 1;
		} else if(    DT_ID != field->datatype
				   && DT_INT != field->datatype
				   && DT_ORG_UNIT != field->datatype
				   && sequence ) {
			printf(
				"Line %ld: Datatype of key for class \"%s\" does not allow a sequence attribute\n",
				xmlGetLineNo( fields ), id );
			rc = 1;
		}
	}

	xmlFree( primary );
	xmlFree( sequence );
	return rc;
}

/**
	@brief Verify that every Link has a matching Field for a given Class.
	@param class Pointer to the current class.
	@param id Class id.
	@return 1 if errors found, or 0 if not.

	Rules:
	- For every link element, there must be a matching field element in the same class.
	- If the link's reltype is "has_many", the field must be a virtual field of type link
	or org_unit.
	- If the link's reltype is "has_a" or "might_have", the field must be a non-virtual link
	of type link or org_unit.
*/
static int val_links_to_fields( const Class* class, const char* id ) {
	if( !class )
		return 1;

	int rc = 0;

	const Link* link = class->links;
	while( link ) {
		if( link->field && *link->field ) {
			const Field* field = searchFieldByName( class, link->field );
			if( field ) {
				if( compareFieldAndLink( class, id, field, link ) )
					rc = 1;
			} else {
				printf( "\"%s\" class has no <field> corresponding to <link> for \"%s\"\n",
					id, (char*) link->field );
				rc = 1;
			}
		}
		link = link->next;
	}

	return rc;
}

/**
	@brief Compare matching field and link elements to see if they are compatible
	@param class Pointer to the current Class.
	@param id Class id.
	@param field Pointer to the Field to be compared to the Link.
	@param link Pointer to the Link to be compared to the Field.
	@return 0 if they are compatible, or 1 if not.

	Rules:
	- If the reltype is "has_many", the field must be virtual.
	- If a field corresponds to a link, and is not the primary key, then it must have a
	datatype "link" or "org_unit".
	- If the datatype is "org_unit", the linkage must be to the class "aou".

	Warnings:
	- If the reltype is "has_a" or "might_have", the the field should probably @em not
	be virtual, but there are legitimate exceptions.
	- If the linkage is to the class "aou", then the datatype should probably be "org_unit".
*/
static int compareFieldAndLink( const Class* class, const char* id,
		const Field* field, const Link* link ) {
	int rc = 0;

	Datatype datatype = field->datatype;
	const char* classref = (const char*) link->classref;

	// Validate the virtuality of the field
	if( RT_HAS_A == link->reltype || RT_MIGHT_HAVE == link->reltype ) {
		if( warn && field->is_virtual ) {
			// This is the child class; field should usually be non-virtual,
			// but there are legitimate exceptions.
			printf( "WARNING: In class \"%s\": field \"%s\" is tied to a \"has_a\" or "
				"\"might_have\" link; perhaps should not be virtual\n",
				id, (char*) field->name );
		}
	} else if ( RT_HAS_MANY == link->reltype ) {
		if( ! field->is_virtual ) {
			printf( "In class \"%s\": field \"%s\" is tied to a \"has_many\" link "
					"and therefore should be virtual\n", id, (char*) field->name );
			rc = 1;
		}
	}

	// Validate the datatype of the field
	if( class->primary && !strcmp( (char*) class->primary, (char*) field->name ) ) {
		; // For the primary key field, the datatype can be anything
	} else if( DT_NONE == datatype || DT_INVALID == datatype ) {
		printf( "In class \"%s\": \"%s\" field should have a datatype for linkage\n",
				id, (char*) field->name );
		rc = 1;
	} else if( DT_ORG_UNIT == datatype ) {
		if( strcmp( classref, "aou" ) ) {
			printf( "In class \"%s\": \"%s\" field should have a datatype "
					"\"link\", not \"org_unit\"\n", id, field->name );
			rc = 1;
		}
	} else if( DT_LINK == datatype ) {
		if( warn && !strcmp( classref, "aou" ) ) {
			printf( "WARNING: In class \"%s\", field \"%s\": Consider changing datatype "
					"to \"org_unit\"\n", id, (char*) field->name );
		}
	} else {
		// Datatype should be "link", or maybe "org_unit"
		if( !strcmp( classref, "aou" ) ) {
			printf( "In class \"%s\": \"%s\" field should have a datatype "
					"\"org_unit\" or \"link\"\n",
					id, (char*) field->name );
			rc = 1;
		} else {
			printf( "In class \"%s\": \"%s\" field should have a datatype \"link\"\n",
					id, (char*) field->name );
			rc = 1;
		}
	}

	return rc;
}

/**
	@brief See if every linked field has a counterpart in the links aggregate.
	@param class Pointer to the current class.
	@param id Class id.
	@return 1 if errors found, or 0 if not.

	Rules:
	- If a field has a datatype of "link" or "org_unit, there must be a corresponding
	entry in the links aggregate.
*/
static int val_fields_to_links( const Class* class, const char* id ) {
	int rc = 0;
	const Field* field = class->fields;
	while( field ) {
		if( DT_LINK != field->datatype && DT_ORG_UNIT != field->datatype ) {
			field = field->next;
			continue;  // not a link?  skip it
		}
		// See if there's a matching entry in the <links> aggregate
		const Link* link = class->links;
		while( link ) {
			if( !strcmp( (char*) field->name, (char*) link->field ) )
				break;
			link = link->next;
		}

		if( !link ) {
			if( !strcmp( (char*) field->name, "id" ) && !strcmp( id, "aou" ) ) {
				// Special exception: primary key of "aou" is of
				// datatype "org_unit", but it's not a foreign key.
				;
			} else {
				printf( "In class \"%s\": Linked field \"%s\" has no matching <link>\n",
						id, (char*) field->name );
				rc = 1;
			}
		}
		field = field->next;
	}
	return rc;
}

/**
	@brief Search a given Class for a Field with a given name.
	@param class Pointer to the class in which to search.
	@param field_name The field name for which to search.
	@return Pointer to the Field if found, or NULL if not.
*/
static const Field* searchFieldByName( const Class* class, const xmlChar* field_name ) {
	if( ! class || ! field_name || ! *field_name )
		return NULL;

	const char* name = (const char*) field_name;
	const Field* field = class->fields;
	while( field ) {
		if( field->name && !strcmp( (char*) field->name, name ) )
			return field;
		field = field->next;
	}

	return NULL;
}

/**
	@brief Validate a fields element.
	@param class Pointer to the current Class.
	@param id Id of the current Class.
	@param fields Pointer to the XML node for the fields element.
	@return 1 if errors found, or 0 if not.

	Rules:
	- There must be at least one field element.
	- No other elements are allowed.
	- Text is not allowed, other than white space.
	- Comments are allowed (and ignored).
*/
static int val_fields( Class* class, const char* id, xmlNodePtr fields ) {
	int rc = 0;
	int field_found = 0;    // boolean

	xmlNodePtr child = fields->children;
	while( child ) {
		const char* child_name = (char*) child->name;
		if( xmlNodeIsText( child ) ) {
			if( ! xmlIsBlankNode( child ) ) {
				// Found unexpected text.  After removing leading and
				// trailing white space, complain about it.
				xmlChar* content = xmlNodeGetContent( child );

				xmlChar* begin = content;
				while( *begin && isspace( *begin ) )
					++begin;
				if( *begin ) {
					xmlChar* end = begin + strlen( (char*) begin ) - 1;
					while( (isspace( *end ) ) )
						--end;
					end[ 1 ] = '\0';
				}

				printf( "Unexpected text in <fields> element of class \"%s\": \"%s\"\n", id,
					(char*) begin );
				xmlFree( content );
			}
		} else if( ! strcmp( child_name, "field" ) ) {
			field_found = 1;
			if( val_one_field( class, id, child ) )
				rc = 1;
		} else if( !strcmp( child_name, "comment" ) )
			;  // ignore comment
		else {
			printf( "Line %ld: Unexpected <%s> element in <fields> of class \"%s\"\n",
				xmlGetLineNo( child ), child_name, id );
			rc = 1;
		}
		child = child->next;
	}

	if( !field_found ) {
		printf( "No <field> element in class \"%s\"\n", id );
		rc = 1;
	}

	return rc;
}

/**
	@brief Validate a field element within a fields element.
	@param class Pointer to the current Class.
	@param id Class id.
	@param field Pointer to the XML node for the field element.
	@return 1 if errors found, or 0 if not.

	Rules:
	- attribute names are limited to: "name", "virtual", "label", "datatype", "array_position",
	"selector", "i18n", "primitive".
	- "name" attribute is required.
	- label attribute, if present, must have a non-empty value.
	- virtual and i18n attributes, if present, must have a value of "true" or "false".
	- if the datatype attribute is present, its value must be one of: "bool", "float", "id",
	"int", "interval", "link", "money", "number", "org_unit", "text", "timestamp".

	Warnings:
	- A non-virtual field should have a datatype attribute.
	- Attribute "array_position" is deprecated.
*/
static int val_one_field( Class* class, const char* id, xmlNodePtr field ) {
	int rc = 0;
	xmlChar* label = NULL;
	xmlChar* field_name = NULL;
	int is_virtual = 0;
	Datatype datatype = DT_NONE;

	// Traverse the attributes
	xmlAttrPtr attr = field->properties;
	while( attr ) {
		const char* attr_name = (char*) attr->name;
		if( !strcmp( attr_name, "name" ) ) {
			field_name = xmlGetProp( field, (xmlChar*) "name" );
		} else if( !strcmp( attr_name, "virtual" ) ) {
			xmlChar* virt = xmlGetProp( field, (xmlChar*) "virtual" );
			if( !strcmp( (char*) virt, "true" ) )
				is_virtual = 1;
			else if( strcmp( (char*) virt, "false" ) ) {
				printf( "Line %ld: Invalid value for virtual attribute: \"%s\"\n",
					xmlGetLineNo( field ), (char*) virt );
				rc = 1;
			}
			xmlFree( virt );
			// To do: verify that the namespace is oils_persist
		} else if( !strcmp( attr_name, "label" ) ) {
			label = xmlGetProp( field, (xmlChar*) "label" );
			if( '\0' == *label ) {
				printf( "Line %ld: Empty value for label attribute for class \"%s\"\n",
					xmlGetLineNo( field ), id );
				xmlFree( label );
				label = NULL;
				rc = 1;
			}
			// To do: verify that the namespace is reporter
		} else if( !strcmp( attr_name, "datatype" ) ) {
			xmlChar* dt_str = xmlGetProp( field, (xmlChar*) "datatype" );
			datatype = translate_datatype( dt_str );
			if( DT_INVALID == datatype ) {
				printf( "Line %ld: Invalid datatype \"%s\" in class \"%s\"\n",
					xmlGetLineNo( field ), (char*) dt_str, id );
				rc = 1;
			}
			xmlFree( dt_str );
			// To do: make sure that the namespace is reporter
		} else if( !strcmp( attr_name, "array_position" ) ) {
			printf( "Line %ld: WARNING: Deprecated array_position attribute "
					"for field \"%s\" in class \"%s\"\n",
					xmlGetLineNo( field ), ((char*) field_name ? : ""), id );
		} else if( !strcmp( attr_name, "selector" ) ) {
			;  // Ignore for now
		} else if( !strcmp( attr_name, "i18n" ) ) {
			xmlChar* i18n = xmlGetProp( field, (xmlChar*) "i18n" );
			if( strcmp( (char*) i18n, "true" ) && strcmp( (char*) i18n, "false" ) ) {
				printf( "Line %ld: Invalid value for i18n attribute: \"%s\"\n",
					xmlGetLineNo( field ), (char*) i18n );
				rc = 1;
			}
			xmlFree( i18n );
			// To do: verify that the namespace is oils_persist
		} else if( !strcmp( attr_name, "primitive" ) ) {
			xmlChar* primitive = xmlGetProp( field, (xmlChar*) "primitive" );
			if( strcmp( (char*) primitive, "string" ) && strcmp( (char*) primitive, "number" ) ) {
				printf( "Line %ld: Invalid value for primitive attribute: \"%s\"\n",
					xmlGetLineNo( field ), (char*) primitive );
				rc = 1;
			}
			xmlFree( primitive );
		} else if( !strcmp( attr_name, "validate" )) {
			xmlChar* validate = xmlGetProp( field, (xmlChar*) "validate" );
			if( !*validate ) {
				// Value should be a regular expression to define a validation rule
				printf( "Line %ld: Empty value for \"validate\" attribute "
					"for field \"%s\" in class \"%s\"\n",
					xmlGetLineNo( field ), (char*) field_name ? : "", id );
				rc = 1;
			}
			xmlFree( validate );
			// To do: verify that the namespace is oils_obj
		} else if( !strcmp( attr_name, "required" )) {
			xmlChar* required = xmlGetProp( field, (xmlChar*) "required" );
			if( strcmp( (char*) required, "true" ) && strcmp( (char*) required, "false" )) {
				printf( 
					"Line %ld: Invalid value \"%s\" for \"required\" attribute "
					"for field \"%s\" in class \"%s\"\n",
					xmlGetLineNo( field ), (char*) required,
					(char*) field_name ? : "", id );
				rc = 1;
			}
			xmlFree( required );
			// To do: verify that the namespace is oils_obj
		} else {
			printf( "Line %ld: Unexpected field attribute \"%s\" in class \"%s\"\n",
				xmlGetLineNo( field ), attr_name, id );
			rc = 1;
		}

		attr = attr->next;
	}

	if( warn && (!is_virtual) && DT_NONE == datatype ) {
		printf( "Line %ld: WARNING: No datatype attribute for field \"%s\" in class \"%s\"\n",
			xmlGetLineNo( field ), ((char*) field_name ? : ""), id );
	}

	if( ! field_name ) {
		printf( "Line %ld: No name attribute for <field> element in class \"%s\"\n",
			xmlGetLineNo( field ), id );
		rc = 1;
	} else if( '\0' == *field_name ) {
		printf( "Line %ld: Field name is empty for <field> element in class \"%s\"\n",
			xmlGetLineNo( field ), id );
		rc = 1;
	} else {
		// Add to the class's field list
		Field* new_field = newField( field_name );
		new_field->is_virtual = is_virtual;
		new_field->label = label;
		new_field->datatype = datatype;
		if( addField( class, id, new_field ) )
			rc = 1;
	}

	return rc;
}

/**
	@brief Translate a datatype string into a Dataype (an enum).
	@param value The value of a datatype attribute.
	@return The datatype in the form of an enum.
*/
static Datatype translate_datatype( const xmlChar* value ) {
	const char* val = (const char*) value;
	Datatype type;

	if( !value || !*value )
		type = DT_NONE;
	else if( !strcmp( val, "bool" ) )
		type = DT_BOOL;
	else if( !strcmp( val, "float" ) )
		type = DT_FLOAT;
	else if( !strcmp( val, "id" ) )
		type = DT_ID;
	else if( !strcmp( val, "int" ) )
		type = DT_INT;
	else if( !strcmp( val, "interval" ) )
		type = DT_INTERVAL;
	else if( !strcmp( val, "link" ) )
		type = DT_LINK;
	else if( !strcmp( val, "money" ) )
		type = DT_MONEY;
	else if( !strcmp( val, "number" ) )
		type = DT_NUMBER;
	else if( !strcmp( val, "org_unit" ) )
		type = DT_ORG_UNIT;
	else if( !strcmp( val, "text" ) )
		type = DT_TEXT;
	else if( !strcmp( val, "timestamp" ) )
		type = DT_TIMESTAMP;
	else
		type = DT_INVALID;

	return type;
}

/**
	@brief Validate a links element.
	@param class Pointer to the current Class.
	@param id Id of the current Class.
	@param links Pointer to the XML node for the links element.
	@return 1 if errors found, or 0 if not.

	Rules:
	- No elements other than "link" are allowed.
	- Text is not allowed, other than white space.
	- Comments are allowed (and ignored).

	Warnings:
	- There is usually at least one link element.
*/
static int val_links( Class* class, const char* id, xmlNodePtr links ) {
	int rc = 0;
	int link_found = 0;    // boolean

	xmlNodePtr child = links->children;
	while( child ) {
		const char* child_name = (char*) child->name;
		if( xmlNodeIsText( child ) ) {
			if( ! xmlIsBlankNode( child ) ) {
				// Found unexpected text.  After removing leading and
				// trailing white space, complain about it.
				xmlChar* content = xmlNodeGetContent( child );

				xmlChar* begin = content;
				while( *begin && isspace( *begin ) )
					++begin;
				if( *begin ) {
					xmlChar* end = begin + strlen( (char*) begin ) - 1;
					while( (isspace( *end ) ) )
						--end;
					end[ 1 ] = '\0';
				}

				printf( "Unexpected text in <links> element of class \"%s\": \"%s\"\n", id,
					(char*) begin );
				xmlFree( content );
			}
		} else if( ! strcmp( child_name, "link" ) ) {
			link_found = 1;
			if( val_one_link( class, id, child ) )
				rc = 1;
		} else if( !strcmp( child_name, "comment" ) )
			;  // ignore comment
		else {
			printf( "Line %ld: Unexpected <%s> element in <link> of class \"%s\"\n",
				xmlGetLineNo( child ), child_name, id );
				rc = 1;
		}
		child = child->next;
	}

	if( warn && !link_found ) {
		printf( "WARNING: No <link> element in class \"%s\"\n", id );
	}

	return rc;
}

/**
		@brief Validate one link element.
		@param class Pointer to the current Class.
		@param id Id of the current Class.
		@param link Pointer to the XML node for the link element.
		@return 1 if errors found, or 0 if not.

	Rules:
	- The only allowed attributes are "field", "reltype", "key", "map", and "class".
	- Except for map, every attribute is required.
	- Except for map, every attribute must have a non-empty value.
	- The value of the reltype attribute must be one of "has_a", "might_have", or "has_many".
*/
static int val_one_link( Class* class, const char* id, xmlNodePtr link ) {
	int rc = 0;
	xmlChar* field_name = NULL;
	Reltype reltype = RT_NONE;
	xmlChar* key = NULL;
	xmlChar* classref = NULL;

	// Traverse the attributes
	xmlAttrPtr attr = link->properties;
	while( attr ) {
		const char* attr_name = (const char*) attr->name;
		if( !strcmp( attr_name, "field" ) ) {
			field_name = xmlGetProp( link, (xmlChar*) "field" );
		} else if (!strcmp( attr_name, "reltype" ) ) {
			;
			xmlChar* rt = xmlGetProp( link, (xmlChar*) "reltype" );
			if( *rt ) {
				reltype = translate_reltype( rt );
				if( RT_INVALID == reltype ) {
					printf(
						"Line %ld: Invalid value \"%s\" for reltype attribute in class \"%s\"\n",
						xmlGetLineNo( link ), (char*) rt, id );
					rc = 1;
				}
			} else {
				printf( "Line %ld: Empty value for reltype attribute in class \"%s\"\n",
					xmlGetLineNo( link ), id );
				rc = 1;
			}
			xmlFree( rt );
		} else if (!strcmp( attr_name, "key" ) ) {
			key = xmlGetProp( link, (xmlChar*) "key" );
		} else if (!strcmp( attr_name, "map" ) ) {
			;   // ignore for now
		} else if (!strcmp( attr_name, "class" ) ) {
			classref = xmlGetProp( link, (xmlChar*) "class" );
		} else {
			printf( "Line %ld: Unexpected attribute %s in links element of class \"%s\"\n",
				xmlGetLineNo( link ), attr_name, id );
			rc = 1;
		}
		attr = attr->next;
	}

	if( !field_name ) {
		printf( "Line %ld: No field attribute found in <link> in class \"%s\"\n",
			xmlGetLineNo( link ), id );
		rc = 1;
	} else if( '\0' == *field_name ) {
		printf( "Line %ld: Field name is empty for <link> element in class \"%s\"\n",
			xmlGetLineNo( link ), id );
		rc = 1;
	} else if( !reltype ) {
		printf( "Line %ld: No reltype attribute found in <link> in class \"%s\"\n",
			xmlGetLineNo( link ), id );
		rc = 1;
	} else if( !key ) {
		printf( "Line %ld: No key attribute found in <link> in class \"%s\"\n",
				xmlGetLineNo( link ), id );
		rc = 1;
	} else if( '\0' == *key ) {
		printf( "Line %ld: key attribute is empty for <link> element in class \"%s\"\n",
			xmlGetLineNo( link ), id );
		rc = 1;
	} else if( !classref ) {
		printf( "Line %ld: No class attribute found in <link> in class \"%s\"\n",
			 xmlGetLineNo( link ), id );
		rc = 1;
	} else if( '\0' == *classref ) {
		printf( "Line %ld: class attribute is empty for <link> element in class \"%s\"\n",
			xmlGetLineNo( link ), id );
		rc = 1;
	} else {
		// Add to Link list
		Link* new_link = newLink( field_name );
		new_link->reltype = reltype;
		new_link->key = key;
		new_link->classref = classref;
		if( addLink( class, id, new_link ) )
			rc = 1;
	}

	return rc;
}

/**
	@brief Translate an attribute value into a Reltype (an enum).
	@param value The value of a reltype attribute.
	@return The value of the attribute translated into the enum Reltype.
*/
static Reltype translate_reltype( const xmlChar* value ) {
	const char* val = (char*) value;
	Reltype reltype;

	if( !val || !*val )
		reltype = RT_NONE;
	else if( !strcmp( val, "has_a" ) )
		reltype = RT_HAS_A;
	else if( !strcmp( val, "might_have" ) )
		reltype = RT_MIGHT_HAVE;
	else if( !strcmp( val, "has_many" ) )
		reltype = RT_HAS_MANY;
	else
		reltype = RT_INVALID;

	return reltype;
}

/**
	@brief Build a list of classes, while checking for several errors.
	@param doc Pointer to the xmlDoc loaded from the IDL.
	@return 1 if errors found, or 0 if not.

	Rules:
	- Every child element of the root must be of the element "class".
	- No text is allowed, other than white space, between classes.
	- Comments are allowed (and ignored) between classes.
*/
static int scan_idl( xmlDocPtr doc ) {
	int rc = 0;

	xmlNodePtr child = xmlDocGetRootElement( doc )->children;
	while( child ) {
		char* child_name = (char*) child->name;
		if( xmlNodeIsText( child ) ) {
			if( ! xmlIsBlankNode( child ) ) {
				// Found unexpected text.  After removing leading and
				// trailing white space, complain about it.
				xmlChar* content = xmlNodeGetContent( child );

				xmlChar* begin = content;
				while( *begin && isspace( *begin ) )
					++begin;
				if( *begin ) {
					xmlChar* end = begin + strlen( (char*) begin ) - 1;
					while( (isspace( *end ) ) )
						--end;
					end[ 1 ] = '\0';
				}

				printf( "Unexpected text between class elements: \"%s\"\n",
					(char*) begin );
				xmlFree( content );
			}
		} else if( !strcmp( child_name, "class" ) ) {
			if( register_class( child ) )
				rc = 1;
		} else if( !strcmp( child_name, "comment" ) )
			;  // ignore comment
		else {
			printf( "Line %ld: Unexpected <%s> element under root\n",
				xmlGetLineNo( child ), child_name );
			rc = 1;
		}

		child = child->next;
	}
	return rc;
}

/**
	@brief Register a class.
	@param class Pointer to the class node.
	@return 1 if errors found, or 0 if not.

	Rules:
	- Every class element must have an "id" attribute.
	- A class id must not be an empty string.
	- Every class id must be unique.

	Warnings:
	- A class id normally consists entirely of lower case letters, digits and underscores.
	- A class id longer than 12 characters is suspiciously long.
*/
static int register_class( xmlNodePtr class ) {
	int rc = 0;
	xmlChar* id = xmlGetProp( class, (xmlChar*) "id" );

	if( ! id ) {
		printf( "Line %ld: Class has no \"id\" attribute\n", xmlGetLineNo( class ) );
		rc = 1;
	} else if( ! *id ) {
		printf( "Line %ld: Class id is an empty string\n", xmlGetLineNo( class ) );
		rc = 1;
	} else {

		// In principle a class id could contain any arbitrary characters, but in practice
		// anything but lower case, digits, and underscores is probably a mistake.
		const xmlChar* p = id;
		while( *p ) {
			if( islower( *p ) || isdigit( *p ) || '_' == *p )
				++p;
			else if( warn ) {
				printf( "Line %ld: WARNING: Dubious class id \"%s\"; not all lower case, "
						"digits, and underscores\n", xmlGetLineNo( class ), (char*) id );
				break;
			}
		}

		// Warn about a suspiciously long id
		if( warn && strlen( (char*) id ) > 12 ) {
			printf( "Line %ld: WARNING: Class id is unusually long: \"%s\"\n",
				xmlGetLineNo( class ), (char*) id );
		}

		// Add the classname to the list of classes.  If the size of
		// the list doesn't change, then we must have a duplicate.
		Class* entry = newClass( class );
		unsigned long class_count = osrfHashGetCount( classes );
		osrfHashSet( classes, entry, (char*) id );
		if( osrfHashGetCount( classes ) == class_count ) {
			printf( "Line %ld: Duplicate class name \"%s\"\n",
				xmlGetLineNo( class ), (char*) id );
			rc = 1;
		}
		xmlFree( id );
	}
	return rc;
}

/**
	@brief Add a field to a class's field list (unless the id collides with an earlier entry).
	@param class Pointer to the current class.
	@param id The class id.
	@param new_field Pointer to the Field to be added.
	@return 0 if successful, or 1 if not (probably due to a duplicate key).

	If the id collides with a previous entry, we free the new Field instead of adding it
	to the list.  If the label collides with a previous entry, we complain, but we go
	ahead and add the Field to the list.

	RULES:
	- Each field name should be unique within the fields element.
	- Each label should be unique within the fields element.
*/
static int addField( Class* class, const char* id, Field* new_field ) {
	if( ! class || ! new_field )
		return 1;

	int rc = 0;
	int dup_name = 0;

	// See if the class has any other fields with the same name or label.
	const Field* old_field = class->fields;
	while( old_field ) {

		// Compare the ids
		if( !strcmp( (char*) old_field->name, (char*) new_field->name ) ) {
			printf( "Duplicate field name \"%s\" in class \"%s\"\n",
				(char*) new_field->name, id );
			dup_name = 1;
			rc = 1;
			break;
		}

		// Compare the labels. if they're both non-empty
		if( old_field->label && *old_field->label
		 && new_field->label && *new_field->label
		 && !strcmp( (char*) old_field->label, (char*) new_field->label )) {
			printf( "Duplicate labels \"%s\" in class \"%s\"\n",
				(char*) old_field->label, id );
			rc = 1;
		}

		old_field = old_field->next;
	}

	if( dup_name ) {
		free( new_field );
	} else {
		new_field->next = class->fields;
		class->fields = new_field;
	}

	return rc;
}

/**
	@brief Add a Link to the Link list of a specified Class (unless it's a duplicate).
	@param class Pointer to the Class to whose list to add the Link.
	@param id Class id.
	@param new_link Pointer to the Link to be added.
	@return 0 if successful, or 1 if not (probably due to a duplicate).

	If there's already a Link in the list with the same field name, free the new Link
	instead of adding it.
*/
static int addLink( Class* class, const char* id, Link* new_link ) {
	if( ! class || ! new_link )
		return 1;

	int rc = 0;
	int dup_name = 0;

	// See if the class has any other links with the same field
	const Link* old_link = class->links;
	while( old_link ) {

		if( !strcmp( (char*) old_link->field, (char*) new_link->field ) ) {
			printf( "Duplicate field name \"%s\" in links of class \"%s\"\n",
				(char*) old_link->field, id );
			rc = 1;
			dup_name = 1;
			break;
		}

		old_link = old_link->next;
	}

	if( dup_name ) {
		freeLink( new_link );
	} else {
		// Add to the linked list
		new_link->next = class->links;
		class->links = new_link;
	}

	return rc;
}

/**
	@brief Create and initialize a new Class.
	@param node Pointer to the XML node for a class element.
	@return Pointer to the newly created Class.

	The calling code is responsible for freeing the Class by calling freeClass().  In practice
	this happens automagically when we free the osrfHash classes.
*/
static Class* newClass( xmlNodePtr node ) {
	Class* class = safe_malloc( sizeof( Class ) );
	class->node = node;
	class->loaded = 0;
	class->is_virtual = 0;
	xmlFree( class->primary );
	class->fields = NULL;
	class->links = NULL;
	return class;
}

/**
	@brief Free a Class and everything it owns.
	@param key The class id (not used).
	@param p A pointer to the Class to be freed, cast to a void pointer.

	This function is designed to be a freeItem callback for an osrfHash.
*/
static void freeClass( char* key, void* p ) {
	Class* class = p;

	// Free the linked list of Fields
	Field* next_field = NULL;
	Field* field = class->fields;
	while( field ) {
		next_field = field->next;
		freeField( field );
		field = next_field;
	}

	// Free the linked list of Links
	Link* next_link = NULL;
	Link* link = class->links;
	while( link ) {
		next_link = link->next;
		freeLink( link );
		link = next_link;
	}

	free( class );
}

/**
	@brief Allocate and initialize a Field.
	@param name Field name.
	@return Pointer to a new Field.

	It is the responsibility of the caller to free the Field by calling freeField().
*/
static Field* newField( xmlChar* name ) {
	Field* field = safe_malloc( sizeof( Field ) );
	field->next         = NULL;
	field->name         = name;
	field->is_virtual   = 0;
	field->label        = NULL;
	field->datatype     = DT_NONE;
	return field;
}

/**
	@brief Free a Field and everything in it.
	@param field Pointer to the Field to be freed.
*/
static void freeField( Field* field ) {
	if( field ) {
		xmlFree( field->name );
		if( field->label )
			xmlFree( field->label );
		free( field );
	}
}

/**
	@brief Allocate and initialize a Link.
	@param field Field name.
	@return Pointer to a new Link.

	It is the responsibility of the caller to free the Link by calling freeLink().
*/
static Link* newLink( xmlChar* field ) {
	Link* link = safe_malloc( sizeof( Link ) );
	link->next         = NULL;
	link->field        = field;
	link->reltype      = RT_NONE;
	link->key          = NULL;
	link->classref     = NULL;
	return link;
}

/**
	@brief Free a Link and everything it owns.
	@param link Pointer to the Link to be freed.
*/
static void freeLink( Link* link ) {
	if( link ) {
		xmlFree( link->field );
		xmlFree( link->key );
		xmlFree( link->classref );
		free( link );
	}
}
