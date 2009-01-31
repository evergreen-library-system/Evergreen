/*
*  C Implementation: dump_idl
*
* Description: 
*
*
* Author: Scott McKellar <scott@esilibrary.com>, (C) 2009
*
* Copyright: See COPYING file that comes with this distribution
*
*/

#include <stdlib.h>
#include <stdio.h>
#include <opensrf/string_array.h>
#include <opensrf/osrf_hash.h>
#include <openils/oils_idl.h>

static void dump_idl( osrfHash* IDLHash );
static void dump_class( osrfHash* class_hash, const char* class_name );
static void dump_fields( osrfHash* field_hash );
static void dump_one_field( osrfHash* field_hash, const char* field_name );
static void dump_links( osrfHash* links_hash );
static void dump_one_link( osrfHash* link_hash, const char* link_name );
static void dump_permacrud( osrfHash* pcrud_hash );
static void dump_action( osrfHash* action_hash, const char* action_name );
static void dump_foreign_context( osrfHash* fc_hash );
static void dump_fc_class( osrfHash* fc_class_hash, const char* class_name );
static void dump_string_array( 
	osrfStringArray* sarr, const char* name, const char* indent );

int main( int argc, char* argv[] ) {
	int rc = 0;
	
	// Suppress informational messages
	osrfLogSetLevel( OSRF_LOG_WARNING );

	// Get name of IDL file, if specified on command line
	const char* IDL_filename = NULL;
	int filename_expected = 0;		// boolean
	int i;
	for( i = 1; i < argc; ++i ) {
		const char* arg = argv[ i ];
		printf( "%s\n", arg );
		if( filename_expected ) {
			IDL_filename = arg;
			filename_expected = 0;
		} else {
			if( '-' == arg[ 0 ] && 'f' == arg[1] ) {
				if( IDL_filename ) {
					fprintf( stderr, "Only one IDL file may be specified\n" );
					return 1;
				} else {
					if( arg[ 2 ] )
						IDL_filename = arg + 2;
					else
						filename_expected = 1;
				}
			}
			else
				break;
		}
	}
	
	if( filename_expected ) {
		fprintf( stderr, "IDL filename expected on command line, not found\n" );
		return 1;
	}

	// No filename?  Look in the environment
	if( !IDL_filename )
		IDL_filename = getenv( "OILS_IDL_FILENAME" );

	// Still no filename?  Apply a default
	if( !IDL_filename )
		IDL_filename = "/openils/conf/fm_IDL.xml";
	
	printf( "IDL filename: %s\n", IDL_filename );
	
	osrfHash* IDL = oilsIDLInit( IDL_filename );
	if( NULL == IDL ) {
		fputs( "Failed to build IDL\n", stderr );
		rc = 1;
	}

	if( i >= argc )
		// No classes specified?  Dump them all
		dump_idl( IDL );
	else do {
		// Dump the requested classes
		dump_class( osrfHashGet( IDL, argv[ i ] ), argv[ i ] );
		++i;
	} while( i < argc );
		
	return rc;
}

static void dump_idl( osrfHash* IDLHash ) {
	if( NULL == IDLHash )
		return;

	if( 0 == osrfHashGetCount( IDLHash ) )
		return;

	osrfHashIterator* iter = osrfNewHashIterator( IDLHash );
	osrfHash* class_hash = NULL;
	
	// Dump each class
	for( ;; ) {
		class_hash = osrfHashIteratorNext( iter );
		if( class_hash )
			dump_class( class_hash, osrfHashIteratorKey( iter ) );
		else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_class( osrfHash* class_hash, const char* class_name )
{
	if( !class_hash || !class_name )
		return;
	
	if( 0 == osrfHashGetCount( class_hash ) )
		return;

	printf( "Class %s\n", class_name );
	const char* indent = "    ";
	
	osrfHashIterator* iter = osrfNewHashIterator( class_hash );
	
	// Dump each attribute, etc. of the class hash
	for( ;; ) {
		void* class_attr = osrfHashIteratorNext( iter );
		if( class_attr ) {
			const char* attr_name = osrfHashIteratorKey( iter );
			if( !strcmp( attr_name, "classname" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) class_attr );
			else if( !strcmp( attr_name, "fieldmapper" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) class_attr );
			else if( !strcmp( attr_name, "tablename" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) class_attr );
			else if( !strcmp( attr_name, "virtual" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) class_attr );
			else if( !strcmp( attr_name, "controller" ) )
				dump_string_array( (osrfStringArray*) class_attr, attr_name, indent );
			else if( !strcmp( attr_name, "fields" ) )
				dump_fields( (osrfHash*) class_attr );
			else if( !strcmp( attr_name, "links" ) )
				dump_links( (osrfHash*) class_attr );
			else if( !strcmp( attr_name, "primarykey" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) class_attr );
			else if( !strcmp( attr_name, "sequence" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) class_attr );
			else if( !strcmp( attr_name, "permacrud" ) )
				dump_permacrud( (osrfHash*) class_attr );
			else if( !strcmp( attr_name, "source_definition" ) )
				printf( "%s%s:\n%s\n", indent, attr_name, (char*) class_attr );
			else
				printf( "%s%s (unknown)\n", indent, attr_name );
		} else
			break;
	}
}

static void dump_fields( osrfHash* fields_hash ) {
	if( NULL == fields_hash )
		return;

	if( 0 == osrfHashGetCount( fields_hash ) )
		return;

	fputs( "    fields\n", stdout );
	
	osrfHashIterator* iter = osrfNewHashIterator( fields_hash );
	osrfHash* fields_attr = NULL;
	
	// Dump each field
	for( ;; ) {
		fields_attr = osrfHashIteratorNext( iter );
		if( fields_attr )
			dump_one_field( fields_attr, osrfHashIteratorKey( iter ) );
		else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_one_field( osrfHash* field_hash, const char* field_name ) {
	if( !field_hash || !field_name )
		return;
	
	if( 0 == osrfHashGetCount( field_hash ) )
		return;

	printf( "        %s\n", field_name  );
	
	osrfHashIterator* iter = osrfNewHashIterator( field_hash );
	const char* field_attr = NULL;
	const char* indent = "            ";
	
	// Dump each field attribute
	for( ;; ) {
		field_attr = osrfHashIteratorNext( iter );
		if( field_attr )
			printf( "%s%s: %s\n", indent, osrfHashIteratorKey( iter ), field_attr );
		else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_links( osrfHash* links_hash ) {
	if( NULL == links_hash )
		return;

	if( 0 == osrfHashGetCount( links_hash ) )
		return;

	fputs( "    links\n", stdout );
	
	osrfHashIterator* iter = osrfNewHashIterator( links_hash );
	osrfHash* links_attr = NULL;
	
	// Dump each link
	for( ;; ) {
		links_attr = osrfHashIteratorNext( iter );
		if( links_attr )
			dump_one_link( links_attr, osrfHashIteratorKey( iter ) );
		else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_one_link( osrfHash* link_hash, const char* link_name ) {
	if( !link_hash || !link_name )
		return;
	
	if( 0 == osrfHashGetCount( link_hash ) )
		return;

	printf( "        %s\n", link_name  );
	
	osrfHashIterator* iter = osrfNewHashIterator( link_hash );
	const void* link_attr = NULL;
	const char* indent = "            ";
	
	// Dump each link attribute
	for( ;; ) {
		link_attr = osrfHashIteratorNext( iter );
		if( link_attr ) {
			const char* link_attr_name = osrfHashIteratorKey( iter );
			if( !strcmp( link_attr_name, "reltype" ) )
				printf( "%s%s: %s\n", indent, link_attr_name, (char*) link_attr );
			else if( !strcmp( link_attr_name, "key" ) )
				printf( "%s%s: %s\n", indent, link_attr_name, (char*) link_attr );
			else if( !strcmp( link_attr_name, "class" ) )
				printf( "%s%s: %s\n", indent, link_attr_name, (char*) link_attr );
			else if( !strcmp( link_attr_name, "map" ) ) 
				dump_string_array( (osrfStringArray*) link_attr, link_attr_name, indent );
			else if( !strcmp( link_attr_name, "field" ) )
				printf( "%s%s: %s\n", indent, link_attr_name, (char*) link_attr );
			else
				printf( "%s%s (unknown)\n", indent, link_attr_name );
		} else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_permacrud( osrfHash* pcrud_hash ) {
	if( NULL == pcrud_hash )
		return;

	if( 0 == osrfHashGetCount( pcrud_hash ) )
		return;

	fputs( "    permacrud\n", stdout );
	
	osrfHashIterator* iter = osrfNewHashIterator( pcrud_hash );
	osrfHash* pcrud_attr = NULL;

	// Dump each action
	for( ;; ) {
		pcrud_attr = osrfHashIteratorNext( iter );
		if( pcrud_attr )
			dump_action( pcrud_attr, osrfHashIteratorKey( iter ) );
		else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_action( osrfHash* action_hash, const char* action_name ) {
	if( !action_hash || !action_name )
		return;

	if( 0 == osrfHashGetCount( action_hash ) )
		return;

	printf( "        %s\n", action_name );

	osrfHashIterator* iter = osrfNewHashIterator( action_hash );
	void* action_attr = NULL;
	const char* indent = "            ";

	// Dump each attribute of the action
	for( ;; ) {
		action_attr = osrfHashIteratorNext( iter );
		if( action_attr ) {
			const char* attr_name = osrfHashIteratorKey( iter );
			if( !strcmp( attr_name, "permission" ) )
				dump_string_array( action_attr, attr_name, indent );
			else if( !strcmp( attr_name, "global_required" ) )
				printf( "%s%s: %s\n", indent, attr_name, (char*) action_attr );
			else if( !strcmp( attr_name, "local_context" ) )
				dump_string_array( action_attr, attr_name, indent );
			else if( !strcmp( attr_name, "foreign_context" ) )
				dump_foreign_context( action_attr );
			else
				printf( "%s%s (unknown)\n", indent, attr_name );
		} else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_foreign_context( osrfHash* fc_hash ) {
	if( !fc_hash )
		return;
	
	if( 0 == osrfHashGetCount( fc_hash ) )
		return;

	fputs( "            foreign_context\n", stdout );

	osrfHashIterator* iter = osrfNewHashIterator( fc_hash );
	osrfHash* fc_attr = NULL;

	// Dump each foreign context attribute
	for( ;; ) {
		fc_attr = osrfHashIteratorNext( iter );
		if( fc_attr )
			dump_fc_class( (osrfHash*) fc_attr, osrfHashIteratorKey( iter ) );
		else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_fc_class( osrfHash* fc_class_hash, const char* class_name )
{
	if( ! fc_class_hash )
		return;
	
	if( 0 == osrfHashGetCount( fc_class_hash ) )
		return;
	
	printf( "                %s\n", class_name );

	osrfHashIterator* iter = osrfNewHashIterator( fc_class_hash );
	void* fc_class_attr = NULL;
	const char* indent = "                    ";

	// Dump each foreign context attribute
	for( ;; ) {
		fc_class_attr = osrfHashIteratorNext( iter );
		if( fc_class_attr ) {
			const char* fc_class_attr_name = osrfHashIteratorKey( iter );
			if( !strcmp( fc_class_attr_name, "field" ) )
				printf( "%s%s: %s\n", indent, fc_class_attr_name, (const char*) fc_class_attr );
			else if( !strcmp( fc_class_attr_name, "fkey" ) )
				printf( "%s%s: %s\n", indent, fc_class_attr_name, (const char*) fc_class_attr );
			else if( !strcmp( fc_class_attr_name, "jump" ) )
				dump_string_array( (osrfStringArray*) fc_class_attr, fc_class_attr_name, indent );
			else if( !strcmp( fc_class_attr_name, "context" ) )
				dump_string_array( (osrfStringArray*) fc_class_attr, fc_class_attr_name, indent );
			else
				printf( "%s%s\n", indent, fc_class_attr_name );
		} else
			break;
	}

	osrfHashIteratorFree( iter );
}

static void dump_string_array( 
	osrfStringArray* sarr, const char* name, const char* indent ) {
	if( !sarr || !name || !indent )
		return;

	int size = sarr->size;

	// Ignore an empty array
	if( 0 == size )
		return;

	printf( "%s%s (string array)\n", indent, name );

	int i;
	for( i = 0; i < size; ++i )
		printf( "%s\t%s\n", indent, osrfStringArrayGetString( sarr, i ) );
}
