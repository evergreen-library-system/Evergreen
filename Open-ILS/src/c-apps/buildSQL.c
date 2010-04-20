/**
	@file buildSQL.c
	@brief Translate an abstract representation of a query into an SQL statement.
*/

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/string_array.h"
#include "openils/oils_buildq.h"

static void buildQuery( BuildSQLState* state, StoredQ* query );
static void buildCombo( BuildSQLState* state, StoredQ* query, const char* type_str );
static void buildSelect( BuildSQLState* state, StoredQ* query );
static void buildFrom( BuildSQLState* state, FromRelation* core_from );
static void buildJoin( BuildSQLState* state, FromRelation* join );
static void buildSelectList( BuildSQLState* state, SelectItem* item );
static void buildOrderBy( BuildSQLState* state, OrderItem* ord_list );
static void buildExpression( BuildSQLState* state, Expression* expr );

static void add_newline( BuildSQLState* state );
static inline void incr_indent( BuildSQLState* state );
static inline void decr_indent( BuildSQLState* state );

/**
	@brief Build an SQL query.
	@param state Pointer to the query-building context.
	@param query Pointer to the query to be built.
	@return Zero if successful, or 1 if not.

	Clear the output buffer, call buildQuery() to do the work, and add a closing semicolon.
*/
int buildSQL( BuildSQLState* state, StoredQ* query ) {
	state->error  = 0;
	buffer_reset( state->sql );
	state->indent = 0;
	buildQuery( state, query );
	if( ! state->error ) {
		// Remove the trailing space, if there is one, and add a semicolon.
		char c = buffer_chomp( state->sql );
		if( c != ' ' )
			buffer_add_char( state->sql, c );  // oops, not a space; put it back
		buffer_add( state->sql, ";\n" );
	}
	return state->error;
}

/**
	@brief Build an SQL query, appending it to what has been built so far.
	@param state Pointer to the query-building context.
	@param query Pointer to the query to be built.

	Look at the query type and branch to the corresponding routine.
*/
static void buildQuery( BuildSQLState* state, StoredQ* query ) {
	if( buffer_length( state->sql ))
		add_newline( state );

	switch( query->type ) {
		case QT_SELECT :
			buildSelect( state, query );
			break;
		case QT_UNION :
			buildCombo( state, query, "UNION" );
			break;
		case QT_INTERSECT :
			buildCombo( state, query, "INTERSECT" );
			break;
		case QT_EXCEPT :
			buildCombo( state, query, "EXCEPT" );
			break;
		default :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: invalid query type %d in query # %d",
				query->type, query->id ));
			state->error = 1;
			break;
	}
}

/**
	@brief Build a UNION, INTERSECT, or EXCEPT query.
	@param state Pointer to the query-building context.
	@param query Pointer to the query to be built.
	@param type_str The query type, as a string.
*/
static void buildCombo( BuildSQLState* state, StoredQ* query, const char* type_str ) {

	QSeq* seq = query->child_list;
	if( !seq ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Internal error: No child queries within %s query # %d",
			type_str, query->id ));
		state->error = 1;
		return;
	}

	// Traverse the list of child queries
	while( seq ) {
		buildQuery( state, seq->child_query );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build child query # %d within %s query %d",
				seq->child_query->id, type_str, query->id );
			return;
		}
		seq = seq->next;
		if( seq ) {
			add_newline( state );
			buffer_add( state->sql, type_str );
			buffer_add_char( state->sql, ' ' );
			if( query->use_all )
				buffer_add( state->sql, "ALL " );
		}
	}

	return;
}

/**
	@brief Build a SELECT statement.
	@param state Pointer to the query-building context.
	@param query Pointer to the StoredQ structure that represents the query.
*/
static void buildSelect( BuildSQLState* state, StoredQ* query ) {

	FromRelation* from_clause = query->from_clause;
	if( !from_clause ) {
		sqlAddMsg( state, "SELECT has no FROM clause in query # %d", query->id );
		state->error = 1;
		return;
	}

	// To do: get SELECT list; just a stub here
	buffer_add( state->sql, "SELECT" );
	incr_indent( state );
	buildSelectList( state, query->select_list );
	if( state->error ) {
		sqlAddMsg( state, "Unable to build SELECT list for query # %d", query->id );
		state->error = 1;
		return;
	}
	decr_indent( state );

	// Build FROM clause, if there is one
	if( query->from_clause ) {
		buildFrom( state, query->from_clause );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build FROM clause for query # %d", query->id );
			state->error = 1;
			return;
		}
	}

	// Build WHERE clause, if there is one
	if( query->where_clause ) {
		add_newline( state );
		buffer_add( state->sql, "WHERE" );
		incr_indent( state );
		add_newline( state );
		buildExpression( state, query->where_clause );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build WHERE clause for query # %d", query->id );
			state->error = 1;
			return;
		}
		//else
			//buffer_add_char( state->sql, ' ' );
		decr_indent( state );
	}

	// Build WHERE clause, if there is one
	if( query->order_by_list ) {
		buildOrderBy( state, query->order_by_list );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build ORDER BY clause for query # %d", query->id );
			state->error = 1;
			return;
		}
	}
	
	state->error = 0;
}

/**
	@brief Build a FROM clause.
	@param Pointer to the query-building context.
	@param Pointer to the StoredQ query to which the FROM clause belongs.
*/
static void buildFrom( BuildSQLState* state, FromRelation* core_from ) {

	add_newline( state );
	buffer_add( state->sql, "FROM" );
	incr_indent( state );
	add_newline( state );

	switch( core_from->type ) {
		case FRT_RELATION :
			if( ! core_from->table_name ) {
				// To do: if class is available, look up table name
				// or source_definition in the IDL
				sqlAddMsg( state, "No table or view name available for core relation # %d",
					core_from->id );
				state->error = 1;
				return;
			}

			// Add table or view
			buffer_add( state->sql, core_from->table_name );
			break;
		case FRT_SUBQUERY :
			buffer_add_char( state->sql, '(' );
			incr_indent( state );
			buildQuery( state, core_from->subquery );
			decr_indent( state );
			add_newline( state );
			buffer_add_char( state->sql, ')' );
			break;
		case FRT_FUNCTION :
			sqlAddMsg( state, "Functions in FROM clause not yet supported" );
			state->error = 1;
			return;
	}

	// Add a table alias, if possible
	if( core_from->table_alias ) {
		buffer_add( state->sql, " AS \"" );
		buffer_add( state->sql, core_from->table_alias );
		buffer_add( state->sql, "\" " );
	}
	else if( core_from->class_name ) {
		buffer_add( state->sql, " AS \"" );
		buffer_add( state->sql, core_from->class_name );
		buffer_add( state->sql, "\" " );
	} else
		buffer_add_char( state->sql, ' ' );

	incr_indent( state );
	FromRelation* join = core_from->join_list;
	while( join ) {
		buildJoin( state, join );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build JOIN clause(s) for relation # %d",
				core_from->id );
			break;
		} else
			join = join->next;
	}
	decr_indent( state );
	decr_indent( state );
}

static void buildJoin( BuildSQLState* state, FromRelation* join ) {
	add_newline( state );
	switch( join->join_type ) {
		case JT_NONE :
			sqlAddMsg( state, "Non-join relation # %d in JOIN clause", join->id );
			state->error = 1;
			return;
		case JT_INNER :
			buffer_add( state->sql, "INNER JOIN " );
			break;
		case JT_LEFT:
			buffer_add( state->sql, "LEFT JOIN " );
			break;
		case JT_RIGHT:
			buffer_add( state->sql, "RIGHT JOIN " );
			break;
		case JT_FULL:
			buffer_add( state->sql, "FULL JOIN " );
			break;
		default :
			sqlAddMsg( state, "Unrecognized join type in relation # %d", join->id );
			state->error = 1;
			return;
	}

	switch( join->type ) {
		case FRT_RELATION :
			// Sanity check
			if( !join->table_name || ! *join->table_name ) {
				sqlAddMsg( state, "No relation designated for relation # %d", join->id );
				state->error = 1;
				return;
			}
			buffer_add( state->sql, join->table_name );
			break;
		case FRT_SUBQUERY :
			// Sanity check
			if( !join->subquery ) {
				sqlAddMsg( state, "Subquery expected, not found for relation # %d", join->id );
				state->error = 1;
				return;
			} else if( !join->table_alias ) {
				sqlAddMsg( state, "No table alias for subquery in FROM relation # %d",
					join->id );
				state->error = 1;
				return;
			}
			buffer_add_char( state->sql, '(' );
			incr_indent( state );
			buildQuery( state, join->subquery );
			decr_indent( state );
			add_newline( state );
			buffer_add_char( state->sql, ')' );
			break;
		case FRT_FUNCTION :
			if( !join->table_name || ! *join->table_name ) {
				sqlAddMsg( state, "Joins to functions not yet supported in relation # %d",
					join->id );
				state->error = 1;
				return;
			}
			break;
	}

	const char* effective_alias = join->table_alias;
	if( !effective_alias )
		effective_alias = join->class_name;

	if( effective_alias ) {
		buffer_add( state->sql, " AS \"" );
		buffer_add( state->sql, effective_alias );
		buffer_add_char( state->sql, '\"' );
	}
	
	if( join->on_clause ) {
		incr_indent( state );
		add_newline( state );
		buffer_add( state->sql, "ON " );
		buildExpression( state, join->on_clause );
		decr_indent( state );
	}

	FromRelation* subjoin = join->join_list;
	while( subjoin ) {
		buildJoin( state, subjoin );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build JOIN clause(s) for relation # %d", join->id );
			break;
		} else
			subjoin = subjoin->next;
	}
}

static void buildSelectList( BuildSQLState* state, SelectItem* item ) {
	
	int first = 1;
	while( item ) {
		if( !first )
			buffer_add_char( state->sql, ',' );
		add_newline( state );
		buildExpression( state, item->expression );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build an expression for SELECT item # %d", item->id );
			state->error = 1;
			break;
		}

		if( item->column_alias ) {
			buffer_add( state->sql, " AS \"" );
			buffer_add( state->sql, item->column_alias );
			buffer_add_char( state->sql, '\"' );
		}
		first = 0;
		item = item->next;
	};
	buffer_add_char( state->sql, ' ' );
}

/**
	@brief Add an ORDER BY clause to the current query.
	@param state Pointer to the query-building context.
	@param ord_list Pointer to the first node in a linked list of OrderItems.
*/
static void buildOrderBy( BuildSQLState* state, OrderItem* ord_list ) {
	add_newline( state );
	buffer_add( state->sql, "ORDER BY" );
	incr_indent( state );

	int first = 1;    // boolean
	while( ord_list ) {
		if( first )
			first = 0;
		else
			buffer_add_char( state->sql, ',' );
		add_newline( state );
		buildExpression( state, ord_list->expression );
		if( state->error ) {
			sqlAddMsg( state, "Unable to add ORDER BY expression # %d", ord_list->id );
			return;
		}

		ord_list = ord_list->next;
	}

	decr_indent( state );
	return;
}

/**
	@brief Build an arbitrary expression.
	@param state Pointer to the query-building context.
	@param expr Pointer to the Expression representing the expression to be built.
*/
static void buildExpression( BuildSQLState* state, Expression* expr ) {
	if( !expr ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Internal error: NULL pointer to Expression" ));
		state->error = 1;
		return;
	}

	if( expr->parenthesize )
		buffer_add_char( state->sql, '(' );

	switch( expr->type ) {
		case EXP_BETWEEN :
			sqlAddMsg( state, "BETWEEN expressions not yet supported" );
			state->error = 1;
			break;
		case EXP_BOOL :
			if( expr->literal ) {
				buffer_add( state->sql, expr->literal );
				buffer_add_char( state->sql, ' ' );
			} else
				buffer_add( state->sql, "FALSE " );
			break;
		case EXP_CASE :
			sqlAddMsg( state, "CASE expressions not yet supported" );
			state->error = 1;
			break;
			case EXP_CAST :                   // Type cast
			sqlAddMsg( state, "Cast expressions not yet supported" );
			state->error = 1;
			break;
		case EXP_COLUMN :                 // Table column
			if( expr->table_alias ) {
				buffer_add_char( state->sql, '\"' );
				buffer_add( state->sql, expr->table_alias );
				buffer_add( state->sql, "\"." );
			}
			if( expr->column_name ) {
				buffer_add( state->sql, expr->column_name );
			} else {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Column name not present in expression # %d", expr->id ));
				state->error = 1;
			}
			break;
		case EXP_EXIST :
			if( !expr->subquery ) {
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"No subquery found for EXIST expression # %d", expr->id ));
				state->error = 1;
			} else {
				buffer_add( state->sql, "EXISTS (" );
				incr_indent( state );
				buildQuery( state, expr->subquery );
				decr_indent( state );
				add_newline( state );
				buffer_add_char( state->sql, ')' );
			}
			break;
		case EXP_FIELD :
		case EXP_FUNCTION :
			sqlAddMsg( state, "Expression type not yet supported" );
			state->error = 1;
			break;
		case EXP_IN :
			if( expr->left_operand ) {
				buildExpression( state, expr->left_operand );
				if( !state->error ) {
					if( expr->subquery ) {
						buffer_add( state->sql, " IN (" );
						incr_indent( state );
						buildQuery( state, expr->subquery );
						decr_indent( state );
						add_newline( state );
						buffer_add_char( state->sql, ')' );
					} else {
						sqlAddMsg( state, "IN lists not yet supported" );
						state->error = 1;
					}
				}
			}
			break;
		case EXP_NOT_BETWEEN :
		case EXP_NOT_EXIST :
		case EXP_NOT_IN :
			sqlAddMsg( state, "Expression type not yet supported" );
			state->error = 1;
			break;
		case EXP_NULL :
			buffer_add( state->sql, "NULL" );
			break;
		case EXP_NUMBER :                    // Numeric literal
			if( !expr->literal ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Internal error: No numeric value in string expression # %d", expr->id ));
				state->error = 1;
			} else {
				buffer_add( state->sql, expr->literal );
			}
			break;
		case EXP_OPERATOR :
			if( expr->left_operand ) {
				buildExpression( state, expr->left_operand );
				if( state->error ) {
					sqlAddMsg( state, "Unable to emit left operand in expression # %d",
						expr->id );
					break;
				}
			}
			buffer_add_char( state->sql, ' ' );
			buffer_add( state->sql, expr->op );
			buffer_add_char( state->sql, ' ' );
			if( expr->right_operand ) {
				buildExpression( state, expr->right_operand );
				if( state->error ) {
					sqlAddMsg( state, "Unable to emit right operand in expression # %d",
							   expr->id );
					break;
				}
			}
			break;
		case EXP_STRING :                     // String literal
			if( !expr->literal ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Internal error: No string value in string expression # %d", expr->id ));
					state->error = 1;
			} else {
				buffer_add_char( state->sql, '\'' );
				buffer_add( state->sql, expr->literal );
				buffer_add_char( state->sql, '\'' );
			}
			break;
		case EXP_SUBQUERY :
			if( expr->subquery ) {
				buffer_add_char( state->sql, '(' );
				incr_indent( state );
				buildQuery( state, expr->subquery );
				decr_indent( state );
				add_newline( state );
				buffer_add_char( state->sql, ')' );
			} else {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Internal error: No subquery in subquery expression # %d", expr->id ));
				state->error = 1;
			}
			break;
	}
	
	if( expr->parenthesize )
		buffer_add_char( state->sql, ')' );
}

static void add_newline( BuildSQLState* state ) {
	buffer_add_char( state->sql, '\n' );

	// Add indentation
	static const char blanks[] = "                                ";   // 32 blanks
	static const size_t maxlen = sizeof( blanks ) - 1;
	const int blanks_per_level = 3;
	int n = state->indent * blanks_per_level;
	while( n > 0 ) {
		size_t len = n >= maxlen ? maxlen : n;
		buffer_add_n( state->sql, blanks, len );
		n -= len;
	}
}

static inline void incr_indent( BuildSQLState* state ) {
	++state->indent;
}

static inline void decr_indent( BuildSQLState* state ) {
	if( state->indent )
		--state->indent;
}
