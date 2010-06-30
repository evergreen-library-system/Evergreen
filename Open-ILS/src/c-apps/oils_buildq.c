/**
	@file buildquery.c
	@brief Routines for maintaining a BuildSQLState.

	A BuildSQLState shuttles information from the routines that load an abstract representation
	of a query to the routines that build an SQL statement.
*/

#include <stdlib.h>
#include <string.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/string_array.h"
#include "openils/oils_buildq.h"

/**
	@brief Construct a new BuildSQLState.
	@param dbhandle Handle for the database connection.
	@return Pointer to the newly constructed BuildSQLState.

	The calling code is responsible for freeing the BuildSQLState by calling BuildSQLStateFree().
*/
BuildSQLState* buildSQLStateNew( dbi_conn dbhandle ) {

	BuildSQLState* state   = safe_malloc( sizeof( BuildSQLState ) );
	state->dbhandle        = dbhandle;
	state->result          = NULL;
	state->error           = 0;
	state->error_msgs      = osrfNewStringArray( 16 );
	state->sql             = buffer_init( 128 );
	state->bindvar_list    = NULL;  // Don't build it until we need it
	state->query_stack     = NULL;
	state->expr_stack      = NULL;
	state->indent          = 0;
	state->defaults_usable = 0;
	state->values_required = 0;
	state->panic           = 0;

	return state;
}

const char* sqlAddMsg( BuildSQLState* state, const char* msg, ... ) {
	if( !state || ! state->error_msgs )
		return "";

	VA_LIST_TO_STRING( msg );
	osrfStringArrayAdd( state->error_msgs, VA_BUF );
	return osrfStringArrayGetString( state->error_msgs, state->error_msgs->size - 1 );
}

/**
	@brief Free a BuildSQLState.
	@param state Pointer to the BuildSQLState to be freed.

	We do @em not close the database connection.
*/
void buildSQLStateFree( BuildSQLState* state ){
	
	if( state ) {
		if( state->result ) {
			dbi_result_free( state->result );
			state->result = NULL;
		}
		osrfStringArrayFree( state->error_msgs );
		buffer_free( state->sql );
		if( state->bindvar_list )
			osrfHashFree( state->bindvar_list );
		while( state->query_stack )
			pop_id( &state->query_stack );
		while( state->expr_stack )
			pop_id( &state->expr_stack );
		while( state->from_stack )
			pop_id( &state->from_stack );
		free( state );
	}
}

/**
	@brief Free up any resources held by the BuildSQL module.
*/
void buildSQLCleanup( void ) {
	storedQCleanup();
}
