/**
	@file oils_execsql.c
	@brief Excecute a specified SQL query and return the results.
*/

#include <stdlib.h>
#include <stdio.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/string_array.h"
#include "opensrf/osrf_json.h"
#include "opensrf/osrf_application.h"
#include "openils/oils_sql.h"
#include "openils/oils_buildq.h"

static jsonObject* get_row( BuildSQLState* state );
static jsonObject* get_date_column( dbi_result result, int col_idx );
static int values_missing( BuildSQLState* state );

/**
	@brief Execute the current SQL statement and return the first row.
	@param state Pointer to the query-building context.
	@return Pointer to a newly-allocated jsonObject representing the row, if there is one; or
		NULL if there isn't.

	The returned row is a JSON_ARRAY of column values, of which each is a JSON_STRING,
	JSON_NUMBER, or JSON_NULL.
*/
jsonObject* oilsFirstRow( BuildSQLState* state ) {

	if( !state )
		return NULL;

	// Make sure all the bind variables have values for them
	if( !state->values_required && values_missing( state )) {
		state->error = 1;
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to execute query: values not available for all bind variables\n" ));
		return NULL;
	}

	if( state->result )
		dbi_result_free( state->result );

	// Execute the query
	state->result = dbi_conn_query( state->dbhandle, OSRF_BUFFER_C_STR( state->sql ));
	if( !state->result ) {
		state->error = 1;
		const char* msg;
		(void) dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to execute query: %s",msg ? msg : "No description available" ));
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
		return NULL;
	}

	// Get the first row
	if( dbi_result_first_row( state->result ))
		return get_row( state );
	else {
		dbi_result_free( state->result );
		state->result = NULL;
		return NULL;         // No rows returned
	}
}

/**
	@brief Return the next row from a previously executed SQL statement.
	@param state Pointer to the query-building context.
	@return Pointer to a newly-allocated jsonObject representing the row, if there is one; or
		NULL if there isn't.

	The returned row is a JSON_ARRAY of column values, of which each is a JSON_STRING,
	JSON_NUMBER, or JSON_NULL.
*/
jsonObject* oilsNextRow( BuildSQLState* state ) {

	if( !state || !state->result )
		return NULL;

	// Get the next row
	if( dbi_result_next_row( state->result ))
		return get_row( state );
	else {
		dbi_result_free( state->result );
		state->result = NULL;
		return NULL;         // No next row returned
	}
}

/**
	@brief Construct a JSON representation of a returned row.
	@param state Pointer to the query-building context.
	@return Pointer to a newly-allocated jsonObject representing the row.
*/
static jsonObject* get_row( BuildSQLState* state  ) {
	unsigned int col_count = dbi_result_get_numfields( state->result );
	jsonObject* row = jsonNewObjectType( JSON_ARRAY );

	unsigned int i = 1;
	for( i = 1; i <= col_count; ++i ) {

		if( dbi_result_field_is_null_idx( state->result, i )) {
			jsonObjectPush( row, jsonNewObjectType( JSON_NULL ));
			continue;       // Column is null
		}

		jsonObject* col_value = NULL;
		int type = dbi_result_get_field_type_idx( state->result, i );
		switch( type ) {
			case DBI_TYPE_INTEGER : {
				long long value = dbi_result_get_longlong_idx( state->result, i );
				col_value = jsonNewNumberObject( (double) value );
				break;
			}
			case DBI_TYPE_DECIMAL : {
				double value = dbi_result_get_double_idx( state->result, i );
				col_value = jsonNewNumberObject( value );
				break;
			}
			case DBI_TYPE_STRING : {
				const char* value = dbi_result_get_string_idx( state->result, i );
				col_value = jsonNewObject( value );
				break;
			}
			case DBI_TYPE_BINARY : {
				osrfLogError( OSRF_LOG_MARK, "Binary types not supported; column set to null" );
				col_value = jsonNewObjectType( JSON_NULL );
				break;
			}
			case DBI_TYPE_DATETIME : {
				col_value = get_date_column( state->result, i );
				break;
			}
			default :
				osrfLogError( OSRF_LOG_MARK,
					"Unrecognized column type %d; column set to null", type );
				col_value = jsonNewObjectType( JSON_NULL );
				break;
		}
		jsonObjectPush( row, col_value );
	}

	return row;
}

/**
	@brief Translate a date column into a string.
	@param result Reference to the current returned row.
	@param col_idx Column number (starting with 1) within the row.
	@return Pointer to a newly-allocated JSON_STRING containing a formatted date string.

	The calling code is responsible for freeing the returned jsonObject by calling
	jsonObjectFree().
*/
static jsonObject* get_date_column( dbi_result result, int col_idx ) {

	time_t timestamp = dbi_result_get_datetime_idx( result, col_idx );
	char timestring[ 256 ] = "";
	int attr = dbi_result_get_field_attribs_idx( result, col_idx );
	struct tm gmdt;

	if( !( attr & DBI_DATETIME_DATE )) {
		gmtime_r( &timestamp, &gmdt );
		strftime( timestring, sizeof( timestring ), "%T", &gmdt );
	} else if( !( attr & DBI_DATETIME_TIME )) {
		gmtime_r( &timestamp, &gmdt );
		strftime( timestring, sizeof( timestring ), "%F", &gmdt );
	} else {
		localtime_r( &timestamp, &gmdt );
		strftime( timestring, sizeof( timestring ), "%FT%T%z", &gmdt );
	}

	return jsonNewObject( timestring );
}

/**
	@brief Determine whether all bind variables have values supplied for them.
	@param state Pointer to the query-building context.
	@return The number of bind variables with no available value.
*/
static int values_missing( BuildSQLState* state ) {
	if( !state->bindvar_list || osrfHashGetCount( state->bindvar_list ) == 0 )
		return 0;   // Nothing to count

	int count = 0;
	osrfHashIterator* iter = osrfNewHashIterator( state->bindvar_list );

	BindVar* bind = NULL;
	while(( bind = osrfHashIteratorNext( iter ))) {
		if( !bind->actual_value && !bind->default_value ) {
			sqlAddMsg( state, "No value for bind value \"%s\", with label \"%s\"",
				bind->name, bind->label );
			++count;
		}
	}

	osrfHashIteratorFree( iter );
	return count;
}
