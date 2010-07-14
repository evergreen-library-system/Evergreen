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
#include "opensrf/osrf_hash.h"
#include "opensrf/osrf_application.h"
#include "openils/oils_idl.h"
#include "openils/oils_sql.h"
#include "openils/oils_buildq.h"

static void build_Query( BuildSQLState* state, const StoredQ* query );
static void buildCombo( BuildSQLState* state, const StoredQ* query, const char* type_str );
static void buildSelect( BuildSQLState* state, const StoredQ* query );
static void buildFrom( BuildSQLState* state, const FromRelation* core_from );
static void buildJoin( BuildSQLState* state, const FromRelation* join );
static void buildSelectList( BuildSQLState* state, const SelectItem* item );
static void buildGroupBy( BuildSQLState* state, const SelectItem* sel_list );
static void buildOrderBy( BuildSQLState* state, const OrderItem* ord_list );
static void buildCase( BuildSQLState* state, const Expression* expr );
static void buildExpression( BuildSQLState* state, const Expression* expr );

static void buildFunction( BuildSQLState* state, const Expression* exp );
static int subexp_count( const Expression* expr );
static void buildTypicalFunction( BuildSQLState* state, const Expression* expr );
static void buildExtract( BuildSQLState* state, const Expression* expr );

static void buildSeries( BuildSQLState* state, const Expression* subexp_list, const char* op );
static void buildBindVar( BuildSQLState* state, const BindVar* bind );
static void buildScalar( BuildSQLState* state, int numeric, const jsonObject* obj );

static void add_newline( BuildSQLState* state );
static inline void incr_indent( BuildSQLState* state );
static inline void decr_indent( BuildSQLState* state );

/**
	@brief Create a jsonObject representing the current list of bind variables.
	@param bindvar_list Pointer to the bindvar_list member of a BuildSQLState.
	@return Pointer to the newly created jsonObject.

	The returned jsonObject is a (possibly empty) JSON_HASH, keyed on the names of the bind
	variables.  The data for each is another level of JSON_HASH with a fixed set of tags:
	- "label"
	- "type"
	- "description"
	- "default_value" (as a jsonObject)
	- "actual_value" (as a jsonObject)

	Any non-existent values are represented as JSON_NULLs.

	The calling code is responsible for freeing the returned jsonOjbect by calling
	jsonObjectFree().
*/
jsonObject* oilsBindVarList( osrfHash* bindvar_list ) {
	jsonObject* list = jsonNewObjectType( JSON_HASH );

	if( bindvar_list && osrfHashGetCount( bindvar_list )) {
		// Traverse our internal list of bind variables
		BindVar* bind = NULL;
		osrfHashIterator* iter = osrfNewHashIterator( bindvar_list );
		while(( bind = osrfHashIteratorNext( iter ))) {
			// Create an hash to represent the bind variable
			jsonObject* bind_obj = jsonNewObjectType( JSON_HASH );

			// Add an entry for each attribute
			jsonObject* attr = jsonNewObject( bind->label );
			jsonObjectSetKey( bind_obj, "label", attr );

			const char* type = NULL;
			switch( bind->type ) {
				case BIND_STR :
					type = "string";
					break;
				case BIND_NUM :
					type = "number";
					break;
				case BIND_STR_LIST :
					type = "string_list";
					break;
				case BIND_NUM_LIST :
					type = "number_list";
					break;
				default :
					type = "(invalid)";
					break;
			}
			attr = jsonNewObject( type );
			jsonObjectSetKey( bind_obj, "type", attr );

			attr = jsonNewObject( bind->description );
			jsonObjectSetKey( bind_obj, "description", attr );

			if( bind->default_value ) {
				attr = jsonObjectClone( bind->default_value );
				jsonObjectSetKey( bind_obj, "default_value", attr );
			}

			if( bind->actual_value ) {
				attr = jsonObjectClone( bind->actual_value );
				jsonObjectSetKey( bind_obj, "actual_value", attr );
			}

			// Add the bind variable to the list
			jsonObjectSetKey( list, osrfHashIteratorKey( iter ), bind_obj );
		}
		osrfHashIteratorFree( iter );
	}

	return list;
}

/**
	@brief Apply values to bind variables, overriding the defaults, if any.
	@param state Pointer to the query-building context.
	@param bindings A JSON_HASH of values.
	@return 0 if successful, or 1 if not.

	The @a bindings parameter must be a JSON_HASH.  The keys are the names of bind variables.
	The values are the corresponding values for the variables.
*/
int oilsApplyBindValues( BuildSQLState* state, const jsonObject* bindings ) {
	if( !state ) {
		osrfLogError( OSRF_LOG_MARK, "NULL pointer to state" );
		return 1;
	} else if( !bindings ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Internal error: No pointer to bindings" ));
		return 1;
	} else if( bindings->type != JSON_HASH ) {
		osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
			"Internal error: bindings parameter is not a JSON_HASH" ));
		return 1;
	}

	int rc = 0;
	jsonObject* value = NULL;
	jsonIterator* iter = jsonNewIterator( bindings );
	while(( value = jsonIteratorNext( iter ))) {
		const char* var_name = iter->key;
		BindVar* bind = osrfHashGet( state->bindvar_list, var_name );
		if( bind ) {
			// Apply or replace the value for the specified variable
			if( bind->actual_value )
				jsonObjectFree( bind->actual_value );
			bind->actual_value = jsonObjectClone( value );
		} else {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Can't assign value to bind variable \"%s\": no such variable", var_name ));
			rc = 1;
		}
	}
	jsonIteratorFree( iter );

	return rc;
}

/**
	@brief Build an SQL query.
	@param state Pointer to the query-building context.
	@param query Pointer to the query to be built.
	@return Zero if successful, or 1 if not.

	Clear the output buffer, call build_Query() to do the work, and add a closing semicolon.
*/
int buildSQL( BuildSQLState* state, const StoredQ* query ) {
	state->error  = 0;
	buffer_reset( state->sql );
	state->indent = 0;
	build_Query( state, query );
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
static void build_Query( BuildSQLState* state, const StoredQ* query ) {
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
static void buildCombo( BuildSQLState* state, const StoredQ* query, const char* type_str ) {

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
		build_Query( state, seq->child_query );
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
static void buildSelect( BuildSQLState* state, const StoredQ* query ) {

	FromRelation* from_clause = query->from_clause;
	if( !from_clause ) {
		sqlAddMsg( state, "SELECT has no FROM clause in query # %d", query->id );
		state->error = 1;
		return;
	}

	// Get SELECT list
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
		decr_indent( state );
	}

	// Build GROUP BY clause, if there is one
	buildGroupBy( state, query->select_list );

	// Build HAVING clause, if there is one
	if( query->having_clause ) {
		add_newline( state );
		buffer_add( state->sql, "HAVING" );
		incr_indent( state );
		add_newline( state );
		buildExpression( state, query->having_clause );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build HAVING clause for query # %d", query->id );
			state->error = 1;
			return;
		}
		decr_indent( state );
	}

	// Build ORDER BY clause, if there is one
	if( query->order_by_list ) {
		buildOrderBy( state, query->order_by_list );
		if( state->error ) {
			sqlAddMsg( state, "Unable to build ORDER BY clause for query # %d", query->id );
			state->error = 1;
			return;
		}
	}

	// Build LIMIT clause, if there is one
	if( query->limit_count ) {
		add_newline( state );
		buffer_add( state->sql, "LIMIT " );
		buildExpression( state, query->limit_count );
	}

	// Build OFFSET clause, if there is one
	if( query->offset_count ) {
		add_newline( state );
		buffer_add( state->sql, "OFFSET " );
		buildExpression( state, query->offset_count );
	}

	state->error = 0;
}

/**
	@brief Build a FROM clause.
	@param Pointer to the query-building context.
	@param Pointer to the StoredQ query to which the FROM clause belongs.
*/
static void buildFrom( BuildSQLState* state, const FromRelation* core_from ) {

	add_newline( state );
	buffer_add( state->sql, "FROM" );
	incr_indent( state );
	add_newline( state );

	switch( core_from->type ) {
		case FRT_RELATION : {
			char* relation = core_from->table_name;
			if( !relation ) {
				if( !core_from->class_name ) {
					sqlAddMsg( state, "No relation specified for core relation # %d",
						core_from->id );
					state->error = 1;
					return;
				}

				// Look up table name, view name, or source_definition in the IDL
				osrfHash* class_hash = osrfHashGet( oilsIDL(), core_from->class_name );
				relation = oilsGetRelation( class_hash );
			}

			// Add table or view
			buffer_add( state->sql, relation );
			if( !core_from->table_name )
				free( relation );   // In this case we strdup'd it, must free it
			break;
		}
		case FRT_SUBQUERY :
			buffer_add_char( state->sql, '(' );
			incr_indent( state );
			build_Query( state, core_from->subquery );
			decr_indent( state );
			add_newline( state );
			buffer_add_char( state->sql, ')' );
			break;
		case FRT_FUNCTION :
			buildFunction( state, core_from->function_call );
			if ( state->error ) {
				sqlAddMsg( state,
					"Unable to include function call # %d in FROM relation # %d",
					core_from->function_call->id, core_from->id );
				return;
			}
			break;
		default :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: Invalid type # %d in FROM relation # %d",
				core_from->type, core_from->id ));
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

/**
	@brief Add a JOIN clause.
	@param state Pointer to the query-building context.
	@param join Pointer to the FromRelation representing the JOIN to be added.
*/
static void buildJoin( BuildSQLState* state, const FromRelation* join ) {
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
			build_Query( state, join->subquery );
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

/**
	@brief Build a SELECT list.
	@param state Pointer to the query-building context.
	@param item Pointer to the first in a linked list of SELECT items.
*/
static void buildSelectList( BuildSQLState* state, const SelectItem* item ) {

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
	@brief Add a GROUP BY clause, if there is one, to the current query.
	@param state Pointer to the query-building context.
	@param sel_list Pointer to the first node in a linked list of SelectItems

	We reference the GROUP BY items by number, not by repeating the expressions.
*/
static void buildGroupBy( BuildSQLState* state, const SelectItem* sel_list ) {
	int seq = 0;       // Sequence number of current SelectItem
	int first = 1;     // Boolean: true for the first GROUPed BY item
	while( sel_list ) {
		++seq;

		if( sel_list->grouped_by ) {
			if( first ) {
				add_newline( state );
				buffer_add( state->sql, "GROUP BY " );
				first = 0;
			}
			else
				buffer_add( state->sql, ", " );

			buffer_fadd( state->sql, "%d", seq );
		}

		sel_list = sel_list->next;
	}
}

/**
	@brief Add an ORDER BY clause to the current query.
	@param state Pointer to the query-building context.
	@param ord_list Pointer to the first node in a linked list of OrderItems.
*/
static void buildOrderBy( BuildSQLState* state, const OrderItem* ord_list ) {
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
static void buildExpression( BuildSQLState* state, const Expression* expr ) {
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
			if( expr->negate )
				buffer_add( state->sql, "NOT " );

			buildExpression( state, expr->left_operand );
			if( state->error ) {
				sqlAddMsg( state, "Unable to emit left operand in BETWEEN expression # %d",
					expr->id );
				break;
			}

			buffer_add( state->sql, " BETWEEN " );

			buildExpression( state, expr->subexp_list );
			if( state->error ) {
				sqlAddMsg( state, "Unable to emit lower limit in BETWEEN expression # %d",
					expr->id );
				break;
			}

			buffer_add( state->sql, " AND " );

			buildExpression( state, expr->subexp_list->next );
			if( state->error ) {
				sqlAddMsg( state, "Unable to emit upper limit in BETWEEN expression # %d",
					expr->id );
				break;
			}

			break;
		case EXP_BIND :
			if( !expr->bind ) {     // Sanity check
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Internal error: no variable for bind variable expression" ));
				state->error = 1;
			} else
				buildBindVar( state, expr->bind );
			break;
		case EXP_BOOL :
			if( expr->negate )
				buffer_add( state->sql, "NOT " );

			if( expr->literal ) {
				buffer_add( state->sql, expr->literal );
				buffer_add_char( state->sql, ' ' );
			} else
				buffer_add( state->sql, "FALSE " );
			break;
		case EXP_CASE :
			buildCase( state, expr );
			if( state->error )
				sqlAddMsg( state, "Unable to build CASE expression # %d", expr->id );

			break;
		case EXP_CAST :                   // Type cast
			if( expr->negate )
				buffer_add( state->sql, "NOT " );

			buffer_add( state->sql, "CAST (" );
			buildExpression( state, expr->left_operand );
			if( state->error )
				sqlAddMsg( state, "Unable to build left operand for CAST expression # %d",
					expr->id );
			else {
				buffer_add( state->sql, " AS " );
				if( expr->cast_type && expr->cast_type->datatype_name ) {
					buffer_add( state->sql, expr->cast_type->datatype_name );
					buffer_add_char( state->sql, ')' );
				} else {
					osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
						"No datatype available for CAST expression # %d", expr->id ));
					state->error = 1;
				}
			}
			break;
		case EXP_COLUMN :                 // Table column
			if( expr->negate )
				buffer_add( state->sql, "NOT " );

			if( expr->table_alias ) {
				buffer_add_char( state->sql, '\"' );
				buffer_add( state->sql, expr->table_alias );
				buffer_add( state->sql, "\"." );
			}
			if( expr->column_name ) {
				buffer_add( state->sql, expr->column_name );
			} else {
				buffer_add_char( state->sql, '*' );
			}
			break;
		case EXP_EXIST :
			if( !expr->subquery ) {
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"No subquery found for EXIST expression # %d", expr->id ));
				state->error = 1;
			} else {
				if( expr->negate )
					buffer_add( state->sql, "NOT " );

				buffer_add( state->sql, "EXISTS (" );
				incr_indent( state );
				build_Query( state, expr->subquery );
				decr_indent( state );
				add_newline( state );
				buffer_add_char( state->sql, ')' );
			}
			break;
		case EXP_FUNCTION :
			buildFunction( state, expr );
			break;
		case EXP_IN :
			if( expr->left_operand ) {
				buildExpression( state, expr->left_operand );
				if( !state->error ) {
					if( expr->negate )
						buffer_add( state->sql, "NOT " );
					buffer_add( state->sql, " IN (" );

					if( expr->subquery ) {
						incr_indent( state );
						build_Query( state, expr->subquery );
						if( state->error )
							sqlAddMsg( state, "Unable to build subquery for IN condition" );
						else {
							decr_indent( state );
							add_newline( state );
							buffer_add_char( state->sql, ')' );
						}
					} else {
						buildSeries( state, expr->subexp_list, NULL );
						if( state->error )
							sqlAddMsg( state, "Unable to build IN list" );
						else
							buffer_add_char( state->sql, ')' );
					}
				}
			}
			break;
		case EXP_ISNULL :
			if( expr->left_operand ) {
				buildExpression( state, expr->left_operand );
				if( state->error ) {
					sqlAddMsg( state, "Unable to emit left operand in IS NULL expression # %d",
						expr->id );
					break;
				}
			}

			if( expr->negate )
				buffer_add( state->sql, " IS NOT NULL" );
			else
				buffer_add( state->sql, " IS NULL" );
			break;
		case EXP_NULL :
			if( expr->negate )
				buffer_add( state->sql, "NOT " );

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
			if( expr->negate )
				buffer_add( state->sql, "NOT (" );

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

			if( expr->negate )
				buffer_add_char( state->sql, ')' );

			break;
		case EXP_SERIES :
			if( expr->negate )
				buffer_add( state->sql, "NOT (" );

			buildSeries( state, expr->subexp_list, expr->op );
			if( state->error ) {
				sqlAddMsg( state, "Unable to build series expression using operator \"%s\"",
					expr->op ? expr->op : "," );
			}
			if( expr->negate )
				buffer_add_char( state->sql, ')' );

			break;
		case EXP_STRING :                     // String literal
			if( !expr->literal ) {
				osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
					"Internal error: No string value in string expression # %d", expr->id ));
					state->error = 1;
			} else {
				char* str = strdup( expr->literal );
				dbi_conn_quote_string( state->dbhandle, &str );
				if( str ) {
					buffer_add( state->sql, str );
					free( str );
				} else {
					osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to format string literal \"%s\" for expression # %d",
							expr->literal, expr->id ));
					state->error = 1;
				}
			}
			break;
		case EXP_SUBQUERY :
			if( expr->negate )
				buffer_add( state->sql, "NOT " );

			if( expr->subquery ) {
				buffer_add_char( state->sql, '(' );
				incr_indent( state );
				build_Query( state, expr->subquery );
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

/**
	@brief Build a CASE expression.
	@param state Pointer to the query-building context.
	@param exp Pointer to an Expression representing a CASE expression.
*/
static void buildCase( BuildSQLState* state, const Expression* expr ) {
	// Sanity checks
	if( ! expr->left_operand ) {
		sqlAddMsg( state, "CASE expression # %d has no left operand", expr->id );
		state->error  = 1;
		return;
	} else if( ! expr->branch_list ) {
		sqlAddMsg( state, "CASE expression # %d has no branches", expr->id );
		state->error  = 1;
		return;
	}

	if( expr->negate )
		buffer_add( state->sql, "NOT (" );

	// left_operand is the expression on which we shall branch
	buffer_add( state->sql, "CASE " );
	buildExpression( state, expr->left_operand );
	if( state->error ) {
		sqlAddMsg( state, "Unable to build operand of CASE expression # %d", expr->id );
		return;
	}

	incr_indent( state );

	// Emit each branch in turn
	CaseBranch* branch = expr->branch_list;
	while( branch ) {
		add_newline( state );

		if( branch->condition ) {
			// Emit a WHEN condition
			buffer_add( state->sql, "WHEN " );
			buildExpression( state, branch->condition );
			incr_indent( state );
			add_newline( state );
			buffer_add( state->sql, "THEN " );
		} else {
			// Emit ELSE
			buffer_add( state->sql, "ELSE " );
			incr_indent( state );
			add_newline( state );
		}

		// Emit the THEN expression
		buildExpression( state, branch->result );
		decr_indent( state );

		branch = branch->next;
	}

	decr_indent( state );
	add_newline( state );
	buffer_add( state->sql, "END" );

	if( expr->negate )
		buffer_add( state->sql, ")" );
}

/**
	@brief Build a function call, with a subfield if specified.
	@param state Pointer to the query-building context.
	@param exp Pointer to an Expression representing a function call.
*/
static void buildFunction( BuildSQLState* state, const Expression* expr ) {
	if( expr->negate )
		buffer_add( state->sql, "NOT " );

	// If a subfield is specified, the function call
	// needs an extra layer of parentheses
	if( expr->column_name )
		buffer_add_char( state->sql, '(' );

	// First, check for some specific functions with peculiar syntax, and treat them
	// as special exceptions.  We rely on the input side to ensure that the function
	// name is available.
	if( !strcasecmp( expr->function_name, "EXTRACT" ))
		buildExtract( state, expr );
	else if( !strcasecmp( expr->function_name, "CURRENT_DATE" ) && ! expr->subexp_list )
		buffer_add( state->sql, "CURRENT_DATE " );
	else if( !strcasecmp( expr->function_name, "CURRENT_TIME" ) && ! expr->subexp_list )
		buffer_add( state->sql, "CURRENT_TIME " );
	else if( !strcasecmp( expr->function_name, "CURRENT_TIMESTAMP" ) && ! expr->subexp_list )
		buffer_add( state->sql, "CURRENT_TIMESTAMP " );
	else if( !strcasecmp( expr->function_name, "LOCALTIME" ) && ! expr->subexp_list )
		buffer_add( state->sql, "LOCALTIME " );
	else if( !strcasecmp( expr->function_name, "LOCALTIMESTAMP" ) && ! expr->subexp_list )
		buffer_add( state->sql, "LOCALTIMESTAMP " );
	else if( !strcasecmp( expr->function_name, "TRIM" )) {
		int arg_count = subexp_count( expr );

		if( (arg_count != 2 && arg_count != 3 ) || expr->subexp_list->type != EXP_STRING )
			buildTypicalFunction( state, expr );
		else {
			sqlAddMsg( state,
				"TRIM function not supported in expr # %d; use ltrim() and/or rtrim()",
				expr->id );
			state->error = 1;
			return;
		}
	} else
		buildTypicalFunction( state, expr );     // Not a special exception.

	if( expr->column_name ) {
		// Add the name of the subfield
		buffer_add( state->sql, ").\"" );
		buffer_add( state->sql, expr->column_name );
		buffer_add_char( state->sql, '\"' );
	}
}

/**
	@brief Count the number of subexpressions attached to a given Expression.
	@param expr Pointer to the Expression whose subexpressions are to be counted.
	@return The number of subexpressions.
*/
static int subexp_count( const Expression* expr ) {
	if( !expr )
		return 0;

	int count = 0;
	const Expression* sub = expr->subexp_list;
	while( sub ) {
		++count;
		sub = sub->next;
	}
	return count;
}

/**
	@brief Build an ordinary function call, i.e. one with no special syntax,
	@param state Pointer to the query-building context.
	@param exp Pointer to an Expression representing a function call.

	Emit the parameters as a comma-separated list of expressions.
*/
static void buildTypicalFunction( BuildSQLState* state, const Expression* expr ) {
	buffer_add( state->sql, expr->function_name );
	buffer_add_char( state->sql, '(' );

	// Add the parameters, if any
	buildSeries( state, expr->subexp_list, NULL );

	buffer_add_char( state->sql, ')' );
}

/**
	@brief Build a call to the EXTRACT function, with its peculiar syntax.
	@param state Pointer to the query-building context.
	@param exp Pointer to an Expression representing an EXTRACT call.

	If there are not exactly two parameters, or if the first parameter is not a string,
	then assume it is an ordinary function overloading on the same name.  We don't try to
	check the type of the second parameter.  Hence it is possible for a legitimately
	overloaded function to be uncallable.

	The first parameter of EXTRACT() must be one of a short list of names for some fragment
	of a date or time.  Here we accept that parameter in the form of a string.  We don't
	surround it with quotes in the output, although PostgreSQL wouldn't mind if we did.
*/
static void buildExtract( BuildSQLState* state, const Expression* expr ) {

	const Expression* arg = expr->subexp_list;

	// See if this is the special form of EXTRACT(), so far as we can tell
	if( subexp_count( expr ) != 2 || arg->type != EXP_STRING ) {
		buildTypicalFunction( state, expr );
		return;
	} else {
		// check the first argument against a list of valid values
		if(    strcasecmp( arg->literal, "century" )
			&& strcasecmp( arg->literal, "day" )
			&& strcasecmp( arg->literal, "decade" )
			&& strcasecmp( arg->literal, "dow" )
			&& strcasecmp( arg->literal, "doy" )
			&& strcasecmp( arg->literal, "epoch" )
			&& strcasecmp( arg->literal, "hour" )
			&& strcasecmp( arg->literal, "isodow" )
			&& strcasecmp( arg->literal, "isoyear" )
			&& strcasecmp( arg->literal, "microseconds" )
			&& strcasecmp( arg->literal, "millennium" )
			&& strcasecmp( arg->literal, "milliseconds" )
			&& strcasecmp( arg->literal, "minute" )
			&& strcasecmp( arg->literal, "month" )
			&& strcasecmp( arg->literal, "quarter" )
			&& strcasecmp( arg->literal, "second" )
			&& strcasecmp( arg->literal, "timezone" )
			&& strcasecmp( arg->literal, "timezone_hour" )
			&& strcasecmp( arg->literal, "timezone_minute" )
			&& strcasecmp( arg->literal, "week" )
			&& strcasecmp( arg->literal, "year" )) {
			// This *could* be an ordinary function, overloading on the name.  However it's
			// more likely that the user misspelled one of the names expected by EXTRACT().
			sqlAddMsg( state,
				"Invalid name \"%s\" as EXTRACT argument in expression # %d",
				expr->literal, expr->id );
			state->error = 1;
		}
	}

	buffer_add( state->sql, "EXTRACT(" );
	buffer_add( state->sql, arg->literal );
	buffer_add( state->sql, " FROM " );

	arg = arg->next;
	if( !arg ) {
		sqlAddMsg( state,
			"Only one argument supplied to EXTRACT function in expression # %d", expr->id );
		state->error = 1;
		return;
	}

	// The second parameter must be of type timestamp, time, or interval.  We don't have
	// a good way of checking it here, so we rely on PostgreSQL to complain if necessary.
	buildExpression( state, arg );
	buffer_add_char( state->sql, ')' );
}

/**
	@brief Build a series of expressions separated by a specified operator, or by commas.
	@param state Pointer to the query-building context.
	@param subexp_list Pointer to the first Expression in a linked list.
	@param op Pointer to the operator, or NULL for commas.

	If the operator is AND or OR (in upper, lower, or mixed case), the second and all
	subsequent operators will begin on a new line.
*/
static void buildSeries( BuildSQLState* state, const Expression* subexp_list, const char* op ) {

	if( !subexp_list)
		return;                // List is empty

	int comma = 0;             // Boolean; true if separator is a comma
	int newline_needed = 0;    // Boolean; true if operator is AND or OR

	if( !op ) {
		op = ",";
		comma = 1;
	} else if( !strcmp( op, "," ))
		comma = 1;
	else if( !strcasecmp( op, "AND" ) || !strcasecmp( op, "OR" ))
		newline_needed = 1;

	int first = 1;               // Boolean; true for first item in list
	while( subexp_list ) {
		if( first )
			first = 0;   // No separator needed yet
		else {
			// Insert a separator
			if( comma )
				buffer_add( state->sql, ", " );
			else {
				if( newline_needed )
					add_newline( state );
				else
					buffer_add_char( state->sql, ' ' );

				buffer_add( state->sql, op );
				buffer_add_char( state->sql, ' ' );
			}
		}

		buildExpression( state, subexp_list );
		subexp_list = subexp_list->next;
	}
}

/**
	@brief Add the value of a bind variable to an SQL statement.
	@param state Pointer to the query-building context.
	@param bind Pointer to the bind variable whose value is to be added to the SQL.

	The value may be a null, a scalar, or an array of nulls and/or scalars, depending on
	the type of the bind variable.
*/
static void buildBindVar( BuildSQLState* state, const BindVar* bind ) {

	// Decide where to get the value, if any
	const jsonObject* value = NULL;
	if( bind->actual_value )
		value = bind->actual_value;
	else if( bind->default_value ) {
		if( state->defaults_usable )
			value = bind->default_value;
		else {
			sqlAddMsg( state, "No confirmed value available for bind variable \"%s\"",
				bind->name );
			state->error = 1;
			return;
		}
	} else if( state->values_required ) {
		sqlAddMsg( state, "No value available for bind variable \"%s\"", bind->name );
		state->error = 1;
		return;
	} else {
		// No value available, and that's okay.  Emit the name of the bind variable.
		buffer_add_char( state->sql, ':' );
		buffer_add( state->sql, bind->name );
		return;
	}

	// If we get to this point, we know that a value is available.  Carry on.

	int numeric = 0;       // Boolean
	if( BIND_NUM == bind->type || BIND_NUM_LIST == bind->type )
		numeric = 1;

	// Emit the value
	switch( bind->type ) {
		case BIND_STR :
		case BIND_NUM :
			buildScalar( state, numeric, value );
			break;
		case BIND_STR_LIST :
		case BIND_NUM_LIST :
			if( JSON_ARRAY == value->type ) {
				// Iterate over array, emit each value
				int first = 1;   // Boolean
				unsigned long max = value->size;
				unsigned long i = 0;
				while( i < max ) {
					if( first )
						first = 0;
					else
						buffer_add( state->sql, ", " );

					buildScalar( state, numeric, jsonObjectGetIndex( value, i ));
					++i;
				}
			} else {
				osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
					"Invalid value for bind variable; expected a list of values" ));
				state->error = 1;
			}
			break;
		default :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: invalid type for bind variable" ));
			state->error = 1;
			break;
	}

	if( state->error )
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
			"Unable to emit value of bind variable \"%s\"", bind->name ));
}

/**
	@brief Add a number or quoted string to an SQL statement.
	@param state Pointer to the query-building context.
	@param numeric Boolean; true if the value is expected to be a number
	@param obj Pointer to the jsonObject whose value is to be added to the SQL.
*/
static void buildScalar( BuildSQLState* state, int numeric, const jsonObject* obj ) {
	switch( obj->type ) {
		case JSON_HASH :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: hash value for bind variable" ));
			state->error = 1;
			break;
		case JSON_ARRAY :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: array value for bind variable" ));
			state->error = 1;
			break;
		case JSON_STRING :
			if( numeric ) {
				sqlAddMsg( state,
					"Invalid value for bind variable: expected a string, found a number" );
				state->error = 1;
			} else {
				char* str = jsonObjectToSimpleString( obj );
				dbi_conn_quote_string( state->dbhandle, &str );
				if( str ) {
					buffer_add( state->sql, str );
					free( str );
				} else {
					osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( state,
						"Unable to format string literal \"%s\" for bind variable",
						jsonObjectGetString( obj )));
					state->error = 1;
				}
			}
			break;
		case JSON_NUMBER :
			if( numeric ) {
				buffer_add( state->sql, jsonObjectGetString( obj ));
			} else {
				sqlAddMsg( state,
					"Invalid value for bind variable: expected a number, found a string" );
				state->error = 1;
			}
			break;
		case JSON_NULL :
			buffer_add( state->sql, "NULL" );
			break;
		case JSON_BOOL :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: boolean value for bind variable" ));
			state->error = 1;
			break;
		default :
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state,
				"Internal error: corrupted value for bind variable" ));
			state->error = 1;
			break;
	}
}

/**
	@brief Start a new line in the output, with the current level of indentation.
	@param state Pointer to the query-building context.
*/
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

/**
	@brief Increase the degree of indentation.
	@param state Pointer to the query-building context.
*/
static inline void incr_indent( BuildSQLState* state ) {
	++state->indent;
}

/**
	@brief Reduce the degree of indentation.
	@param state Pointer to the query-building context.
*/
static inline void decr_indent( BuildSQLState* state ) {
	if( state->indent )
		--state->indent;
}
