/**
	@file oils_storedq.c
	@brief Load an abstract representation of a query from the database.
*/

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/string_array.h"
#include "opensrf/osrf_hash.h"
#include "opensrf/osrf_application.h"
#include "openils/oils_sql.h"
#include "openils/oils_buildq.h"

#define PRINT if( verbose ) printf

struct IdNode_ {
	IdNode* next;
	int id;
	char* alias;
};

static int oils_result_get_bool_idx( dbi_result result, int i );

static FromRelation* getFromRelation( BuildSQLState* state, int id );
static FromRelation* constructFromRelation( BuildSQLState* state, dbi_result result );
static FromRelation* getJoinList( BuildSQLState* state, int id );
static void joinListFree( FromRelation* join_list );
static void fromRelationFree( FromRelation* fr );

static QSeq* loadChildQueries( BuildSQLState* state, int parent_id, const char* type_str );
static QSeq* constructQSeq( BuildSQLState* state, dbi_result result );
static void freeQSeqList( QSeq* seq );
static StoredQ* constructStoredQ( BuildSQLState* state, dbi_result result );

static SelectItem* getSelectList( BuildSQLState* state, int query_id );
static SelectItem* constructSelectItem( BuildSQLState* state, dbi_result result );
static void selectListFree( SelectItem* sel );

static BindVar* getBindVar( BuildSQLState* state, const char* name );
static BindVar* constructBindVar( BuildSQLState* state, dbi_result result );
static void bindVarFree( char* name, void* p );

static CaseBranch* getCaseBranchList( BuildSQLState* state, int parent_id );
static CaseBranch* constructCaseBranch( BuildSQLState* state, dbi_result result );
static void freeBranchList( CaseBranch* branch );

static Datatype* getDatatype( BuildSQLState* state, int id );
static Datatype* constructDatatype( BuildSQLState* state, dbi_result result );
static void datatypeFree( Datatype* datatype );

static Expression* getExpression( BuildSQLState* state, int id );
static Expression* constructExpression( BuildSQLState* state, dbi_result result );
static void expressionListFree( Expression* exp );
static void expressionFree( Expression* exp );
static Expression* getExpressionList( BuildSQLState* state, int id );

static OrderItem* getOrderByList( BuildSQLState* state, int query_id );
static OrderItem* constructOrderItem( BuildSQLState* state, dbi_result result );
static void orderItemListFree( OrderItem* ord );

static void push_id( IdNode** stack, int id, const char* alias );
static const IdNode* searchIdStack( const IdNode* stack, int id, const char* alias );

// A series of free lists to store already-allocated objects that are not in use, for
// potential reuse.  This is a hack to reduce churning through malloc() and free().
static StoredQ* free_storedq_list = NULL;
static FromRelation* free_from_relation_list = NULL;
static SelectItem* free_select_item_list = NULL;
static BindVar* free_bindvar_list = NULL;
static CaseBranch* free_branch_list = NULL;
static Datatype* free_datatype_list = NULL;
static Expression* free_expression_list = NULL;
static IdNode* free_id_node_list = NULL;
static QSeq* free_qseq_list = NULL;
static OrderItem* free_order_item_list = NULL;

// Boolean; settable by call to oilsStoredQSetVerbose(), used by PRINT macro.
// The idea is to allow debugging messages from a command line test driver for ease of
// testing and development, but not from a real server, where messages to stdout don't
// go anywhere.
static int verbose = 0;

/**
	@brief Build a list of column names for a specified query.
	@param state Pointer to the query-building context.
	@param query Pointer to the specified query.
	@return Pointer to a newly-allocated JSON_ARRAY of column names, if successful;
		otherwise NULL.

	The column names are those assigned by PostgreSQL, e.g.:
		- a column alias, if an AS clause defines one
		- a column name (not qualified by a table name or alias, even if the query
		  specifies one)
		- where the item is a function call, the name of the function
		- where the item is a subquery or other expression, whatever PostgreSQL decides on,
		  typically '?column?'

	The resulting column names may include duplicates.

	The calling code is responsible for freeing the list by calling jsonObjectFree().
*/
jsonObject* oilsGetColNames( BuildSQLState* state, StoredQ* query ) {
	if( !state || !query ) return NULL;

	// Build SQL in the usual way (with some temporary option settings)
	int defaults_usable = state->defaults_usable;
	int values_required = state->values_required;
	state->defaults_usable = 1;   // We can't execute the test query unless we
	state->values_required = 1;   // have a value for every bind variable.
	int rc = buildSQL( state, query );
	state->defaults_usable = defaults_usable;
	state->values_required = values_required;
	if( rc ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to build SQL statement for query id # %d", query->id ));
		state->error = 1;
		return NULL;
	}

	// Wrap it in an outer query to get the column names, but no rows
	growing_buffer* wrapper = buffer_init( 80 + strlen( OSRF_BUFFER_C_STR( state->sql )));
	buffer_add( wrapper, "SELECT \"phony query\".* FROM (" );
	buffer_add( wrapper, OSRF_BUFFER_C_STR( state->sql ));
	buffer_chomp( wrapper );    // remove the terminating newline
	buffer_chomp( wrapper );    // remove the terminating semicolon
	buffer_add( wrapper, ") AS \"phony query\" WHERE FALSE;" );

	// Execute the wrapped query
	dbi_result result = dbi_conn_query( state->dbhandle, OSRF_BUFFER_C_STR( wrapper ));
	buffer_free( wrapper );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to execute dummy query for column names: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
		return NULL;
	}

	// Examine the query result to get the column names

	unsigned int num_cols = dbi_result_get_numfields( result );
	jsonObject* cols = jsonNewObjectType( JSON_ARRAY );
	unsigned int i;
	for( i = 1; i <= num_cols; ++i ) {
		const char* fname = dbi_result_get_field_name( result, i );
		if( fname )
			jsonObjectPush( cols, jsonNewObject( fname ));
	}

	dbi_result_free( result );
	return cols;
}

/**
	@brief Load a stored query.
	@param state Pointer to the query-building context.
	@param query_id ID of the query in query.stored_query.
	@return A pointer to the newly loaded StoredQ if successful, or NULL if not.

	The calling code is responsible for freeing the StoredQ by calling storedQFree().
*/
StoredQ* getStoredQuery( BuildSQLState* state, int query_id ) {
	if( !state )
		return NULL;

	// Check the stack to see if the current query is nested inside itself.  If it is, then
	// abort in order to avoid infinite recursion.  If it isn't, then add it to the stack.
	// (Make sure to pop it off the stack before returning.)
	if( searchIdStack( state->query_stack, query_id, NULL )) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Infinite recursion detected; query # %d is nested within itself", query_id ));
		state->error = 1;
		return NULL;
	} else
		push_id( &state->query_stack, query_id, NULL );

	StoredQ* sq = NULL;
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, type, use_all, use_distinct, from_clause, where_clause, having_clause, "
		"limit_count, offset_count FROM query.stored_query WHERE id = %d;", query_id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			sq = constructStoredQ( state, result );
			if( sq ) {
				PRINT( "Got a query row\n" );
				PRINT( "\tid: %d\n", sq->id );
				PRINT( "\ttype: %d\n", (int) sq->type );
				PRINT( "\tuse_all: %s\n", sq->use_all ? "true" : "false" );
				PRINT( "\tuse_distinct: %s\n", sq->use_distinct ? "true" : "false" );
			} else
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to build a query for id = %d", query_id ));
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Stored query not found for id %d", query_id ));
			state->error = 1;
		}

		dbi_result_free( result );
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.stored_query table: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	pop_id( &state->query_stack );
	return sq;
}

/**
	@brief Construct a StoredQ.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.stored_query.
	@return Pointer to a newly constructed StoredQ, if successful, or NULL if not.

	The calling code is responsible for freeing the StoredQ by calling storedQFree().
*/
static StoredQ* constructStoredQ( BuildSQLState* state, dbi_result result ) {

	// Get the column values from the result
	int id               = dbi_result_get_int_idx( result, 1 );
	const char* type_str = dbi_result_get_string_idx( result, 2 );

	QueryType type;
	if( !strcmp( type_str, "SELECT" ))
		type = QT_SELECT;
	else if( !strcmp( type_str, "UNION" ))
		type = QT_UNION;
	else if( !strcmp( type_str, "INTERSECT" ))
		type = QT_INTERSECT;
	else if( !strcmp( type_str, "EXCEPT" ))
		type = QT_EXCEPT;
	else {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Invalid query type \"%s\"", type_str ));
		return NULL;
	}

	int use_all             = oils_result_get_bool_idx( result, 3 );
	int use_distinct        = oils_result_get_bool_idx( result, 4 );

	int from_clause_id;
	if( dbi_result_field_is_null_idx( result, 5 ) )
		from_clause_id = -1;
	else
		from_clause_id = dbi_result_get_int_idx( result, 5 );

	int where_clause_id;
	if( dbi_result_field_is_null_idx( result, 6 ) )
		where_clause_id = -1;
	else
		where_clause_id = dbi_result_get_int_idx( result, 6 );

	int having_clause_id;
	if( dbi_result_field_is_null_idx( result, 7 ) )
		having_clause_id = -1;
	else
		having_clause_id = dbi_result_get_int_idx( result, 7 );

	int limit_count_id;
	if( dbi_result_field_is_null_idx( result, 8 ) )
		limit_count_id = -1;
	else
		limit_count_id = dbi_result_get_int_idx( result, 8 );

	int offset_count_id;
	if( dbi_result_field_is_null_idx( result, 9 ) )
		offset_count_id = -1;
	else
		offset_count_id = dbi_result_get_int_idx( result, 9 );

	FromRelation* from_clause = NULL;
	if( QT_SELECT == type ) {
		// A SELECT query needs a FROM clause; go get it
		if( from_clause_id != -1 ) {
			from_clause = getFromRelation( state, from_clause_id );
			if( !from_clause ) {
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to construct FROM clause for id = %d", from_clause_id ));
				return NULL;
			}
		}
	} else {
		// Must be one of UNION, INTERSECT, or EXCEPT
		if( from_clause_id != -1 )
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"FROM clause found and ignored for %s query in query #%d", type_str, id ));
	}

	// If this is a SELECT query, we need a SELECT list.  Go get one.
	SelectItem* select_list = NULL;
	QSeq* child_list = NULL;
	if( QT_SELECT == type ) {
		select_list = getSelectList( state, id );
		if( !select_list ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"No SELECT list found for query id = %d", id ));
			fromRelationFree( from_clause );
			return NULL;
		}
	} else {
		// Construct child queries of UNION, INTERSECT, or EXCEPT query
		child_list = loadChildQueries( state, id, type_str );
		if( !child_list ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to load child queries for %s query # %d", type_str, id ));
			state->error = 1;
			fromRelationFree( from_clause );
			return NULL;
		}
	}

	// Get the WHERE clause, if there is one
	Expression* where_clause = NULL;
	if( where_clause_id != -1 ) {
		where_clause = getExpression( state, where_clause_id );
		if( ! where_clause ) {
			// shouldn't happen due to foreign key constraint
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to fetch WHERE expression for query id = %d", id ));
			freeQSeqList( child_list );
			fromRelationFree( from_clause );
			selectListFree( select_list );
			state->error = 1;
			return NULL;
		}
	}

	// Get the HAVING clause, if there is one
	Expression* having_clause = NULL;
	if( having_clause_id != -1 ) {
		having_clause = getExpression( state, having_clause_id );
		if( ! having_clause ) {
			// shouldn't happen due to foreign key constraint
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to fetch HAVING expression for query id = %d", id ));
			expressionFree( where_clause );
			freeQSeqList( child_list );
			selectListFree( select_list );
			fromRelationFree( from_clause );
			state->error = 1;
			return NULL;
		}
	}

	// Get the ORDER BY clause, if there is one
	OrderItem* order_by_list = getOrderByList( state, id );
	if( state->error ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to load ORDER BY clause for query %d", id ));
		expressionFree( having_clause );
		expressionFree( where_clause );
		freeQSeqList( child_list );
		selectListFree( select_list );
		fromRelationFree( from_clause );
		return NULL;
	}

	// Get the LIMIT clause, if there is one
	Expression* limit_count = NULL;
	if( limit_count_id != -1 ) {
		limit_count = getExpression( state, limit_count_id );
		if( ! limit_count ) {
			// shouldn't happen due to foreign key constraint
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to fetch LIMIT expression for query id = %d", id ));
			orderItemListFree( order_by_list );
			freeQSeqList( child_list );
			selectListFree( select_list );
			fromRelationFree( from_clause );
			state->error = 1;
			return NULL;
		}
	}

	// Get the OFFSET clause, if there is one
	Expression* offset_count = NULL;
	if( offset_count_id != -1 ) {
		offset_count = getExpression( state, offset_count_id );
		if( ! offset_count ) {
			// shouldn't happen due to foreign key constraint
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to fetch OFFSET expression for query id = %d", id ));
			expressionFree( limit_count );
			orderItemListFree( order_by_list );
			freeQSeqList( child_list );
			selectListFree( select_list );
			fromRelationFree( from_clause );
			state->error = 1;
			return NULL;
		}
	}

	// Allocate a StoredQ: from the free list if possible, from the heap if necessary

	StoredQ* sq;
	if( free_storedq_list ) {
		sq = free_storedq_list;
		free_storedq_list = free_storedq_list->next;
	} else
		sq = safe_malloc( sizeof( StoredQ ) );

	// Populate the StoredQ
	sq->next = NULL;
	sq->id = id;

	sq->type = type;
	sq->use_all = use_all;
	sq->use_distinct = use_distinct;
	sq->from_clause = from_clause;
	sq->where_clause = where_clause;
	sq->select_list = select_list;
	sq->child_list = child_list;
	sq->having_clause = having_clause;
	sq->order_by_list = order_by_list;
	sq->limit_count = limit_count;
	sq->offset_count = offset_count;

	return sq;
}

/**
	@brief Load the child queries subordinate to a UNION, INTERSECT, or EXCEPT query.
	@param state Pointer to the query-building context.
	@param parent ID of the UNION, INTERSECT, or EXCEPT query.
	@param type_str The type of the query ("UNION", "INTERSECT", or "EXCEPT").
	@return If successful, a pointer to a linked list of QSeq, each bearing a pointer to a
		StoredQ; otherwise NULL.

	The @a type_str parameter is used only for building error messages.
*/
static QSeq* loadChildQueries( BuildSQLState* state, int parent_id, const char* type_str ) {
	QSeq* child_list = NULL;

	// The ORDER BY is in descending order so that we can build the list by adding to
	// the head, and it will wind up in the right order.
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, parent_query, seq_no, child_query "
		"FROM query.query_sequence WHERE parent_query = %d ORDER BY seq_no DESC", parent_id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			int count = 0;
			while( 1 ) {
				++count;
				QSeq* seq = constructQSeq( state, result );
				if( seq ) {
					PRINT( "Found a child query\n" );
					PRINT( "\tid: %d\n", seq->id );
					PRINT( "\tparent id: %d\n", seq->parent_query_id );
					PRINT( "\tseq_no: %d\n", seq->seq_no );
					// Add to the head of the list
					seq->next = child_list;
					child_list = seq;
				} else{
					freeQSeqList( child_list );
					return NULL;
				}
				if( !dbi_result_next_row( result ))
					break;
			}
			if( count < 2 ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"%s query # %d has only one child query", type_str, parent_id ));
				state->error = 1;
				freeQSeqList( child_list );
				return NULL;
			}
		} else {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"%s query # %d has no child queries within it", type_str, parent_id ));
			state->error = 1;
			if( ! oilsIsDBConnected( state->dbhandle ))
				state->panic = 1;
			return NULL;
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.query_sequence table: # %d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		return NULL;
	}

	return child_list;
}

/**
	@brief Construct a QSeq.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.query_sequence.
	@return Pointer to a newly constructed QSeq, if successful, or NULL if not.

	The calling code is responsible for freeing QSeqs by calling freeQSeqList().
*/
static QSeq* constructQSeq( BuildSQLState* state, dbi_result result ) {
	int id = dbi_result_get_int_idx( result, 1 );
	int parent_query_id = dbi_result_get_int_idx( result, 2 );
	int seq_no = dbi_result_get_int_idx( result, 3 );
	int child_query_id = dbi_result_get_int_idx( result, 4 );

	StoredQ* child_query = getStoredQuery( state, child_query_id );
	if( !child_query ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to load child query # %d for parent query %d",
			child_query_id, parent_query_id ));
		state->error = 1;
		return NULL;
	}

	// Allocate a QSeq; from the free list if possible, from the heap if necessary
	QSeq* seq = NULL;
	if( free_qseq_list ) {
		seq = free_qseq_list;
		free_qseq_list = free_qseq_list->next;
	} else
		seq = safe_malloc( sizeof( QSeq ));

	seq->next            = NULL;
	seq->id              = id;
	seq->parent_query_id = parent_query_id;
	seq->seq_no          = seq_no;
	seq->child_query     = child_query;

	return seq;
}

/**
	@brief Free a list of QSeq's.
	@param seq Pointer to the first in a linked list of QSeq's to be freed.

	Each QSeq goes onto a free list for potential reuse.
*/
static void freeQSeqList( QSeq* seq ) {
	if( !seq )
		return;

	QSeq* first = seq;
	while( seq ) {
		storedQFree( seq->child_query );
		seq->child_query = NULL;

		if( seq->next )
			seq = seq->next;
		else {
			seq->next = free_qseq_list;
			seq = NULL;
		}
	}

	free_qseq_list = first;
}

/**
	@brief Deallocate the memory owned by a StoredQ.
	@param sq Pointer to the StoredQ to be deallocated.
*/
void storedQFree( StoredQ* sq ) {
	if( sq ) {
		fromRelationFree( sq->from_clause );
		sq->from_clause = NULL;
		selectListFree( sq->select_list );
		sq->select_list = NULL;
		expressionFree( sq->where_clause );
		sq->where_clause = NULL;
		if( sq->child_list ) {
			freeQSeqList( sq->child_list );
			sq->child_list = NULL;
		}
		if( sq->order_by_list ) {
			orderItemListFree( sq->order_by_list );
			sq->order_by_list = NULL;
		}
		if( sq->having_clause ) {
			expressionFree( sq->having_clause );
			sq->having_clause = NULL;
		}
		if( sq->limit_count ) {
			expressionFree( sq->limit_count );
			sq->limit_count = NULL;
		}
		if( sq->offset_count ) {
			expressionFree( sq->offset_count );
			sq->offset_count = NULL;
		}

		// Stick the empty husk on the free list for potential reuse
		sq->next = free_storedq_list;
		free_storedq_list = sq;
	}
}

/**
	@brief Given an id from query.from_relation, load a FromRelation.
	@param state Pointer the the query-building context.
	@param id Id of the FromRelation.
	@return Pointer to a newly-created FromRelation if successful, or NULL if not.

	The calling code is responsible for freeing the new FromRelation by calling
	fromRelationFree().
*/
static FromRelation* getFromRelation( BuildSQLState* state, int id ) {
	FromRelation* fr = NULL;
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, type, table_name, class_name, subquery, function_call, "
		"table_alias, parent_relation, seq_no, join_type, on_clause "
		"FROM query.from_relation WHERE id = %d;", id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			fr = constructFromRelation( state, result );
			if( fr ) {
				PRINT( "Got a from_relation row\n" );
				PRINT( "\tid: %d\n", fr->id );
				PRINT( "\ttype: %d\n", (int) fr->type );
				PRINT( "\ttable_name: %s\n", fr->table_name ? fr->table_name : "(none)" );
				PRINT( "\tclass_name: %s\n", fr->class_name ? fr->class_name : "(none)" );
				PRINT( "\tsubquery_id: %d\n", fr->subquery_id );
				PRINT( "\tfunction_call_id: %d\n", fr->function_call_id );
				PRINT( "\ttable_alias: %s\n", fr->table_alias ? fr->table_alias : "(none)" );
				PRINT( "\tparent_relation_id: %d\n", fr->parent_relation_id );
				PRINT( "\tseq_no: %d\n", fr->seq_no );
				PRINT( "\tjoin_type = %d\n", fr->join_type );
				// Check the stack to see if the current from clause is nested inside itself.
				// If it is, then abort in order to avoid infinite recursion.  If it isn't,
				// then add it to the stack.  (Make sure to pop it off the stack before
				// returning.)
				const char* effective_alias = fr->table_alias;
				if( !effective_alias )
					effective_alias = fr->class_name;
				const IdNode* node = searchIdStack( state->from_stack, id, effective_alias );
				if( node ) {
					if( node->id == id )
						osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
							"Infinite recursion detected; from clause # %d is nested "
							"within itself", id ));
					else
						osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
							"Conflicting nested table aliases \"%s\" in from clause # %d",
							effective_alias, node->id ));
					state->error = 1;
					return NULL;
				} else
					push_id( &state->from_stack, id, effective_alias );
			} else
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to build a FromRelation for id = %d", id ));
		} else {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"FROM relation not found for id = %d", id ));
			state->error = 1;
		}
		dbi_result_free( result );
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.from_relation table: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	if( fr )
		pop_id( &state->from_stack );

	return fr;
}

/**
	@brief Construct a FromRelation.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.from_relation.
	@return Pointer to a newly constructed FromRelation, if successful, or NULL if not.

	The calling code is responsible for freeing FromRelations by calling joinListFree().
*/
static FromRelation* constructFromRelation( BuildSQLState* state, dbi_result result ) {
	// Get the column values from the result
	int id                  = dbi_result_get_int_idx( result, 1 );
	const char* type_str    = dbi_result_get_string_idx( result, 2 );

	FromRelationType type;
	if( !strcmp( type_str, "RELATION" ))
		type = FRT_RELATION;
	else if( !strcmp( type_str, "SUBQUERY" ))
		type = FRT_SUBQUERY;
	else if( !strcmp( type_str, "FUNCTION" ))
		type = FRT_FUNCTION;
	else
		type = FRT_RELATION;     // shouldn't happen due to database constraint

	const char* table_name   = dbi_result_get_string_idx( result, 3 );
	const char* class_name   = dbi_result_get_string_idx( result, 4 );

	int subquery_id;
	if( dbi_result_field_is_null_idx( result, 5 ) )
		subquery_id           = -1;
	else
		subquery_id           = dbi_result_get_int_idx( result, 5 );

	int function_call_id;
	if( dbi_result_field_is_null_idx( result, 6 ) )
		function_call_id      = -1;
	else
		function_call_id      = dbi_result_get_int_idx( result, 6 );

	Expression* function_call = NULL;
	const char* table_alias   = dbi_result_get_string_idx( result, 7 );

	int parent_relation_id;
	if( dbi_result_field_is_null_idx( result, 8 ) )
		parent_relation_id    = -1;
	else
		parent_relation_id    = dbi_result_get_int_idx( result, 8 );

	int seq_no                = dbi_result_get_int_idx( result, 9 );

	JoinType join_type;
	const char* join_type_str = dbi_result_get_string_idx( result, 10 );
	if( !join_type_str )
		join_type = JT_NONE;
	else if( !strcmp( join_type_str, "INNER" ) )
		join_type = JT_INNER;
	else if( !strcmp( join_type_str, "LEFT" ) )
		join_type = JT_LEFT;
	else if( !strcmp( join_type_str, "RIGHT" ) )
		join_type = JT_RIGHT;
	else if( !strcmp( join_type_str, "FULL" ) )
		join_type = JT_FULL;
	else
		join_type = JT_NONE;     // shouldn't happen due to database constraint

	int on_clause_id;
	if( dbi_result_field_is_null_idx( result, 11 ) )
		on_clause_id   = -1;
	else
		on_clause_id   = dbi_result_get_int_idx( result, 11 );

	StoredQ* subquery = NULL;

	switch ( type ) {
		case FRT_RELATION :
			if( table_name && ! is_identifier( table_name )) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Table name \"%s\" is not a valid identifier for FROM relation # %d",
	 				table_name, id ));
				state->error = 1;
				return NULL;
			}
			break;
		case FRT_SUBQUERY :
			if( -1 == subquery_id ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Internal error: no subquery specified for FROM relation # %d", id ));
				state->error = 1;
				return NULL;
			}
			if( ! table_alias ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Subquery needs alias in FROM relation # %d", id ));
				state->error = 1;
				return NULL;
			}
			subquery = getStoredQuery( state, subquery_id );
			if( ! subquery ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to load subquery for FROM relation # %d", id ));
				state->error = 1;
				return NULL;
			}
			break;
		case FRT_FUNCTION :
			if( -1 == function_call_id ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"FROM clause # %d purports to reference a function; not identified", id ));
				state->error = 1;
				return NULL;
			}

			function_call = getExpression( state, function_call_id );
			if( !function_call ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to build function call # %d in FROM relation # %d",
					function_call_id, id ));
				state->error = 1;
				return NULL;
			} else if( function_call->type != EXP_FUNCTION ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"In FROM relation # %d: supposed function call expression # %d "
					"is not a function call", id, function_call_id ));
				state->error = 1;
				return NULL;
			}
	}

	FromRelation* join_list = getJoinList( state, id );
	if( state->error ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to load join list for FROM relation # %d", id ));
		return NULL;
	}

	Expression* on_clause = NULL;
	if( on_clause_id != -1 ) {
		on_clause = getExpression( state, on_clause_id );
		if( !on_clause ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to load ON condition for FROM relation # %d", id ));
			joinListFree( join_list );
			state->error = 1;
			return NULL;
		}
		else
			PRINT( "\tGot an ON condition\n" );
	}

	// Allocate a FromRelation: from the free list if possible, from the heap if necessary

	FromRelation* fr;
	if( free_from_relation_list ) {
		fr = free_from_relation_list;
		free_from_relation_list = free_from_relation_list->next;
	} else
		fr = safe_malloc( sizeof( FromRelation ) );

	// Populate the FromRelation

	fr->next = NULL;
	fr->id = id;
	fr->type = type;
	fr->table_name = table_name ? strdup( table_name ) : NULL;
	fr->class_name = class_name ? strdup( class_name ) : NULL;
	fr->subquery_id = subquery_id;
	fr->subquery = subquery;
	fr->function_call_id = function_call_id;
	fr->function_call = function_call;
	fr->table_alias = table_alias ? strdup( table_alias ) : NULL;
	fr->parent_relation_id = parent_relation_id;
	fr->seq_no = seq_no;
	fr->join_type = join_type;
	fr->on_clause = on_clause;
	fr->join_list = join_list;

	return fr;
}

/**
	@brief Build a list of joined relations.
	@param state Pointer to the query-building context.
	@param id ID of the parent relation.
	@return A pointer to the first in a linked list of FromRelations, if there are any; or
		NULL if there aren't any, or in case of an error.

	Look for relations joined directly to the parent relation, and make a list of them.
*/
static FromRelation* getJoinList( BuildSQLState* state, int id ) {
	FromRelation* join_list = NULL;

	// The ORDER BY is in descending order so that we can build the list by adding to
	// the head, and it will wind up in the right order.
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, type, table_name, class_name, subquery, function_call, "
		"table_alias, parent_relation, seq_no, join_type, on_clause "
		"FROM query.from_relation WHERE parent_relation = %d ORDER BY seq_no DESC", id );

	if( result ) {
		if( dbi_result_first_row( result ) ) {
			while( 1 ) {
				FromRelation* relation = constructFromRelation( state, result );
				if( relation ) {
					PRINT( "Found a joined relation\n" );
					PRINT( "\tjoin_type: %d\n", relation->join_type );
					PRINT( "\ttable_name: %s\n", relation->table_name );
					relation->next = join_list;
					join_list = relation;
				} else {
					osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to build join list for from relation id #%d", id ));
					joinListFree( join_list );
					join_list = NULL;
					break;
				}
				if( !dbi_result_next_row( result ) )
					break;
			};
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.from_relation table for join list: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	return join_list;
}

/**
	@brief Free a list of FromRelations.
	@param join_list Pointer to the first FromRelation in the list.
*/
static void joinListFree( FromRelation* join_list ) {
	while( join_list ) {
		FromRelation* temp = join_list->next;
		fromRelationFree( join_list );
		join_list = temp;
	}
}

/**
	@brief Deallocate a FromRelation.
	@param fr Pointer to the FromRelation to be freed.

	Free the strings that the FromRelation owns.  The FromRelation itself goes onto a
	free list for potential reuse.
*/
static void fromRelationFree( FromRelation* fr ) {
	if( fr ) {
		free( fr->table_name );
		fr->table_name = NULL;
		free( fr->class_name );
		fr->class_name = NULL;
		if( fr->subquery ) {
			storedQFree( fr->subquery );
			fr->subquery = NULL;
		}
		if( fr->function_call ) {
			expressionFree( fr->function_call );
			fr->function_call = NULL;
		}
		free( fr->table_alias );
		fr->table_alias = NULL;
		if( fr->on_clause ) {
			expressionFree( fr->on_clause );
			fr->on_clause = NULL;
		}
		joinListFree( fr->join_list );
		fr->join_list = NULL;

		fr->next = free_from_relation_list;
		free_from_relation_list = fr;
	}
}

/**
	@brief Build a SELECT list for a given query ID.
	@param state Pointer to the query-building context.
	@param query_id ID of the query to which the SELECT list belongs.
*/
static SelectItem* getSelectList( BuildSQLState* state, int query_id ) {
	SelectItem* select_list = NULL;

	// The ORDER BY is in descending order so that we can build the list by adding to
	// the head, and it will wind up in the right order.
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, stored_query, seq_no, expression, column_alias, grouped_by "
		"FROM query.select_item WHERE stored_query = %d ORDER BY seq_no DESC", query_id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			while( 1 ) {
				SelectItem* item = constructSelectItem( state, result );
				if( item ) {
					PRINT( "Found a SELECT item\n" );
					PRINT( "\tid: %d\n", item->id );
					PRINT( "\tstored_query_id: %d\n", item->stored_query_id );
					PRINT( "\tseq_no: %d\n", item->seq_no );
					PRINT( "\tcolumn_alias: %s\n",
							item->column_alias ? item->column_alias : "(none)" );
					PRINT( "\tgrouped_by: %d\n", item->grouped_by );

					item->next = select_list;
					select_list = item;
				} else {
					osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to build select list for query id #%d", query_id ));
					selectListFree( select_list );
					select_list = NULL;
					break;
				}
				if( !dbi_result_next_row( result ) )
					break;
			};
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"No SELECT list found for query # %d", query_id ));
			state->error = 1;
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.select_list table: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	return select_list;
}

/**
	@brief Construct a SelectItem.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.select_item.
	@return Pointer to a newly constructed SelectItem, if successful, or NULL if not.

	The calling code is responsible for freeing the SelectItems by calling selectListFree().
*/
static SelectItem* constructSelectItem( BuildSQLState* state, dbi_result result ) {

	// Get the column values
	int id                   = dbi_result_get_int_idx( result, 1 );
	int stored_query_id      = dbi_result_get_int_idx( result, 2 );
	int seq_no               = dbi_result_get_int_idx( result, 3 );
	int expression_id        = dbi_result_get_int_idx( result, 4 );
	const char* column_alias = dbi_result_get_string_idx( result, 5 );
	int grouped_by           = oils_result_get_bool_idx( result, 6 );

	// Construct an Expression
	Expression* expression = getExpression( state, expression_id );
	if( !expression ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to fetch expression for id = %d", expression_id ));
		state->error = 1;
		return NULL;
	};

	// Allocate a SelectItem: from the free list if possible, from the heap if necessary

	SelectItem* sel;
	if( free_select_item_list ) {
		sel = free_select_item_list;
		free_select_item_list = free_select_item_list->next;
	} else
		sel = safe_malloc( sizeof( SelectItem ) );

	sel->next            = NULL;
	sel->id              = id;
	sel->stored_query_id = stored_query_id;
	sel->seq_no          = seq_no;
	sel->expression      = expression;
	sel->column_alias    = column_alias ? strdup( column_alias ) : NULL;
	sel->grouped_by      = grouped_by;

	return sel;
}

/**
	@brief Free a list of SelectItems.
	@param sel Pointer to the first item in the list to be freed.

	Free the column alias and expression owned by each item.  Put the entire list into a free
	list of SelectItems.
*/
static void selectListFree( SelectItem* sel ) {
	if( !sel )
		return;    // Nothing to free

	SelectItem* first = sel;
	while( 1 ) {
		free( sel->column_alias );
		sel->column_alias = NULL;
		expressionFree( sel->expression );
		sel->expression = NULL;

		if( NULL == sel->next ) {
			sel->next = free_select_item_list;
			break;
		} else
			sel = sel->next;
	};

	// Transfer the entire list to the free list
	free_select_item_list = first;
}

/**
	@brief Given the name of a bind variable, build a corresponding BindVar.
	@param state Pointer to the query-building context.
	@param name Name of the bind variable.
	@return Pointer to the newly-built BindVar.

	Since the same bind variable may appear multiple times, we load it only once for the
	entire query, and reference the one copy wherever needed.
*/
static BindVar* getBindVar( BuildSQLState* state, const char* name ) {
	BindVar* bind = NULL;
	if( state->bindvar_list ) {
		bind = osrfHashGet( state->bindvar_list, name );
		if( bind )
			return bind;   // Already loaded it...
	}

	// Load a BindVar from the Database.(after escaping any special characters)
	char* esc_str = strdup( name );
	dbi_conn_quote_string( state->dbhandle, &esc_str );
	if( !esc_str ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to format bind variable name \"%s\"", name ));
		state->error = 1;
		return NULL;
	}
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT name, type, description, default_value, label "
		"FROM query.bind_variable WHERE name = %s;", esc_str );
	free( esc_str );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			bind = constructBindVar( state, result );
			if( bind ) {
				PRINT( "Got a bind variable for %s\n", name );
			} else
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to load bind variable \"%s\"", name ));
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"No bind variable found with name \"%s\"", name ));
			state->error = 1;
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.bind_variable table for \"%s\": #%d %s",
			name, errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	if( bind ) {
		// Add the new bind variable to the list
		if( !state->bindvar_list ) {
			// Don't have a list yet?  Start one.
			state->bindvar_list = osrfNewHash();
			osrfHashSetCallback( state->bindvar_list, bindVarFree );
		}
		osrfHashSet( state->bindvar_list, bind, name );
	} else
		state->error = 1;

	return bind;
}

/**
	@brief Construct a BindVar to represent a bind variable.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.bind_variable.
	@return Pointer to a newly constructed BindVar, if successful, or NULL if not.

	The calling code is responsible for freeing the BindVar by calling bindVarFree().
*/
static BindVar* constructBindVar( BuildSQLState* state, dbi_result result ) {

	const char* name = dbi_result_get_string_idx( result, 1 );

	const char* type_str = dbi_result_get_string_idx( result, 2 );
	BindVarType type;
	if( !strcmp( type_str, "string" ))
		type = BIND_STR;
	else if( !strcmp( type_str, "number" ))
		type = BIND_NUM;
	else if( !strcmp( type_str, "string_list" ))
		type = BIND_STR_LIST;
	else if( !strcmp( type_str, "number_list" ))
		type = BIND_NUM_LIST;
	else {         // Shouldn't happen due to database constraint...
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Internal error: invalid bind variable type \"%s\" for bind variable \"%s\"",
			type_str, name ));
		state->error = 1;
		return NULL;
	}

	const char* description = dbi_result_get_string_idx( result, 3 );

	// The default value is encoded as JSON.  Translate it into a jsonObject.
	const char* default_value_str = dbi_result_get_string_idx( result, 4 );
	jsonObject* default_value = NULL;
	if( default_value_str ) {
		default_value = jsonParse( default_value_str );
		if( !default_value ) {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to parse JSON string for default value of bind variable \"%s\"",
				name ));
			state->error = 1;
			return NULL;
		}
	}

	const char* label = dbi_result_get_string_idx( result, 5 );

	// Allocate a BindVar: from the free list if possible, from the heap if necessary
	BindVar* bind = NULL;
	if( free_bindvar_list ) {
		bind = free_bindvar_list;
		free_bindvar_list = free_bindvar_list->next;
	} else
		bind = safe_malloc( sizeof( BindVar ) );

	bind->next = NULL;
	bind->name = strdup( name );
	bind->label = strdup( label );
	bind->type = type;
	bind->description = strdup( description );
	bind->default_value = default_value;
	bind->actual_value = NULL;

	return bind;
}

/**
	@brief Deallocate a BindVar.
	@param key Pointer to the bind variable name (not used).
	@param p Pointer to the BindVar to be deallocated, cast to a void pointer.

	Free the strings and jsonObjects owned by the BindVar, and put the BindVar itself into a
	free list.

	This function is a callback installed in an osrfHash; hence the peculiar signature.
*/
static void bindVarFree( char* key, void* p ) {
	if( p ) {
		BindVar* bind = p;
		free( bind->name );
		free( bind->label );
		free( bind->description );
		if( bind->default_value ) {
			jsonObjectFree( bind->default_value );
			bind->default_value = NULL;
		}
		if( bind->actual_value ) {
			jsonObjectFree( bind->actual_value );
			bind->actual_value = NULL;
		}

		// Prepend to free list
		bind->next = free_bindvar_list;
		free_bindvar_list = bind;
	}
}

/**
	@brief Given an id for a parent expression, build a list of CaseBranch structs.
	@param Pointer to the query-building context.
	@param id ID of a row in query.case_branch.
	@return Pointer to a newly-created CaseBranch if successful, or NULL if not.
*/
static CaseBranch* getCaseBranchList( BuildSQLState* state, int parent_id ) {
	CaseBranch* branch_list = NULL;
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, condition, result "
		"FROM query.case_branch WHERE parent_expr = %d "
		"ORDER BY seq_no desc;", parent_id );
	if( result ) {
		int condition_found = 0;   // Boolean
		if( dbi_result_first_row( result ) ) {
			// Boolean: true for the first branch we encounter.  That's actually the last
			// branch in the CASE, because we're reading them in reverse order.  The point
			// is to enforce the rule that only the last branch can be an ELSE.
			int first = 1;
			while( 1 ) {
				CaseBranch* branch = constructCaseBranch( state, result );
				if( branch ) {
					PRINT( "Found a case branch\n" );
					branch->next = branch_list;
					branch_list  = branch;
				} else {
					osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to build CASE branch for expression id #%d", parent_id ));
					freeBranchList( branch_list );
					branch_list = NULL;
					break;
				}

				if( branch->condition )
					condition_found = 1;
				else if( !first ) {
					sqlAddMsg( state, "ELSE branch # %d not at end of CASE expression # %d",
						branch->id, parent_id );
					freeBranchList( branch_list );
					branch_list = NULL;
					break;
				}
				first = 0;

				if( !dbi_result_next_row( result ) )
					break;
			};  // end while
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"No branches found for CASE expression %d", parent_id ));
			state->error = 1;
		}

		// Make sure that at least one branch includes a condition
		if( !condition_found ) {
			sqlAddMsg( state, "No conditional branch in CASE expression # %d", parent_id );
			freeBranchList( branch_list );
			branch_list = NULL;
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.case_branch table for parent expression # %d: %s",
			parent_id, errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	return branch_list;
}

static CaseBranch* constructCaseBranch( BuildSQLState* state, dbi_result result ) {
	int id = dbi_result_get_int_idx( result, 1 );

	int condition_id;
	if( dbi_result_field_is_null_idx( result, 2 ))
		condition_id = -1;
	else
		condition_id = dbi_result_get_int_idx( result, 2 );

	Expression* condition = NULL;
	if( condition_id != -1 ) {   // If it's -1, we have an ELSE condition
		condition = getExpression( state, condition_id );
		if( ! condition ) {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to build condition expression for case branch # %d", id ));
			state->error = 1;
			return NULL;
		}
	}

	int result_id = dbi_result_get_int_idx( result, 3 );

	Expression* result_p = NULL;
	if( -1 == result_id ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"No result expression defined for case branch # %d", id ));
		state->error = 1;
		if( condition )
			expressionFree( condition );
		return NULL;
	} else {
		result_p = getExpression( state, result_id );
		if( ! result_p ) {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to build result expression for case branch # %d", id ));
			state->error = 1;
			if( condition )
				expressionFree( condition );
			return NULL;
		}
	}

	// Allocate a CaseBranch: from the free list if possible, from the heap if necessary
	CaseBranch* branch = NULL;
	if( free_branch_list ) {
		branch = free_branch_list;
		free_branch_list = free_branch_list->next;
	} else
		branch = safe_malloc( sizeof( CaseBranch ) );

	// Populate the new CaseBranch
	branch->id = id;
	branch->condition = condition;
	branch->result = result_p;

	return branch;
}

/**
	@brief Free a list of CaseBranches.
	@param branch Pointer to the first in a linked list of CaseBranches to be freed.

	Each CaseBranch goes onto a free list for potential reuse.
*/
static void freeBranchList( CaseBranch* branch ) {
	if( !branch )
		return;

	CaseBranch* first = branch;
	while( branch ) {
		if( branch->condition ) {
			expressionFree( branch->condition );
			branch->condition = NULL;
		}
		expressionFree( branch->result );
		branch->result = NULL;

		if( branch->next )
			branch = branch->next;
		else {
			branch->next = free_branch_list;
			branch = NULL;
		}
	}

	free_branch_list = first;
}

/**
	@brief Given an id for a row in query.datatype, build an Datatype struct.
	@param Pointer to the query-building context.
	@param id ID of a row in query.datatype.
	@return Pointer to a newly-created Datatype if successful, or NULL if not.
*/
static Datatype* getDatatype( BuildSQLState* state, int id ) {
	Datatype* datatype = NULL;
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, datatype_name, is_numeric, is_composite "
		"FROM query.datatype WHERE id = %d", id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			datatype = constructDatatype( state, result );
			if( datatype ) {
				PRINT( "Got a datatype\n" );
				PRINT( "\tid = %d\n", id );
				PRINT( "\tdatatype = %s\n", datatype->datatype_name );
			} else
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to construct a Datatype for id = %d", id ));
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"No datatype found for id = %d", id ));
			state->error = 1;
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.datatype table: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}
	return datatype;
}

/**
	@brief Construct a Datatype.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.datatype.
	@return Pointer to a newly constructed Datatype, if successful, or NULL if not.

	The calling code is responsible for freeing the Datatype by calling datatypeFree().
*/
static Datatype* constructDatatype( BuildSQLState* state, dbi_result result ) {
	int id           = dbi_result_get_int_idx( result, 1 );
	const char* datatype_name = dbi_result_get_string_idx( result, 2 );
	int is_numeric   = oils_result_get_bool_idx( result, 3 );
	int is_composite = oils_result_get_bool_idx( result, 4 );

	if( !datatype_name || !*datatype_name ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"No datatype name provided for CAST expression # %d", id ));
		state->error = 1;
		return NULL;
	}

	// Make sure that the datatype name is composed entirely of certain approved
	// characters.  This check is not an attempt to validate the datatype name, but
	// only to prevent certain types of SQL injection.
	const char* p = datatype_name;
	while( *p ) {
		unsigned char c = *p;
		if( isalnum( c )
			|| isspace( c )
			|| ',' == c
			|| '(' == c
			|| ')' == c
			|| '[' == c
			|| ']' == c
			|| '.' == c
		)
			++p;
		else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Invalid datatype name \"%s\" for datatype # %d; "
				"contains unexpected character \"%c\"", datatype_name, id, (char) c ));
			state->error = 1;
			return NULL;
		}
	}

	// Allocate a Datatype: from the free list if possible, from the heap if necessary
	Datatype* datatype = NULL;
	if( free_datatype_list ) {
		datatype = free_datatype_list;
		free_datatype_list = free_datatype_list->next;
	} else
		datatype = safe_malloc( sizeof( Datatype ) );

	datatype->id            = id;
	datatype->datatype_name = strdup( datatype_name );
	datatype->is_numeric    = is_numeric;
	datatype->is_composite  = is_composite;

	return datatype;
}

/**
	@brief Free a Datatype.
	@param datatype Pointer to the Datatype to be freed.
*/
static void datatypeFree( Datatype* datatype ) {
	if( datatype ) {
		free( datatype->datatype_name );
		free( datatype );
	}
}

/**
	@brief Given an id for a row in query.expression, build an Expression struct.
	@param Pointer to the query-building context.
	@param id ID of a row in query.expression.
	@return Pointer to a newly-created Expression if successful, or NULL if not.
*/
static Expression* getExpression( BuildSQLState* state, int id ) {

	// Check the stack to see if the current expression is nested inside itself.  If it is,
	// then abort in order to avoid infinite recursion.  If it isn't, then add it to the
	// stack.  (Make sure to pop it off the stack before returning.)
	if( searchIdStack( state->expr_stack, id, NULL )) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Infinite recursion detected; expression # %d is nested within itself", id ));
		state->error = 1;
		return NULL;
	} else
		push_id( &state->expr_stack, id, NULL );

	Expression* exp = NULL;
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT exp.id, exp.type, exp.parenthesize, exp.parent_expr, exp.seq_no, "
		"exp.literal, exp.table_alias, exp.column_name, exp.left_operand, exp.operator, "
		"exp.right_operand, exp.subquery, exp.cast_type, exp.negate, exp.bind_variable, "
		"func.function_name "
		"FROM query.expression AS exp LEFT JOIN query.function_sig AS func "
		"ON (exp.function_id = func.id) "
		"WHERE exp.id = %d;", id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			exp = constructExpression( state, result );
			if( exp ) {
				PRINT( "Got an expression\n" );
				PRINT( "\tid = %d\n", exp->id );
				PRINT( "\ttype = %d\n", exp->type );
				PRINT( "\tparenthesize = %d\n", exp->parenthesize );
				PRINT( "\tcolumn_name = %s\n", exp->column_name ? exp->column_name : "(none)" );
			} else
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to construct an Expression for id = %d", id ));
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"No expression found for id = %d", id ));
			state->error = 1;
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.expression table: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	pop_id( &state->expr_stack );
	return exp;
}

/**
	@brief Construct an Expression.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.expression.
	@return Pointer to a newly constructed Expression, if successful, or NULL if not.

	The calling code is responsible for freeing the Expression by calling expressionFree().
*/
static Expression* constructExpression( BuildSQLState* state, dbi_result result ) {

	int id = dbi_result_get_int_idx( result, 1 );
	const char* type_str = dbi_result_get_string_idx( result, 2 );

	ExprType type;
	if( !strcmp( type_str, "xbet" ))
		type = EXP_BETWEEN;
	else if( !strcmp( type_str, "xbind" ))
		type = EXP_BIND;
	else if( !strcmp( type_str, "xbool" ))
		type = EXP_BOOL;
	else if( !strcmp( type_str, "xcase" ))
		type = EXP_CASE;
	else if( !strcmp( type_str, "xcast" ))
		type = EXP_CAST;
	else if( !strcmp( type_str, "xcol" ))
		type = EXP_COLUMN;
	else if( !strcmp( type_str, "xex" ))
		type = EXP_EXIST;
	else if( !strcmp( type_str, "xfunc" ))
		type = EXP_FUNCTION;
	else if( !strcmp( type_str, "xin" ))
		type = EXP_IN;
	else if( !strcmp( type_str, "xisnull" ))
		type = EXP_ISNULL;
	else if( !strcmp( type_str, "xnull" ))
		type = EXP_NULL;
	else if( !strcmp( type_str, "xnum" ))
		type = EXP_NUMBER;
	else if( !strcmp( type_str, "xop" ))
		type = EXP_OPERATOR;
	else if( !strcmp( type_str, "xser" ))
		type = EXP_SERIES;
	else if( !strcmp( type_str, "xstr" ))
		type = EXP_STRING;
	else if( !strcmp( type_str, "xsubq" ))
		type = EXP_SUBQUERY;
	else
		type = EXP_NULL;     // shouldn't happen due to database constraint

	int parenthesize = oils_result_get_bool_idx( result, 3 );

	int parent_expr_id;
	if( dbi_result_field_is_null_idx( result, 4 ))
		parent_expr_id = -1;
	else
		parent_expr_id = dbi_result_get_int_idx( result, 4 );

	int seq_no = dbi_result_get_int_idx( result, 5 );
	const char* literal = dbi_result_get_string_idx( result, 6 );
	const char* table_alias = dbi_result_get_string_idx( result, 7 );
	const char* column_name = dbi_result_get_string_idx( result, 8 );

	int left_operand_id;
	if( dbi_result_field_is_null_idx( result, 9 ))
		left_operand_id = -1;
	else
		left_operand_id = dbi_result_get_int_idx( result, 9 );

	const char* operator = dbi_result_get_string_idx( result, 10 );

	int right_operand_id;
	if( dbi_result_field_is_null_idx( result, 11 ))
		right_operand_id = -1;
	else
		right_operand_id = dbi_result_get_int_idx( result, 11 );

	int subquery_id;
	if( dbi_result_field_is_null_idx( result, 12 ))
		subquery_id = -1;
	else
		subquery_id = dbi_result_get_int_idx( result, 12 );

	int cast_type_id;
	if( dbi_result_field_is_null_idx( result, 13 ))
		cast_type_id = -1;
	else
		cast_type_id = dbi_result_get_int_idx( result, 13 );

	int negate = oils_result_get_bool_idx( result, 14 );
	const char* bind_variable = dbi_result_get_string_idx( result, 15 );
	const char* function_name = dbi_result_get_string_idx( result, 16 );

	Expression* left_operand = NULL;
	Expression* right_operand = NULL;
	StoredQ* subquery = NULL;
	Datatype* cast_type = NULL;
	BindVar* bind = NULL;
	CaseBranch* branch_list = NULL;
	Expression* subexp_list = NULL;

	if( EXP_BETWEEN == type ) {
		// Get the left operand
		if( -1 == left_operand_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"No left operand defined for BETWEEN expression # %d", id ));
			state->error = 1;
			return NULL;
		} else {
			left_operand = getExpression( state, left_operand_id );
			if( !left_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get left operand in BETWEEN expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

		// Get the end points of the BETWEEN range
		subexp_list = getExpressionList( state, id );
		if( state->error ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to get subexpressions for BETWEEN expression # %d", id ));
			expressionFree( left_operand );
			return NULL;
		} else if( !subexp_list ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"BETWEEN range is empty in expression # %d", id ));
			state->error = 1;
			expressionFree( left_operand );
			return NULL;
		} else if( !subexp_list->next ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"BETWEEN range has only one end point in expression # %d", id ));
			state->error = 1;
			expressionListFree( subexp_list );
			expressionFree( left_operand );
			return NULL;
		} else if( subexp_list->next->next ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"BETWEEN range has more than two subexpressions in expression # %d", id ));
			state->error = 1;
			expressionListFree( subexp_list );
			expressionFree( left_operand );
			return NULL;
		}

	} else if( EXP_BIND == type ) {
		if( bind_variable ) {
			// To do: Build a BindVar
			bind = getBindVar( state, bind_variable );
			if( ! bind ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to load bind variable \"%s\" for expression # %d",
		bind_variable, id ));
				state->error = 1;
				return NULL;
			}
			PRINT( "\tBind variable is \"%s\"\n", bind_variable );
		} else {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"No variable specified for bind variable expression # %d",
	   bind_variable, id ));
			state->error = 1;
			return NULL;
		}
		if( right_operand_id != -1 ) {
			right_operand = getExpression( state, right_operand_id );
			if( !right_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get right operand in expression # %d", id ));
				state->error = 1;
				expressionFree( left_operand );
				return NULL;
			}
		}

	} else if( EXP_CASE == type ) {
		// Get the left operand
		if( -1 == left_operand_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"No left operand defined for CASE expression # %d", id ));
			state->error = 1;
			return NULL;
		} else {
			left_operand = getExpression( state, left_operand_id );
			if( !left_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get left operand in CASE expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

		branch_list = getCaseBranchList( state, id );
		if( ! branch_list ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to build branches for CASE expression # %d", id ));
			state->error = 1;
			return NULL;
		}

	} else if( EXP_CAST == type ) {
		// Get the left operand
		if( -1 == left_operand_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"No left operand defined for CAST expression # %d", id ));
			state->error = 1;
			return NULL;
		} else {
			left_operand = getExpression( state, left_operand_id );
			if( !left_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get left operand for CAST expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

		if( -1 == cast_type_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"No datatype specified for CAST expression # %d", id ));
			state->error = 1;
			return NULL;
		} else {
			cast_type = getDatatype( state, cast_type_id );
			if( !cast_type ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get datatype for CAST expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

	} else if( EXP_COLUMN == type ) {
		if( column_name && !is_identifier( column_name )) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Column name \"%s\" is invalid identifier for expression # %d",
				column_name, id ));
			state->error = 1;
			return NULL;
		}

	} else if( EXP_EXIST == type ) {
		if( -1 == subquery_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: No subquery found for EXIST expression # %d", id ));
			state->error = 1;
			return NULL;
		} else {
			subquery = getStoredQuery( state, subquery_id );
			if( !subquery ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to load subquery for EXIST expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

	} else if( EXP_FUNCTION == type ) {
		if( !function_name ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Function call expression # %d provides no function name", id ));
			state->error = 1;
			return NULL;
		} else if( !is_identifier( function_name )) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Function call expression # %d contains an invalid function name \"%s\"",
				id, function_name ));
			state->error = 1;
			return NULL;
		} else {
			subexp_list = getExpressionList( state, id );
			if( state->error ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get parameter list for function expression # %d", id ));
				return NULL;
			}
		}

	} else if( EXP_IN == type ) {
		if( -1 == left_operand_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"IN condition has no left operand in expression # %d", id ));
			state->error = 1;
			return NULL;
		} else {
			left_operand = getExpression( state, left_operand_id );
			if( !left_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get left operand for IN condition in expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

		if( -1 == subquery_id ) {
			// Load an IN list of subexpressions
			subexp_list = getExpressionList( state, id );
			if( state->error ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get subexpressions for IN list" ));
				return NULL;
			} else if( !subexp_list ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"IN list is empty in expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		} else {
			// Load a subquery
			subquery = getStoredQuery( state, subquery_id );
			if( !subquery ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to load subquery for IN expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

	} else if( EXP_ISNULL == type ) {
		if( -1 == left_operand_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Expression # %d IS NULL has no left operand", id ));
			state->error = 1;
			return NULL;
		}

		if( left_operand_id != -1 ) {
			left_operand = getExpression( state, left_operand_id );
			if( !left_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get left operand in expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

	} else if( EXP_NUMBER == type ) {
		if( !literal ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Numeric expression # %d provides no numeric value", id ));
			state->error = 1;
			return NULL;
		} else if( !jsonIsNumeric( literal )) {
			// Purported number is not numeric.  We use JSON rules here to determine what
			// a valid number is, just because we already have a function lying around that
			// can do that validation.  PostgreSQL probably doesn't use the same exact rules.
			// If that's a problem, we can write a separate validation routine to follow
			// PostgreSQL's rules, once we figure out what those rules are.
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Numeric expression # %d is not a valid number: \"%s\"", id, literal ));
			state->error = 1;
			return NULL;
		}

	} else if( EXP_OPERATOR == type ) {
		// Make sure we have a plausible operator
		if( !operator ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Operator expression # %d has no operator", id ));
			state->error = 1;
			return NULL;
		} else if( !is_good_operator( operator )) {
			// The specified operator contains one or more characters that aren't allowed
			// in an operator.  This isn't a true validation; it's just a protective
			// measure to prevent certain kinds of sql injection.
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Operator expression # %d contains invalid operator \"%s\"", id, operator ));
			state->error = 1;
			return NULL;
		}

		// Load left and/or right operands
		if( -1 == left_operand_id && -1 == right_operand_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Expression # %d is an operator with no operands", id ));
			state->error = 1;
			return NULL;
		}

		if( left_operand_id != -1 ) {
			left_operand = getExpression( state, left_operand_id );
			if( !left_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get left operand in expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

		if( right_operand_id != -1 ) {
			right_operand = getExpression( state, right_operand_id );
			if( !right_operand ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to get right operand in expression # %d", id ));
				state->error = 1;
				return NULL;
			}
		}

	} else if( EXP_SERIES == type ) {
		subexp_list = getExpressionList( state, id );
		if( state->error ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Unable to get subexpressions for expression series using operator \"%s\"",
					operator ? operator : "," ));
			return NULL;
		} else if( !subexp_list ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Series expression is empty in expression # %d", id ));
			state->error = 1;
			return NULL;
		} else if( operator && !is_good_operator( operator )) {
			// The specified operator contains one or more characters that aren't allowed
			// in an operator.  This isn't a true validation; it's just a protective
			// measure to prevent certain kinds of sql injection.
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Series expression # %d contains invalid operator \"%s\"", id, operator ));
			state->error = 1;
			return NULL;
		}

	} else if( EXP_STRING == type ) {
		if( !literal ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"String expression # %d provides no string value", id ));
			state->error = 1;
			return NULL;
		}

	} else if( EXP_SUBQUERY == type ) {
		if( -1 == subquery_id ) {
			osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
				"Subquery expression # %d has no query id", id ));
			state->error = 1;
			return NULL;
		} else {
			// Load a subquery, if there is one
			subquery = getStoredQuery( state, subquery_id );
			if( !subquery ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Unable to load subquery for expression # %d", id ));
				state->error = 1;
				return NULL;
			}
			if( subquery->select_list && subquery->select_list->next ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Subquery # %d as expression returns more than one column", subquery_id ));
				state->error = 1;
				return NULL;
			}
			PRINT( "\tExpression is subquery %d\n", subquery_id );
		}
	}

	// Allocate an Expression: from the free list if possible, from the heap if necessary
	Expression* exp = NULL;
	if( free_expression_list ) {
		exp = free_expression_list;
		free_expression_list = free_expression_list->next;
	} else
		exp = safe_malloc( sizeof( Expression ) );

	// Populate the Expression
	exp->next = NULL;
	exp->id = id;
	exp->type = type;
	exp->parenthesize = parenthesize;
	exp->parent_expr_id = parent_expr_id;
	exp->seq_no = seq_no;
	exp->literal = literal ? strdup( literal ) : NULL;
	exp->table_alias = table_alias ? strdup( table_alias ) : NULL;
	exp->column_name = column_name ? strdup( column_name ) : NULL;
	exp->left_operand = left_operand;
	exp->op = operator ? strdup( operator ) : NULL;
	exp->right_operand = right_operand;
	exp->subquery_id = subquery_id;
	exp->subquery = subquery;
	exp->cast_type = cast_type;
	exp->negate = negate;
	exp->bind = bind;
	exp->branch_list = branch_list;
	exp->subexp_list = subexp_list;
	exp->function_name = function_name ? strdup( function_name ) : NULL;

	return exp;
}

/**
	@brief Free all the Expressions in a linked list of Expressions.
	@param exp Pointer to the first Expression in the list.
*/
static void expressionListFree( Expression* exp ) {
	while( exp ) {
		Expression* next = exp->next;
		expressionFree( exp );
		exp = next;
	}
}

/**
	@brief Deallocate an Expression.
	@param exp Pointer to the Expression to be deallocated.

	Free the strings owned by the Expression.  Put the Expression itself, and any
	subexpressions that it owns, into a free list.
*/
static void expressionFree( Expression* exp ) {
	if( exp ) {
		free( exp->literal );
		exp->literal = NULL;
		free( exp->table_alias );
		exp->table_alias = NULL;
		free( exp->column_name );
		exp->column_name = NULL;
		if( exp->left_operand ) {
			expressionFree( exp->left_operand );
			exp->left_operand = NULL;
		}
		if( exp->op ) {
			free( exp->op );
			exp->op = NULL;
		}
		if( exp->right_operand ) {
			expressionFree( exp->right_operand );
			exp->right_operand = NULL;
		}
		if( exp->subquery ) {
			storedQFree( exp->subquery );
			exp->subquery = NULL;
		}
		if( exp->cast_type ) {
			datatypeFree( exp->cast_type );
			exp->cast_type = NULL;
		}

		// We don't free the bind member here because the Expression doesn't own it;
		// the bindvar_list hash owns it, so that multiple Expressions can reference it.

		if( exp->subexp_list ) {
			// Free the linked list of subexpressions
			expressionListFree( exp->subexp_list );
			exp->subexp_list = NULL;
		}

		if( exp->branch_list ) {
			freeBranchList( exp->branch_list );
			exp->branch_list = NULL;
		}

		if( exp->function_name ) {
			free( exp->function_name );
			exp->function_name = NULL;
		}

		// Prepend to the free list
		exp->next = free_expression_list;
		free_expression_list = exp;
	}
}

/**
	@brief Build a list of subexpressions.
	@param state Pointer to the query-building context.
	@param id ID of the parent Expression.
	@return A pointer to the first in a linked list of Expressions, if there are any; or
		NULL if there aren't any, or in case of an error.
*/
static Expression* getExpressionList( BuildSQLState* state, int id ) {
	Expression* exp_list = NULL;

	// The ORDER BY is in descending order so that we can build the list by adding to
	// the head, and it will wind up in the right order.
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT exp.id, exp.type, exp.parenthesize, exp.parent_expr, exp.seq_no, "
		"exp.literal, exp.table_alias, exp.column_name, exp.left_operand, exp.operator, "
		"exp.right_operand, exp.subquery, exp.cast_type, exp.negate, exp.bind_variable, "
		"func.function_name "
		"FROM query.expression AS exp LEFT JOIN query.function_sig AS func "
		"ON (exp.function_id = func.id) "
		"WHERE exp.parent_expr = %d "
		"ORDER BY exp.seq_no desc;", id );

	if( result ) {
		if( dbi_result_first_row( result ) ) {
			while( 1 ) {
				Expression* exp = constructExpression( state, result );
				if( exp ) {
					PRINT( "Found a subexpression\n" );
					exp->next = exp_list;
					exp_list  = exp;
				} else {
					osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to build subexpression list for expression id #%d", id ));
					expressionListFree( exp_list );
					exp_list = NULL;
					break;
				}
				if( !dbi_result_next_row( result ) )
					break;
			};
		}
	} else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.expression table for expression list: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	return exp_list;
}

/**
	@brief Build a list of ORDER BY items as a linked list of OrderItems.
	@param state Pointer to the query-building context.
	@param query_id ID for the query to which the ORDER BY belongs.
	@return Pointer to the first node in a linked list of OrderItems.

	The calling code is responsible for freeing the list by calling orderItemListFree().
*/
static OrderItem* getOrderByList( BuildSQLState* state, int query_id ) {
	OrderItem* ord_list = NULL;

	// The ORDER BY is in descending order so that we can build the list by adding to
	// the head, and it will wind up in the right order.
	dbi_result result = dbi_conn_queryf( state->dbhandle,
		"SELECT id, stored_query, seq_no, expression "
		"FROM query.order_by_item WHERE stored_query = %d ORDER BY seq_no DESC", query_id );
	if( result ) {
		if( dbi_result_first_row( result ) ) {
			while( 1 ) {
				OrderItem* item = constructOrderItem( state, result );
				if( item ) {
					PRINT( "Found an ORDER BY item\n" );

					item->next = ord_list;
					ord_list = item;
				} else {
					osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to build ORDER BY item for query id #%d", query_id ));
					orderItemListFree( ord_list );
					ord_list = NULL;
					break;
				}
				if( !dbi_result_next_row( result ) )
					break;
			};
		}
	}  else {
		const char* msg;
		int errnum = dbi_conn_error( state->dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to query query.order_by_list table: #%d %s",
			errnum, msg ? msg : "No description available" ));
		state->error = 1;
		if( ! oilsIsDBConnected( state->dbhandle ))
			state->panic = 1;
	}

	return ord_list;
}

/**
	@brief Construct an OrderItem.
	@param Pointer to the query-building context.
	@param result Database cursor positioned at a row in query.order_by_item.
	@return Pointer to a newly constructed OrderItem, if successful, or NULL if not.

	The calling code is responsible for freeing the OrderItems by calling orderItemListFree().
*/
static OrderItem* constructOrderItem( BuildSQLState* state, dbi_result result ) {
	int id                   = dbi_result_get_int_idx( result, 1 );
	int stored_query_id      = dbi_result_get_int_idx( result, 2 );
	int seq_no               = dbi_result_get_int_idx( result, 3 );
	int expression_id        = dbi_result_get_int_idx( result, 4 );
	// Allocate a SelectItem: from the free list if possible, from the heap if necessary

	// Construct an Expression
	Expression* expression = getExpression( state, expression_id );
	if( !expression ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to fetch ORDER BY expression for id = %d", expression_id ));
		state->error = 1;
		return NULL;
	};

	// Allocate an OrderItem; from the free list if possible, or from the heap if necessary.
	OrderItem* ord;
	if( free_order_item_list ) {
		ord = free_order_item_list;
		free_order_item_list = free_order_item_list->next;
	} else
		ord = safe_malloc( sizeof( OrderItem ));

	ord->next            = NULL;
	ord->id              = id;
	ord->stored_query_id = stored_query_id;
	ord->seq_no          = seq_no;
	ord->expression      = expression;

	return ord;
}

/**
	@brief Deallocate a linked list of OrderItems.
	@param exp Pointer to the first OrderItem in the list to be deallocated.

	Deallocate the memory owned by the OrderItems.  Put the items themselves into a free list.
*/
static void orderItemListFree( OrderItem* ord ) {
	if( !ord )
		return;    // Nothing to free

	OrderItem* first = ord;
	while( 1 ) {
		expressionFree( ord->expression );
		ord->expression = NULL;

		if( NULL == ord->next ) {
			ord->next = free_order_item_list;
			break;
		} else
			ord = ord->next;
	};

	// Transfer the entire list to the free list
	free_order_item_list = first;
}

/**
	@brief Push an IdNode onto a stack of IdNodes.
	@param stack Pointer to the stack.
	@param id Id of the new node.
	@param alias Alias, if any, of the new node.
*/
static void push_id( IdNode** stack, int id, const char* alias ) {

	if( stack ) {
		// Allocate a node; from the free list if possible, from the heap if necessary.
		IdNode* node = NULL;
		if( free_id_node_list ) {
			node = free_id_node_list;
			free_id_node_list = free_id_node_list->next;
		} else
			node = safe_malloc( sizeof( IdNode ));

		// Populate it
		node->next = *stack;
		node->id = id;
		if( alias )
			node->alias = strdup( alias );
		else
			node->alias = NULL;

		// Reseat the stack
		*stack = node;
	}
}

/**
	@brief Remove the node at the top of an IdNode stack.
	@param stack Pointer to the IdNode stack.
*/
void pop_id( IdNode** stack ) {
	if( stack ) {
		IdNode* node = *stack;
		*stack = node->next;

		if( node->alias ) {
			free( node->alias );
			node->alias = NULL;
		}

		node->next = free_id_node_list;
		free_id_node_list = node;
	}
}

/**
	@brief Search a stack of IDs for a match by either ID or, optionally, by alias.
	@param stack Pointer to the stack.
	@param id The id to search for.
	@param alias (Optional) the alias to search for.
	@return A pointer to the matching node if one is found, or NULL if not.

	This search is used to detect cases where a query, expression, or FROM clause is nested
	inside itself, in order to avoid infinite recursion; or in order to avoid conflicting
	table references in a FROM clause.
*/
static const IdNode* searchIdStack( const IdNode* stack, int id, const char* alias ) {
	if( stack ) {
		const IdNode* node = stack;
		while( node ) {
			if( node->id == id )
				return node;        // Matched on id
			else if( alias && node->alias && !strcmp( alias, node->alias ))
				return node;        // Matched on alias
			else
				node = node->next;
		}
	}
	return NULL;   // No match found
}

/**
	@brief Free up any resources held by the StoredQ module.
*/
void storedQCleanup( void ) {

	// Free all the nodes in the free state list
	StoredQ* sq = free_storedq_list;
	while( sq ) {
		free_storedq_list = sq->next;
		free( sq );
		sq = free_storedq_list;
	}

	// Free all the nodes in the free from_relation list
	FromRelation* fr = free_from_relation_list;
	while( fr ) {
		free_from_relation_list = fr->next;
		free( fr );
		fr = free_from_relation_list;
	}

	// Free all the nodes in the free expression list
	Expression* exp = free_expression_list;
	while( exp ) {
		free_expression_list = exp->next;
		free( exp );
		exp = free_expression_list;
	}

	// Free all the nodes in the free select item list
	SelectItem* sel = free_select_item_list;
	while( sel ) {
		free_select_item_list = sel->next;
		free( sel );
		sel = free_select_item_list;
	}

	// Free all the nodes in the free select item list
	IdNode* node = free_id_node_list;
	while( node ) {
		free_id_node_list = node->next;
		free( node );
		node = free_id_node_list;
	}

	// Free all the nodes in the free query sequence list
	QSeq* seq = free_qseq_list;
	while( seq ) {
		free_qseq_list = seq->next;
		free( seq );
		seq = free_qseq_list;
	}

	// Free all the nodes in the free order item list
	OrderItem* ord = free_order_item_list;
	while( ord ) {
		free_order_item_list = ord->next;
		free( ord );
		ord = free_order_item_list;
	}

	// Free all the nodes in the bind variable free list
	BindVar* bind = free_bindvar_list;
	while( bind ) {
		free_bindvar_list = bind->next;
		free( bind );
		bind = free_bindvar_list;
	}

	// Free all the nodes in the case branch free list
	CaseBranch* branch = free_branch_list;
	while( branch ) {
		free_branch_list = branch->next;
		free( branch );
		branch = free_branch_list;
	}

	// Free all the nodes in the datatype free list
	Datatype* datatype = free_datatype_list;
	while( datatype ) {
		free_datatype_list = datatype->next;
		free( datatype );
		datatype = free_datatype_list;
	}
}

/**
	@brief Return a boolean value from a database result.
	@param result The database result.
	@param i Index of the column in the result, starting with 1 );
	@return 1 if true, or 0 for false.

	Null values and error conditions are interpreted as FALSE.
*/
static int oils_result_get_bool_idx( dbi_result result, int i ) {
	if( result ) {
		const char* str = dbi_result_get_string_idx( result, i );
		return (str && *str == 't' ) ? 1 : 0;
	} else
		return 0;
}

/**
	@brief Enable verbose messages.

	The messages are written to standard output, which for a server is /dev/null.  Hence this
	option is useful only for a non-server.  It is intended only as a convenience for
	development and debugging.
*/
void oilsStoredQSetVerbose( void ) {
	verbose = 1;
}
